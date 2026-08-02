import assert from "node:assert/strict";
import test from "node:test";

import {
  elementTypes,
  enumCases,
  rendererVersion,
  readVocabulary,
  validate,
  validateBundledPayload,
} from "../validate-share-card-templates.mjs";

test("the bundled share card templates are valid", () => {
  assert.deepEqual(validateBundledPayload(), []);
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
