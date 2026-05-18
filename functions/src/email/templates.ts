import {getBetaInviteUrl, getMarketingWebsiteUrl} from "./config";
import type {
  EmailJobPayload,
  FeedbackAdminNotifyPayload,
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
  const iconUrl = `${websiteUrl}/images/ascend-a-icon.png`;
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

// =============================================================================
// Feedback Admin Notification
// =============================================================================

const FEEDBACK_TYPE_LABELS: Record<string, string> = {
  bug_report: "Bug Report",
  feature_request: "Feature Request",
  get_help: "Help Request",
};

const FEEDBACK_TYPE_COLORS: Record<string, string> = {
  bug_report: "#ef4444",
  feature_request: "#b4cc00",
  get_help: "#3b82f6",
};

/**
 * Returns the human-readable label for a feedback type.
 * @param {string} type - Raw feedback type value
 * @return {string} Display label
 */
function feedbackTypeLabel(type: string): string {
  return FEEDBACK_TYPE_LABELS[type] ?? type;
}

/**
 * Returns the accent color for a feedback type.
 * @param {string} type - Raw feedback type value
 * @return {string} Hex color string
 */
function feedbackTypeColor(type: string): string {
  return FEEDBACK_TYPE_COLORS[type] ?? "#6b7280";
}

/**
 * Renders the admin notification email for a feedback submission.
 * @param {FeedbackAdminNotifyPayload} payload - Feedback document data
 * @return {TransactionalEmailRenderResult} Subject and rendered bodies
 */
export function renderFeedbackAdminNotifyEmail(
  payload: FeedbackAdminNotifyPayload
): TransactionalEmailRenderResult {
  const label = feedbackTypeLabel(payload.type);
  const color = feedbackTypeColor(payload.type);
  const subject = `Ascend Feedback: ${label}`;

  const escapedMessage = escapeHtml(payload.message);
  const escapedEmail = escapeHtml(payload.userEmail);
  const escapedUserId = escapeHtml(payload.userId);
  const escapedDevice = escapeHtml(payload.deviceModel);
  const escapedOs = escapeHtml(payload.osVersion);
  const escapedAppVersion = escapeHtml(payload.appVersion);
  const escapedBuild = escapeHtml(payload.buildNumber);
  const escapedFeedbackId = escapeHtml(payload.feedbackId);
  const escapedLabel = escapeHtml(label);

  const text = [
    `New ${label} from ${payload.userEmail}`,
    "",
    "Message:",
    payload.message,
    "",
    "---",
    `User: ${payload.userEmail} (${payload.userId})`,
    `Device: ${payload.deviceModel}, iOS ${payload.osVersion}`,
    `App: v${payload.appVersion} (${payload.buildNumber})`,
    `Feedback ID: ${payload.feedbackId}`,
  ].join("\n");

  // eslint-disable-next-line max-len
  const metaRow = (labelText: string, value: string): string => `<tr><td style="padding:6px 12px 6px 0;font-size:13px;color:#9ca3af;white-space:nowrap;vertical-align:top;">${labelText}</td><td style="padding:6px 0;font-size:13px;color:#374151;">${value}</td></tr>`;

  const html = [
    "<!doctype html>",
    // eslint-disable-next-line max-len
    "<html lang=\"en\"><body style=\"margin:0;padding:0;background:#f4f2eb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111111;\">",
    // eslint-disable-next-line max-len
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"background:#f4f2eb;padding:24px 12px;\"><tr><td align=\"center\">",
    // eslint-disable-next-line max-len
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"max-width:620px;background:#ffffff;border:1px solid rgba(17,17,17,0.08);border-radius:24px;overflow:hidden;\">",

    // Header
    // eslint-disable-next-line max-len
    "<tr><td style=\"background:#111111;padding:20px 28px;\"><span style=\"font-size:14px;color:#ffffff;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;\">Ascend Feedback</span></td></tr>",

    // Type badge + user
    "<tr><td style=\"padding:28px 28px 0;\">",
    // eslint-disable-next-line max-len
    `<span style="display:inline-block;padding:6px 14px;border-radius:8px;background:${color};color:#ffffff;font-size:12px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;">${escapedLabel}</span>`,
    // eslint-disable-next-line max-len
    `<p style="margin:14px 0 0;font-size:14px;color:#6b7280;">From <strong style="color:#111111;">${escapedEmail}</strong></p>`,
    "</td></tr>",

    // Message
    "<tr><td style=\"padding:20px 28px;\">",
    // eslint-disable-next-line max-len
    `<div style="padding:16px 20px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:12px;font-size:15px;line-height:1.65;color:#374151;white-space:pre-wrap;">${escapedMessage}</div>`,
    "</td></tr>",

    // Metadata
    "<tr><td style=\"padding:0 28px 28px;\">",
    // eslint-disable-next-line max-len
    "<table role=\"presentation\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"width:100%;\">",
    metaRow("User ID", escapedUserId),
    // eslint-disable-next-line max-len
    metaRow("Device", `${escapedDevice}, iOS ${escapedOs}`),
    // eslint-disable-next-line max-len
    metaRow("App Version", `v${escapedAppVersion} (${escapedBuild})`),
    metaRow("Feedback ID", escapedFeedbackId),
    "</table>",
    "</td></tr>",

    // Footer
    // eslint-disable-next-line max-len
    "<tr><td style=\"padding:0 28px 24px;\"><div style=\"border-top:1px solid rgba(17,17,17,0.08);padding-top:16px;text-align:center;\"><p style=\"margin:0;font-size:12px;color:#9ca3af;\">Reply to this email to respond directly to the user.</p></div></td></tr>",

    "</table></td></tr></table></body></html>",
  ].join("");

  return {html, subject, text};
}
