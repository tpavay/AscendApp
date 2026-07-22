import assert from "node:assert/strict";
import test from "node:test";
import {resolveEnvironment} from "../lib/migration-discipline.mjs";
import {promotedWorkoutClimbId} from "../lib/workout-query-fields.mjs";

test("promotes a headphone-motion climb id from source metadata", () => {
  assert.equal(promotedWorkoutClimbId({
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({climbId: " gateway-arch "}),
  }), "gateway-arch");
});

test("does not promote non-climb, invalid, or non-headphone workouts", () => {
  assert.equal(promotedWorkoutClimbId({
    source: "manual",
    sourceMetadata: JSON.stringify({climbId: "gateway-arch"}),
  }), null);
  assert.equal(promotedWorkoutClimbId({
    source: "headphone_motion",
    sourceMetadata: "not-json",
  }), null);
  assert.equal(promotedWorkoutClimbId({
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({stopReason: "user_stopped"}),
  }), null);
  assert.equal(promotedWorkoutClimbId({
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({climbId: "x".repeat(161)}),
  }), null);
});

test("production migration requires an exact project confirmation", () => {
  assert.throws(() => resolveEnvironment("prod"), /hard-refuses production/);
  assert.throws(
    () => resolveEnvironment("prod", {
      allowProduction: true,
      productionConfirmation: "wrong-project",
    }),
    /confirm-production ascend-prod-9c8f2/
  );
  assert.deepEqual(resolveEnvironment("prod", {
    allowProduction: true,
    productionConfirmation: "ascend-prod-9c8f2",
  }), {
    env: "prod",
    projectId: "ascend-prod-9c8f2",
    production: true,
  });
});
