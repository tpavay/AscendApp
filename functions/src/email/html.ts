/**
 * Escapes untrusted content before it is interpolated into HTML.
 *
 * Shared by every surface in the email subsystem that renders HTML, so a
 * hardening change here cannot miss one of them.
 * @param {string} value - Raw string value
 * @return {string} HTML-escaped value
 */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
