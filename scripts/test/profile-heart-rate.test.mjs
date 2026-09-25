import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

import {
  DELETE_FIELD,
  deployedRulesAllowHeartRate,
  planProfileHeartRateBackfill,
} from "../backfill-profile-heart-rate.mjs";
import {
  deriveProfileHeartRate,
  deriveProfileHeartRateFromWorkoutDocuments,
  profileHeartRateFields,
} from "../lib/profile-heart-rate.mjs";
import {PROFILE_FIELD_SETS} from "../seed/fixtures/profile-fixtures.mjs";

const vector = JSON.parse(readFileSync(
  fileURLToPath(new URL(
    "../../SharedTestVectors/profile-heart-rate-summary-vector.json",
    import.meta.url
  )),
  "utf-8"
));

test("the derivation matches the shared vector the iOS app is held to", () => {
  for (const vectorCase of vector.cases) {
    assert.deepEqual(
      deriveProfileHeartRate(vectorCase.climbs),
      vectorCase.expected,
      vectorCase.name
    );
  }
});

test("private workout documents are read by their synced field names", () => {
  assert.deepEqual(
    deriveProfileHeartRateFromWorkoutDocuments([
      {durationSeconds: 1200, avgHeartRateBpm: 141, maxHeartRateBpm: 172},
      {durationSeconds: 900},
    ]),
    {averageBpm: 141, maxBpm: 172}
  );
});

test("an absent aggregate is an absent key, never a null", () => {
  assert.deepEqual(profileHeartRateFields({averageBpm: null, maxBpm: 174}), {
    max_heart_rate_bpm: 174,
  });
  assert.deepEqual(profileHeartRateFields({averageBpm: null, maxBpm: null}), {});
});

test("the seed audit accepts the heart-rate fields on profile_stats", () => {
  assert.ok(PROFILE_FIELD_SETS.profileStats.has("average_heart_rate_bpm"));
  assert.ok(PROFILE_FIELD_SETS.profileStats.has("max_heart_rate_bpm"));
});

const heartRateWorkouts = [
  {durationSeconds: 2400, avgHeartRateBpm: 150, maxHeartRateBpm: 176},
  {durationSeconds: 600, avgHeartRateBpm: 120, maxHeartRateBpm: 181},
];

test("a profile without heart rate gains the derived aggregates", () => {
  const plan = planProfileHeartRateBackfill([
    {userId: "a", stats: {total_climbs: 2}, workouts: heartRateWorkouts},
  ]);

  assert.equal(plan.current, 0);
  assert.deepEqual(plan.updates, [{
    userId: "a",
    kind: "publish",
    fields: {average_heart_rate_bpm: 144, max_heart_rate_bpm: 181},
  }]);
});

test("a second run on backfilled data writes nothing", () => {
  const plan = planProfileHeartRateBackfill([
    {
      userId: "a",
      stats: {average_heart_rate_bpm: 144, max_heart_rate_bpm: 181},
      workouts: heartRateWorkouts,
    },
    {userId: "b", stats: {total_climbs: 3}, workouts: [{durationSeconds: 900}]},
  ]);

  assert.equal(plan.current, 2);
  assert.deepEqual(plan.updates, []);
});

test("only the field that drifted is rewritten", () => {
  const plan = planProfileHeartRateBackfill([
    {
      userId: "a",
      stats: {average_heart_rate_bpm: 139, max_heart_rate_bpm: 181},
      workouts: heartRateWorkouts,
    },
  ]);

  assert.deepEqual(plan.updates, [{
    userId: "a",
    kind: "change",
    fields: {average_heart_rate_bpm: 144},
  }]);
});

test("a climber with no heart rate left loses the published aggregates", () => {
  const plan = planProfileHeartRateBackfill([
    {
      userId: "a",
      stats: {average_heart_rate_bpm: 144, max_heart_rate_bpm: 181},
      workouts: [{durationSeconds: 900}],
    },
  ]);

  assert.deepEqual(plan.updates, [{
    userId: "a",
    kind: "clear",
    fields: {average_heart_rate_bpm: DELETE_FIELD, max_heart_rate_bpm: DELETE_FIELD},
  }]);
});

test("the apply refuses rules that do not yet list both fields", () => {
  const current = readFileSync(
    fileURLToPath(new URL("../../firestore.rules", import.meta.url)),
    "utf-8"
  );
  assert.equal(deployedRulesAllowHeartRate(current), true);
  assert.equal(
    deployedRulesAllowHeartRate(current.replaceAll('"max_heart_rate_bpm"', '"x"')),
    false
  );
});
