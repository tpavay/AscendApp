import {escapeHtml} from "./html";
import {getMarketingWebsiteUrl} from "./config";
import type {
  DropEmailFact,
  DropEmailFeaturedItem,
  DropEmailItem,
  DropEmailItemGroup,
  DropEmailPayload,
  DropEmailTheme,
  EmailJobPayload,
  EmailRenderContext,
  TransactionalEmailRenderResult,
} from "./types";

// =============================================================================
// Drop announcement email (round 13 of the Mountain art direction, approved
// 2026-10-02): one shared frame - brand bar with a theme tag, hero, eyebrow,
// heavy headline, a row of facts, "How to earn" grouped by way of earning,
// lime CTA, footer - and a palette per theme.
//
// Every colour is a solid hex, never rgba: Outlook on Windows drops an rgba
// colour entirely, so a translucent border in the mock is pre-blended here
// over the surface it sits on. Gradients, glows and the cobweb motif are
// progressive enhancement over a solid `bgcolor` that already reads right.
// The layout is dark by design and says so (`color-scheme: dark`), the same
// way the recap emails stop Apple Mail and Outlook.com re-theming them.
// =============================================================================

interface DropPalette {
  accentRule: string;
  bannerBorder: string;
  bannerFrom: string;
  bannerInk: string;
  bannerTo: string;
  bannerDot: string;
  body: string;
  card: string;
  cardLine: string;
  eyebrow: string;
  footer: string;
  footerLink: string;
  footerLine: string;
  ink: string;
  legendaryBorder: string;
  legendaryFrom: string;
  legendaryInk: string;
  legendaryMuted: string;
  legendaryTo: string;
  legendaryWell: string;
  leadBorder: string;
  muted: string;
  page: string;
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
    accentRule: "#ff7a1a",
    bannerBorder: "#67351b",
    bannerDot: "#ff8a2b",
    bannerFrom: "#3f231b",
    bannerInk: "#ffd9b8",
    bannerTo: "#2e233f",
    body: "#cbbfd8",
    card: "#15101b",
    cardLine: "#412212",
    eyebrow: "#ff8a2b",
    footer: "#7f7192",
    footerLink: "#b0a3c6",
    footerLine: "#28232d",
    ink: "#f7f1e6",
    leadBorder: "#4e6c1b",
    legendaryBorder: "#b29036",
    legendaryFrom: "#2a2010",
    legendaryInk: "#fff3d6",
    legendaryMuted: "#c9b98f",
    legendaryTo: "#1d1626",
    legendaryWell: "#261c14",
    muted: "#a493bb",
    page: "#0b0910",
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
const LEGENDARY_GOLD = "#F5C742";
const LEGENDARY_GOLD_INK = "#1a1206";
const FONT_STACK = "-apple-system,BlinkMacSystemFont,'SF Pro Text'," +
  "'Segoe UI',Arial,sans-serif";
const PRESENTATION_TABLE = "role=\"presentation\" cellspacing=\"0\" " +
  "cellpadding=\"0\" border=\"0\"";

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
 * Parses an item drawn as a full-width card.
 * @param {unknown} value - Stored item
 * @return {DropEmailFeaturedItem} Validated item
 */
function parseFeaturedItem(value: unknown): DropEmailFeaturedItem {
  if (!isPlainObject(value)) {
    throw new Error("drop_email_invalid_payload:featured");
  }
  return {
    ...parseItem(value),
    description: requiredText(value, "description"),
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
    group.lead = {...parseFeaturedItem(lead), badge: requiredText(lead, "badge")};
  }
  if (value.legendary !== undefined) {
    group.legendary = parseFeaturedItem(value.legendary);
  }
  if (!group.lead && group.items.length === 0 && !group.legendary) {
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
  if (typeof theme !== "string" || !Object.prototype.hasOwnProperty.call(DROP_PALETTES, theme)) {
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

  return {
    assetBaseUrl: requiredHttpsUrl(payload, "assetBaseUrl"),
    banner: optionalText(payload, "banner"),
    ctaLabel: requiredText(payload, "ctaLabel"),
    ctaUrl: requiredHttpsUrl(payload, "ctaUrl"),
    dropId: requiredText(payload, "dropId"),
    earnHeading: requiredText(payload, "earnHeading"),
    eyebrow: requiredText(payload, "eyebrow"),
    facts: payload.facts.map(parseFact),
    groups: payload.groups.map(parseGroup),
    headlineLines,
    heroImageAlt: requiredText(payload, "heroImageAlt"),
    heroImagePath: requiredImagePath(payload, "heroImagePath"),
    intro: requiredText(payload, "intro"),
    motifImagePath: payload.motifImagePath === undefined ?
      undefined :
      requiredImagePath(payload, "motifImagePath"),
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
  const paths = [payload.heroImagePath];
  if (payload.motifImagePath) {
    paths.push(payload.motifImagePath);
  }
  for (const group of payload.groups) {
    if (group.lead) {
      paths.push(group.lead.imagePath);
    }
    paths.push(...group.items.map((item) => item.imagePath));
    if (group.legendary) {
      paths.push(group.legendary.imagePath);
    }
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
    ...(group.legendary ? [group.legendary] : []),
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
 * Renders a lime pill or gold label.
 * @param {string} text - Label text
 * @param {string} background - Fill
 * @param {string} ink - Text colour
 * @return {string} Inline label HTML
 */
function pillHtml(text: string, background: string, ink: string): string {
  return [
    `<span style="display:inline-block;background:${background};color:${ink};`,
    "font-size:9px;line-height:1;font-weight:900;letter-spacing:0.16em;",
    "text-transform:uppercase;padding:4px 7px;border-radius:99px;",
    `white-space:nowrap;">${escapeHtml(text)}</span>`,
  ].join("");
}

/**
 * Renders the brand bar: the A, ASCEND, and the drop's tag.
 * @param {DropPalette} palette - Theme palette
 * @param {string} tag - Tag text
 * @return {string} `<tr>` HTML
 */
function brandRowHtml(palette: DropPalette, tag: string): string {
  const iconUrl = escapeHtml(
    `${getMarketingWebsiteUrl()}/images/ascend-a-icon.png`
  );
  return [
    "<tr><td bgcolor=\"#000000\" style=\"background:#000000;padding:20px 22px ",
    `20px 26px;border-bottom:2px solid ${palette.accentRule};">`,
    `<table ${PRESENTATION_TABLE} width="100%"><tr>`,
    "<td valign=\"middle\" width=\"48\" style=\"padding-right:12px;\">",
    `<img src="${iconUrl}" width="36" height="36" alt="Ascend icon" `,
    "style=\"display:block;width:36px;height:36px;border:0;",
    "border-radius:9px;\" /></td>",
    "<td valign=\"middle\" style=\"font-size:15px;line-height:1;",
    "color:#ffffff;font-weight:800;letter-spacing:0.08em;",
    "text-transform:uppercase;\">Ascend</td>",
    "<td valign=\"middle\" align=\"right\">",
    `<span style="display:inline-block;background:${palette.tag};`,
    `color:${palette.tagInk};font-size:10px;line-height:1;font-weight:800;`,
    "letter-spacing:0.16em;text-transform:uppercase;padding:8px 11px;",
    `border-radius:99px;white-space:nowrap;">${escapeHtml(tag)}</span>`,
    "</td></tr></table></td></tr>",
  ].join("");
}

/**
 * Renders the hero photograph. The fade into the card is baked into the
 * image, since a CSS overlay does not survive Gmail.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML
 */
function heroRowHtml(payload: DropEmailPayload, palette: DropPalette): string {
  return [
    `<tr><td bgcolor="${palette.card}" style="padding:0;line-height:0;">`,
    `<img src="${imageUrl(payload, payload.heroImagePath)}" width="600" `,
    `alt="${escapeHtml(payload.heroImageAlt)}" style="display:block;`,
    "width:100%;max-width:600px;height:auto;border:0;\" /></td></tr>",
  ].join("");
}

/**
 * Renders the optional theme banner under the hero.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML, or empty without a banner
 */
function bannerRowHtml(
  payload: DropEmailPayload,
  palette: DropPalette
): string {
  if (!payload.banner) {
    return "";
  }
  return [
    `<tr><td bgcolor="${palette.card}" style="padding:4px 24px 0;">`,
    `<table ${PRESENTATION_TABLE} width="100%"><tr>`,
    `<td bgcolor="${palette.bannerFrom}" style="background-color:`,
    `${palette.bannerFrom};background-image:linear-gradient(90deg,`,
    `${palette.bannerFrom},${palette.bannerTo});border:1px solid `,
    `${palette.bannerBorder};border-radius:14px;padding:12px 14px;">`,
    `<table ${PRESENTATION_TABLE}><tr>`,
    "<td valign=\"middle\" width=\"20\" style=\"padding-right:10px;\">",
    "<div style=\"width:10px;height:10px;border-radius:99px;background:",
    `${palette.bannerDot};box-shadow:0 0 10px 3px ${palette.bannerDot};`,
    "font-size:0;line-height:0;\">&nbsp;</div></td>",
    "<td valign=\"middle\" style=\"font-size:13px;line-height:1.4;",
    `font-weight:700;color:${palette.bannerInk};">`,
    escapeHtml(payload.banner),
    "</td></tr></table></td></tr></table></td></tr>",
  ].join("");
}

/**
 * Renders the eyebrow, headline, intro and facts. The motif (the cobweb)
 * is a background image on this cell, so a client that drops background
 * images loses decoration, never content.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML
 */
function introRowHtml(payload: DropEmailPayload, palette: DropPalette): string {
  const motif = payload.motifImagePath ?
    imageUrl(payload, payload.motifImagePath) :
    null;
  const motifStyle = motif ?
    `background-image:url('${motif}');background-repeat:no-repeat;` +
      "background-position:right top;background-size:110px 110px;" :
    "";
  const headline = payload.headlineLines.map(escapeHtml).join("<br>");
  const factCells = payload.facts.map((fact, index) => {
    const padding = index === 0 ? "0 4px 0 0" :
      index === payload.facts.length - 1 ? "0 0 0 4px" : "0 4px";
    return [
      `<td valign="top" width="${Math.floor(100 / payload.facts.length)}%" `,
      `style="padding:${padding};">`,
      `<div style="background:${palette.tile};border:1px solid `,
      `${palette.tileLine};border-radius:14px;padding:12px 11px 11px;">`,
      "<div style=\"font-size:21px;line-height:1.1;font-weight:900;",
      `letter-spacing:-0.02em;color:${palette.tileInk};white-space:nowrap;">`,
      escapeHtml(fact.value),
      "</div>",
      "<div style=\"margin-top:4px;font-size:10px;line-height:1.3;",
      "font-weight:800;letter-spacing:0.1em;text-transform:uppercase;",
      `color:${palette.tileMuted};">${escapeHtml(fact.label)}</div>`,
      "</div></td>",
    ].join("");
  }).join("");

  return [
    `<tr><td bgcolor="${palette.card}" `,
    motif ? `background="${motif}" ` : "",
    `style="padding:28px 24px 4px;${motifStyle}">`,
    "<p style=\"margin:0 0 14px;font-size:12px;line-height:1.3;",
    `color:${palette.eyebrow};font-weight:800;letter-spacing:0.22em;`,
    `text-transform:uppercase;">${escapeHtml(payload.eyebrow)}</p>`,
    "<h1 style=\"margin:0 0 16px;font-size:38px;line-height:1.02;",
    `font-weight:900;letter-spacing:-0.03em;color:${palette.ink};`,
    `text-shadow:0 0 24px ${palette.accentRule}59;">${headline}</h1>`,
    "<p style=\"margin:0 0 20px;font-size:17px;line-height:1.6;",
    `color:${palette.body};">${escapeHtml(payload.intro)}</p>`,
    payload.facts.length > 0 ?
      `<table ${PRESENTATION_TABLE} width="100%"><tr>${factCells}</tr></table>` :
      "",
    "</td></tr>",
  ].join("");
}

/**
 * Renders the image well a thumbnail sits in.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {DropEmailItem} item - Item drawn
 * @param {number} size - Rendered image size in CSS pixels
 * @param {string} well - Well fill
 * @return {string} Well HTML
 */
function wellHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  item: DropEmailItem,
  size: number,
  well: string
): string {
  return [
    `<div style="background-color:${well};background-image:`,
    `${palette.wellGlow};border-radius:10px;padding:8px;text-align:center;`,
    "line-height:0;\">",
    `<img src="${imageUrl(payload, item.imagePath)}" width="${size}" `,
    `height="${size}" alt="${escapeHtml(item.name)}" style="display:inline-`,
    `block;width:100%;max-width:${size}px;height:auto;border:0;" />`,
    "</div>",
  ].join("");
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
 * size, as the approved mock did, rather than overflowing its tile.
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
    wellHtml(payload, palette, item, 120, palette.well),
    `<div style="margin-top:8px;${nameSize}line-height:1.25;`,
    `font-weight:800;color:${palette.tileInk};">${itemNameHtml(item.name)}`,
    "</div>",
    "<div style=\"margin-top:5px;font-size:10px;line-height:1.2;",
    "font-weight:800;letter-spacing:0.06em;text-transform:uppercase;",
    `color:${palette.requirement};">${escapeHtml(item.requirement)}</div>`,
    "</div>",
  ].join("");
}

/**
 * Lays tiles out three across, or two across when the count does not fill
 * rows of three - a group of four is two rows of two, never three and an
 * orphan.
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
  const columns = items.length % 3 === 0 ? 3 : Math.min(items.length, 2);
  const width = Math.floor(100 / columns);
  const rows: string[] = [];
  for (let start = 0; start < items.length; start += columns) {
    const cells = items.slice(start, start + columns).map((item, index) => {
      const padding = index === 0 ? "0 4px 8px 0" :
        index === columns - 1 ? "0 0 8px 4px" : "0 4px 8px";
      return `<td valign="top" width="${width}%" style="padding:${padding};">` +
        `${tileHtml(payload, palette, item)}</td>`;
    });
    while (cells.length < columns) {
      cells.push(`<td width="${width}%"></td>`);
    }
    rows.push(`<tr>${cells.join("")}</tr>`);
  }
  return `<table ${PRESENTATION_TABLE} width="100%">${rows.join("")}</table>`;
}

/**
 * Renders a group's free lead item: a wide card with a lime pill.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {DropEmailFeaturedItem & {badge: string}} item - Lead item
 * @return {string} Card HTML
 */
function leadCardHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  item: DropEmailFeaturedItem & {badge: string}
): string {
  return [
    `<table ${PRESENTATION_TABLE} width="100%" style="margin-bottom:8px;">`,
    `<tr><td bgcolor="${palette.tile}" style="background:${palette.tile};`,
    `border:1px solid ${palette.leadBorder};border-radius:16px;`,
    "padding:10px 12px;\">",
    `<table ${PRESENTATION_TABLE} width="100%"><tr>`,
    "<td valign=\"middle\" width=\"72\" style=\"padding-right:12px;\">",
    wellHtml(payload, palette, item, 56, palette.well),
    "</td><td valign=\"middle\">",
    "<div style=\"font-size:15px;line-height:1.25;font-weight:800;",
    `color:${palette.tileInk};">${itemNameHtml(item.name)}</div>`,
    "<div style=\"margin-top:3px;font-size:13px;line-height:1.4;",
    `color:${palette.tileMuted};">${escapeHtml(item.description)}</div>`,
    "</td><td valign=\"middle\" align=\"right\" style=\"padding-left:8px;\">",
    pillHtml(item.badge, LIME, ON_LIME),
    "</td></tr></table></td></tr></table>",
  ].join("");
}

/**
 * Renders a group's legendary finale: a gold-edged wide card.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {DropEmailFeaturedItem} item - Legendary item
 * @return {string} Card HTML
 */
function legendaryCardHtml(
  payload: DropEmailPayload,
  palette: DropPalette,
  item: DropEmailFeaturedItem
): string {
  return [
    `<table ${PRESENTATION_TABLE} width="100%" style="margin-bottom:8px;">`,
    `<tr><td bgcolor="${palette.legendaryFrom}" style="background-color:`,
    `${palette.legendaryFrom};background-image:linear-gradient(135deg,`,
    `${palette.legendaryFrom},${palette.legendaryTo} 60%);border:1px solid `,
    `${palette.legendaryBorder};border-radius:16px;padding:12px;">`,
    `<table ${PRESENTATION_TABLE} width="100%"><tr>`,
    "<td valign=\"middle\" width=\"88\" style=\"padding-right:12px;\">",
    wellHtml(payload, palette, item, 68, palette.legendaryWell),
    "</td><td valign=\"middle\">",
    pillHtml("Legendary", LEGENDARY_GOLD, LEGENDARY_GOLD_INK),
    "<span style=\"display:inline-block;margin-left:8px;font-size:10px;",
    "line-height:1;font-weight:900;letter-spacing:0.1em;",
    `text-transform:uppercase;color:${LEGENDARY_GOLD};">`,
    escapeHtml(item.requirement),
    "</span>",
    "<div style=\"margin-top:7px;font-size:16px;line-height:1.25;",
    `font-weight:800;color:${palette.legendaryInk};">`,
    itemNameHtml(item.name),
    "</div>",
    "<div style=\"margin-top:3px;font-size:12.5px;line-height:1.4;",
    `color:${palette.legendaryMuted};">${escapeHtml(item.description)}</div>`,
    "</td></tr></table></td></tr></table>",
  ].join("");
}

/**
 * Renders "How to earn" and every group under it.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML
 */
function earnRowHtml(payload: DropEmailPayload, palette: DropPalette): string {
  const groups = payload.groups.map((group) => [
    "<div style=\"margin:0 0 10px;\">",
    "<p style=\"margin:0 0 8px;font-size:11px;line-height:1.3;",
    "font-weight:800;letter-spacing:0.14em;text-transform:uppercase;",
    `color:${palette.muted};">${escapeHtml(group.heading)}</p>`,
    group.lead ? leadCardHtml(payload, palette, group.lead) : "",
    tileGridHtml(payload, palette, group.items),
    group.legendary ?
      legendaryCardHtml(payload, palette, group.legendary) :
      "",
    "</div>",
  ].join("")).join("");

  return [
    `<tr><td bgcolor="${palette.card}" style="padding:20px 24px 0;">`,
    `<table ${PRESENTATION_TABLE} width="100%" style="margin:0 0 12px;"><tr>`,
    "<td valign=\"middle\" style=\"white-space:nowrap;padding-right:10px;",
    "font-size:12px;line-height:1;font-weight:800;letter-spacing:0.22em;",
    `text-transform:uppercase;color:${palette.ink};">`,
    escapeHtml(payload.earnHeading),
    "</td><td valign=\"middle\" width=\"100%\">",
    "<div style=\"height:1px;line-height:1px;font-size:0;background:",
    `${palette.footerLine};">&nbsp;</div></td></tr></table>`,
    groups,
    "</td></tr>",
  ].join("");
}

/**
 * Renders the lime CTA.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @return {string} `<tr>` HTML
 */
function ctaRowHtml(payload: DropEmailPayload, palette: DropPalette): string {
  return [
    `<tr><td bgcolor="${palette.card}" align="center" `,
    "style=\"padding:14px 24px 30px;text-align:center;\">",
    `<a href="${escapeHtml(payload.ctaUrl)}" style="display:inline-block;`,
    `padding:18px 26px;border-radius:16px;background:${LIME};`,
    `color:${ON_LIME};font-size:16px;line-height:1;font-weight:800;`,
    "text-decoration:none;text-transform:uppercase;letter-spacing:0.04em;",
    "box-shadow:0 0 0 1px #86d30a99,0 0 28px #86d30a73;\">",
    escapeHtml(payload.ctaLabel),
    "</a></td></tr>",
  ].join("");
}

/**
 * Renders the footer: why this arrived, help, privacy, unsubscribe.
 * @param {DropEmailPayload} payload - Validated payload
 * @param {DropPalette} palette - Theme palette
 * @param {string | null | undefined} unsubscribeUrl - Signed link
 * @return {string} `<tr>` HTML
 */
function footerRowHtml(
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
  return [
    `<tr><td bgcolor="${palette.card}" style="padding:0 24px 30px;">`,
    `<div style="border-top:1px solid ${palette.footerLine};`,
    "padding-top:20px;text-align:center;\">",
    `<p style="${paragraph}">${escapeHtml(payload.whyReceived)}</p>`,
    `<p style="${paragraph}">Need help? Reply to this email.</p>`,
    `<p style="${paragraph}margin-bottom:0;">`,
    `<a href="${privacyUrl}" style="${linkStyle}">Privacy Policy</a>`,
    unsubscribe,
    "</p></div></td></tr>",
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
  if (payload.banner) {
    lines.push("", payload.banner);
  }
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
    if (group.legendary) {
      lines.push(`- ${group.legendary.name} (legendary, ` +
        `${group.legendary.requirement}): ` +
        group.legendary.description);
    }
  }
  lines.push(
    "",
    `${payload.ctaLabel}: ${payload.ctaUrl}`,
    "",
    payload.whyReceived,
    "Need help? Reply to this email.",
    `Privacy Policy: ${getMarketingWebsiteUrl()}/privacy`
  );
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
    "</head>",
    `<body bgcolor="${palette.page}" style="margin:0;padding:0;`,
    `background:${palette.page};font-family:${FONT_STACK};color:`,
    `${palette.ink};-webkit-font-smoothing:antialiased;">`,
    "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;",
    `color:transparent;">${escapeHtml(payload.preheader)}</div>`,
    `<table ${PRESENTATION_TABLE} width="100%" bgcolor="${palette.page}" `,
    `style="background:${palette.page};"><tr>`,
    "<td align=\"center\" style=\"padding:24px 12px;\">",
    `<table ${PRESENTATION_TABLE} width="100%" bgcolor="${palette.card}" `,
    `style="max-width:600px;background:${palette.card};border:1px solid `,
    `${palette.cardLine};border-radius:28px;overflow:hidden;`,
    "border-collapse:separate;\">",
    brandRowHtml(palette, payload.tag),
    heroRowHtml(payload, palette),
    bannerRowHtml(payload, palette),
    introRowHtml(payload, palette),
    earnRowHtml(payload, palette),
    ctaRowHtml(payload, palette),
    footerRowHtml(payload, palette, context.unsubscribeUrl),
    "</table></td></tr></table></body></html>",
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
