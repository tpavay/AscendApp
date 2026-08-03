import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  normalizeReplaySplitSteps,
} from "../src/liveReplaySplitNormalization.js";

interface VectorCase {
  name: string;
  splitIntervalSeconds: number;
  splitSteps: number[];
  finalDurationSeconds: number;
  finalSteps: number;
  expected: number[];
}

// Compiled output is CommonJS (see tsconfig NodeNext + no package "type"), so
// __dirname is the compiled lib/test directory; walk up to the repo root.
const vectorPath = join(
  __dirname,
  "../../../SharedTestVectors/live-replay-split-normalization-vector.json"
);
const vector = JSON.parse(readFileSync(vectorPath, "utf8")) as {
  cases: VectorCase[];
};

test("TS normalization matches the shared parity vector", () => {
  assert.ok(vector.cases.length >= 7, "vector should carry every shape");

  for (const testCase of vector.cases) {
    const actual = normalizeReplaySplitSteps({
      splitIntervalSeconds: testCase.splitIntervalSeconds,
      splitSteps: testCase.splitSteps,
      finalDurationSeconds: testCase.finalDurationSeconds,
      finalSteps: testCase.finalSteps,
    });
    assert.deepEqual(
      actual,
      testCase.expected,
      `case ${testCase.name} diverged from the shared vector`
    );
  }
});

test("reconstructs a fractional-duration replay curve at bucket ends", () => {
  // Only the server sees sub-second durations; iOS floors before normalizing,
  // so this shape cannot live in the cross-language vector.
  const steps = normalizeReplaySplitSteps({
    splitIntervalSeconds: 10,
    splitSteps: [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 809,
    ],
    finalDurationSeconds: 451.9039319753647,
    finalSteps: 809,
  });

  assert.equal(steps.length, 46);
  assert.equal(steps[0], 18);
  assert.equal(steps[42], 770);
  assert.equal(steps[45], 809);
});
