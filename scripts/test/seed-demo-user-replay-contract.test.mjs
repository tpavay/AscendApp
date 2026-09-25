import assert from "node:assert/strict";
import {test} from "node:test";

import {
  buildDemoAttemptCurveWrite,
  buildDemoReplayEntry,
} from "../seed/lib/demo-replay-entry.mjs";
import {raceGoalKeysByWorkoutId} from "../lib/live-replay-race-best.mjs";

test("demo replay entries carry the server context contract", () => {
  const updatedAt = {kind: "server-timestamp"};
  const entry = buildDemoReplayEntry({
    context: {
      contextId: "empire-state-building",
      contextType: "live_climb",
      durationSeconds: 480,
      finalSteps: 1_860,
      splitSteps: [0, 420, 900, 1_400, 1_860],
      workoutId: "workout-1",
    },
    identityState: "published",
    schemaVersion: 1,
    splitIndex: 2,
    splitIntervalSeconds: 120,
    updatedAt,
    user: {
      avatarToken: "TP",
      displayName: "Test Person",
      photoURL: "",
      uid: "user-1",
    },
  });

  assert.equal(entry.contextId, "empire-state-building");
  assert.equal(entry.contextType, "live_climb");
  assert.equal(entry.stepsAtBucket, 900);
  assert.equal(entry.updatedAt, updatedAt);
  // A tower entry carries no goal keys; only the global Just Climb board
  // races goals.
  assert.equal("bestForGoals" in entry, false);
});

test("a demo Just Climb entry carries the goal keys its one attempt wins", () => {
  const entry = buildDemoReplayEntry({
    context: {
      contextId: "global",
      contextType: "just_climb",
      durationSeconds: 480,
      finalSteps: 1_860,
      splitSteps: [0, 420, 900, 1_400, 1_860],
      workoutId: "workout-1",
    },
    identityState: "published",
    schemaVersion: 1,
    splitIndex: 2,
    splitIntervalSeconds: 120,
    updatedAt: {kind: "server-timestamp"},
    user: {
      avatarToken: "TP",
      displayName: "Test Person",
      photoURL: "",
      uid: "user-1",
    },
  });

  // The demo user's only attempt is their best under every step goal it
  // reached and every duration goal, so a goal session in staging still
  // meets them on the board.
  assert.equal(entry.isBestForUser, true);
  assert.ok(entry.bestForGoals.includes("steps:1800"));
  assert.equal(entry.bestForGoals.includes("steps:1900"), false);
  assert.ok(entry.bestForGoals.includes("duration:300"));
  assert.ok(entry.bestForGoals.includes("duration:10800"));
});

// The server reads a Just Climb attempt's curve from `attemptCurves` and only
// rebuilds one from the bucket entries when the document is missing - and a
// rebuild from `stepsAtBucket` anchors every value one interval late, because
// bucket 0 is the start line. The demo seed therefore stores the exact curve
// it judged the entry's goal keys on, so a reconciliation over the staging
// board derives the same keys the seed wrote.
test("a demo Just Climb attempt stores the curve its goal keys were judged on", () => {
  const updatedAt = {kind: "server-timestamp"};
  const input = {
    context: {
      contextId: "global",
      contextType: "just_climb",
      durationSeconds: 480,
      finalSteps: 1_860,
      splitSteps: [0, 420, 900, 1_400, 1_860],
      workoutId: "workout-1",
    },
    identityState: "published",
    schemaVersion: 1,
    splitIndex: 0,
    splitIntervalSeconds: 120,
    updatedAt,
    user: {
      avatarToken: "TP",
      displayName: "Test Person",
      photoURL: "",
      uid: "user-1",
    },
  };

  const curve = buildDemoAttemptCurveWrite(input);
  assert.deepEqual(curve, {
    finalDurationSeconds: 480,
    finalSteps: 1_860,
    schemaVersion: 1,
    splitIntervalSeconds: 120,
    splitSteps: [420, 900, 1_400, 1_860],
    updatedAt,
    userId: "user-1",
    workoutId: "workout-1",
  });

  const entry = buildDemoReplayEntry(input);
  assert.deepEqual(
    raceGoalKeysByWorkoutId([curve]).get("workout-1"),
    entry.bestForGoals
  );
});

test("a demo tower attempt stores no curve", () => {
  assert.equal(
    buildDemoAttemptCurveWrite({
      context: {
        contextId: "empire-state-building",
        contextType: "live_climb",
        durationSeconds: 480,
        finalSteps: 1_860,
        splitSteps: [0, 420, 900, 1_400, 1_860],
        workoutId: "workout-1",
      },
      splitIntervalSeconds: 120,
      updatedAt: {kind: "server-timestamp"},
      user: {uid: "user-1"},
    }),
    null
  );
});
