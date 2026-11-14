import {getMarketingWebsiteUrl} from "./config";
import {cleanFirstName, isValidTimeZone} from "./birthday";
import {DRIP_EMAIL_COPY, DRIP_SIGNATURE} from "./dripCopy";
import type {DripEmailType} from "./dripCopy";
import {escapeHtml} from "./html";
import type {
  DripEmailPayload,
  EmailJobPayload,
  EmailRenderContext,
  TransactionalEmailRenderResult,
} from "./types";

/**
 * The plain note the lifecycle drip emails use, the look of a newsletter
 * written by a person: one narrow left-aligned column of 14px sans-serif text
 * on white, one idea per paragraph with a generous gap between, an optional
 * short bulleted list, a text link on its own line instead of a button, and
 * the shared footer lines (why you got this, Privacy Policy, Unsubscribe). No
 * images, no buttons, no chrome. The words are in `dripCopy.ts`; nothing here
 * decides what to say.
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
 * The calendar day an instant falls on in a zone, as a day count.
 * @param {number} instantMs - The instant, epoch milliseconds
 * @param {string} zone - A valid IANA zone
 * @return {number} Whole days since the epoch, on that zone's calendar
 */
function calendarDay(instantMs: number, zone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "numeric",
    timeZone: zone,
    year: "numeric",
  }).formatToParts(new Date(instantMs));
  const read = (type: string): number =>
    Number(parts.find((part) => part.type === type)?.value);
  return Date.UTC(read("year"), read("month") - 1, read("day")) / 86_400_000;
}

/**
 * How soon the trial ends, counted in calendar days on the climber's own
 * calendar so it agrees with the date in the body and is never a wrong number.
 * @param {number} trialEndsAtMs - Trial end, epoch milliseconds
 * @param {string | undefined} timeZone - The climber's zone, when known
 * @param {Date} now - The moment the email is rendered
 * @return {string} "today", "tomorrow" or "in N days"
 */
export function formatTrialEndsIn(
  trialEndsAtMs: number,
  timeZone: string | undefined,
  now: Date
): string {
  const zone = timeZone && isValidTimeZone(timeZone) ?
    timeZone : DEFAULT_CHARGE_DATE_ZONE;
  const days = calendarDay(trialEndsAtMs, zone) -
    calendarDay(now.getTime(), zone);
  if (days <= 0) return "today";
  if (days === 1) return "tomorrow";
  return `in ${days} days`;
}

/**
 * Fills the copy's `{chargeDate}` and `{trialEndsIn}` placeholders.
 * @param {string} text - A subject, preheader or paragraph from the copy file
 * @param {DripEmailPayload} payload - The job's payload
 * @param {Date} now - The moment the email is rendered
 * @return {string} Text with placeholders filled
 */
function fillPlaceholders(
  text: string,
  payload: DripEmailPayload,
  now: Date
): string {
  const needsTrialEnd = text.includes("{chargeDate}") ||
    text.includes("{trialEndsIn}");
  if (!needsTrialEnd) return text;
  if (typeof payload.trialEndsAtMs !== "number") {
    throw new Error("trial reminder payload needs trialEndsAtMs");
  }
  return text
    .split("{chargeDate}")
    .join(formatChargeDate(payload.trialEndsAtMs, payload.timeZone))
    .split("{trialEndsIn}")
    .join(formatTrialEndsIn(payload.trialEndsAtMs, payload.timeZone, now));
}

/**
 * Renders one drip email.
 * @param {DripEmailType} type - Which email
 * @param {DripEmailPayload} payload - The job's payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @param {Date} now - The moment the email is rendered
 * @return {TransactionalEmailRenderResult} Subject, HTML and plain text
 */
export function renderDripEmail(
  type: DripEmailType,
  payload: DripEmailPayload,
  context: EmailRenderContext = {},
  now: Date = new Date()
): TransactionalEmailRenderResult {
  const copy = DRIP_EMAIL_COPY[type];
  const fill = (text: string): string =>
    fillPlaceholders(text, payload, now);
  const firstName = cleanFirstName(payload.firstName);
  const greeting = firstName ? `Hi ${firstName},` : "Hi,";
  const subject = fill(copy.subject);
  const preheader = fill(copy.preheader);
  const blocks = copy.blocks.map((block) => typeof block === "string" ?
    fill(block) : {bullets: block.bullets.map(fill)});
  const privacyUrl = `${getMarketingWebsiteUrl()}/privacy`;

  const paragraphStyle = "margin:0 0 1.2em;";
  const listStyle = "margin:0 0 1.2em;padding-left:22px;";
  const footerStyle = "margin:0 0 6px;font-size:12px;line-height:1.6;" +
    "color:#777777;";
  const unsubscribeHtml = context.unsubscribeUrl ? [
    " &middot; <a href=\"", escapeHtml(context.unsubscribeUrl),
    "\" style=\"color:#777777;\">Unsubscribe</a>",
  ].join("") : "";

  const blockHtml = (block: typeof blocks[number]): string =>
    typeof block === "string" ?
      `<p style="${paragraphStyle}">${escapeHtml(block)}</p>` :
      [
        `<ul style="${listStyle}">`,
        ...block.bullets.map((item) => `<li>${escapeHtml(item)}</li>`),
        "</ul>",
      ].join("");

  const html = [
    "<!doctype html>",
    "<html lang=\"en\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
    "<meta name=\"color-scheme\" content=\"light\">",
    "<meta name=\"supported-color-schemes\" content=\"light\">",
    "</head><body style=\"margin:0;padding:0;background:#ffffff;",
    "color:#222222;font-family:Arial,Helvetica,sans-serif;",
    "font-size:14px;line-height:1.5;\">",
    "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;",
    "color:transparent;\">", escapeHtml(preheader), "</div>",
    "<div style=\"max-width:520px;margin:0 auto;padding:24px 20px 40px;",
    "text-align:left;\">",
    `<p style="${paragraphStyle}">${escapeHtml(greeting)}</p>`,
    ...blocks.map(blockHtml),
    `<p style="${paragraphStyle}"><a href="${escapeHtml(payload.ctaUrl)}" `,
    "style=\"color:#222222;text-decoration:underline;\">",
    escapeHtml(copy.linkLabel), "</a></p>",
    "<p style=\"margin:0;\">",
    escapeHtml(DRIP_SIGNATURE.name), "<br>",
    "<span style=\"font-size:13px;color:#777777;\">",
    escapeHtml(DRIP_SIGNATURE.role), "</span></p>",
    "<div style=\"margin-top:32px;border-top:1px solid #e5e5e5;",
    "padding-top:16px;\">",
    `<p style="${footerStyle}">${escapeHtml(copy.whyReceived)}</p>`,
    `<p style="${footerStyle}"><a href="${escapeHtml(privacyUrl)}" `,
    "style=\"color:#777777;\">Privacy Policy</a>", unsubscribeHtml, "</p>",
    "</div></div></body></html>",
  ].join("");

  const text = [
    greeting,
    "",
    ...blocks.flatMap((block) => typeof block === "string" ?
      [block, ""] : [...block.bullets.map((item) => `- ${item}`), ""]),
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

  return {html, subject, text};
}

/**
 * Validates a stored payload and renders the drip email for it.
 * @param {DripEmailType} type - Which email
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @param {Date} now - The moment the email is rendered
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderDripEmailFromPayload(
  type: DripEmailType,
  payload: EmailJobPayload,
  context: EmailRenderContext = {},
  now: Date = new Date()
): TransactionalEmailRenderResult {
  return renderDripEmail(type, parseDripPayload(payload), context, now);
}
