#!/usr/bin/env node
/**
 * Validates the bundled share-card template payload against the shipped renderer.
 *
 * Templates are data now, so a typo in a stat name or an element type is a
 * content edit that would otherwise reach a user as a card with a hole in it.
 * The renderer is lenient by design — an unknown element draws nothing, an
 * unknown stat drops its cell — which is right at runtime and wrong at author
 * time. This turns those silent degradations into a build failure.
 *
 * The vocabulary is read out of the Swift sources rather than duplicated here,
 * so there is no second list to drift.
 *
 * Usage: node scripts/validate-share-card-templates.mjs
 */
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

const ROOT = new URL("../", import.meta.url);

export const PATHS = {
  payload: "AscendApp/Features/ShareComposer/Resources/share-card-templates-v1.json",
  format: "AscendApp/Features/ShareComposer/Models/ShareCardFormat.swift",
  label: "AscendApp/Features/ShareComposer/Models/ShareCardLabel.swift",
  sticker: "AscendApp/Features/ShareComposer/Models/ShareStatSticker.swift",
};

/**
 * Reads a repository file as text.
 * @param {string} relativePath Path relative to the repository root.
 * @return {string} File contents.
 */
function read(relativePath) {
  return readFileSync(new URL(relativePath, ROOT), "utf8");
}

/**
 * The element types the renderer's decoder switch accepts.
 * @param {string} source `ShareCardFormat.swift`.
 * @return {Set<string>} Known element type names.
 */
export function elementTypes(source) {
  const decoder = source.slice(source.indexOf("enum ShareCardElement"));
  return new Set(
    [...decoder.matchAll(/case "(\w+)": self = \./g)].map((match) => match[1])
  );
}

/**
 * The renderer version this binary ships.
 * @param {string} source `ShareCardFormat.swift`.
 * @return {number} Renderer version.
 */
export function rendererVersion(source) {
  const match = source.match(/static let rendererVersion = (\d+)/);
  if (!match) throw new Error("could not read rendererVersion from ShareCardFormat.swift");
  return Number(match[1]);
}

/**
 * Case names of a Swift enum.
 * @param {string} source Swift source text.
 * @param {string} name Enum name.
 * @return {Set<string>} Case names.
 */
export function enumCases(source, name) {
  const start = source.indexOf(`enum ${name}`);
  if (start < 0) throw new Error(`could not find enum ${name}`);
  const body = source.slice(start, source.indexOf("\n}", start));
  return new Set(
    [...body.matchAll(/^\s{4}case (\w+)/gm)].map((match) => match[1])
  );
}

/**
 * Collects every problem in a template payload.
 * @param {object} vocabulary Known names.
 * @param {Set<string>} vocabulary.elements Element types.
 * @param {Set<string>} vocabulary.stats Stat kinds.
 * @param {Set<string>} vocabulary.placements Label placements.
 * @param {Set<string>} vocabulary.policies Label policies.
 * @param {Set<string>} vocabulary.requirements Template requirements.
 * @param {number} vocabulary.version Renderer version.
 * @param {object} document Parsed payload.
 * @return {string[]} Problems, empty when the payload is valid.
 */
export function validate(vocabulary, document) {
  const problems = [];

  if (typeof document.formatVersion !== "number") {
    problems.push("payload has no numeric formatVersion");
  }
  if (!Array.isArray(document.templates) || document.templates.length === 0) {
    problems.push("payload has no templates");
    return problems;
  }

  const seenIds = new Set();
  for (const template of document.templates) {
    const id = template.id ?? "<missing id>";
    if (!template.id) problems.push("a template has no id");
    if (seenIds.has(id)) problems.push(`${id}: duplicate id`);
    seenIds.add(id);

    if (!template.title) problems.push(`${id}: no picker title`);
    if (typeof template.minRendererVersion !== "number") {
      problems.push(`${id}: no minRendererVersion`);
    } else if (template.minRendererVersion > vocabulary.version) {
      problems.push(
        `${id}: minRendererVersion ${template.minRendererVersion} is above the ` +
          `shipped renderer (${vocabulary.version}); this binary would skip it`
      );
    }
    for (const requirement of template.requires ?? []) {
      if (!vocabulary.requirements.has(requirement)) {
        problems.push(`${id}: unknown requirement "${requirement}"`);
      }
    }
    if (template.background !== undefined) {
      checkColor(template.background, `${id}.background`, problems);
    }
    // The wordmark tint sits on the template, not in `root`, so the walk below
    // never reaches it — and a typo here ships the one mark every card must
    // show as opaque black.
    if (template.wordmarkTint !== undefined) {
      checkColor(template.wordmarkTint, `${id}.wordmarkTint`, problems);
    }
    if (!template.root) {
      problems.push(`${id}: no root node`);
      continue;
    }
    walk(template.root, `${id}.root`, vocabulary, problems);
  }

  return problems;
}

/**
 * Keys whose value is a color, a color plus opacity, a fill, or a stroke. Every
 * color literal in the payload sits at one of these, however deeply nested.
 */
const COLOR_KEYS = new Set([
  "tint", "color", "fill", "track", "stroke", "border", "background", "stops", "overlay",
  "wordmarkTint", "textTint", "fastTint", "slowTint", "trackTint",
]);

/** Color names the renderer resolves against the render context. */
const COLOR_SLOTS = new Set(["value", "label"]);

/** The only literal spelling `ShareCardColor.color(fromHex:)` reads correctly. */
const HEX_COLOR = /^#?[0-9a-fA-F]{6}$/;

/**
 * Checks one node and its children.
 * @param {object} node Node to check.
 * @param {string} path Human-readable location.
 * @param {object} vocabulary Known names.
 * @param {string[]} problems Accumulator.
 * @return {void}
 */
function walk(node, path, vocabulary, problems) {
  if (typeof node !== "object" || node === null) {
    problems.push(`${path}: not an object`);
    return;
  }
  const type = node.type;
  if (!type) {
    problems.push(`${path}: no type`);
    return;
  }
  if (!vocabulary.elements.has(type)) {
    problems.push(
      `${path}: unknown element type "${type}" — the renderer would draw nothing`
    );
    return;
  }

  checkColors(node, path, problems);

  if (type === "metric") {
    checkStat(node.stat, `${path}.stat`, vocabulary, problems);
    if (!node.value) problems.push(`${path}: a metric needs a value style`);
    if (node.labelPlacement && !vocabulary.placements.has(node.labelPlacement)) {
      problems.push(`${path}: unknown labelPlacement "${node.labelPlacement}"`);
    }
    if (node.labelPolicy && !vocabulary.policies.has(node.labelPolicy)) {
      problems.push(`${path}: unknown labelPolicy "${node.labelPolicy}"`);
    }
  }

  if (type === "text") {
    if (!node.style) problems.push(`${path}: a text run needs a style`);
    for (const [index, segment] of (node.segments ?? []).entries()) {
      checkSegment(segment, `${path}.segments[${index}]`, vocabulary, problems);
    }
    for (const [index, segment] of (node.fallback ?? []).entries()) {
      checkSegment(segment, `${path}.fallback[${index}]`, vocabulary, problems);
    }
  }

  if (type === "stack") {
    const children = node.children ?? [];
    if (children.length === 0) problems.push(`${path}: an empty stack draws nothing`);
    for (const [index, child] of children.entries()) {
      walk(child, `${path}.children[${index}]`, vocabulary, problems);
    }
  }
}

/**
 * Finds every color a node names and checks each one.
 *
 * A misspelled slot or a malformed hex is the one authoring typo the renderer
 * cannot signal: `ShareCardColor` treats any unrecognised string as a hex and
 * `color(fromHex:)` falls back to `0`, so the mistake ships as opaque black
 * rather than as a missing element. Children are skipped — `walk` recurses into
 * them so their problems are reported at their own path.
 *
 * @param {*} value Node or nested value to scan.
 * @param {string} path Human-readable location.
 * @param {string[]} problems Accumulator.
 * @return {void}
 */
function checkColors(value, path, problems) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => checkColors(entry, `${path}[${index}]`, problems));
    return;
  }
  if (typeof value !== "object" || value === null) return;
  for (const [key, nested] of Object.entries(value)) {
    if (key === "children") continue;
    if (COLOR_KEYS.has(key)) checkColor(nested, `${path}.${key}`, problems);
    else checkColors(nested, `${path}.${key}`, problems);
  }
}

/**
 * Checks a value at a color-bearing key, in any spelling the format accepts:
 * a bare string, a tint object, a fill, a stroke, or an array of any of those.
 * @param {*} value Value to check.
 * @param {string} path Human-readable location.
 * @param {string[]} problems Accumulator.
 * @return {void}
 */
function checkColor(value, path, problems) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => checkColor(entry, `${path}[${index}]`, problems));
    return;
  }
  if (typeof value === "string") {
    if (!COLOR_SLOTS.has(value) && !HEX_COLOR.test(value)) {
      problems.push(
        `${path}: unknown color "${value}" — the renderer would draw it opaque black`
      );
    }
    return;
  }
  checkColors(value, path, problems);
}

/**
 * Checks a text segment's stat reference.
 * @param {*} segment Segment value.
 * @param {string} path Human-readable location.
 * @param {object} vocabulary Known names.
 * @param {string[]} problems Accumulator.
 * @return {void}
 */
function checkSegment(segment, path, vocabulary, problems) {
  if (typeof segment === "string") return;
  if (typeof segment !== "object" || segment === null) {
    problems.push(`${path}: not a literal or a stat segment`);
    return;
  }
  if (segment.literal !== undefined) return;
  checkStat(segment.stat, `${path}.stat`, vocabulary, problems);
  if (segment.facet && !["value", "label", "detail"].includes(segment.facet)) {
    problems.push(`${path}: unknown facet "${segment.facet}"`);
  }
}

/**
 * Checks a stat reference against the shipped stat catalog.
 * @param {*} stat Reference in either spelling.
 * @param {string} path Human-readable location.
 * @param {object} vocabulary Known names.
 * @param {string[]} problems Accumulator.
 * @return {void}
 */
function checkStat(stat, path, vocabulary, problems) {
  const kind = typeof stat === "string" ? stat : stat?.kind;
  if (!kind) {
    problems.push(`${path}: no stat named`);
    return;
  }
  if (!vocabulary.stats.has(kind)) {
    problems.push(
      `${path}: unknown stat "${kind}" — the element would silently disappear`
    );
  }
}

/**
 * Reads the vocabulary out of the Swift sources.
 * @return {object} Known names and the renderer version.
 */
export function readVocabulary() {
  const format = read(PATHS.format);
  const label = read(PATHS.label);
  const sticker = read(PATHS.sticker);
  return {
    elements: elementTypes(format),
    stats: enumCases(sticker, "ShareStatStickerKind"),
    placements: enumCases(label, "ShareCardLabelPlacement"),
    policies: enumCases(label, "ShareCardLabelPolicy"),
    requirements: enumCases(format, "ShareCardRequirement"),
    version: rendererVersion(format),
  };
}

/**
 * Validates the bundled payload.
 * @return {string[]} Problems, empty when valid.
 */
export function validateBundledPayload() {
  return validate(readVocabulary(), JSON.parse(read(PATHS.payload)));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const problems = validateBundledPayload();
  if (problems.length > 0) {
    console.error("Share card templates are invalid:");
    for (const problem of problems) console.error(`  - ${problem}`);
    process.exit(1);
  }
  console.log("Share card templates are valid.");
}
