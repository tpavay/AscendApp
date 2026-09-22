import assert from "node:assert/strict";
import {test} from "node:test";

import {buildDemoReplayEntry} from "../seed/lib/demo-replay-entry.mjs";

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
