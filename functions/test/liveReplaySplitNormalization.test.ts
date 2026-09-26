import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  isPreFixSamplerClamp,
  normalizeReplaySplitSteps,
  replayBoardSplitSteps,
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
  boardCases: VectorCase[];
};

test("TS normalization matches the shared parity vector", () => {
  assert.ok(vector.cases.length >= 10, "vector should carry every shape");

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

test("TS board grid matches the shared parity vector", () => {
  assert.ok(vector.boardCases.length >= 5, "vector should carry every shape");

  for (const testCase of vector.boardCases) {
    const actual = replayBoardSplitSteps({
      splitIntervalSeconds: testCase.splitIntervalSeconds,
      splitSteps: testCase.splitSteps,
      finalDurationSeconds: testCase.finalDurationSeconds,
      finalSteps: testCase.finalSteps,
    });
    assert.deepEqual(
      actual,
      testCase.expected,
      `board case ${testCase.name} diverged from the shared vector`
    );
  }
});

interface StoredClimb {
  splitIntervalSeconds: number;
  splitSteps: number[];
  durationSeconds: number;
  steps: number;
}

/**
 * The captain's 1:30:07 climb as the pre-fix sampler stored it.
 * @return {StoredClimb} The stored curve and the workout's final stats.
 */
function preFixNinetyMinuteClimb(): StoredClimb {
  const fixturePath = join(
    __dirname,
    "../../../SharedTestVectors/pre-fix-sampler-long-climbs.json"
  );
  const fixture = JSON.parse(readFileSync(fixturePath, "utf8")) as {
    climbs: StoredClimb[];
  };
  return fixture.climbs[0];
}

test("the captain's clamped climb publishes where he really was", () => {
  const climb = preFixNinetyMinuteClimb();
  const board = replayBoardSplitSteps({
    splitIntervalSeconds: climb.splitIntervalSeconds,
    splitSteps: climb.splitSteps,
    finalDurationSeconds: climb.durationSeconds,
    finalSteps: climb.steps,
  });

  // One entry for every ten seconds of the 5,407.98-second climb.
  assert.equal(board.length, 541);
  // The first 59:50 is exactly what was recorded.
  assert.deepEqual(board.slice(0, 359), climb.splitSteps.slice(0, 359));
  // 60:00 no longer carries the finish: from the 5,015 steps at 59:50 the
  // unrecorded half hour runs at its true average pace to 7,708.
  assert.equal(board[358], 5015);
  assert.ok(board[359] > 5015 && board[359] < 5040, `60:00 = ${board[359]}`);
  assert.ok(board[449] > 6300 && board[449] < 6400, `75:00 = ${board[449]}`);
  assert.equal(board[540], 7708);
  for (let index = 1; index < board.length; index += 1) {
    assert.ok(board[index] >= board[index - 1], `bucket ${index} regressed`);
  }
});

test("a curve the pre-fix sampler never clamped is not repaired", () => {
  assert.equal(isPreFixSamplerClamp(360, 10, 5407.98), true);
  assert.equal(isPreFixSamplerClamp(360, 10, 3600), true);
  // Ending inside its last window, the last bucket is honest.
  assert.equal(isPreFixSamplerClamp(360, 10, 3599.9), false);
  // Compacted curves always run past their finish.
  assert.equal(isPreFixSamplerClamp(271, 20, 5407.98), false);
  assert.equal(isPreFixSamplerClamp(181, 20, 3605), false);
});

test("a ten-hour compacted curve publishes every board bucket", () => {
  // The sampler's curve for a steady 80 spm climb of ten hours: 226
  // checkpoints at 160 seconds.
  const intervalSeconds = 160;
  const durationSeconds = 36000;
  const finalSteps = 48000;
  const splitSteps = Array.from({length: 226}, (_, index) =>
    Math.min(finalSteps, Math.floor(((index * 160) + 159) * 4 / 3))
  );

  const board = replayBoardSplitSteps({
    splitIntervalSeconds: intervalSeconds,
    splitSteps,
    finalDurationSeconds: durationSeconds,
    finalSteps,
  });

  assert.equal(board.length, 3601);
  // Rivals move at the pace they climbed, well past the old 60:00 wall.
  assert.ok(Math.abs(board[359] - 4800) <= 3, `1h = ${board[359]}`);
  assert.ok(Math.abs(board[1799] - 24000) <= 3, `5h = ${board[1799]}`);
  assert.equal(board[3600], finalSteps);
});

