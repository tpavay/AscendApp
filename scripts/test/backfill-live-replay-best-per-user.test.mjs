import test from "node:test";
import assert from "node:assert/strict";

import {
  MAX_REPLAY_SPLIT_CHECKPOINTS,
  bestAttemptWorkoutId,
  bestForUserFlagUpdates,
  ranksOnSteps,
  userAttemptEntry,
} from "../backfill-live-replay-best-per-user.mjs";

// The runbook makes running this against production a release step, and the
// flag it writes is what every live-race read filters on: a wrong winner is a
// wrong rival frozen on every board until the next publish. So the selection is
// exercised here against fixtures, on both metrics, before it ever meets a row.

const LIVE_CLIMB = "live_climb";
const ROUTINE = "routine";
const ROUTINE_TEMPLATE = "routine_template";
const CLIMBER = "climber-a";

function attempt(overrides) {
  return {
    userId: CLIMBER,
    splitBucketCount: 61,
    ...overrides,
  };
}

function parsed(data, contextType) {
  const entry = userAttemptEntry(data, data.workoutId, contextType);
  assert.notEqual(entry, null, `${data.workoutId} should be a usable attempt`);
  return entry;
}

function flagChanges(updates) {
  return updates
    .map((update) => [update.workoutId, update.isBestForUser])
    .sort(([left], [right]) => left.localeCompare(right));
}

// Mirrors `ranksOnSteps` in functions/src/liveReplayLeaderboard.ts: only a
// routine template ranks on steps. A plain routine ranks on the clock even
// though it is a routine.
test("only a routine_template board ranks on steps", () => {
  assert.equal(ranksOnSteps(ROUTINE_TEMPLATE), true);
  assert.equal(ranksOnSteps(LIVE_CLIMB), false);
  assert.equal(ranksOnSteps(ROUTINE), false);
  assert.equal(ranksOnSteps("just_climb"), false);
});

test("a routine_template board keeps the most steps, not the fastest run", () => {
  const attempts = [
    parsed(attempt({
      workoutId: "fast-few",
      completionDurationSeconds: 600,
      finalSteps: 900,
    }), ROUTINE_TEMPLATE),
    parsed(attempt({
      workoutId: "slow-many",
      completionDurationSeconds: 1200,
      finalSteps: 1400,
      isBestForUser: false,
    }), ROUTINE_TEMPLATE),
    parsed(attempt({
      workoutId: "middle",
      completionDurationSeconds: 900,
      finalSteps: 1100,
      isBestForUser: true,
    }), ROUTINE_TEMPLATE),
  ];

  assert.equal(bestAttemptWorkoutId(attempts, ROUTINE_TEMPLATE), "slow-many");
  assert.deepEqual(flagChanges(bestForUserFlagUpdates(attempts, ROUTINE_TEMPLATE)), [
    ["middle", false],
    ["slow-many", true],
  ]);
});

test("a live_climb board keeps the fastest run", () => {
  const attempts = [
    parsed(attempt({
      workoutId: "slow",
      completionDurationSeconds: 700,
      finalSteps: 551,
      isBestForUser: true,
    }), LIVE_CLIMB),
    parsed(attempt({
      workoutId: "fast",
      completionDurationSeconds: 512,
      finalSteps: 551,
    }), LIVE_CLIMB),
  ];

  assert.equal(bestAttemptWorkoutId(attempts, LIVE_CLIMB), "fast");
  assert.deepEqual(flagChanges(bestForUserFlagUpdates(attempts, LIVE_CLIMB)), [
    ["fast", true],
    ["slow", false],
  ]);
});

// A plain routine sits outside collapsesRepeatFinishers next to just_climb and
// still ranks on the clock; the metric list and the collapse list are not the
// same list.
test("a plain routine board ranks on the clock like a live climb", () => {
  const attempts = [
    parsed(attempt({
      workoutId: "more-steps-slower",
      completionDurationSeconds: 1500,
      finalSteps: 2000,
    }), ROUTINE),
    parsed(attempt({
      workoutId: "fewer-steps-faster",
      completionDurationSeconds: 1200,
      finalSteps: 1500,
    }), ROUTINE),
  ];

  assert.equal(bestAttemptWorkoutId(attempts, ROUTINE), "fewer-steps-faster");
});

// Both the trigger and this script must pick the same row or they flag
// different attempts; the immutable workout ID is the shared tiebreak.
test("equal values resolve on workout ID so the trigger and the backfill agree", () => {
  const attempts = [
    parsed(attempt({workoutId: "b", completionDurationSeconds: 600}), LIVE_CLIMB),
    parsed(attempt({workoutId: "a", completionDurationSeconds: 600}), LIVE_CLIMB),
    parsed(attempt({workoutId: "c", completionDurationSeconds: 600}), LIVE_CLIMB),
  ];

  assert.equal(bestAttemptWorkoutId(attempts, LIVE_CLIMB), "a");
});

test("attempts already carrying the right flag are not rewritten", () => {
  const attempts = [
    parsed(attempt({
      workoutId: "best",
      completionDurationSeconds: 500,
      isBestForUser: true,
    }), LIVE_CLIMB),
    parsed(attempt({
      workoutId: "other",
      completionDurationSeconds: 900,
      isBestForUser: false,
    }), LIVE_CLIMB),
    parsed(attempt({
      workoutId: "never-flagged",
      completionDurationSeconds: 950,
    }), LIVE_CLIMB),
  ];

  assert.deepEqual(bestForUserFlagUpdates(attempts, LIVE_CLIMB), []);
});

// The fail-closed branch. A climber whose rows carry nothing usable for the
// board's metric resolves no winner, and the only acceptable outcome is that
// nothing is written - never `isBestForUser: false` across their rows, which
// would strip them out of the live race on the strength of a value that could
// not be read.
test("rows without a usable value for the board's metric are rejected, not demoted", () => {
  const unusable = [
    attempt({workoutId: "no-steps", completionDurationSeconds: 600, isBestForUser: true}),
    attempt({workoutId: "negative-steps", completionDurationSeconds: 600, finalSteps: -5}),
    attempt({workoutId: "string-steps", completionDurationSeconds: 600, finalSteps: "900"}),
    attempt({workoutId: "fractional-steps", completionDurationSeconds: 600, finalSteps: 900.5}),
    attempt({workoutId: "no-owner", userId: undefined, completionDurationSeconds: 600, finalSteps: 900}),
  ];

  for (const data of unusable) {
    assert.equal(
      userAttemptEntry(data, data.workoutId, ROUTINE_TEMPLATE),
      null,
      `${data.workoutId} must be rejected before it can reach the flag diff`
    );
  }

  const usable = unusable
    .map((data) => userAttemptEntry(data, data.workoutId, ROUTINE_TEMPLATE))
    .filter((entry) => entry !== null);
  assert.equal(bestAttemptWorkoutId(usable, ROUTINE_TEMPLATE), null);
  assert.deepEqual(bestForUserFlagUpdates(usable, ROUTINE_TEMPLATE), []);
});

test("no winner means no writes, whatever the rows currently carry", () => {
  assert.deepEqual(bestForUserFlagUpdates([], LIVE_CLIMB), []);
  assert.deepEqual(bestForUserFlagUpdates([], ROUTINE_TEMPLATE), []);
});

test("a duration-ranked board rejects a row with no duration and ignores its steps", () => {
  assert.equal(
    userAttemptEntry(
      attempt({workoutId: "steps-only", finalSteps: 551}),
      "steps-only",
      LIVE_CLIMB
    ),
    null
  );
  assert.equal(
    parsed(attempt({workoutId: "no-steps", completionDurationSeconds: 600}), LIVE_CLIMB)
      .rankingValue,
    600
  );
});

test("a steps-ranked board takes its ranking value from finalSteps", () => {
  const entry = parsed(attempt({
    workoutId: "w",
    completionDurationSeconds: 600,
    finalSteps: 1400,
  }), ROUTINE_TEMPLATE);

  assert.equal(entry.rankingValue, 1400);
  assert.equal(entry.workoutId, "w");
  assert.equal(entry.userId, CLIMBER);
  assert.equal(entry.splitBucketCount, 61);
  assert.equal(entry.hasKnownBucketSpan, true);
  assert.equal(entry.isBestForUser, false);
});

// A row written before the span was stored sweeps the whole checkpoint range,
// so a promoted climber's final bucket is never stranded; the dry-run estimate
// stays honest about how many buckets that really is.
test("a row with no stored span sweeps every checkpoint and reports the span as unknown", () => {
  const entry = parsed({
    userId: CLIMBER,
    workoutId: "legacy",
    completionDurationSeconds: 125,
    splitIntervalSeconds: 10,
  }, LIVE_CLIMB);

  assert.equal(entry.splitBucketCount, MAX_REPLAY_SPLIT_CHECKPOINTS);
  assert.equal(entry.hasKnownBucketSpan, false);
  assert.equal(entry.estimatedEntryCount, 13);
});
