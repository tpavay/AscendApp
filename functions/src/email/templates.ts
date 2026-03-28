import {getBetaInviteUrl, getMarketingWebsiteUrl} from "./config";
import type {
  EmailJobPayload,
  TransactionalEmailRenderResult,
  WaitlistWelcomePayload,
} from "./types";

/**
 * Escapes untrusted HTML content for safe email rendering.
 * @param {string} value - Raw user-provided content
 * @return {string} Escaped HTML string
 */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Validates the payload for a waitlist welcome email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {WaitlistWelcomePayload} Validated payload
 */
function parseWaitlistWelcomePayload(
  payload: EmailJobPayload
): WaitlistWelcomePayload {
  if (
    !payload ||
    typeof payload !== "object" ||
    typeof payload.source !== "string"
  ) {
    throw new Error("invalid_waitlist_welcome_payload");
  }

  return {
    source: payload.source,
  };
}

/**
 * Renders the waitlist welcome email content.
 * @param {WaitlistWelcomePayload} payload - Template payload
 * @return {TransactionalEmailRenderResult} Subject and rendered bodies
 */
export function renderWaitlistWelcomeEmail(
  payload: WaitlistWelcomePayload
): TransactionalEmailRenderResult {
  void payload;

  const betaInviteUrl = getBetaInviteUrl();
  const websiteUrl = getMarketingWebsiteUrl();
  const iconUrl = `${websiteUrl}/images/StairmasterIconAccent.png`;
  const privacyPolicyUrl = `${websiteUrl}/privacy`;
  const primaryCtaUrl = betaInviteUrl ?? websiteUrl;
  const primaryCtaLabel = betaInviteUrl ?
    "Join the beta on TestFlight" :
    "Visit ascendstepper.com";
  const subject = betaInviteUrl ?
    "You're in. Start testing Ascend on TestFlight" :
    "You're on the Ascend waitlist";
  const eyebrow = betaInviteUrl ? "Signup Confirmed" : "Waitlist Confirmed";
  const headlineLeading = betaInviteUrl ? "START TESTING" : "YOU'RE ON";
  const headlineAccent = betaInviteUrl ? "TODAY." : "THE LIST.";
  const bodyCopy = betaInviteUrl ?
    [
      "Thanks for signing up for Ascend. We're currently in beta,",
      "so you can start testing right away. No waiting required.",
    ].join(" ") :
    [
      "Thanks for signing up for Ascend.",
      "We'll email you when early access and launch details are ready.",
    ].join(" ");
  const helperCopy = betaInviteUrl ?
    "You'll need Apple's TestFlight app installed." :
    "We'll keep you posted when beta access opens.";
  const escapedBetaInviteUrl = betaInviteUrl ? escapeHtml(betaInviteUrl) : null;
  const escapedIconUrl = escapeHtml(iconUrl);
  const escapedPrimaryCtaUrl = escapeHtml(primaryCtaUrl);
  const escapedPrivacyPolicyUrl = escapeHtml(privacyPolicyUrl);

  return {
    subject,
    text: [
      betaInviteUrl ? "Start testing today." : "You're on the list.",
      "",
      bodyCopy,
      helperCopy,
      "",
      `${primaryCtaLabel}: ${primaryCtaUrl}`,
      "",
      "Talk soon,",
      "Tyler",
      "Ascend",
      "",
      "Need help? Reply to this email.",
      `Privacy Policy: ${privacyPolicyUrl}`,
    ].join("\n"),
    html: [
      "<!doctype html>",
      // eslint-disable-next-line max-len
      "<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\"><body style=\"margin:0;padding:0;background:#f4f2eb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111111;\">",
      // eslint-disable-next-line max-len
      "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"background:#f4f2eb;padding:24px 12px;\"><tr><td align=\"center\">",
      // eslint-disable-next-line max-len
      "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"max-width:620px;background:#ffffff;border:1px solid rgba(17,17,17,0.08);border-radius:32px;overflow:hidden;\">",
      // eslint-disable-next-line max-len
      "<tr><td style=\"background:#111111;padding:28px 32px;\"><table role=\"presentation\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\"><tr><td valign=\"middle\" style=\"padding-right:14px;\"><img src=\"",
      escapedIconUrl,
      // eslint-disable-next-line max-len
      "\" width=\"42\" height=\"42\" alt=\"Ascend icon\" style=\"display:block;width:42px;height:42px;border:0;border-radius:10px;\" /></td><td valign=\"middle\" style=\"font-size:16px;line-height:1;color:#ffffff;font-weight:800;letter-spacing:0.08em;text-transform:uppercase;\">Ascend</td></tr></table></td></tr>",
      // eslint-disable-next-line max-len
      "<tr><td style=\"padding:40px 32px 24px;\"><p style=\"margin:0 0 18px;font-size:12px;line-height:1.3;color:#b4cc00;font-weight:700;letter-spacing:0.28em;text-transform:uppercase;\">",
      eyebrow,
      "</p>",
      // eslint-disable-next-line max-len
      "<h1 style=\"margin:0 0 20px;font-size:58px;line-height:0.94;font-weight:900;letter-spacing:-0.04em;color:#111111;\">",
      headlineLeading,
      "<br /><span style=\"color:#b4cc00;\">",
      headlineAccent,
      "</span></h1>",
      // eslint-disable-next-line max-len
      "<p style=\"margin:0 0 28px;font-size:18px;line-height:1.65;color:#4b5563;max-width:470px;\">",
      bodyCopy.replace(/'/g, "&#39;").replace(/—/g, "&mdash;"),
      "</p>",
      // eslint-disable-next-line max-len
      "<p style=\"margin:0 0 28px;font-size:15px;line-height:1.6;color:#9ca3af;text-align:center;\">",
      helperCopy.replace(/'/g, "&#39;"),
      "</p>",
      "<div style=\"text-align:center;\">",
      // eslint-disable-next-line max-len
      "<a href=\"",
      betaInviteUrl ? escapedBetaInviteUrl : escapedPrimaryCtaUrl,
      // eslint-disable-next-line max-len
      "\" style=\"display:inline-block;padding:20px 28px;border-radius:18px;background:#b4cc00;color:#111111;font-size:18px;line-height:1;font-weight:800;text-decoration:none;text-transform:uppercase;letter-spacing:0.04em;\">",
      primaryCtaLabel,
      "</a></div></td></tr>",
      // eslint-disable-next-line max-len
      "<tr><td style=\"padding:0 32px 36px;\"><div style=\"border-top:1px solid rgba(17,17,17,0.08);padding-top:24px;text-align:center;\"><p style=\"margin:0 0 10px;font-size:14px;line-height:1.6;color:#9ca3af;\">You received this because you signed up at ascendstepper.com.</p><p style=\"margin:0 0 10px;font-size:14px;line-height:1.6;color:#9ca3af;\">Need help? Reply to this email.</p><p style=\"margin:0;font-size:14px;line-height:1.6;\"><a href=\"",
      escapedPrivacyPolicyUrl,
      // eslint-disable-next-line max-len
      "\" style=\"color:#6b7280;text-decoration:underline;\">Privacy Policy</a></p></div></td></tr>",
      "</table></td></tr></table></body></html>",
    ].join(""),
  };
}

/**
 * Validates and renders a waitlist welcome email from a generic payload.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {TransactionalEmailRenderResult} Subject and rendered bodies
 */
export function renderWaitlistWelcomeEmailFromPayload(
  payload: EmailJobPayload
): TransactionalEmailRenderResult {
  return renderWaitlistWelcomeEmail(parseWaitlistWelcomePayload(payload));
}
