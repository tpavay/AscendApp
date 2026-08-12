import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

import {
  PATHS,
  elementTypes,
  enumCases,
  rendererVersion,
  readVocabulary,
  validate,
  validateBundledPayload,
} from "../validate-share-card-templates.mjs";

const REPOSITORY_ROOT = new URL("../../", import.meta.url);

test("the bundled share card templates are valid", () => {
  assert.deepEqual(validateBundledPayload(), []);
});

test("bundled templates never substitute plain text for the fixed wordmark", () => {
  const payload = JSON.parse(readFileSync(new URL(PATHS.payload, REPOSITORY_ROOT)));
  const brandedTextNodes = [];

  // A segment is either a bare string or an object whose `literal` and
  // `placeholder` both reach the card, and a text node can carry the brand in
  // either `segments` or the `fallback` it swaps in.
  const brandedRun = (segments) =>
    segments?.some((segment) => {
      const literals =
        typeof segment === "string" ? [segment] : [segment?.literal, segment?.placeholder];
      return literals.some((literal) => typeof literal === "string" && literal.includes("ASCEND"));
    });

  const visit = (node, templateId) => {
    if (!node || typeof node !== "object") return;
    if (node.type === "text" && (brandedRun(node.segments) || brandedRun(node.fallback))) {
      brandedTextNodes.push(templateId);
    }
    node.children?.forEach((child) => visit(child, templateId));
  };

  payload.templates.forEach((template) => visit(template.root, template.id));
  assert.deepEqual(brandedTextNodes, []);
});

test("bundled card copy never says global", () => {
  const payload = readFileSync(new URL(PATHS.payload, REPOSITORY_ROOT), "utf8");
  assert.equal(payload.toLowerCase().includes("global"), false);
});

test("the vocabulary is read out of the Swift sources", () => {
  const vocabulary = readVocabulary();

  // If any of these went missing the validator would silently pass everything.
  assert.ok(vocabulary.elements.has("metric"), "metric element");
  assert.ok(vocabulary.elements.has("stack"), "stack element");
  assert.ok(vocabulary.elements.has("splits"), "splits element");
  assert.ok(vocabulary.stats.has("steps"), "steps stat");
  assert.ok(vocabulary.stats.has("climbRankWithTotal"), "climbRankWithTotal stat");
  assert.ok(vocabulary.placements.has("leading"), "leading placement");
  assert.ok(vocabulary.policies.has("automatic"), "automatic policy");
  assert.ok(vocabulary.requirements.has("climb"), "climb requirement");
  assert.ok(vocabulary.version >= 1, "renderer version");
});

test("a template naming an unknown stat fails validation", () => {
  const vocabulary = readVocabulary();
  const problems = validate(vocabulary, {
    formatVersion: 1,
    templates: [
      {
        id: "typo",
        title: "Typo",
        minRendererVersion: 1,
        requires: ["climb"],
        root: {type: "metric", stat: "stpes", value: {size: 40}},
      },
    ],
  });

  assert.equal(problems.length, 1);
  assert.match(problems[0], /unknown stat "stpes"/);
});

test("a template naming an unknown element fails validation", () => {
  const vocabulary = readVocabulary();
  const problems = validate(vocabulary, {
    formatVersion: 1,
    templates: [
      {
        id: "future",
        title: "Future",
        minRendererVersion: 1,
        root: {type: "hologram"},
      },
    ],
  });

  assert.equal(problems.length, 1);
  assert.match(problems[0], /unknown element type "hologram"/);
});

// A misspelled slot or a malformed hex is the one typo the renderer cannot
// signal: it draws opaque black instead of dropping the element.
test("a template naming an unknown color fails validation", () => {
  const vocabulary = readVocabulary();
  const problems = validate(vocabulary, {
    formatVersion: 1,
    templates: [
      {
        id: "tints",
        title: "Tints",
        minRendererVersion: 1,
        background: {kind: "linearGradient", stops: ["lable", "#0B0B0B"]},
        root: {
          type: "text",
          segments: ["Hello"],
          style: {size: 20, tint: {color: "#F4F1E", opacity: 0.5}},
        },
      },
    ],
  });

  assert.equal(problems.length, 2, problems.join("; "));
  assert.match(problems[0], /unknown color "lable"/);
  assert.match(problems[1], /unknown color "#F4F1E"/);
});

// The wordmark tint sits beside `root`, and the splits tints sit on a spec the
// walk does not treat as a node, so both need naming explicitly or a typo ships
// the card's only brand mark - and its bars - as opaque black.
test("a typo in the wordmark or splits tints fails validation", () => {
  const vocabulary = readVocabulary();
  const problems = validate(vocabulary, {
    formatVersion: 1,
    templates: [
      {
        id: "tints",
        title: "Tints",
        minRendererVersion: 1,
        wordmarkTint: "vlaue",
        root: {
          type: "splits",
          layout: "stepQuintiles",
          textTint: "#0D0D1",
          fastTint: "value",
          slowTint: "lable",
          trackTint: "#DEDEDE",
        },
      },
    ],
  });

  assert.equal(problems.length, 3, problems.join("; "));
  assert.match(problems[0], /wordmarkTint: unknown color "vlaue"/);
  assert.match(problems[1], /textTint: unknown color "#0D0D1"/);
  assert.match(problems[2], /slowTint: unknown color "lable"/);
});

test("the context color slots and hex literals pass validation", () => {
  const vocabulary = readVocabulary();
  const problems = validate(vocabulary, {
    formatVersion: 1,
    templates: [
      {
        id: "tints",
        title: "Tints",
        minRendererVersion: 1,
        background: "#0B0B0B",
        root: {
          type: "stack",
          background: {kind: "material", material: "thin", opacity: 0.4},
          border: {tint: {color: "label", opacity: 0.3}, width: 1},
          children: [
            {type: "rule", tint: "value"},
            {type: "artwork", overlay: ["#000000", {color: "value", opacity: 0}]},
          ],
        },
      },
    ],
  });

  assert.deepEqual(problems, []);
});

test("a template authored above the shipped renderer fails validation", () => {
  const vocabulary = readVocabulary();
  const problems = validate(vocabulary, {
    formatVersion: 1,
    templates: [
      {
        id: "ahead",
        title: "Ahead",
        minRendererVersion: vocabulary.version + 1,
        root: {type: "spacer"},
      },
    ],
  });

  assert.equal(problems.length, 1);
  assert.match(problems[0], /above the shipped renderer/);
});

test("the Swift readers tolerate their real sources", () => {
  const format =
    'enum ShareCardElement: Codable {\n' +
    '    init(from decoder: any Decoder) throws {\n' +
    '        case "stack": self = .stack(try ShareCardStack(from: decoder))\n' +
    '        case "text": self = .text(try ShareCardText(from: decoder))\n' +
    "    }\n}\n" +
    "    static let rendererVersion = 7\n";

  assert.deepEqual([...elementTypes(format)], ["stack", "text"]);
  assert.equal(rendererVersion(format), 7);
  assert.deepEqual(
    [...enumCases("enum Thing: String {\n    case one\n    case two\n}\n", "Thing")],
    ["one", "two"]
  );
});
