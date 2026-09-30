import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join} from "node:path";
import {
  isPreFixSamplerClamp,
  normalizeReplaySplitSteps,
  replayBoardSplitSteps,
} from "../lib/live-replay-split-normalization.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const vector = JSON.parse(
  readFileSync(
    join(here, "../../SharedTestVectors/live-replay-split-normalization-vector.json"),
    "utf8"
  )
);

test("the scripts normalizer matches the shared vector the function and iOS read", () => {
  assert.ok(vector.cases.length >= 10);
  for (const testCase of vector.cases) {
    assert.deepEqual(
      normalizeReplaySplitSteps(testCase),
      testCase.expected,
      `case ${testCase.name} diverged from the shared vector`
    );
  }
});

test("the scripts board grid matches the shared vector the function reads", () => {
  assert.ok(vector.boardCases.length >= 5);
  for (const testCase of vector.boardCases) {
    assert.deepEqual(
      replayBoardSplitSteps(testCase),
      testCase.expected,
      `board case ${testCase.name} diverged from the shared vector`
    );
  }
});

test("recognises only the clamp the pre-fix sampler wrote", () => {
  assert.equal(isPreFixSamplerClamp(360, 10, 5407.98), true);
  assert.equal(isPreFixSamplerClamp(360, 10, 3599.9), false);
  assert.equal(isPreFixSamplerClamp(271, 20, 5407.98), false);
  assert.equal(isPreFixSamplerClamp(360, 20, 7300), false);
});
