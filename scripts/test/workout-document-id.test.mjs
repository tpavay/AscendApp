import assert from "node:assert/strict";
import test from "node:test";
import {
  deriveLandmarkResult,
  groupCompletions,
} from "../lib/landmark-result-derivation.mjs";
import {canonicalWorkoutDocumentId} from "../lib/workout-document-id.mjs";
import {
  BATCH_WRITE_LIMIT,
  packBatchSizes,
  planCaseVariantWorkoutMerges,
  plannedUnitSizes,
} from "../lib/workout-id-case-migration.mjs";

const LOWERCASE_ID = "51c91094-5475-4b25-ab8f-a5d809f90a2f";
const UPPERCASE_ID = LOWERCASE_ID.toUpperCase();
const CLIMB_ID = "empire-state-building";

test("case variants converge on one workout write and one completion", () => {
  const writes = new Map();
  const data = completedWorkout();
  writes.set(canonicalWorkoutDocumentId(LOWERCASE_ID), data);
  writes.set(canonicalWorkoutDocumentId(UPPERCASE_ID), data);

  assert.equal(writes.size, 1);
  const workouts = [...writes].map(([workoutId, workout]) => ({
    userId: "user-1",
    workoutId,
    data: workout,
  }));
  const completions = groupCompletions(workouts).get("user-1").get(CLIMB_ID);
  const projection = deriveLandmarkResult(CLIMB_ID, completions);

  assert.equal(projection.attemptCount, 1);
  assert.equal(projection.bestWorkoutId, UPPERCASE_ID);
});

test("cleanup plan safely merges seed and client variants", () => {
  const lowercaseData = completedWorkout({
    updatedAt: fakeTimestamp(100),
    participations: [{workoutId: LOWERCASE_ID, contextType: "climb_attempt"}],
  });
  const uppercaseData = completedWorkout({
    updatedAt: fakeTimestamp(200),
    participations: [{workoutId: UPPERCASE_ID, contextType: "climb_attempt"}],
  });

  const plan = planCaseVariantWorkoutMerges([
    {userId: "user-1", workoutId: LOWERCASE_ID, data: lowercaseData},
    {userId: "user-1", workoutId: UPPERCASE_ID, data: uppercaseData},
  ]);

  assert.equal(plan.conflicts.length, 0);
  assert.equal(plan.merges.length, 1);
  assert.equal(plan.merges[0].canonicalWorkoutId, UPPERCASE_ID);
  assert.deepEqual(plan.merges[0].deleteWorkoutIds, [LOWERCASE_ID]);
  assert.equal(plan.merges[0].targetData.participations[0].workoutId, UPPERCASE_ID);
  assert.equal(plan.merges[0].targetData.updatedAt.toMillis(), 200);
});

test("cleanup plan renames a lone non-canonical document", () => {
  const plan = planCaseVariantWorkoutMerges([
    {
      userId: "user-1",
      workoutId: LOWERCASE_ID,
      data: completedWorkout({
        participations: [{workoutId: LOWERCASE_ID, contextType: "climb_attempt"}],
      }),
    },
  ]);

  assert.equal(plan.conflicts.length, 0);
  assert.equal(plan.merges.length, 1);
  assert.equal(plan.merges[0].canonicalWorkoutId, UPPERCASE_ID);
  assert.deepEqual(plan.merges[0].deleteWorkoutIds, [LOWERCASE_ID]);
  assert.equal(plan.merges[0].targetData.participations[0].workoutId, UPPERCASE_ID);
});

test("cleanup plan leaves already-canonical documents alone", () => {
  const plan = planCaseVariantWorkoutMerges([
    {userId: "user-1", workoutId: UPPERCASE_ID, data: completedWorkout()},
  ]);

  assert.equal(plan.merges.length, 0);
  assert.equal(plan.conflicts.length, 0);
});

test("cleanup plan blocks payload conflicts instead of deleting data", () => {
  const plan = planCaseVariantWorkoutMerges([
    {userId: "user-1", workoutId: LOWERCASE_ID, data: completedWorkout({steps: 2_096})},
    {userId: "user-1", workoutId: UPPERCASE_ID, data: completedWorkout({steps: 2_000})},
  ]);

  assert.equal(plan.merges.length, 0);
  assert.equal(plan.conflicts.length, 1);
  assert.deepEqual(plan.conflicts[0].conflictingFields, ["steps"]);
});

test("apply plan chunks past the Firestore batch limit without splitting a group", () => {
  const merges = Array.from({length: 400}, () => ({deleteWorkoutIds: ["a"]}));
  const affectedProjections = Array.from({length: 120}, () => ({}));

  const sizes = packBatchSizes(plannedUnitSizes(merges, affectedProjections));

  assert.equal(sizes.reduce((sum, size) => sum + size, 0), 920);
  assert.ok(sizes.every((size) => size <= BATCH_WRITE_LIMIT));
  assert.deepEqual(sizes, [500, 420]);
});

test("apply plan fits a small run in one batch", () => {
  const sizes = packBatchSizes(plannedUnitSizes(
    [{deleteWorkoutIds: ["a"]}, {deleteWorkoutIds: ["b", "c"]}],
    [{}]
  ));

  assert.deepEqual(sizes, [6]);
});

test("apply plan refuses a single group larger than one batch", () => {
  const oversized = [{deleteWorkoutIds: Array.from({length: BATCH_WRITE_LIMIT}, () => "a")}];

  assert.throws(
    () => packBatchSizes(plannedUnitSizes(oversized, [])),
    /above Firestore's 500-write batch limit/
  );
});

test("invalid workout ids are rejected at the canonical boundary", () => {
  assert.throws(() => canonicalWorkoutDocumentId("not-a-uuid"), /Invalid workout UUID/);
});

function completedWorkout(overrides = {}) {
  return {
    source: "headphone_motion",
    steps: 2_096,
    durationSeconds: 1_338,
    updatedAt: fakeTimestamp(100),
    sourceMetadata: JSON.stringify({
      climbId: CLIMB_ID,
      stopReason: "target_reached",
      targetStepCount: 2_096,
      trackingMode: "live_climb",
    }),
    ...overrides,
  };
}

function fakeTimestamp(millis) {
  return {toMillis: () => millis};
}
