import {escapeHtml} from "./html";
import {getMarketingWebsiteUrl} from "./config";
import type {
  DropEmailFact,
  DropEmailItem,
  DropEmailItemGroup,
  DropEmailLeadItem,
  DropEmailPayload,
  DropEmailPicture,
  DropEmailTheme,
  EmailJobPayload,
  EmailRenderContext,
  TransactionalEmailRenderResult,
} from "./types";

// =============================================================================
// Drop announcement email. Round 13 of the Mountain art direction set the
// palette and item tiles; the captain's review of the staging tests
// (2026-10-02) set the layout: text first, and full-width bands of colour.
//
// Each section is a band that runs edge to edge of the reading pane, with its
// content in a centred column no wider than COLUMN_WIDTH - a full-width table
// row with a `bgcolor`, holding a centred inner table, which is how Gmail,
// Apple Mail and Outlook all draw a full-bleed band. The header band carries
// the headline as live text first; art and cobwebs are decoration beside and
// behind it. The mountain picture sits lower, beside the haunted line it
// illustrates.
//
// Every colour is a solid hex, never rgba: Outlook on Windows drops an rgba
// colour entirely. Gradients, glows and background-image cobwebs are
// progressive enhancement over a solid `bgcolor` that already reads right.
// The layout is dark by design and says so (`color-scheme: dark`), the way
// the recap emails stop Apple Mail and Outlook.com re-theming them.
//
// Many clients block remote pictures until the reader allows them, and Gmail
// never loads them in Spam. So every <img> has fixed pixel dimensions, a fill
// and styled alt text, and sits in a box of its own fixed size: a blocked
// picture reads as a deliberate tile, never a broken icon in a collapsed box.
// The brand mark is a background image behind a solid black cell, so when it
// is blocked the bar shows the ASCEND wordmark alone.
// =============================================================================

interface DropPalette {
  accent: string;
  altInk: string;
  body: string;
  ctaBand: string;
  earnBand: string;
  eyebrow: string;
  factBorder: string;
  factInk: string;
  factLabel: string;
  factTile: string;
  factsBand: string;
  featureBand: string;
  featureInk: string;
  featureFill: string;
  footer: string;
  footerBand: string;
  footerLink: string;
  footerLine: string;
  headerBand: string;
  headerGlow: string;
  ink: string;
  leadBorder: string;
  muted: string;
  requirement: string;
  tag: string;
  tagInk: string;
  tile: string;
  tileInk: string;
  tileLine: string;
  tileMuted: string;
  well: string;
  wellGlow: string;
}

const DROP_PALETTES: Record<DropEmailTheme, DropPalette> = {
  halloween: {
    accent: "#ff7a1a",
    altInk: "#8f7fa8",
    body: "#d6cbe3",
    ctaBand: "#24163a",
    earnBand: "#15101b",
    eyebrow: "#ff8a2b",
    factBorder: "#4a3368",
    factInk: "#f7f1e6",
    factLabel: "#c9b8e6",
    factTile: "#321f4d",
    factsBand: "#24163a",
    featureBand: "#ff7a1a",
    featureFill: "#3a1c08",
    featureInk: "#1a0d03",
    footer: "#8a7c9c",
    footerBand: "#0b0910",
    footerLink: "#b9acce",
    footerLine: "#241e2c",
    headerBand: "#0b0910",
    headerGlow: "radial-gradient(ellipse at 78% 40%,#3a1f52 0%,#0b0910 62%)",
    ink: "#f7f1e6",
    leadBorder: "#4e6c1b",
    muted: "#a493bb",
    requirement: "#ff9a4a",
    tag: "#ff7a1a",
    tagInk: "#120a02",
    tile: "#201828",
    tileInk: "#f7f1e6",
    tileLine: "#37294a",
    tileMuted: "#a99cc0",
    well: "#1d1627",
    wellGlow: "radial-gradient(circle at 50% 45%,#2e2340,#120d18 75%)",
  },
};

const LIME = "#86D30A";
const ON_LIME = "#111111";
const FONT_STACK = "-apple-system,BlinkMacSystemFont,'SF Pro Text'," +
  "'Segoe UI',Arial,sans-serif";
const PRESENTATION_TABLE = "role=\"presentation\" cellspacing=\"0\" " +
  "cellpadding=\"0\" border=\"0\"";
/** The readable column every band centres its content in. */
const COLUMN_WIDTH = 600;
/** The feature picture: a 900x300 band, drawn full column width. */
const FEATURE_WIDTH = 552;
const FEATURE_HEIGHT = 184;
const HEADER_ART_SIZE = 112;
const WIDE_HEADER_ART_SIZE = 176;
const COBWEB_SIZE = 110;
/** The lower-corner web, kept inside the band's bottom padding. */
const CORNER_WEB_SIZE = 80;
/** A tile's picture: fixed, and small enough for three across on a phone. */
const TILE_IMAGE_SIZE = 72;
const LEAD_IMAGE_SIZE = 56;
const TILE_COLUMNS = 3;

/**
 * Checks whether an unknown payload is a plain object.
 * @param {unknown} value - Unknown payload
 * @return {boolean} True when value is object-like
 */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

/**
 * Reads a required non-empty string from a stored payload.
 * @param {Record<string, unknown>} source - Stored object
 * @param {string} key - Field name
 * @return {string} Trimmed value
 */
function requiredText(source: Record<string, unknown>, key: string): string {
  const value = source[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`drop_email_invalid_payload:${key}`);
  }
  return value.trim();
}

/**
 * Reads an optional non-empty string from a stored payload.
 * @param {Record<string, unknown>} source - Stored object
 * @param {string} key - Field name
 * @return {string | undefined} Trimmed value, or undefined when absent
 */
function optionalText(
  source: Record<string, unknown>,
  key: string
): string | undefined {
  if (source[key] === undefined || source[key] === null) {
    return undefined;
  }
  return requiredText(source, key);
}

/**
 * Reads a required https URL, normalized without a trailing slash.
 * @param {Record<string, unknown>} source - Stored object
 * @param {string} key - Field name
 * @return {string} Normalized URL
 */
function requiredHttpsUrl(
  source: Record<string, unknown>,
  key: string
): string {
  const raw = requiredText(source, key);
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`drop_email_invalid_payload:${key}`);
  }
  if (url.protocol !== "https:") {
    throw new Error(`drop_email_invalid_payload:${key}`);
  }
  url.hash = "";
  return url.toString().replace(/\/+$/, "");
}

/**
 * Reads a site-relative image path. Absolute URLs and parent segments are
 * refused so every image comes from the one checked asset site.
 * @param {Record<string, unknown>} source - Stored object
 * @param {string} key - Field name
 * @return {string} Relative path without a leading slash
 */
function requiredImagePath(
  source: Record<string, unknown>,
  key: string
): string {
  const path = requiredText(source, key);
  if (!/^[a-z0-9][a-z0-9._/-]*\.(png|jpg|jpeg|gif)$/i.test(path) ||
    path.includes("..")) {
    throw new Error(`drop_email_invalid_payload:${key}`);
  }
  return path;
}

/**
 * Parses an optional picture with its alt text.
 * @param {unknown} value - Stored picture
 * @param {string} key - Field name, for the error
 * @return {DropEmailPicture | undefined} Validated picture
 */
function optionalPicture(
  value: unknown,
  key: string
): DropEmailPicture | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (!isPlainObject(value)) {
    throw new Error(`drop_email_invalid_payload:${key}`);
  }
  return {alt: requiredText(value, "alt"), path: requiredImagePath(value, "path")};
}

/**
 * Parses one item.
 * @param {unknown} value - Stored item
 * @return {DropEmailItem} Validated item
 */
function parseItem(value: unknown): DropEmailItem {
  if (!isPlainObject(value)) {
    throw new Error("drop_email_invalid_payload:item");
  }
  return {
    catalogItemId: requiredText(value, "catalogItemId"),
    imagePath: requiredImagePath(value, "imagePath"),
    name: requiredText(value, "name"),
    requirement: requiredText(value, "requirement"),
  };
}

/**
 * Parses one way-of-earning group.
 * @param {unknown} value - Stored group
 * @return {DropEmailItemGroup} Validated group
 */
function parseGroup(value: unknown): DropEmailItemGroup {
  if (!isPlainObject(value) || !Array.isArray(value.items)) {
    throw new Error("drop_email_invalid_payload:group");
  }
  const group: DropEmailItemGroup = {
    heading: requiredText(value, "heading"),
    items: value.items.map(parseItem),
  };
  if (value.lead !== undefined) {
    const lead = value.lead;
    if (!isPlainObject(lead)) {
      throw new Error("drop_email_invalid_payload:lead");
    }
    group.lead = {
      ...parseItem(lead),
      badge: requiredText(lead, "badge"),
      description: requiredText(lead, "description"),
    };
  }
  if (!group.lead && group.items.length === 0) {
    throw new Error("drop_email_invalid_payload:empty_group");
  }
  return group;
}

/**
 * Parses one fact tile.
 * @param {unknown} value - Stored fact
 * @return {DropEmailFact} Validated fact
 */
function parseFact(value: unknown): DropEmailFact {
  if (!isPlainObject(value)) {
    throw new Error("drop_email_invalid_payload:fact");
  }
  return {label: requiredText(value, "label"), value: requiredText(value, "value")};
}

/**
 * Validates a stored drop payload before anything is drawn from it. A job
 * outlives the build that queued it, so nothing here trusts its shape.
 * @param {EmailJobPayload} payload - Stored job payload
 * @return {DropEmailPayload} Validated payload
 */
export function parseDropEmailPayload(
  payload: EmailJobPayload
): DropEmailPayload {
  if (!isPlainObject(payload)) {
    throw new Error("drop_email_invalid_payload");
  }
  const theme = payload.theme;
  if (typeof theme !== "string" ||
    !Object.prototype.hasOwnProperty.call(DROP_PALETTES, theme)) {
    throw new Error("drop_email_invalid_payload:theme");
  }
  if (!Array.isArray(payload.groups) || payload.groups.length === 0 ||
    !Array.isArray(payload.facts) || !Array.isArray(payload.headlineLines) ||
    payload.headlineLines.length === 0) {
    throw new Error("drop_email_invalid_payload:shape");
  }
  const headlineLines = payload.headlineLines.map((line) => {
    if (typeof line !== "string" || line.trim().length === 0) {
      throw new Error("drop_email_invalid_payload:headlineLines");
    }
    return line.trim();
  });
  let cobwebs: DropEmailPayload["cobwebs"];
  if (payload.cobwebs !== undefined && payload.cobwebs !== null) {
    if (!isPlainObject(payload.cobwebs)) {
      throw new Error("drop_email_invalid_payload:cobwebs");
    }
    cobwebs = {
      left: requiredImagePath(payload.cobwebs, "left"),
      right: requiredImagePath(payload.cobwebs, "right"),
    };
  }

  return {
    assetBaseUrl: requiredHttpsUrl(payload, "assetBaseUrl"),
    banner: optionalText(payload, "banner"),
    cobwebs,
    ctaLabel: requiredText(payload, "ctaLabel"),
    ctaUrl: requiredHttpsUrl(payload, "ctaUrl"),
    dropId: requiredText(payload, "dropId"),
    earnHeading: requiredText(payload, "earnHeading"),
    eyebrow: requiredText(payload, "eyebrow"),
    facts: payload.facts.map(parseFact),
    feature: optionalPicture(payload.feature, "feature"),
    groups: payload.groups.map(parseGroup),
    headerArt: optionalPicture(payload.headerArt, "headerArt"),
    headlineLines,
    intro: requiredText(payload, "intro"),
    postalAddress: optionalText(payload, "postalAddress"),
    preheader: requiredText(payload, "preheader"),
    subject: requiredText(payload, "subject"),
    tag: requiredText(payload, "tag"),
    theme: theme as DropEmailTheme,
    whyReceived: requiredText(payload, "whyReceived"),
  };
}

/**
 * Every image a drop draws, as site-relative paths - what the sender checks
 * is deployed before it queues a single job.
 * @param {DropEmailPayload} payload - Validated payload
 * @return {string[]} Unique relative image paths
 */
export function dropEmailImagePaths(payload: DropEmailPayload): string[] {
  const paths: string[] = [];
  if (payload.headerArt) {
    paths.push(payload.headerArt.path);
  }
  if (payload.cobwebs) {
    paths.push(payload.cobwebs.left, payload.cobwebs.right);
  }
  for (const item of dropEmailItems(payload)) {
    paths.push(item.imagePath);
  }
  if (payload.feature) {
    paths.push(payload.feature.path);
  }
  return [...new Set(paths)];
}

/**
 * Every catalogue item a drop names, in the order the email draws them.
 * @param {DropEmailPayload} payload - Validated payload
 * @return {DropEmailItem[]} Items
 */
export function dropEmailItems(payload: DropEmailPayload): DropEmailItem[] {
  return payload.groups.flatMap((group) => [
    ...(group.lead ? [group.lead] : []),
    ...group.items,
  ]);
}

/**
 * Resolves a site-relative image path against the payload's asset site.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {string} path - Relative image path
 * @return {string} Escaped absolute URL
 */
function imageUrl(payload: DropEmailPayload, path: string): string {
  return escapeHtml(`${payload.assetBaseUrl}/${path}`);
}

/**
 * The inline style every picture carries, so a blocked one is a filled box
 * of exactly its own size with its alt text set small and centred in it.
 * @param {string} fill - The box's fill
 * @param {string} ink - The alt text's colour
 * @param {string} sizing - Width and height declarations
 * @return {string} Style attribute value
 */
function blockedImageStyle(fill: string, ink: string, sizing: string): string {
  return `display:block;border:0;outline:none;text-decoration:none;${sizing}` +
    `background-color:${fill};color:${ink};font-family:${FONT_STACK};` +
    "font-size:10px;line-height:1.3;font-weight:700;text-align:center;";
}

/**
 * Wraps a section's content in a full-width band of colour with a centred
 * readable column, the shape every client draws edge to edge.
 * @param {string} color - The band's colour
 * @param {string} padding - The column's padding
 * @param {string} content - The column's HTML
 * @param {string} extraStyle - Extra declarations for the band cell
 * @param {string} extraAttributes - Extra attributes for the band cell
 * @return {string} `<tr>` HTML
 */
function bandHtml(
  color: string,
  padding: string,
  content: string,
  extraStyle = "",
  extraAttributes = "",
  columnClass = ""
): string {
  return [
    `<tr><td align="center" bgcolor="${color}" ${extraAttributes}`,
    `style="background-color:${color};${extraStyle}">`,
    `<table ${PRESENTATION_TABLE} width="100%" align="center" `,
    `style="max-width:${COLUMN_WIDTH}px;margin:0 auto;"><tr>`,
    `<td${columnClass ? ` class="${columnClass}"` : ""} `,
    `style="padding:${padding};">${content}</td>`,
    "</tr></table></td></tr>",
  ].join("");
}

/**
 * Renders a lime pill.
 * @param {string} text - Label text
 * @return {string} Inline label HTML
 */
function pillHtml(text: string): string {
  return [
    `<span style="display:inline-block;background:${LIME};color:${ON_LIME};`,
    "font-size:9px;line-height:1;font-weight:900;letter-spacing:0.16em;",
    "text-transform:uppercase;padding:4px 7px;border-radius:99px;",
    `white-space:nowrap;">${escapeHtml(text)}</span>`,
  ].join("");
}

/**
 * The header band: brand bar, then the headline as live text with the art
 * beside it and cobwebs behind the art and in the band's lower corner, then
 * the intro. With every picture blocked it is still a coloured band that
 * says what the email is about.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML
 */
function headerBandHtml(
  payload: DropEmailPayload,
  palette: DropPalette
): string {
  const iconUrl = escapeHtml(
    `${getMarketingWebsiteUrl()}/images/ascend-a-icon.png`
  );
  const brand = [
    `<table ${PRESENTATION_TABLE} width="100%"><tr>`,
    "<td valign=\"middle\" width=\"48\" style=\"padding-right:12px;\">",
    `<table ${PRESENTATION_TABLE}><tr>`,
    `<td width="36" height="36" bgcolor="#000000" background="${iconUrl}" `,
    "style=\"width:36px;height:36px;background-color:#000000;",
    `background-image:url('${iconUrl}');background-size:36px 36px;`,
    "background-repeat:no-repeat;border-radius:9px;font-size:0;",
    "line-height:0;\">&nbsp;</td></tr></table></td>",
    "<td valign=\"middle\" style=\"font-size:15px;line-height:1;",
    "color:#ffffff;font-weight:800;letter-spacing:0.08em;",
    "text-transform:uppercase;\">Ascend</td>",
    "<td valign=\"middle\" align=\"right\">",
    `<span style="display:inline-block;background:${palette.tag};`,
    `color:${palette.tagInk};font-size:10px;line-height:1;font-weight:800;`,
    "letter-spacing:0.16em;text-transform:uppercase;padding:8px 11px;",
    `border-radius:99px;white-space:nowrap;">${escapeHtml(payload.tag)}`,
    "</span></td></tr></table>",
  ].join("");

  const right = payload.cobwebs ?
    imageUrl(payload, payload.cobwebs.right) :
    null;
  const left = payload.cobwebs ? imageUrl(payload, payload.cobwebs.left) : null;
  const art = payload.headerArt ? [
    "<td class=\"dh-artcell\" valign=\"middle\" align=\"right\" ",
    `width="${HEADER_ART_SIZE + 8}" `,
    right ? `background="${right}" ` : "",
    "style=\"padding-left:8px;",
    right ?
      `background-image:url('${right}');background-repeat:no-repeat;` +
        `background-position:right top;background-size:${COBWEB_SIZE}px ` +
        `${COBWEB_SIZE}px;` :
      "",
    "\">",
    `<img class="dh-art" src="${imageUrl(payload, payload.headerArt.path)}" `,
    `width="${HEADER_ART_SIZE}" height="${HEADER_ART_SIZE}" `,
    `alt="${escapeHtml(payload.headerArt.alt)}" style="`,
    // No fill: the art is a cut-out on the band's glow, and a blocked one
    // leaves its alt text on the band itself.
    blockedImageStyle(
      "transparent",
      palette.altInk,
      `width:${HEADER_ART_SIZE}px;height:${HEADER_ART_SIZE}px;margin:0 0 0 auto;`
    ),
    "\" /></td>",
  ].join("") : "";

  const headline = payload.headlineLines.map(escapeHtml).join("<br>");
  const title = [
    `<table ${PRESENTATION_TABLE} width="100%" style="margin-top:30px;"><tr>`,
    "<td valign=\"middle\">",
    "<p style=\"margin:0 0 12px;font-size:12px;line-height:1.3;",
    `color:${palette.eyebrow};font-weight:800;letter-spacing:0.22em;`,
    `text-transform:uppercase;">${escapeHtml(payload.eyebrow)}</p>`,
    "<h1 class=\"dh-h1\" style=\"margin:0;font-size:40px;line-height:1.02;font-weight:900;",
    `letter-spacing:-0.03em;color:${palette.ink};text-shadow:0 0 24px `,
    `${palette.accent}59;">${headline}</h1>`,
    "</td>",
    art,
    "</tr></table>",
    "<p class=\"dh-intro\" style=\"margin:18px 0 0;font-size:17px;",
    "line-height:1.55;",
    `color:${palette.body};">${proseHtml(payload.intro)}</p>`,
  ].join("");

  const leftWeb = left ?
    `background-image:url('${left}'),${palette.headerGlow};` +
      "background-repeat:no-repeat;background-position:left bottom,center;" +
      `background-size:${CORNER_WEB_SIZE}px ${CORNER_WEB_SIZE}px,cover;` :
    `background-image:${palette.headerGlow};`;
  return bandHtml(
    palette.headerBand,
    // The bottom padding is taller than the corner web, so the web never
    // reaches the intro's last line.
    `24px 24px ${CORNER_WEB_SIZE + 8}px`,
    brand + title,
    leftWeb,
    left ? `background="${left}" ` : "",
    "dh-pad"
  );
}

/**
 * Wide-window sizes for the header band, so on a desktop the headline and
 * art fill it instead of floating small in it. Inline styles stay the phone
 * sizes: a client that ignores this block (Outlook on Windows, some Gmail
 * views) draws the phone layout, which still reads correctly. The bottom
 * padding only tightens once the window is wide enough for the corner web to
 * sit in the gutter beside the column rather than under the text.
 * @return {string} `<style>` element
 */
function wideHeaderStyle(): string {
  const gutterWidth = COLUMN_WIDTH + 2 * CORNER_WEB_SIZE + 40;
  return [
    "<style>",
    "@media only screen and (min-width:640px){",
    ".dh-h1{font-size:60px !important;}",
    ".dh-intro{font-size:19px !important;}",
    `.dh-artcell{width:${WIDE_HEADER_ART_SIZE + 8}px !important;}`,
    `.dh-art{width:${WIDE_HEADER_ART_SIZE}px !important;`,
    `height:${WIDE_HEADER_ART_SIZE}px !important;}`,
    "}",
    `@media only screen and (min-width:${gutterWidth}px){`,
    ".dh-pad{padding-bottom:40px !important;}",
    "}",
    "</style>",
  ].join("");
}

/**
 * The facts band.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML, or empty without facts
 */
function factsBandHtml(
  payload: DropEmailPayload,
  palette: DropPalette
): string {
  if (payload.facts.length === 0) {
    return "";
  }
  const cells = payload.facts.map((fact, index) => {
    const padding = index === 0 ? "0 4px 0 0" :
      index === payload.facts.length - 1 ? "0 0 0 4px" : "0 4px";
    return [
      `<td valign="top" width="${Math.floor(100 / payload.facts.length)}%" `,
      `style="padding:${padding};">`,
      `<div style="background:${palette.factTile};border:1px solid `,
      `${palette.factBorder};border-radius:14px;padding:13px 10px 12px;">`,
      "<div style=\"font-size:22px;line-height:1.1;font-weight:900;",
      `letter-spacing:-0.02em;color:${palette.factInk};white-space:nowrap;">`,
      escapeHtml(fact.value),
      "</div>",
      // One line in every card at phone width, so the three stay one height.
      "<div style=\"margin-top:5px;font-size:9.5px;line-height:1.3;",
      "font-weight:800;letter-spacing:0.05em;text-transform:uppercase;",
      "white-space:nowrap;",
      `color:${palette.factLabel};">${escapeHtml(fact.label)}</div>`,
      "</div></td>",
    ].join("");
  }).join("");
  return bandHtml(
    palette.factsBand,
    "22px 24px",
    `<table ${PRESENTATION_TABLE} width="100%"><tr>${cells}</tr></table>`
  );
}

/**
 * Renders the well a thumbnail sits in: a fixed-height box with the
 * picture centred at a fixed size, so it holds its shape with the picture
 * blocked as surely as with it shown.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {DropEmailItem} item - Item drawn
 * @param {number} size - Picture size in CSS pixels
 * @return {string} Well HTML
 */
function wellHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  item: DropEmailItem,
  size: number
): string {
  const style = blockedImageStyle(
    palette.well,
    palette.altInk,
    `width:${size}px;height:${size}px;margin:0 auto;`
  );
  return [
    `<table ${PRESENTATION_TABLE} width="100%"><tr>`,
    `<td align="center" valign="middle" height="${size + 16}" `,
    `bgcolor="${palette.well}" style="height:${size + 16}px;`,
    `background-color:${palette.well};background-image:${palette.wellGlow};`,
    "border-radius:10px;padding:8px;line-height:0;\">",
    `<img src="${imageUrl(payload, item.imagePath)}" width="${size}" `,
    `height="${size}" alt="${escapeHtml(item.name)}" style="${style}" />`,
    "</td></tr></table>",
  ].join("");
}

/**
 * Prose as visible HTML whose last two words never part, so no paragraph
 * ends on a word alone on its line.
 * @param {string} text - Paragraph text
 * @return {string} Escaped HTML
 */
function proseHtml(text: string): string {
  const escaped = escapeHtml(text);
  const last = escaped.lastIndexOf(" ");
  return last < 0 ?
    escaped :
    `${escaped.slice(0, last)}&nbsp;${escaped.slice(last + 1)}`;
}

/**
 * An item name as visible HTML: its hyphens never break, so
 * "Jack-o'-Lantern" stays one word instead of ending a line on "Jack-o'-".
 * @param {string} name - Item name
 * @return {string} Escaped HTML
 */
function itemNameHtml(name: string): string {
  return escapeHtml(name).replace(/-/g, "&#8209;");
}

/**
 * Renders one item tile: thumbnail, name, requirement. A one-word name too
 * long for a third of a phone (the hyphenated Jack-o'-Lantern) steps down a
 * size rather than overflowing its tile.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {DropEmailItem} item - Item drawn
 * @return {string} Tile HTML
 */
function tileHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  item: DropEmailItem
): string {
  const isLongWord = !item.name.includes(" ") && item.name.length > 12;
  const nameSize = isLongWord ? "font-size:10.5px;letter-spacing:-0.01em;" :
    "font-size:12px;";
  return [
    `<div style="background:${palette.tile};border:1px solid `,
    `${palette.tileLine};border-radius:14px;padding:7px 7px 10px;`,
    "text-align:center;\">",
    wellHtml(payload, palette, item, TILE_IMAGE_SIZE),
    // Two lines reserved for every name, so a row of tiles keeps one height
    // whether a name wraps or not.
    `<div style="margin-top:8px;height:30px;${nameSize}line-height:15px;`,
    `font-weight:800;color:${palette.tileInk};">${itemNameHtml(item.name)}`,
    "</div>",
    "<div style=\"margin-top:5px;font-size:10px;line-height:1.2;",
    "font-weight:800;letter-spacing:0.06em;text-transform:uppercase;",
    `white-space:nowrap;color:${palette.requirement};">`,
    `${escapeHtml(item.requirement)}</div>`,
    "</div>",
  ].join("");
}

/**
 * Lays tiles out three across. A short last row keeps the same tile width
 * and sits centred, so five items read as three and two, never as a
 * stretched pair.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {DropEmailItem[]} items - Tiles
 * @return {string} Grid HTML
 */
function tileGridHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  items: DropEmailItem[]
): string {
  if (items.length === 0) {
    return "";
  }
  const rows: string[] = [];
  for (let start = 0; start < items.length; start += TILE_COLUMNS) {
    const row = items.slice(start, start + TILE_COLUMNS);
    // The row's table is a third of the width per tile, so each cell takes
    // an equal share of that, and every tile comes out a third wide.
    const width = Math.floor(100 / row.length);
    const cells = row.map((item) =>
      `<td valign="top" width="${width}%" style="padding:0 4px 8px;">` +
      `${tileHtml(payload, palette, item)}</td>`
    ).join("");
    const rowWidth = Math.round(100 * row.length / TILE_COLUMNS);
    rows.push(
      `<table ${PRESENTATION_TABLE} width="${rowWidth}%" align="center" ` +
        `style="margin:0 auto;"><tr>${cells}</tr></table>`
    );
  }
  return `<div style="margin:0 -4px;">${rows.join("")}</div>`;
}

/**
 * Renders a group's free lead item: a wide card with a lime pill.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {DropEmailLeadItem} item - Lead item
 * @return {string} Card HTML
 */
function leadCardHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  item: DropEmailLeadItem
): string {
  return [
    `<table ${PRESENTATION_TABLE} width="100%" style="margin-bottom:8px;">`,
    `<tr><td bgcolor="${palette.tile}" style="background:${palette.tile};`,
    `border:1px solid ${palette.leadBorder};border-radius:16px;`,
    "padding:10px 12px;\">",
    `<table ${PRESENTATION_TABLE} width="100%"><tr>`,
    `<td valign="middle" width="${LEAD_IMAGE_SIZE + 16}" `,
    "style=\"padding-right:12px;\">",
    wellHtml(payload, palette, item, LEAD_IMAGE_SIZE),
    "</td><td valign=\"middle\">",
    "<div style=\"font-size:15px;line-height:1.25;font-weight:800;",
    `color:${palette.tileInk};">${itemNameHtml(item.name)}</div>`,
    "<div style=\"margin-top:3px;font-size:13px;line-height:1.4;",
    `color:${palette.tileMuted};">${proseHtml(item.description)}</div>`,
    "</td><td valign=\"middle\" align=\"right\" style=\"padding-left:8px;\">",
    pillHtml(item.badge),
    "</td></tr></table></td></tr></table>",
  ].join("");
}

/**
 * The how-to-earn band: every group of items.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML
 */
function earnBandHtml(payload: DropEmailPayload, palette: DropPalette): string {
  const groups = payload.groups.map((group) => [
    "<div style=\"margin:0 0 12px;\">",
    "<p style=\"margin:0 0 8px;font-size:11px;line-height:1.3;",
    "font-weight:800;letter-spacing:0.14em;text-transform:uppercase;",
    `color:${palette.muted};">${escapeHtml(group.heading)}</p>`,
    group.lead ? leadCardHtml(payload, palette, group.lead) : "",
    tileGridHtml(payload, palette, group.items),
    "</div>",
  ].join("")).join("");
  const heading = [
    `<table ${PRESENTATION_TABLE} width="100%" style="margin:0 0 14px;"><tr>`,
    "<td valign=\"middle\" style=\"white-space:nowrap;padding-right:10px;",
    "font-size:12px;line-height:1;font-weight:800;letter-spacing:0.22em;",
    `text-transform:uppercase;color:${palette.ink};">`,
    escapeHtml(payload.earnHeading),
    "</td><td valign=\"middle\" width=\"100%\">",
    "<div style=\"height:1px;line-height:1px;font-size:0;background:",
    `${palette.tileLine};">&nbsp;</div></td></tr></table>`,
  ].join("");
  return bandHtml(palette.earnBand, "30px 24px 18px", heading + groups);
}

/**
 * The feature band: the picture and the line it illustrates, on the theme's
 * accent colour. Blocked, the picture is a dark panel carrying its alt text
 * and the line still reads.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML, or empty with neither
 */
function featureBandHtml(
  payload: DropEmailPayload,
  palette: DropPalette
): string {
  if (!payload.feature && !payload.banner) {
    return "";
  }
  const picture = payload.feature ? [
    `<img src="${imageUrl(payload, payload.feature.path)}" `,
    `width="${FEATURE_WIDTH}" height="${FEATURE_HEIGHT}" `,
    `alt="${escapeHtml(payload.feature.alt)}" style="`,
    blockedImageStyle(
      palette.featureFill,
      "#ffd9b8",
      `width:100%;max-width:${FEATURE_WIDTH}px;height:auto;` +
        "border-radius:14px;font-size:13px;"
    ),
    "\" />",
  ].join("") : "";
  const line = payload.banner ? [
    `<p style="margin:${payload.feature ? "16px" : "0"} 0 0;font-size:19px;`,
    `line-height:1.35;font-weight:800;color:${palette.featureInk};`,
    `letter-spacing:-0.01em;">${proseHtml(payload.banner)}</p>`,
  ].join("") : "";
  return bandHtml(palette.featureBand, "26px 24px 28px", picture + line);
}

/**
 * The call-to-action band.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML
 */
function ctaBandHtml(payload: DropEmailPayload, palette: DropPalette): string {
  const button = [
    "<div style=\"text-align:center;\">",
    `<a href="${escapeHtml(payload.ctaUrl)}" style="display:inline-block;`,
    `padding:18px 28px;border-radius:16px;background:${LIME};`,
    `color:${ON_LIME};font-size:16px;line-height:1;font-weight:800;`,
    "text-decoration:none;text-transform:uppercase;letter-spacing:0.04em;",
    "box-shadow:0 0 0 1px #86d30a99,0 0 28px #86d30a73;\">",
    escapeHtml(payload.ctaLabel),
    "</a></div>",
  ].join("");
  return bandHtml(palette.ctaBand, "30px 24px", button);
}

/**
 * The footer band: why this arrived, help, the sender's postal address when
 * one is set, privacy, unsubscribe.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {string | null | undefined} unsubscribeUrl - Signed link
 * @return {string} `<tr>` HTML
 */
function footerBandHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  unsubscribeUrl: string | null | undefined
): string {
  const linkStyle = `color:${palette.footerLink};text-decoration:underline;`;
  const privacyUrl = escapeHtml(`${getMarketingWebsiteUrl()}/privacy`);
  const unsubscribe = unsubscribeUrl ? [
    `<span style="color:${palette.footer};"> &middot; </span>`,
    `<a href="${escapeHtml(unsubscribeUrl)}" style="${linkStyle}">`,
    "Unsubscribe</a>",
  ].join("") : "";
  const paragraph = "margin:0 0 9px;font-size:13px;line-height:1.55;" +
    `color:${palette.footer};`;
  const address = payload.postalAddress ?
    `<p style="${paragraph}">${escapeHtml(payload.postalAddress)}</p>` :
    "";
  return bandHtml(palette.footerBand, "26px 24px 34px", [
    "<div style=\"text-align:center;\">",
    `<p style="${paragraph}">${proseHtml(payload.whyReceived)}</p>`,
    `<p style="${paragraph}">Need help? Reply to this email.</p>`,
    address,
    `<p style="${paragraph}margin-bottom:0;">`,
    `<a href="${privacyUrl}" style="${linkStyle}">Privacy Policy</a>`,
    unsubscribe,
    "</p></div>",
  ].join(""));
}

/**
 * The hidden preheader, padded so an inbox preview ends with it instead of
 * running on into the email's first visible words ("AscendHalloween...").
 * @param {string} preheader - Preheader text
 * @return {string} Hidden preheader HTML
 */
function preheaderHtml(preheader: string): string {
  return [
    "<div style=\"display:none;max-height:0;max-width:0;overflow:hidden;",
    "opacity:0;mso-hide:all;font-size:1px;line-height:1px;",
    `color:transparent;">${escapeHtml(preheader)}`,
    "&#847;&zwnj;&nbsp;".repeat(90),
    "</div>",
  ].join("");
}

/**
 * Builds the plain-text part: every fact, item and link the HTML carries.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {string | null | undefined} unsubscribeUrl - Signed link
 * @return {string} Plain-text body
 */
function dropEmailText(
  payload: DropEmailPayload,
  unsubscribeUrl: string | null | undefined
): string {
  const lines = [
    payload.headlineLines.join(" "),
    payload.eyebrow,
    "",
    payload.intro,
  ];
  if (payload.facts.length > 0) {
    lines.push("", payload.facts.map((fact) =>
      `${fact.value} ${fact.label.toLowerCase()}`).join(" / "));
  }
  lines.push("", payload.earnHeading.toUpperCase());
  for (const group of payload.groups) {
    lines.push("", group.heading);
    if (group.lead) {
      lines.push(`- ${group.lead.name} (${group.lead.badge}): ` +
        group.lead.description);
    }
    for (const item of group.items) {
      lines.push(`- ${item.name}: ${item.requirement}`);
    }
  }
  if (payload.banner) {
    lines.push("", payload.banner);
  }
  lines.push(
    "",
    `${payload.ctaLabel}: ${payload.ctaUrl}`,
    "",
    payload.whyReceived,
    "Need help? Reply to this email."
  );
  if (payload.postalAddress) {
    lines.push(payload.postalAddress);
  }
  lines.push(`Privacy Policy: ${getMarketingWebsiteUrl()}/privacy`);
  if (unsubscribeUrl) {
    lines.push(`Unsubscribe: ${unsubscribeUrl}`);
  }
  return lines.join("\n");
}

/**
 * Renders a drop announcement.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderDropEmail(
  payload: DropEmailPayload,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  const palette = DROP_PALETTES[payload.theme];
  const html = [
    "<!doctype html>",
    "<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\"><head>",
    "<meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
    "<meta name=\"color-scheme\" content=\"dark\">",
    "<meta name=\"supported-color-schemes\" content=\"dark\">",
    `<title>${escapeHtml(payload.subject)}</title>`,
    wideHeaderStyle(),
    "</head>",
    `<body bgcolor="${palette.footerBand}" style="margin:0;padding:0;`,
    `background:${palette.footerBand};font-family:${FONT_STACK};color:`,
    `${palette.ink};-webkit-font-smoothing:antialiased;">`,
    preheaderHtml(payload.preheader),
    `<table ${PRESENTATION_TABLE} width="100%" `,
    `bgcolor="${palette.footerBand}" style="width:100%;`,
    `background:${palette.footerBand};">`,
    headerBandHtml(payload, palette),
    factsBandHtml(payload, palette),
    earnBandHtml(payload, palette),
    featureBandHtml(payload, palette),
    ctaBandHtml(payload, palette),
    footerBandHtml(payload, palette, context.unsubscribeUrl),
    "</table></body></html>",
  ].join("");

  return {
    html,
    subject: payload.subject,
    text: dropEmailText(payload, context.unsubscribeUrl),
  };
}

/**
 * Catalog entry point: validates the stored payload, then renders it.
 * @param {EmailJobPayload} payload - Stored job payload
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Rendered email
 */
export function renderDropEmailFromPayload(
  payload: EmailJobPayload,
  context: EmailRenderContext
): TransactionalEmailRenderResult {
  return renderDropEmail(parseDropEmailPayload(payload), context);
}
