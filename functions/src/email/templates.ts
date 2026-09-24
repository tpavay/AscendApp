import {
  getMarketingWebsiteUrl,
  getTransactionalReplyToEmail,
} from "./config";
import {escapeHtml} from "./html";
import type {
  EmailJobPayload,
  EmailRenderContext,
  EmptyEmailPayload,
  FeedbackAdminNotifyPayload,
  FirstAscentClaimedPayload,
  FirstClimbCompletedPayload,
  LeaderboardFirstPlacePayload,
  RecapActivePayload,
  RecapCalendarCell,
  RecapDeltaChip,
  RecapInactivePayload,
  TransactionalEmailRenderResult,
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
 * Reads an optional, non-empty string from a stored template payload.
 * @param {Record<string, unknown>} payload - Stored job payload
 * @param {string} key - Payload key
 * @return {string | undefined} Trimmed string, when present
 */
function optionalString(
  payload: Record<string, unknown>,
  key: string
): string | undefined {
  const value = payload[key];
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    undefined;
}

/**
 * Reads a required finite number from a stored template payload.
 * @param {Record<string, unknown>} payload - Stored job payload
 * @param {string} key - Payload key
 * @param {string} errorCode - Error to throw when invalid
 * @return {number} The number
 */
function requiredNumber(
  payload: Record<string, unknown>,
  key: string,
  errorCode: string
): number {
  const value = payload[key];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(errorCode);
  }
  return value;
}

/**
 * Reads an optional finite number from a stored template payload.
 * @param {Record<string, unknown>} payload - Stored job payload
 * @param {string} key - Payload key
 * @return {number | undefined} The number, when present
 */
function optionalNumber(
  payload: Record<string, unknown>,
  key: string
): number | undefined {
  const value = payload[key];
  return typeof value === "number" && Number.isFinite(value) ?
    value :
    undefined;
}

/**
 * Reads a string array from a stored template payload, dropping anything
 * that is not a non-empty string rather than rejecting the whole email.
 * @param {Record<string, unknown>} payload - Stored job payload
 * @param {string} key - Payload key
 * @return {string[]} Non-empty trimmed strings
 */
function stringArray(payload: Record<string, unknown>, key: string): string[] {
  const value = payload[key];
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((entry): entry is string =>
      typeof entry === "string" && entry.trim().length > 0)
    .map((entry) => entry.trim());
}

/**
 * Formats a count with thousands separators for recap copy.
 * @param {number} value - Raw count
 * @return {string} Locale-formatted count
 */
function formatCount(value: number): string {
  return Math.max(0, Math.round(value)).toLocaleString("en-US");
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
      "\" style=\"color:#6b7280;text-decoration:underline;\">Unsubscribe</a>",
    ] : []),
  ].join("");

  const ctaHtml = [
    "<a href=\"",
    escapedCtaUrl,
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
      "<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\"><body style=\"margin:0;padding:0;background:#f4f2eb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111111;\">",
      "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;\">",
      escapeHtml(content.preheader),
      "</div>",
      "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"background:#f4f2eb;padding:24px 12px;\"><tr><td align=\"center\">",
      "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"max-width:620px;background:#ffffff;border:1px solid rgba(17,17,17,0.08);border-radius:28px;overflow:hidden;\">",
      "<tr><td style=\"background:#111111;padding:24px 30px;\"><table role=\"presentation\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\"><tr><td valign=\"middle\" style=\"padding-right:12px;\"><img src=\"",
      escapedIconUrl,
      "\" width=\"38\" height=\"38\" alt=\"Ascend icon\" style=\"display:block;width:38px;height:38px;border:0;border-radius:9px;\" /></td><td valign=\"middle\" style=\"font-size:15px;line-height:1;color:#ffffff;font-weight:800;letter-spacing:0.08em;text-transform:uppercase;\">Ascend</td></tr></table></td></tr>",
      "<tr><td style=\"padding:36px 30px 26px;\">",
      "<p style=\"margin:0 0 16px;font-size:12px;line-height:1.3;color:",
      BRAND_ACCENT_COLOR,
      ";font-weight:700;letter-spacing:0.22em;text-transform:uppercase;\">",
      escapeHtml(content.eyebrow),
      "</p>",
      "<h1 style=\"margin:0 0 20px;font-size:42px;line-height:1.02;font-weight:900;letter-spacing:-0.03em;color:#111111;\">",
      escapeHtml(content.headline),
      "</h1>",
      bodyHtml,
      "<div style=\"padding-top:10px;text-align:center;\">",
      ctaHtml,
      "</div></td></tr>",
      "<tr><td style=\"padding:0 30px 34px;\"><div style=\"border-top:1px solid rgba(17,17,17,0.08);padding-top:22px;text-align:center;\"><p style=\"margin:0 0 10px;font-size:13px;line-height:1.6;color:#9ca3af;\">",
      escapeHtml(content.whyReceived),
      "</p><p style=\"margin:0 0 10px;font-size:13px;line-height:1.6;color:#9ca3af;\">Need help? Reply to this email.</p><p style=\"margin:0;font-size:13px;line-height:1.6;\">",
      footerLinksHtml,
      "</p></div></td></tr>",
      "</table></td></tr></table></body></html>",
    ].join(""),
  };
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
// Weekly / Monthly Recap
//
// Bespoke dark-themed layout (captain, 2026-09-24, Wispr-Flow-inspired
// structure in Ascend's own brand - dark, green accent, no borrowed colors,
// mascot, or copy). Does not use renderBrandedEmail's light card layout: a
// bold editorial hero with an optional milestone callout, a percentile/rank
// callout, stat cards with green "up only" delta chips, and a per-day
// activity calendar heatmap. Copy is past tense throughout ("last week" /
// "last month") since every send lands after the period it describes has
// closed.
// =============================================================================

const RECAP_BG = "#0c0e10";
const RECAP_CARD_BG = "#1c1f22";
const RECAP_BORDER = "rgba(255,255,255,0.10)";
const RECAP_ACCENT_BORDER = "rgba(134,211,10,0.35)";
const RECAP_TEXT = "#f5f5f5";
const RECAP_TEXT_MUTED = "#9aa0a6";
const RECAP_CHIP_BG = "rgba(134,211,10,0.16)";
const RECAP_CAL_NONE = "#1f2226";
const RECAP_CAL_ACTIVE = "#2f4c14";
const RECAP_ON_ACCENT_TEXT = "#0c0e10";

interface RecapCadenceCopy {
  ctaLabel: string;
  eyebrow: string;
  headlineAccent: string;
  headlineLead: string;
  inactiveHeadline: string;
  periodNoun: string;
  reviewHeading: string;
  subject: string;
  subjectInactive: string;
  whyReceivedActive: string;
  whyReceivedInactive: string;
}

const WEEKLY_RECAP_COPY: RecapCadenceCopy = {
  ctaLabel: "Open Ascend",
  eyebrow: "Weekly Recap",
  headlineAccent: "ON THE STAIRSTEPPER.",
  headlineLead: "YOUR WEEK",
  inactiveHeadline: "THE BOARD MISSED YOU.",
  periodNoun: "last week",
  reviewHeading: "Your week in review",
  subject: "Your week on the board",
  subjectInactive: "A climb is waiting",
  whyReceivedActive: "You received this because Ascend sends climbers a " +
    "weekly recap of their climbs.",
  whyReceivedInactive: "You received this because a week passed with no " +
    "Ascend climbs on your account.",
};

const MONTHLY_RECAP_COPY: RecapCadenceCopy = {
  ctaLabel: "Open Ascend",
  eyebrow: "Monthly Recap",
  headlineAccent: "ON THE STAIRSTEPPER.",
  headlineLead: "YOUR MONTH",
  inactiveHeadline: "THE BOARD IS STILL THERE.",
  periodNoun: "last month",
  reviewHeading: "Your month in review",
  subject: "Your month on the board",
  subjectInactive: "Still time to climb this month",
  whyReceivedActive: "You received this because Ascend sends climbers a " +
    "monthly recap of their climbs.",
  whyReceivedInactive: "You received this because a month passed with no " +
    "Ascend climbs on your account.",
};

/**
 * Parses a recap payload shared by an active climber's weekly or monthly
 * email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {string} errorCode - Error to throw when invalid
 * @return {RecapActivePayload} Validated payload
 */
function parseRecapActivePayload(
  payload: EmailJobPayload,
  errorCode: string
): RecapActivePayload {
  if (!isPlainObject(payload)) {
    throw new Error(errorCode);
  }

  return {
    achievementLabel: optionalString(payload, "achievementLabel"),
    calendar: calendarArray(payload.calendar),
    climbsCompleted: requiredNumber(payload, "climbsCompleted", errorCode),
    climbsDelta: parseDeltaChip(payload.climbsDelta),
    ctaUrl: requiredUrl(payload, "ctaUrl", errorCode),
    currentStreakWeeks: optionalNumber(payload, "currentStreakWeeks"),
    fieldSize: optionalNumber(payload, "fieldSize"),
    floorsDelta: parseDeltaChip(payload.floorsDelta),
    landmarksFinished: stringArray(payload, "landmarksFinished"),
    milestoneText: optionalString(payload, "milestoneText"),
    percentileBand: optionalString(payload, "percentileBand"),
    periodLabel: requiredString(payload, "periodLabel", errorCode),
    rank: optionalNumber(payload, "rank"),
    stepsDelta: parseDeltaChip(payload.stepsDelta),
    totalFloors: requiredNumber(payload, "totalFloors", errorCode),
    totalSteps: requiredNumber(payload, "totalSteps", errorCode),
  };
}

/**
 * Parses a recap payload shared by a zero-activity climber's re-engagement
 * email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {string} errorCode - Error to throw when invalid
 * @return {RecapInactivePayload} Validated payload
 */
function parseRecapInactivePayload(
  payload: EmailJobPayload,
  errorCode: string
): RecapInactivePayload {
  if (!isPlainObject(payload)) {
    throw new Error(errorCode);
  }

  return {
    ctaUrl: requiredUrl(payload, "ctaUrl", errorCode),
    periodLabel: requiredString(payload, "periodLabel", errorCode),
    suggestedClimbName: optionalString(payload, "suggestedClimbName"),
  };
}

/**
 * Parses a stored delta chip, dropping anything that does not carry every
 * field an "up" chip needs.
 * @param {unknown} value - Raw stored field
 * @return {RecapDeltaChip | undefined} The chip, when it parses
 */
function parseDeltaChip(value: unknown): RecapDeltaChip | undefined {
  if (!isPlainObject(value) || value.direction !== "up") {
    return undefined;
  }
  const label = typeof value.label === "string" ? value.label : "";
  const chipValue = typeof value.value === "string" ? value.value : "";
  return label && chipValue ? {direction: "up", label, value: chipValue} : undefined;
}

/**
 * Parses a stored calendar cell array, dropping anything malformed rather
 * than failing the whole render.
 * @param {unknown} value - Raw stored field
 * @return {RecapCalendarCell[]} Parsed calendar cells
 */
function calendarArray(value: unknown): RecapCalendarCell[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const cells: RecapCalendarCell[] = [];
  for (const entry of value) {
    if (!isPlainObject(entry)) {
      continue;
    }
    const level = entry.level;
    if (level !== "blank" && level !== "none" && level !== "active" &&
      level !== "peak") {
      continue;
    }
    const dayOfMonth = typeof entry.dayOfMonth === "number" ?
      entry.dayOfMonth :
      null;
    cells.push({dayOfMonth, level});
  }
  return cells;
}

/**
 * Renders one stat card's inline styles.
 * @param {string} value - Big headline number
 * @param {string} label - Caption below the number
 * @param {RecapDeltaChip | undefined} chip - Optional green delta chip
 * @return {string} Card HTML
 */
function renderStatCardHtml(
  value: string,
  label: string,
  chip: RecapDeltaChip | undefined
): string {
  const chipHtml = chip ? [
    "<span style=\"display:inline-block;margin-top:10px;padding:4px 10px;",
    `border-radius:8px;background:${RECAP_CHIP_BG};color:`,
    `${BRAND_ACCENT_COLOR};font-size:12px;font-weight:700;">▲ `,
    `${escapeHtml(chip.value)} ${escapeHtml(chip.label)}</span>`,
  ].join("") : [
    // Reserves the chip's height so a chip-less card matches its row-mate.
    "<span aria-hidden=\"true\" style=\"display:inline-block;",
    "margin-top:10px;padding:4px 10px;font-size:12px;visibility:hidden;\">",
    "&nbsp;</span>",
  ].join("");

  return [
    `<div style="border:1px solid ${RECAP_BORDER};border-radius:16px;`,
    `padding:18px;background:${RECAP_CARD_BG};">`,
    `<p style="margin:0;font-size:28px;font-weight:800;color:${RECAP_TEXT};`,
    `line-height:1.1;">${escapeHtml(value)}</p>`,
    `<p style="margin:6px 0 0;font-size:13px;color:${RECAP_TEXT_MUTED};">`,
    `${escapeHtml(label)}</p>`,
    chipHtml,
    "</div>",
  ].join("");
}

/**
 * Renders the 2x2 stat card grid as an email-safe table.
 * @param {Array<[string, string, RecapDeltaChip | undefined]>} cards -
 *   Exactly four (value, label, chip) tuples
 * @return {string} Grid HTML
 */
function renderStatGridHtml(
  cards: Array<[string, string, RecapDeltaChip | undefined]>
): string {
  // The gutter sits between the two cards only, so the outer edges stay
  // flush with the milestone and percentile boxes above the grid.
  const cell = (
    card: [string, string, RecapDeltaChip | undefined],
    padding: string
  ): string =>
    `<td width="50%" style="padding:${padding};vertical-align:top;">` +
    `${renderStatCardHtml(card[0], card[1], card[2])}</td>`;
  const left = (card: [string, string, RecapDeltaChip | undefined]) =>
    cell(card, "0 8px 16px 0");
  const right = (card: [string, string, RecapDeltaChip | undefined]) =>
    cell(card, "0 0 16px 8px");

  return [
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" ",
    "cellpadding=\"0\" border=\"0\"><tr>",
    left(cards[0]),
    right(cards[1]),
    "</tr><tr>",
    left(cards[2]),
    right(cards[3]),
    "</tr></table>",
  ].join("");
}

/**
 * Renders one calendar day cell.
 * @param {RecapCalendarCell} cell - Cell to render
 * @return {string} Cell HTML
 */
function renderCalendarCellHtml(cell: RecapCalendarCell): string {
  if (cell.level === "blank") {
    return "<td style=\"padding:3px;\"></td>";
  }
  const background = cell.level === "peak" ?
    BRAND_ACCENT_COLOR :
    cell.level === "active" ? RECAP_CAL_ACTIVE : RECAP_CAL_NONE;
  const textColor = cell.level === "peak" ? RECAP_ON_ACCENT_TEXT : RECAP_TEXT;
  return [
    "<td style=\"padding:3px;\"><div style=\"background:",
    background,
    ";border-radius:8px;padding:8px 0;text-align:center;font-size:12px;",
    "font-weight:700;color:",
    textColor,
    ";\">",
    String(cell.dayOfMonth ?? ""),
    "</div></td>",
  ].join("");
}

/**
 * Renders the activity calendar heatmap table plus its legend.
 * @param {RecapCalendarCell[]} cells - Calendar cells, Monday-aligned
 * @return {string} Calendar HTML, or an empty string with no cells
 */
function renderCalendarHtml(cells: RecapCalendarCell[]): string {
  if (cells.length === 0) {
    return "";
  }

  const weekdayHeader = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    .map((day) => "<td style=\"padding:0 3px 8px;text-align:center;" +
      `font-size:11px;font-weight:700;color:${RECAP_TEXT_MUTED};">` +
      `${day}</td>`)
    .join("");

  const weekRows: string[] = [];
  for (let i = 0; i < cells.length; i += 7) {
    const week = cells.slice(i, i + 7).map(renderCalendarCellHtml).join("");
    weekRows.push(`<tr>${week}</tr>`);
  }

  const legendSwatch = (color: string, label: string): string => [
    "<span style=\"display:inline-block;width:10px;height:10px;",
    `border-radius:3px;background:${color};margin-right:6px;`,
    "vertical-align:middle;\"></span>",
    `<span style="font-size:12px;color:${RECAP_TEXT_MUTED};`,
    "margin-right:16px;vertical-align:middle;\">",
    label,
    "</span>",
  ].join("");

  return [
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" ",
    "cellpadding=\"0\" border=\"0\"><tr>",
    weekdayHeader,
    "</tr>",
    weekRows.join(""),
    "</table>",
    "<p style=\"margin:14px 0 0;\">",
    legendSwatch(BRAND_ACCENT_COLOR, "Peak day"),
    legendSwatch(RECAP_CAL_ACTIVE, "Active"),
    legendSwatch(RECAP_CAL_NONE, "No activity"),
    "</p>",
  ].join("");
}

/**
 * Renders the milestone-unlocked outlined callout, when there is one.
 * @param {string | undefined} milestoneText - Milestone sentence
 * @return {string} Callout HTML, or an empty string with no milestone
 */
function renderMilestoneCalloutHtml(milestoneText: string | undefined): string {
  if (!milestoneText) {
    return "";
  }
  return [
    `<div style="margin-top:24px;border:1px solid ${RECAP_ACCENT_BORDER};`,
    "border-radius:16px;padding:16px 20px;\">",
    "<p style=\"margin:0 0 6px;font-size:11px;letter-spacing:0.16em;",
    `text-transform:uppercase;color:${BRAND_ACCENT_COLOR};font-weight:700;">`,
    "Milestone unlocked</p>",
    `<p style="margin:0;font-size:15px;line-height:1.5;color:${RECAP_TEXT};`,
    `font-weight:600;">${escapeHtml(milestoneText)}</p>`,
    "</div>",
  ].join("");
}

/**
 * Renders the hero's lead metric (round 3): the climber's concrete rank AND
 * percentile shown together, whenever the field is large enough for a rank
 * to mean anything. The rank is always stated exactly; the percentile band
 * is an optional badge alongside it, since not every rank reaches one.
 * @param {number | undefined} rank - This climber's rank in the closed
 *   period
 * @param {number | undefined} fieldSize - Total climbers ranked
 * @param {string | undefined} band - Percentile band ("Top N%"), if earned
 * @return {string} Callout HTML, or an empty string with no rankable field
 */
function renderRankHeroHtml(
  rank: number | undefined,
  fieldSize: number | undefined,
  band: string | undefined
): string {
  if (rank === undefined || fieldSize === undefined || fieldSize <= 1) {
    return "";
  }
  const bandBadgeHtml = band ? [
    "<span style=\"display:inline-block;margin-top:12px;padding:6px 14px;",
    `border-radius:999px;background:${BRAND_ACCENT_COLOR};color:`,
    `${RECAP_ON_ACCENT_TEXT};font-size:13px;font-weight:800;">`,
    escapeHtml(band),
    "</span>",
  ].join("") : "";

  return [
    `<div style="margin-top:24px;border:1px solid ${RECAP_ACCENT_BORDER};`,
    "border-radius:20px;padding:26px 20px;text-align:center;background:",
    "rgba(134,211,10,0.06);\">",
    "<p style=\"margin:0 0 8px;font-size:12px;letter-spacing:0.12em;",
    `text-transform:uppercase;color:${RECAP_TEXT_MUTED};">You ranked</p>`,
    `<p style="margin:0;font-size:30px;font-weight:900;color:${RECAP_TEXT};`,
    `letter-spacing:-0.01em;">#${rank} of ${fieldSize} climbers</p>`,
    bandBadgeHtml,
    "</div>",
  ].join("");
}

/**
 * Renders the achievement-earned outlined callout, when the climber earned
 * one of the app's existing tracked achievements for the period. A distinct
 * box from the milestone callout below it - this one names a permanent,
 * canonical record; the milestone callout is a same-email highlight.
 * @param {string | undefined} achievementLabel - Achievement label, if any
 * @return {string} Callout HTML, or an empty string with none
 */
function renderAchievementCalloutHtml(
  achievementLabel: string | undefined
): string {
  if (!achievementLabel) {
    return "";
  }
  return [
    `<div style="margin-top:16px;border:1px solid ${RECAP_ACCENT_BORDER};`,
    "border-radius:16px;padding:16px 20px;\">",
    "<p style=\"margin:0 0 6px;font-size:11px;letter-spacing:0.16em;",
    `text-transform:uppercase;color:${BRAND_ACCENT_COLOR};font-weight:700;">`,
    "Achievement earned</p>",
    `<p style="margin:0;font-size:15px;line-height:1.5;color:${RECAP_TEXT};`,
    `font-weight:600;">${escapeHtml(achievementLabel)}</p>`,
    "</div>",
  ].join("");
}

/**
 * Renders the shared dark outer shell every recap email uses.
 * @param {string} preheader - Hidden inbox-preview text
 * @param {string} bodyRowsHtml - `<tr>` rows for the card body
 * @return {string} Full HTML document
 */
function renderRecapShellHtml(preheader: string, bodyRowsHtml: string): string {
  const iconUrl = escapeHtml(`${getMarketingWebsiteUrl()}/images/ascend-a-icon.png`);
  return [
    "<!doctype html>",
    "<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\"><body style=",
    `"margin:0;padding:0;background:${RECAP_BG};font-family:-apple-system,`,
    `BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:${RECAP_TEXT};">`,
    "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;",
    "color:transparent;\">",
    escapeHtml(preheader),
    "</div>",
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" ",
    `cellpadding="0" border="0" style="background:${RECAP_BG};padding:24px `,
    "12px;\"><tr><td align=\"center\">",
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" ",
    "cellpadding=\"0\" border=\"0\" style=\"max-width:620px;background:",
    RECAP_BG,
    `;border:1px solid ${RECAP_BORDER};border-radius:28px;overflow:hidden;">`,
    "<tr><td style=\"background:#000000;padding:24px 30px;\"><table role=",
    "\"presentation\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\"><tr>",
    "<td valign=\"middle\" style=\"padding-right:12px;\"><img src=\"",
    iconUrl,
    "\" width=\"38\" height=\"38\" alt=\"Ascend icon\" style=\"display:",
    "block;width:38px;height:38px;border:0;border-radius:9px;\" /></td>",
    "<td valign=\"middle\" style=\"font-size:15px;line-height:1;color:",
    "#ffffff;font-weight:800;letter-spacing:0.08em;text-transform:",
    "uppercase;\">Ascend</td></tr></table></td></tr>",
    bodyRowsHtml,
    "</table></td></tr></table></body></html>",
  ].join("");
}

/**
 * Renders the footer row shared by every recap email.
 * @param {string} whyReceived - Why-received sentence
 * @param {string | null | undefined} unsubscribeUrl - Unsubscribe link
 * @return {string} Footer `<tr>` HTML
 */
function renderRecapFooterHtml(
  whyReceived: string,
  unsubscribeUrl: string | null | undefined
): string {
  const privacyPolicyUrl = escapeHtml(`${getMarketingWebsiteUrl()}/privacy`);
  const unsubscribeHtml = unsubscribeUrl ? [
    "<span style=\"color:#4b5054;\"> &middot; </span><a href=\"",
    escapeHtml(unsubscribeUrl),
    `" style="color:${RECAP_TEXT_MUTED};text-decoration:underline;">`,
    "Unsubscribe</a>",
  ].join("") : "";

  return [
    "<tr><td style=\"padding:8px 30px 34px;\"><div style=\"border-top:1px ",
    `solid ${RECAP_BORDER};padding-top:20px;text-align:center;">`,
    "<p style=\"margin:0 0 10px;font-size:12px;line-height:1.6;color:",
    `${RECAP_TEXT_MUTED};">${escapeHtml(whyReceived)}</p>`,
    "<p style=\"margin:0;font-size:12px;line-height:1.6;\"><a href=\"",
    privacyPolicyUrl,
    `" style="color:${RECAP_TEXT_MUTED};text-decoration:underline;">`,
    "Privacy Policy</a>",
    unsubscribeHtml,
    "</p></div></td></tr>",
  ].join("");
}

/**
 * Renders the CTA button HTML, shared by every recap email.
 * @param {string} label - Button label
 * @param {string} url - Button destination
 * @return {string} Button HTML
 */
function renderRecapCtaHtml(label: string, url: string): string {
  return [
    "<a href=\"",
    escapeHtml(url),
    "\" style=\"display:inline-block;padding:16px 26px;border-radius:16px;",
    `background:${BRAND_ACCENT_COLOR};color:${RECAP_ON_ACCENT_TEXT};`,
    "font-size:15px;font-weight:800;text-decoration:none;text-transform:",
    "uppercase;letter-spacing:0.04em;\">",
    escapeHtml(label),
    "</a>",
  ].join("");
}

/**
 * Builds the plain-text stat lines shared by both cadences' active recap.
 * @param {RecapActivePayload} payload - Validated recap payload
 * @return {string[]} Plain-text lines
 */
function buildRecapActiveTextLines(payload: RecapActivePayload): string[] {
  const chipText = (chip: RecapDeltaChip | undefined): string =>
    chip ? ` (up ${chip.value} ${chip.label})` : "";

  const lines = [
    `${formatCount(payload.totalSteps)} steps${chipText(payload.stepsDelta)}`,
    `${formatCount(payload.totalFloors)} floors${chipText(payload.floorsDelta)}`,
    `${formatCount(payload.climbsCompleted)} climbs completed` +
      chipText(payload.climbsDelta),
  ];
  if (payload.currentStreakWeeks !== undefined) {
    lines.push(`${payload.currentStreakWeeks}-week streak`);
  }
  if (payload.rank !== undefined && payload.fieldSize !== undefined &&
    payload.fieldSize > 1) {
    const band = payload.percentileBand ? ` (${payload.percentileBand})` : "";
    lines.push(`You ranked #${payload.rank} of ${payload.fieldSize} ` +
      `climbers${band}`);
  }
  if (payload.achievementLabel) {
    lines.push(`Achievement earned: ${payload.achievementLabel}`);
  }
  if (payload.landmarksFinished.length > 0) {
    lines.push(`Landmarks finished: ${payload.landmarksFinished.join(", ")}`);
  }
  return lines;
}

/**
 * Renders the active-climber recap for either cadence.
 * @param {RecapCadenceCopy} copy - Cadence-specific copy
 * @param {RecapActivePayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
function renderRecapActiveEmail(
  copy: RecapCadenceCopy,
  payload: RecapActivePayload,
  context: EmailRenderContext
): TransactionalEmailRenderResult {
  const fourthCard: [string, string, RecapDeltaChip | undefined] =
    payload.currentStreakWeeks !== undefined ?
      [
        String(payload.currentStreakWeeks),
        "week streak",
        undefined,
      ] :
      [
        formatCount(payload.landmarksFinished.length),
        payload.landmarksFinished.length === 1 ?
          "landmark finished" :
          "landmarks finished",
        undefined,
      ];

  const landmarksLine = payload.landmarksFinished.length > 0 ? [
    "<p style=\"margin:18px 0 0;font-size:14px;line-height:1.6;color:",
    `${RECAP_TEXT_MUTED};">Landmarks finished: `,
    `<span style="color:${RECAP_TEXT};">`,
    escapeHtml(payload.landmarksFinished.join(", ")),
    "</span>.</p>",
  ].join("") : "";

  const bodyRowsHtml = [
    "<tr><td style=\"padding:40px 30px 34px;\">",
    "<p style=\"margin:0 0 14px;font-size:12px;letter-spacing:0.22em;",
    `text-transform:uppercase;color:${BRAND_ACCENT_COLOR};font-weight:700;">`,
    escapeHtml(copy.eyebrow),
    "</p>",
    "<h1 style=\"margin:0;font-size:40px;line-height:1.05;font-weight:800;",
    `color:#ffffff;letter-spacing:-0.02em;">${escapeHtml(copy.headlineLead)}`,
    "</h1>",
    "<h1 style=\"margin:0 0 14px;font-size:40px;line-height:1.05;",
    `font-weight:900;color:${BRAND_ACCENT_COLOR};letter-spacing:-0.02em;">`,
    `${escapeHtml(copy.headlineAccent)}</h1>`,
    `<p style="margin:0;font-size:14px;color:${RECAP_TEXT_MUTED};">`,
    escapeHtml(payload.periodLabel),
    "</p>",
    renderRankHeroHtml(payload.rank, payload.fieldSize, payload.percentileBand),
    renderAchievementCalloutHtml(payload.achievementLabel),
    renderMilestoneCalloutHtml(payload.milestoneText),
    "</td></tr>",
    "<tr><td style=\"padding:0 30px 34px;\">",
    "<h2 style=\"margin:0 0 18px;font-size:20px;font-weight:800;color:",
    `${RECAP_TEXT};">${escapeHtml(copy.reviewHeading)}</h2>`,
    renderStatGridHtml([
      [
        formatCount(payload.totalSteps),
        "steps",
        payload.stepsDelta,
      ],
      [
        formatCount(payload.totalFloors),
        "floors",
        payload.floorsDelta,
      ],
      [
        formatCount(payload.climbsCompleted),
        "climbs completed",
        payload.climbsDelta,
      ],
      fourthCard,
    ]),
    landmarksLine,
    "</td></tr>",
    "<tr><td style=\"padding:0 30px 34px;\">",
    "<h2 style=\"margin:0 0 14px;font-size:20px;font-weight:800;color:",
    `${RECAP_TEXT};">Your activity</h2>`,
    renderCalendarHtml(payload.calendar),
    "</td></tr>",
    "<tr><td style=\"padding:0 30px 40px;text-align:center;\">",
    renderRecapCtaHtml(copy.ctaLabel, payload.ctaUrl),
    "</td></tr>",
    renderRecapFooterHtml(copy.whyReceivedActive, context.unsubscribeUrl),
  ].join("");

  const textLines = [
    copy.headlineLead + " " + copy.headlineAccent,
    payload.periodLabel,
    "",
    ...(payload.milestoneText ? [
      `Milestone unlocked: ${payload.milestoneText}`,
      "",
    ] : []),
    ...buildRecapActiveTextLines(payload),
    "",
    `${copy.ctaLabel}: ${payload.ctaUrl}`,
    "",
    copy.whyReceivedActive,
    `Privacy Policy: ${getMarketingWebsiteUrl()}/privacy`,
    ...(context.unsubscribeUrl ?
      [`Unsubscribe: ${context.unsubscribeUrl}`] :
      []),
  ].join("\n");

  return {
    html: renderRecapShellHtml(
      `${formatCount(payload.climbsCompleted)} climbs, ` +
        `${formatCount(payload.totalSteps)} steps ${copy.periodNoun}.`,
      bodyRowsHtml
    ),
    subject: copy.subject,
    text: textLines,
  };
}

/**
 * Renders the zero-activity re-engagement email for either cadence. Gentle
 * by design - a softer version of the same visual language, the state, then
 * one clear action, never a guilt-trip about the gap.
 * @param {RecapCadenceCopy} copy - Cadence-specific copy
 * @param {RecapInactivePayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
function renderRecapInactiveEmail(
  copy: RecapCadenceCopy,
  payload: RecapInactivePayload,
  context: EmailRenderContext
): TransactionalEmailRenderResult {
  const suggestionLine = payload.suggestedClimbName ? [
    "<p style=\"margin:14px 0 0;font-size:16px;line-height:1.6;color:",
    `${RECAP_TEXT};">`,
    escapeHtml(payload.suggestedClimbName),
    " is open and ready.</p>",
  ].join("") : "";

  const bodyRowsHtml = [
    "<tr><td style=\"padding:40px 30px 40px;\">",
    "<p style=\"margin:0 0 14px;font-size:12px;letter-spacing:0.22em;",
    `text-transform:uppercase;color:${BRAND_ACCENT_COLOR};font-weight:700;">`,
    "Next Climb",
    "</p>",
    "<h1 style=\"margin:0 0 18px;font-size:34px;line-height:1.1;",
    "font-weight:800;color:#ffffff;letter-spacing:-0.02em;\">",
    escapeHtml(copy.inactiveHeadline),
    "</h1>",
    "<p style=\"margin:0;font-size:16px;line-height:1.6;color:",
    `${RECAP_TEXT_MUTED};">No new steps on the board ${copy.periodNoun}. `,
    "Pick a climb and put your name back on it.</p>",
    suggestionLine,
    "<div style=\"padding-top:28px;\">",
    renderRecapCtaHtml("Open Ascend", payload.ctaUrl),
    "</div></td></tr>",
    renderRecapFooterHtml(copy.whyReceivedInactive, context.unsubscribeUrl),
  ].join("");

  const textLines = [
    copy.inactiveHeadline,
    "",
    `No new steps on the board ${copy.periodNoun}. Pick a climb and put ` +
      "your name back on it.",
    ...(payload.suggestedClimbName ?
      [`${payload.suggestedClimbName} is open and ready.`] :
      []),
    "",
    `Open Ascend: ${payload.ctaUrl}`,
    "",
    copy.whyReceivedInactive,
    `Privacy Policy: ${getMarketingWebsiteUrl()}/privacy`,
    ...(context.unsubscribeUrl ?
      [`Unsubscribe: ${context.unsubscribeUrl}`] :
      []),
  ].join("\n");

  return {
    html: renderRecapShellHtml(
      `The board missed you ${copy.periodNoun}. Here's one to try.`,
      bodyRowsHtml
    ),
    subject: copy.subjectInactive,
    text: textLines,
  };
}

/**
 * Renders the weekly recap email for a climber active in the window.
 * @param {RecapActivePayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderWeeklyRecapActiveEmail(
  payload: RecapActivePayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderRecapActiveEmail(WEEKLY_RECAP_COPY, payload, context);
}

/**
 * Validates and renders the weekly recap email for an active climber.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderWeeklyRecapActiveEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderWeeklyRecapActiveEmail(
    parseRecapActivePayload(payload, "invalid_weekly_recap_active_payload"),
    context
  );
}

/**
 * Renders the weekly re-engagement email for a climber with no activity in
 * the window.
 * @param {RecapInactivePayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderWeeklyRecapInactiveEmail(
  payload: RecapInactivePayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderRecapInactiveEmail(WEEKLY_RECAP_COPY, payload, context);
}

/**
 * Validates and renders the weekly re-engagement email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderWeeklyRecapInactiveEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderWeeklyRecapInactiveEmail(
    parseRecapInactivePayload(payload, "invalid_weekly_recap_inactive_payload"),
    context
  );
}

/**
 * Renders the monthly recap email for a climber active in the window.
 * @param {RecapActivePayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderMonthlyRecapActiveEmail(
  payload: RecapActivePayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderRecapActiveEmail(MONTHLY_RECAP_COPY, payload, context);
}

/**
 * Validates and renders the monthly recap email for an active climber.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderMonthlyRecapActiveEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderMonthlyRecapActiveEmail(
    parseRecapActivePayload(payload, "invalid_monthly_recap_active_payload"),
    context
  );
}

/**
 * Renders the monthly re-engagement email for a climber with no activity in
 * the window.
 * @param {RecapInactivePayload} payload - Template payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderMonthlyRecapInactiveEmail(
  payload: RecapInactivePayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderRecapInactiveEmail(MONTHLY_RECAP_COPY, payload, context);
}

/**
 * Validates and renders the monthly re-engagement email.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderMonthlyRecapInactiveEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  return renderMonthlyRecapInactiveEmail(
    parseRecapInactivePayload(
      payload,
      "invalid_monthly_recap_inactive_payload"
    ),
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

  const metaRow = (labelText: string, value: string): string => `<tr><td style="padding:6px 12px 6px 0;font-size:13px;color:#9ca3af;white-space:nowrap;vertical-align:top;">${labelText}</td><td style="padding:6px 0;font-size:13px;color:#374151;">${value}</td></tr>`;

  const html = [
    "<!doctype html>",
    "<html lang=\"en\"><body style=\"margin:0;padding:0;background:#f4f2eb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111111;\">",
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"background:#f4f2eb;padding:24px 12px;\"><tr><td align=\"center\">",
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"max-width:620px;background:#ffffff;border:1px solid rgba(17,17,17,0.08);border-radius:24px;overflow:hidden;\">",

    // Header
    "<tr><td style=\"background:#111111;padding:20px 28px;\"><span style=\"font-size:14px;color:#ffffff;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;\">Ascend Feedback</span></td></tr>",

    // Type badge + user
    "<tr><td style=\"padding:28px 28px 0;\">",
    `<span style="display:inline-block;padding:6px 14px;border-radius:8px;background:${color};color:#ffffff;font-size:12px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;">${escapedLabel}</span>`,
    `<p style="margin:14px 0 0;font-size:14px;color:#6b7280;">From <strong style="color:#111111;">${escapedEmail}</strong></p>`,
    "</td></tr>",

    // Message
    "<tr><td style=\"padding:20px 28px;\">",
    `<div style="padding:16px 20px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:12px;font-size:15px;line-height:1.65;color:#374151;white-space:pre-wrap;">${escapedMessage}</div>`,
    "</td></tr>",

    // Metadata
    "<tr><td style=\"padding:0 28px 28px;\">",
    "<table role=\"presentation\" cellspacing=\"0\" cellpadding=\"0\" border=\"0\" style=\"width:100%;\">",
    metaRow("User ID", escapedUserId),
    metaRow("Device", `${escapedDevice}, iOS ${escapedOs}`),
    metaRow("App Version", `v${escapedAppVersion} (${escapedBuild})`),
    metaRow("Feedback ID", escapedFeedbackId),
    "</table>",
    "</td></tr>",

    // Footer
    "<tr><td style=\"padding:0 28px 24px;\"><div style=\"border-top:1px solid rgba(17,17,17,0.08);padding-top:16px;text-align:center;\"><p style=\"margin:0;font-size:12px;color:#9ca3af;\">Reply to this email to respond directly to the user.</p></div></td></tr>",

    "</table></td></tr></table></body></html>",
  ].join("");

  return {html, subject, text};
}
