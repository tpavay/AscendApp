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
});
