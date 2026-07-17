import * as admin from "firebase-admin";
// Imported from the modular entry point rather than reached through
// admin.firestore.Timestamp: the Functions emulator proxies the admin
// namespace and strips those static properties, which would make this
// endpoint untestable locally.
import {Timestamp} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {buildNextCommunicationPreferences} from "../lifecycle";
import {getUnsubscribeSigningKey, transactionalEmailConfig} from "./config";
import {escapeHtml} from "./html";
import {verifyUnsubscribeToken} from "./unsubscribeToken";

const BRAND_ACCENT_COLOR = "#86D30A";

export type UnsubscribeOutcome =
  | "already_unsubscribed"
  | "unsubscribed";

/**
 * Renders a standalone confirmation or error page.
 *
 * The page is intentionally self-contained: it is served straight from the
 * function, so it cannot rely on any hosted stylesheet or asset.
 * @param {string} heading - Page headline
 * @param {string} body - Supporting copy
 * @param {string | null} confirmToken - Token to POST back, when confirming
 * @return {string} Complete HTML document
 */
export function renderUnsubscribePage(
  heading: string,
  body: string,
  confirmToken: string | null = null
): string {
  const formHtml = confirmToken ?
    [
      "<form method=\"post\" action=\"/api/unsubscribe?token=",
      encodeURIComponent(confirmToken),
      "\" style=\"margin:28px 0 0;\">",
      "<button type=\"submit\" style=\"display:inline-block;padding:16px 24px;",
      "border:0;border-radius:16px;cursor:pointer;background:",
      BRAND_ACCENT_COLOR,
      ";color:#111111;font-size:16px;font-weight:800;",
      "text-transform:uppercase;letter-spacing:0.04em;\">",
      "Unsubscribe",
      "</button></form>",
    ].join("") :
    "";

  return [
    "<!doctype html>",
    "<html lang=\"en\"><head><meta charset=\"utf-8\" />",
    // eslint-disable-next-line max-len
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />",
    "<meta name=\"robots\" content=\"noindex\" />",
    "<title>Ascend Emails</title></head>",
    // eslint-disable-next-line max-len
    "<body style=\"margin:0;padding:48px 20px;background:#f4f2eb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111111;\">",
    // eslint-disable-next-line max-len
    "<main style=\"max-width:520px;margin:0 auto;background:#ffffff;border:1px solid rgba(17,17,17,0.08);border-radius:28px;padding:40px 32px;text-align:center;\">",
    // eslint-disable-next-line max-len
    "<h1 style=\"margin:0 0 16px;font-size:32px;line-height:1.05;font-weight:900;letter-spacing:-0.03em;\">",
    escapeHtml(heading),
    "</h1>",
    // eslint-disable-next-line max-len
    "<p style=\"margin:0;font-size:17px;line-height:1.6;color:#4b5563;\">",
    escapeHtml(body),
    "</p>",
    formHtml,
    "</main></body></html>",
  ].join("");
}

/**
 * Disables lifecycle emails for a verified uid.
 *
 * Merges rather than overwrites so the shared preferences document keeps the
 * push notification preference, and skips the write when the user is already
 * unsubscribed so repeated clicks cannot amplify writes.
 * @param {string} uid - Verified Firebase Auth user ID
 * @return {Promise<UnsubscribeOutcome>} What the request actually changed
 */
export async function disableLifecycleEmails(
  uid: string
): Promise<UnsubscribeOutcome> {
  const firestore = admin.firestore();
  const preferencesRef = firestore
    .collection("users")
    .doc(uid)
    .collection("communication_preferences")
    .doc("current");

  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(preferencesRef);
    const existing = snapshot.exists ? snapshot.data() ?? {} : {};
    if (existing.lifecycleEmailsEnabled === false) {
      return "already_unsubscribed";
    }

    const now = Timestamp.now();
    transaction.set(
      preferencesRef,
      buildNextCommunicationPreferences(
        existing,
        {
          lifecycleEmailsEnabled: false,
          unsubscribedAt: now,
          unsubscribedVia: "email_link",
        },
        now
      ),
      {merge: true}
    );

    return "unsubscribed";
  });
}

/**
 * Handles one-click and link-based unsubscribe requests from email.
 *
 * GET renders a confirmation page rather than acting, so link scanners and
 * mail-client prefetchers cannot unsubscribe a user by following the footer
 * link. POST performs the opt-out, which is what RFC 8058 one-click sends.
 */
export const unsubscribeFromEmails = onRequest(
  {secrets: [transactionalEmailConfig]},
  async (request, response) => {
    response.set("Cache-Control", "no-store");

    if (request.method !== "GET" && request.method !== "POST") {
      response.set("Allow", "GET, POST");
      response.status(405).send(renderUnsubscribePage(
        "Method not supported.",
        "Open the unsubscribe link from your email to manage Ascend emails."
      ));
      return;
    }

    const uid = verifyUnsubscribeToken(
      request.query.token,
      getUnsubscribeSigningKey()
    );
    if (!uid) {
      response.status(400).send(renderUnsubscribePage(
        "This link is not valid.",
        [
          "The unsubscribe link is incomplete or has been changed.",
          "Manage email preferences in Ascend under Settings, Notifications.",
        ].join(" ")
      ));
      return;
    }

    if (request.method === "GET") {
      response.status(200).send(renderUnsubscribePage(
        "Unsubscribe from Ascend emails?",
        [
          "You will stop receiving climb and progress emails.",
          "Account and security emails still reach you.",
        ].join(" "),
        typeof request.query.token === "string" ? request.query.token : null
      ));
      return;
    }

    try {
      const outcome = await disableLifecycleEmails(uid);
      console.log("unsubscribeFromEmails processed", {outcome, uid});
    } catch (error) {
      console.error("unsubscribeFromEmails failed", {
        message: error instanceof Error ? error.message : "unknown_error",
        uid,
      });
      response.status(500).send(renderUnsubscribePage(
        "Something went wrong.",
        "Try the link again, or turn emails off in Ascend under Settings."
      ));
      return;
    }

    response.status(200).send(renderUnsubscribePage(
      "You're unsubscribed.",
      [
        "Ascend will stop sending climb and progress emails.",
        "Turn them back on anytime in Settings, Notifications.",
      ].join(" ")
    ));
  }
);
