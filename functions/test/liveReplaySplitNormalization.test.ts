import test from "node:test";
import assert from "node:assert/strict";
import {normalizeReplaySplitSteps} from "../src/liveReplaySplitNormalization.js";

test("normalizes a final-jump Giza replay curve", () => {
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
  assert.equal(steps[0], 0);
  assert.equal(steps[42], 752);
  assert.equal(steps[45], 809);
});

test("preserves useful monotonic replay progress", () => {
  const steps = normalizeReplaySplitSteps({
    splitIntervalSeconds: 10,
    splitSteps: [0, 14, 30, 44, 63],
    finalDurationSeconds: 42,
    finalSteps: 63,
  });

  assert.deepEqual(steps, [0, 14, 30, 44, 63]);
});

test("clamps regressing replay buckets", () => {
  const steps = normalizeReplaySplitSteps({
    splitIntervalSeconds: 10,
    splitSteps: [0, 18, 12, 40],
    finalDurationSeconds: 31,
    finalSteps: 40,
  });

  assert.deepEqual(steps, [0, 18, 18, 40]);
});
