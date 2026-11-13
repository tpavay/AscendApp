import {getMarketingWebsiteUrl} from "./config";
import {cleanFirstName, isValidTimeZone} from "./birthday";
import {
  DRIP_EMAIL_COPY,
  DRIP_SIGNATURE,
  TRIAL_PRICE_LABEL,
} from "./dripCopy";
import type {DripEmailType} from "./dripCopy";
import {escapeHtml} from "./html";
import type {
  DripEmailPayload,
  EmailJobPayload,
  EmailRenderContext,
  TransactionalEmailRenderResult,
} from "./types";

/**
 * The plain founder-letter look the lifecycle drip emails use: one narrow
 * centered column of small text on white, a text link instead of a button, and
 * the shared footer lines (why you got this, Privacy Policy, Unsubscribe). It
 * is deliberately not the dark recap shell: these read as a note from a person.
 * The words are in `dripCopy.ts`; nothing here decides what to say.
 */

const DEFAULT_CHARGE_DATE_ZONE = "America/Chicago";

/**
 * Reads the stored payload, refusing anything that is not a drip payload.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {DripEmailPayload} Validated payload
 */
function parseDripPayload(payload: EmailJobPayload): DripEmailPayload {
  const value = payload as unknown as Record<string, unknown>;
  if (!value || typeof value !== "object" ||
    typeof value.ctaUrl !== "string" || !value.ctaUrl.startsWith("https://")) {
    throw new Error("drip email payload needs an https ctaUrl");
  }
  return {
    ctaUrl: value.ctaUrl,
    ...(typeof value.firstName === "string" ?
      {firstName: value.firstName} : {}),
    ...(typeof value.timeZone === "string" ?
      {timeZone: value.timeZone} : {}),
    ...(typeof value.trialEndsAtMs === "number" ?
      {trialEndsAtMs: value.trialEndsAtMs} : {}),
  };
}

/**
 * The day a trial ends, written for the climber's own calendar.
 * @param {number} trialEndsAtMs - Trial end, epoch milliseconds
 * @param {string | undefined} timeZone - The climber's zone, when known
 * @return {string} e.g. "Saturday, November 21"
 */
export function formatChargeDate(
  trialEndsAtMs: number,
  timeZone: string | undefined
): string {
  const zone = timeZone && isValidTimeZone(timeZone) ?
    timeZone : DEFAULT_CHARGE_DATE_ZONE;
  return new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "long",
    timeZone: zone,
    weekday: "long",
  }).format(new Date(trialEndsAtMs));
}

/**
 * Fills the copy's `{chargeDate}` and `{price}` placeholders.
 * @param {string} paragraph - A paragraph from the copy file
 * @param {DripEmailPayload} payload - The job's payload
 * @return {string} Paragraph with placeholders filled
 */
function fillPlaceholders(
  paragraph: string,
  payload: DripEmailPayload
): string {
  if (paragraph.includes("{chargeDate}") &&
    typeof payload.trialEndsAtMs !== "number") {
    throw new Error("trial reminder payload needs trialEndsAtMs");
  }
  const chargeDate = typeof payload.trialEndsAtMs === "number" ?
    formatChargeDate(payload.trialEndsAtMs, payload.timeZone) : "";
  return paragraph
    .split("{price}").join(TRIAL_PRICE_LABEL)
    .split("{chargeDate}").join(chargeDate);
}

/**
 * Renders one drip email.
 * @param {DripEmailType} type - Which email
 * @param {DripEmailPayload} payload - The job's payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Subject, HTML and plain text
 */
export function renderDripEmail(
  type: DripEmailType,
  payload: DripEmailPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  const copy = DRIP_EMAIL_COPY[type];
  const firstName = cleanFirstName(payload.firstName);
  const greeting = firstName ? `Hi ${firstName},` : "Hi,";
  const paragraphs = copy.paragraphs.map(
    (paragraph) => fillPlaceholders(paragraph, payload)
  );
  const privacyUrl = `${getMarketingWebsiteUrl()}/privacy`;

  const paragraphStyle = "margin:0 0 16px;";
  const footerStyle = "margin:0 0 6px;font-size:12px;line-height:1.6;" +
    "color:#777777;";
  const unsubscribeHtml = context.unsubscribeUrl ? [
    " &middot; <a href=\"", escapeHtml(context.unsubscribeUrl),
    "\" style=\"color:#777777;\">Unsubscribe</a>",
  ].join("") : "";

  const html = [
    "<!doctype html>",
    "<html lang=\"en\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
    "<meta name=\"color-scheme\" content=\"light\">",
    "<meta name=\"supported-color-schemes\" content=\"light\">",
    "</head><body style=\"margin:0;padding:0;background:#ffffff;",
    "color:#222222;font-family:Georgia,'Times New Roman',serif;",
    "font-size:16px;line-height:1.55;\">",
    "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;",
    "color:transparent;\">", escapeHtml(copy.preheader), "</div>",
    "<div style=\"max-width:480px;margin:0 auto;padding:32px 20px 40px;\">",
    `<p style="${paragraphStyle}">${escapeHtml(greeting)}</p>`,
    ...paragraphs.map(
      (paragraph) =>
        `<p style="${paragraphStyle}">${escapeHtml(paragraph)}</p>`
    ),
    `<p style="${paragraphStyle}"><a href="${escapeHtml(payload.ctaUrl)}" `,
    "style=\"color:#222222;text-decoration:underline;\">",
    escapeHtml(copy.linkLabel), "</a></p>",
    "<p style=\"margin:24px 0 0;\">",
    escapeHtml(DRIP_SIGNATURE.name), "<br>",
    "<span style=\"font-size:13px;color:#777777;\">",
    escapeHtml(DRIP_SIGNATURE.role), "</span></p>",
    "<div style=\"margin-top:32px;border-top:1px solid #e5e5e5;",
    "padding-top:16px;font-family:Arial,Helvetica,sans-serif;\">",
    `<p style="${footerStyle}">${escapeHtml(copy.whyReceived)}</p>`,
    `<p style="${footerStyle}"><a href="${escapeHtml(privacyUrl)}" `,
    "style=\"color:#777777;\">Privacy Policy</a>", unsubscribeHtml, "</p>",
    "</div></div></body></html>",
  ].join("");

  const text = [
    greeting,
    "",
    ...paragraphs.flatMap((paragraph) => [paragraph, ""]),
    `${copy.linkLabel}: ${payload.ctaUrl}`,
    "",
    DRIP_SIGNATURE.name,
    DRIP_SIGNATURE.role,
    "",
    copy.whyReceived,
    `Privacy Policy: ${privacyUrl}`,
    ...(context.unsubscribeUrl ?
      [`Unsubscribe: ${context.unsubscribeUrl}`] : []),
  ].join("\n");

  return {html, subject: copy.subject, text};
}

/**
 * Validates a stored payload and renders the drip email for it.
 * @param {DripEmailType} type - Which email
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderDripEmailFromPayload(
  type: DripEmailType,
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderDripEmail(type, parseDripPayload(payload), context);
}
