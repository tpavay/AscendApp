import {escapeHtml} from "./html";

/**
 * Marks mail from a test environment so it can never be read as production.
 *
 * Dev and staging send through the same domain, under the same sender name
 * and with the same templates as production, to test accounts that carry
 * their owner's real address. On 2026-10-05 a weekly recap from dev and a
 * "We missed you" from staging reached the founder's inbox and were reported
 * as a production failure, because nothing in either message said where it
 * came from. An environment that sets `environmentLabel` gets all three
 * marks at once: the sender name, the subject, and a banner above the body.
 */

export interface EnvironmentLabelledMessage {
  fromName: string;
  html: string;
  subject: string;
  text: string;
}

// Solid colours and a `bgcolor` attribute: Outlook on Windows drops rgba and
// CSS backgrounds on a table, and this banner must survive every client.
const BANNER_BACKGROUND = "#F5A623";
const BANNER_TEXT = "#000000";
const BODY_OPEN_TAG = /<body\b[^>]*>/i;

/**
 * The banner's wording, shared by the HTML and plain-text parts.
 * @param {string} label - Environment label, e.g. "STAGING"
 * @return {{heading: string, detail: string}} Banner copy
 */
function bannerCopy(label: string): {heading: string; detail: string} {
  return {
    detail: `Sent by Ascend's ${label} test environment, not the live app.`,
    heading: `${label} test email`,
  };
}

/**
 * Renders the banner as a full-width table row.
 * @param {string} label - Environment label
 * @return {string} Banner HTML
 */
function renderBannerHtml(label: string): string {
  const copy = bannerCopy(label);
  return [
    "<table role=\"presentation\" width=\"100%\" cellspacing=\"0\" ",
    `cellpadding="0" border="0" bgcolor="${BANNER_BACKGROUND}" `,
    `style="background:${BANNER_BACKGROUND};"><tr>`,
    "<td align=\"center\" style=\"padding:12px 16px;font-family:",
    "-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;",
    `font-size:13px;line-height:1.4;color:${BANNER_TEXT};">`,
    "<strong style=\"font-weight:800;letter-spacing:0.08em;",
    `text-transform:uppercase;">${escapeHtml(copy.heading)}</strong>`,
    `<br>${escapeHtml(copy.detail)}</td></tr></table>`,
  ].join("");
}

/**
 * Applies an environment's label to one outgoing message.
 *
 * Done once, where the message is handed to the provider, so every email
 * type is marked - the queued ones and the directly sent admin notification
 * alike - and a new template cannot forget to. With no label the message is
 * returned exactly as it was, which is production.
 * @param {EnvironmentLabelledMessage} message - Rendered message and sender
 * @param {string | undefined} label - The environment's label, if it has one
 * @return {EnvironmentLabelledMessage} The message to send
 */
export function labelMessageForEnvironment(
  message: EnvironmentLabelledMessage,
  label: string | undefined
): EnvironmentLabelledMessage {
  if (!label) {
    return message;
  }

  const banner = renderBannerHtml(label);
  const copy = bannerCopy(label);
  // Directly after <body>, so it is the first thing drawn and the first
  // words of the inbox preview. A fragment with no <body> still gets it.
  const html = BODY_OPEN_TAG.test(message.html) ?
    message.html.replace(BODY_OPEN_TAG, (open) => `${open}${banner}`) :
    `${banner}${message.html}`;

  return {
    fromName: `${message.fromName} ${label}`,
    html,
    subject: `[${label}] ${message.subject}`,
    text: `[${copy.heading.toUpperCase()}] ${copy.detail}\n\n${message.text}`,
  };
}
