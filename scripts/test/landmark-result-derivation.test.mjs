import test from "node:test";
import assert from "node:assert/strict";
import {
  groupCompletions,
  deriveLandmarkResult,
  shouldSkipLandmarkResultWrite,
} from "../lib/landmark-result-derivation.mjs";

const ESB = "empire-state-building";

test("groups only completed landmark workouts, by user then climb", () => {
  const byUser = groupCompletions([
    {userId: "u1", workoutId: "w1", data: completedWorkout({climbId: ESB})},
    {userId: "u1", workoutId: "w2", data: completedWorkout({climbId: "cn-tower"})},
    {userId: "u1", workoutId: "w3", data: completedWorkout({
      climbId: "cn-tower",
      steps: 900,
      targetStepCount: 1000,
      stopReason: "user_stopped",
    })},
    {userId: "u1", workoutId: "w4", data: {source: "manual"}},
    {userId: "u2", workoutId: "w5", data: completedWorkout({climbId: ESB})},
  ]);

  assert.equal(byUser.get("u1").get(ESB).length, 1);
  assert.equal(byUser.get("u1").get("cn-tower").length, 1); // short one dropped
  assert.equal(byUser.get("u2").get(ESB).length, 1);
});

// Test 3 regression at the derivation level: three completed workouts of one
// climb collapse to ONE landmark result (attemptCount 3, one doc) - killing the
// "globe 1, aggregate 3" split.
test("three completions of one climb derive one result, attemptCount 3", () => {
  const byUser = groupCompletions([
    {userId: "u1", workoutId: "a", data: completedWorkout({climbId: ESB})},
    {userId: "u1", workoutId: "b", data: completedWorkout({climbId: ESB})},
    {userId: "u1", workoutId: "c", data: completedWorkout({climbId: ESB})},
  ]);
  const completions = byUser.get("u1").get(ESB);
  const result = deriveLandmarkResult(ESB, completions);
  assert.equal(result.attemptCount, 3);
  assert.equal(result.climbId, ESB);
});

// Test 5 (idempotent backfill run TWICE): apply the plan over an in-memory
// store, then re-plan+apply. The second pass writes zero documents because the
// stored projection already reflects the derived event (validate-before-write).
test("materialization is idempotent - a second apply writes nothing", () => {
  const workouts = [
    {userId: "u1", workoutId: "a", data: completedWorkout({climbId: ESB})},
    {userId: "u1", workoutId: "b", data: completedWorkout({climbId: "cn-tower"})},
  ];
  const store = new Map();

  const first = applyOnce(workouts, store);
  assert.equal(first, 2, "first apply materializes both landmarks");

  const second = applyOnce(workouts, store);
  assert.equal(second, 0, "second apply is a no-op");

  const third = applyOnce(workouts, store);
  assert.equal(third, 0, "a third apply is still a no-op");
});

test("materialization rewrites once a new completion of a climb appears", () => {
  const workouts = [
    {userId: "u1", workoutId: "a", data: completedWorkout({climbId: ESB})},
  ];
  const store = new Map();
  assert.equal(applyOnce(workouts, store), 1);

  workouts.push({
    userId: "u1",
    workoutId: "b",
    data: completedWorkout({climbId: ESB, durationSeconds: 500}),
  });
  assert.equal(applyOnce(workouts, store), 1, "new completion triggers rewrite");
  assert.equal(applyOnce(workouts, store), 0, "then converges again");
});

/**
 * Runs one plan+apply pass of the backfill's core over an in-memory store,
 * mirroring scripts/backfill-landmark-results.mjs without Firestore.
 * @param {object[]} workouts Raw workouts with owning user ids.
 * @param {Map<string, object>} store In-memory landmarkResults store.
 * @return {number} Documents written this pass.
 */
function applyOnce(workouts, store) {
  const byUser = groupCompletions(workouts);
  let written = 0;
  for (const [userId, byClimb] of byUser) {
    for (const [climbId, completions] of byClimb) {
      const projection = deriveLandmarkResult(climbId, completions);
      const key = `${userId}/${climbId}`;
      const existing = store.get(key) ?? null;
      if (shouldSkipLandmarkResultWrite(existing, projection)) {
        continue;
      }
      store.set(key, projection);
      written += 1;
    }
  }
  return written;
}

/**
 * Builds a completed live-climb workout document.
 * @param {object} overrides Field overrides.
 * @return {Record<string, unknown>} Workout document.
 */
function completedWorkout(overrides = {}) {
  const target = overrides.targetStepCount ?? 2096;
  return {
    source: "headphone_motion",
    steps: overrides.steps ?? 2096,
    durationSeconds: overrides.durationSeconds ?? 900,
    startedAt: {toMillis: () => overrides.startedAtMillis ?? 1_700_000_000_000},
    sourceMetadata: JSON.stringify({
      climbId: overrides.climbId ?? "cn-tower",
      trackingMode: "live_climb",
      stopReason: overrides.stopReason ?? "target_reached",
      targetStepCount: target,
      climbTargetStepCount: target,
    }),
  };
}
