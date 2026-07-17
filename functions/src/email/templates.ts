import {
  getBetaInviteUrl,
  getMarketingWebsiteUrl,
  getTransactionalReplyToEmail,
} from "./config";
import type {
  EmailJobPayload,
  EmailRenderContext,
  EmptyEmailPayload,
  FeedbackAdminNotifyPayload,
  FirstAscentClaimedPayload,
  FirstClimbCompletedPayload,
  LeaderboardFirstPlacePayload,
  TransactionalEmailRenderResult,
  WaitlistWelcomePayload,
} from "./types";

const BRAND_ACCENT_COLOR = "#86D30A";

interface BrandedEmailContent {
  bodyParagraphs: string[];
  ctaLabel: string;
  ctaUrl?: string;
  eyebrow: string;
  headline: string;
  preheader: string;
  subject: string;
  unsubscribeUrl?: string | null;
  whyReceived: string;
}

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
 * Checks whether an unknown payload is a plain object.
 * @param {unknown} value - Unknown payload
 * @return {boolean} True when value is object-like
 */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

/**
 * Normalizes a public HTTPS URL for email CTAs.
 * @param {unknown} value - Raw URL value
 * @return {string | null} Normalized URL or null
 */
function normalizeEmailUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.trim().length === 0) {
    return null;
  }

  try {
    const url = new URL(value.trim());
    if (url.protocol !== "https:") {
      return null;
    }

    url.hash = "";
    return url.toString().replace(/\/+$/, "");
  } catch {
    return null;
  }
}

/**
 * Returns a configured app URL or the marketing site fallback.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {string} CTA URL
 */
function appUrlFromPayload(payload: EmailJobPayload): string {
  if (isPlainObject(payload)) {
    const configuredUrl = normalizeEmailUrl(payload.appUrl);
    if (configuredUrl) {
      return configuredUrl;
    }
  }

  return getMarketingWebsiteUrl();
}

/**
 * Parses an optional lifecycle template payload.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {EmptyEmailPayload} Validated optional payload
 */
function parseEmptyEmailPayload(payload: EmailJobPayload): EmptyEmailPayload {
  if (!isPlainObject(payload)) {
    return {};
  }

  const appUrl = normalizeEmailUrl(payload.appUrl);
  return appUrl ? {appUrl} : {};
}

/**
 * Reads a required string from a stored template payload.
 * @param {Record<string, unknown>} payload - Stored job payload
 * @param {string} key - Payload key
 * @param {string} errorCode - Error to throw when invalid
 * @return {string} Trimmed string
 */
function requiredString(
  payload: Record<string, unknown>,
  key: string,
  errorCode: string
): string {
  const value = payload[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(errorCode);
  }

  return value.trim();
}

/**
 * Reads a required HTTPS URL from a stored template payload.
 * @param {Record<string, unknown>} payload - Stored job payload
 * @param {string} key - Payload key
 * @param {string} errorCode - Error to throw when invalid
 * @return {string} Normalized URL
 */
function requiredUrl(
  payload: Record<string, unknown>,
  key: string,
  errorCode: string
): string {
  const value = normalizeEmailUrl(payload[key]);
  if (!value) {
    throw new Error(errorCode);
  }

  return value;
}

/**
 * Builds a mailto URL for reply-first lifecycle emails.
 * @param {string} subject Original email subject
 * @return {string} Mailto URL
 */
function replyCtaUrl(subject: string): string {
  const replyTo = getTransactionalReplyToEmail();
  const replySubject = encodeURIComponent(`Re: ${subject}`);
  return `mailto:${replyTo}?subject=${replySubject}`;
}

/**
 * Renders the shared customer-facing transactional email layout.
 * @param {BrandedEmailContent} content - Template content
 * @return {TransactionalEmailRenderResult} Rendered email
 */
function renderBrandedEmail(
  content: BrandedEmailContent
): TransactionalEmailRenderResult {
  const websiteUrl = getMarketingWebsiteUrl();
  const iconUrl = `${websiteUrl}/images/ascend-a-icon.png`;
  const privacyPolicyUrl = `${websiteUrl}/privacy`;
  const escapedIconUrl = escapeHtml(iconUrl);
  const escapedPrivacyPolicyUrl = escapeHtml(privacyPolicyUrl);
  const ctaUrl = content.ctaUrl ?? replyCtaUrl(content.subject);
  const escapedCtaUrl = escapeHtml(ctaUrl);
  const unsubscribeUrl = content.unsubscribeUrl ?? null;
  const escapedBody = content.bodyParagraphs.map((paragraph) =>
    escapeHtml(paragraph)
  );

  const text = [
    content.preheader,
    "",
    content.headline,
    "",
    ...content.bodyParagraphs.flatMap((paragraph) => [paragraph, ""]),
    `${content.ctaLabel}: ${ctaUrl}`,
    "",
    content.whyReceived,
    `Privacy Policy: ${privacyPolicyUrl}`,
    ...(unsubscribeUrl ? [`Unsubscribe: ${unsubscribeUrl}`] : []),
  ].join("\n");

  const bodyHtml = escapedBody.map((paragraph) => [
    // eslint-disable-next-line max-len
    "<p style=\"margin:0 0 18px;font-size:17px;line-height:1.65;color:#4b5563;max-width:500px;\">",
    paragraph,
    "</p>",
  ].join("")).join("");

  const footerLinksHtml = [
    "<a href=\"",
    escapedPrivacyPolicyUrl,
    "\" style=\"color:#6b7280;text-decoration:underline;\">Privacy Policy</a>",
    ...(unsubscribeUrl ? [
      "<span style=\"color:#9ca3af;\"> &middot; </span><a href=\"",
      escapeHtml(unsubscribeUrl),
      // eslint-disable-next-line max-len
      "\" style=\"color:#6b7280;text-decoration:underline;\">Unsubscribe</a>",
    ] : []),
  ].join("");

  const ctaHtml = [
    "<a href=\"",
    escapedCtaUrl,
    // eslint-disable-next-line max-len
    "\" style=\"display:inline-block;padding:18px 24px;border-radius:16px;background:",
    BRAND_ACCENT_COLOR,
    ";color:#111111;font-size:16px;line-height:1;font-weight:800;",
    "text-decoration:none;text-transform:uppercase;letter-spacing:0.04em;\">",
    escapeHtml(content.ctaLabel),
    "</a>",
  ].join("");

  return {
    subject: content.subject,
    text,
    html: [
      "<!doctype html>",
      // eslint-disable-next-line max-len
      "<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\"><body style=\"margin:0;padding:0;background:#f4f2eb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111111;\">",
      // eslint-disable-next-line max-len
      "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;\">",
      escapeHtml(content.preheader),
      "</div>",
      // eslint-disable-next-line max-len
      "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"background:#f4f2eb;padding:24px 12px;\"><tr><td align=\"center\">",
      // eslint-disable-next-line max-len
      "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"max-width:620px;background:#ffffff;border:1px solid rgba(17,17,17,0.08);border-radius:28px;overflow:hidden;\">",
      // eslint-disable-next-line max-len
      "<tr><td style=\"background:#111111;padding:24px 30px;\"><table role=\"presentation\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\"><tr><td valign=\"middle\" style=\"padding-right:12px;\"><img src=\"",
      escapedIconUrl,
      // eslint-disable-next-line max-len
      "\" width=\"38\" height=\"38\" alt=\"Ascend icon\" style=\"display:block;width:38px;height:38px;border:0;border-radius:9px;\" /></td><td valign=\"middle\" style=\"font-size:15px;line-height:1;color:#ffffff;font-weight:800;letter-spacing:0.08em;text-transform:uppercase;\">Ascend</td></tr></table></td></tr>",
      "<tr><td style=\"padding:36px 30px 26px;\">",
      // eslint-disable-next-line max-len
      "<p style=\"margin:0 0 16px;font-size:12px;line-height:1.3;color:",
      BRAND_ACCENT_COLOR,
      ";font-weight:700;letter-spacing:0.22em;text-transform:uppercase;\">",
      escapeHtml(content.eyebrow),
      "</p>",
      // eslint-disable-next-line max-len
      "<h1 style=\"margin:0 0 20px;font-size:42px;line-height:1.02;font-weight:900;letter-spacing:-0.03em;color:#111111;\">",
      escapeHtml(content.headline),
      "</h1>",
      bodyHtml,
      "<div style=\"padding-top:10px;text-align:center;\">",
      ctaHtml,
      "</div></td></tr>",
      // eslint-disable-next-line max-len
      "<tr><td style=\"padding:0 30px 34px;\"><div style=\"border-top:1px solid rgba(17,17,17,0.08);padding-top:22px;text-align:center;\"><p style=\"margin:0 0 10px;font-size:13px;line-height:1.6;color:#9ca3af;\">",
      escapeHtml(content.whyReceived),
      // eslint-disable-next-line max-len
      "</p><p style=\"margin:0 0 10px;font-size:13px;line-height:1.6;color:#9ca3af;\">Need help? Reply to this email.</p><p style=\"margin:0;font-size:13px;line-height:1.6;\">",
      footerLinksHtml,
      "</p></div></td></tr>",
      "</table></td></tr></table></body></html>",
    ].join(""),
  };
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
    !isPlainObject(payload) ||
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
      "<tr><td style=\"padding:40px 32px 24px;\"><p style=\"margin:0 0 18px;font-size:12px;line-height:1.3;color:",
      BRAND_ACCENT_COLOR,
      ";font-weight:700;letter-spacing:0.28em;text-transform:uppercase;\">",
      eyebrow,
      "</p>",
      // eslint-disable-next-line max-len
      "<h1 style=\"margin:0 0 20px;font-size:58px;line-height:0.94;font-weight:900;letter-spacing:-0.04em;color:#111111;\">",
      headlineLeading,
      "<br /><span style=\"color:",
      BRAND_ACCENT_COLOR,
      ";\">",
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
      "\" style=\"display:inline-block;padding:20px 28px;border-radius:18px;background:",
      BRAND_ACCENT_COLOR,
      ";color:#111111;font-size:18px;line-height:1;font-weight:800;",
      "text-decoration:none;text-transform:uppercase;letter-spacing:0.04em;\">",
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
// App-Triggered Customer Templates
// =============================================================================

/**
 * Renders the positive rating follow-up email.
 * @param {EmptyEmailPayload} payload - Optional template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderRatingPositiveFollowupEmail(
  payload: EmptyEmailPayload = {},
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  void payload;

  return renderBrandedEmail({
    unsubscribeUrl: context.unsubscribeUrl,
    subject: "Thanks for climbing with Ascend",
    preheader: "Your feedback helps shape what we build next.",
    eyebrow: "Founder Note",
    headline: "KEEP PUSHING ASCEND.",
    bodyParagraphs: [
      "Tyler here. Thanks for climbing with Ascend.",
      [
        "If Ascend is making your stair-stepper work more competitive,",
        "reply with what you want next. More climbs, harder goals,",
        "better routines, leaderboard filters - I read every reply.",
      ].join(" "),
    ],
    ctaLabel: "Reply with feedback",
    whyReceived: [
      "You received this because you answered yes to Ascend's",
      "in-app enjoyment prompt.",
    ].join(" "),
  });
}

/**
 * Validates and renders the positive rating follow-up email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderRatingPositiveFollowupEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderRatingPositiveFollowupEmail(
    parseEmptyEmailPayload(payload),
    context
  );
}

/**
 * Renders the negative rating feedback email.
 * @param {EmptyEmailPayload} payload - Optional template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderRatingNegativeFeedbackEmail(
  payload: EmptyEmailPayload = {},
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  void payload;

  return renderBrandedEmail({
    unsubscribeUrl: context.unsubscribeUrl,
    subject: "Tell me what missed",
    preheader: "One reply helps make Ascend better.",
    eyebrow: "Founder Note",
    headline: "TELL ME WHAT MISSED.",
    bodyParagraphs: [
      "Tyler here. Ascend missed for you, and I want to know where.",
      [
        "Reply with the part that felt off: climb tracking, leaderboards,",
        "routines, onboarding, paywall, design, or anything else.",
        "Short is fine.",
      ].join(" "),
    ],
    ctaLabel: "Reply with what missed",
    whyReceived: [
      "You received this because you answered no to Ascend's",
      "in-app enjoyment prompt.",
    ].join(" "),
  });
}

/**
 * Validates and renders the negative rating feedback email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderRatingNegativeFeedbackEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderRatingNegativeFeedbackEmail(
    parseEmptyEmailPayload(payload),
    context
  );
}

/**
 * Renders the onboarding abandonment email before paywall.
 * @param {EmptyEmailPayload} payload - Optional template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderOnboardingAbandonedBeforePaywallEmail(
  payload: EmptyEmailPayload = {},
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  const appUrl = appUrlFromPayload(payload);

  return renderBrandedEmail({
    unsubscribeUrl: context.unsubscribeUrl,
    subject: "Your first climb is waiting",
    preheader: "Pick a landmark. Put your steps on the board.",
    eyebrow: "First Climb",
    headline: "PICK THE CLIMB.",
    bodyParagraphs: [
      "You started Ascend but did not pick your first climb.",
      "Choose a landmark, start stepping, and put a real result on the board.",
    ],
    ctaLabel: "Start your first climb",
    ctaUrl: appUrl,
    whyReceived: [
      "You received this because onboarding started and your first",
      "Ascend climb is still unfinished.",
    ].join(" "),
  });
}

/**
 * Validates and renders the onboarding abandonment email before paywall.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderOnboardingAbandonedBeforePaywallEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderOnboardingAbandonedBeforePaywallEmail(
    parseEmptyEmailPayload(payload),
    context
  );
}

/**
 * Renders the onboarding abandonment email after paywall.
 * @param {EmptyEmailPayload} payload - Optional template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderOnboardingAbandonedAfterPaywallEmail(
  payload: EmptyEmailPayload = {},
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  const appUrl = appUrlFromPayload(payload);

  return renderBrandedEmail({
    unsubscribeUrl: context.unsubscribeUrl,
    subject: "Race real climbs",
    preheader: [
      "Leaderboards, First Ascents, and stair-stepper records",
      "live inside Ascend.",
    ].join(" "),
    eyebrow: "Race The Board",
    headline: "RACE REAL CLIMBS.",
    bodyParagraphs: [
      [
        "Ascend turns stair-stepper sessions into climbs, ranks,",
        "and permanent records.",
      ].join(" "),
      "Start with one landmark. Race the board from there.",
    ],
    ctaLabel: "Start climbing",
    ctaUrl: appUrl,
    whyReceived: [
      "You received this because you reached Ascend onboarding but",
      "have not finished the first-climb setup.",
    ].join(" "),
  });
}

/**
 * Validates and renders the onboarding abandonment email after paywall.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderOnboardingAbandonedAfterPaywallEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderOnboardingAbandonedAfterPaywallEmail(
    parseEmptyEmailPayload(payload),
    context
  );
}

/**
 * Parses the first climb completed template payload.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {FirstClimbCompletedPayload} Validated payload
 */
function parseFirstClimbCompletedPayload(
  payload: EmailJobPayload
): FirstClimbCompletedPayload {
  if (!isPlainObject(payload)) {
    throw new Error("invalid_first_climb_completed_payload");
  }

  const climbName = typeof payload.climbName === "string" ?
    payload.climbName.trim() :
    "";

  return {
    climbName: climbName.length > 0 ? climbName : undefined,
    resultUrl: requiredUrl(
      payload,
      "resultUrl",
      "invalid_first_climb_completed_payload"
    ),
  };
}

/**
 * Renders the first climb completed email.
 * @param {FirstClimbCompletedPayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderFirstClimbCompletedEmail(
  payload: FirstClimbCompletedPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  const resultLine = payload.climbName ?
    `Your first Ascend climb, ${payload.climbName}, is logged.` :
    "Your first Ascend climb is logged.";

  return renderBrandedEmail({
    unsubscribeUrl: context.unsubscribeUrl,
    subject: "First climb logged",
    preheader: "Your stair-stepper work is on the board.",
    eyebrow: "First Result",
    headline: "FIRST CLIMB LOGGED.",
    bodyParagraphs: [
      resultLine,
      "Now you have a rank to beat, a history to build, and a board to climb.",
    ],
    ctaLabel: "View your result",
    ctaUrl: payload.resultUrl,
    whyReceived: [
      "You received this because your first eligible Ascend Live Climb",
      "was completed.",
    ].join(" "),
  });
}

/**
 * Validates and renders the first climb completed email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderFirstClimbCompletedEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderFirstClimbCompletedEmail(
    parseFirstClimbCompletedPayload(payload),
    context
  );
}

/**
 * Parses the First Ascent claimed template payload.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {FirstAscentClaimedPayload} Validated payload
 */
function parseFirstAscentClaimedPayload(
  payload: EmailJobPayload
): FirstAscentClaimedPayload {
  if (!isPlainObject(payload)) {
    throw new Error("invalid_first_ascent_claimed_payload");
  }

  return {
    climbName: requiredString(
      payload,
      "climbName",
      "invalid_first_ascent_claimed_payload"
    ),
    climbUrl: requiredUrl(
      payload,
      "climbUrl",
      "invalid_first_ascent_claimed_payload"
    ),
  };
}

/**
 * Renders the First Ascent claimed email.
 * @param {FirstAscentClaimedPayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderFirstAscentClaimedEmail(
  payload: FirstAscentClaimedPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderBrandedEmail({
    unsubscribeUrl: context.unsubscribeUrl,
    subject: "You claimed it first",
    preheader: "That First Ascent is yours.",
    eyebrow: "First Ascent",
    headline: "YOU CLAIMED IT FIRST.",
    bodyParagraphs: [
      `You were first up ${payload.climbName}.`,
      [
        "That First Ascent stays on the climb.",
        "Keep climbing before the board fills in behind you.",
      ].join(" "),
    ],
    ctaLabel: "View the climb",
    ctaUrl: payload.climbUrl,
    whyReceived: [
      "You received this because Ascend confirmed you were the first",
      "valid finisher on this climb.",
    ].join(" "),
  });
}

/**
 * Validates and renders the First Ascent claimed email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderFirstAscentClaimedEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderFirstAscentClaimedEmail(
    parseFirstAscentClaimedPayload(payload),
    context
  );
}

/**
 * Parses the leaderboard first place template payload.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {LeaderboardFirstPlacePayload} Validated payload
 */
function parseLeaderboardFirstPlacePayload(
  payload: EmailJobPayload
): LeaderboardFirstPlacePayload {
  if (!isPlainObject(payload)) {
    throw new Error("invalid_leaderboard_first_place_payload");
  }

  return {
    leaderboardName: requiredString(
      payload,
      "leaderboardName",
      "invalid_leaderboard_first_place_payload"
    ),
    leaderboardUrl: requiredUrl(
      payload,
      "leaderboardUrl",
      "invalid_leaderboard_first_place_payload"
    ),
  };
}

/**
 * Renders the leaderboard first place email.
 * @param {LeaderboardFirstPlacePayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderLeaderboardFirstPlaceEmail(
  payload: LeaderboardFirstPlacePayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderBrandedEmail({
    unsubscribeUrl: context.unsubscribeUrl,
    subject: "You own the board",
    preheader: "You moved into #1.",
    eyebrow: "Leaderboard",
    headline: "YOU OWN THE BOARD.",
    bodyParagraphs: [
      `You moved into #1 on ${payload.leaderboardName}.`,
      "The board is yours until someone climbs past you. Defend it.",
    ],
    ctaLabel: "View leaderboard",
    ctaUrl: payload.leaderboardUrl,
    whyReceived: [
      "You received this because Ascend confirmed you reached #1",
      "on this leaderboard.",
    ].join(" "),
  });
}

/**
 * Validates and renders the leaderboard first place email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderLeaderboardFirstPlaceEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderLeaderboardFirstPlaceEmail(
    parseLeaderboardFirstPlacePayload(payload),
    context
  );
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
  feature_request: BRAND_ACCENT_COLOR,
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
