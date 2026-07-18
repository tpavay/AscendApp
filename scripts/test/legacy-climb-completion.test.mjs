import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join} from "node:path";
import {isRecoverableLegacyCompletion} from "../lib/legacy-climb-completion.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const vectorPath = join(
  here,
  "../../SharedTestVectors/legacy-recoverable-completion-vector.json"
);
const vector = JSON.parse(readFileSync(vectorPath, "utf8"));

// Test 7 (predicate parity): the mjs predicate is the SAME contract the Swift
// and TS predicates are, pinned by the one shared vector so the four sites
// (Swift, TS, this mjs lib, the backfills) cannot drift. This is the "import/pin
// the shared vector instead of a fourth copy" the #229 review asked for.
test("mjs predicate matches the shared parity vector", () => {
  assert.ok(vector.cases.length >= 10, "vector should carry every shape");

  for (const testCase of vector.cases) {
    const actual = isRecoverableLegacyCompletion({
      source: testCase.source,
      climbId: testCase.climbId,
      stopReason: testCase.stopReason,
      steps: testCase.steps,
      targetStepCount: testCase.targetStepCount,
    });
    assert.equal(
      actual,
      testCase.expected,
      `case ${testCase.name} expected ${testCase.expected}`
    );
  }
});
