import test from "node:test";
import assert from "node:assert/strict";
import {
  groupCompletions,
  deriveLandmarkResult,
  recomputeLandmarkResult,
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

test("a live trigger racing a stale backfill plan keeps the full projection", async () => {
  const staleBackfillRead = deferred();
  const releaseStaleBackfill = deferred();
  const store = makeTransactionalStore(
    {a: completedWorkout({climbId: ESB})},
    {
      async afterWorkoutList(call) {
        if (call === 1) {
          staleBackfillRead.resolve();
          await releaseStaleBackfill.promise;
        }
      },
    }
  );

  const staleBackfill = recomputeLandmarkResult(store, "u1", ESB);
  await staleBackfillRead.promise;

  store.setWorkout(
    "b",
    completedWorkout({climbId: ESB, durationSeconds: 500})
  );
  await recomputeLandmarkResult(store, "u1", ESB);
  releaseStaleBackfill.resolve();
  await staleBackfill;

  const result = store.readResult(ESB);
  assert.equal(result.attemptCount, 2);
  assert.equal(result.bestWorkoutId, "b");
});

test("transactional backfill rerun is byte-identical and writes nothing", async () => {
  const store = makeTransactionalStore({
    a: completedWorkout({climbId: ESB}),
  });

  assert.equal(await recomputeLandmarkResult(store, "u1", ESB), "written");
  const firstDocument = structuredClone(store.readResult(ESB));
  assert.equal(await recomputeLandmarkResult(store, "u1", ESB), "skipped");

  assert.equal(store.writes, 1);
  assert.deepEqual(store.readResult(ESB), firstDocument);
});

test("repair reconciliation deletes an orphaned stored projection", async () => {
  const store = makeTransactionalStore({});
  const stale = deriveLandmarkResult(ESB, [{
    workoutId: "deleted-workout",
    climbId: ESB,
    steps: 2096,
    elapsedSeconds: 900,
    completedAtMillis: 1_700_000_900_000,
  }]);
  store.seedResult(ESB, stale);

  assert.equal(await recomputeLandmarkResult(store, "u1", ESB), "deleted");
  assert.equal(store.readResult(ESB), null);
  assert.equal(await recomputeLandmarkResult(store, "u1", ESB), "skipped");
  assert.equal(store.deletes, 1);
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

/** In-memory optimistic transaction store with retry-on-version-change. */
function makeTransactionalStore(workouts, options = {}) {
  const canonicalWorkouts = {...workouts};
  const results = new Map();
  let workoutListCalls = 0;
  let version = 0;

  return {
    writes: 0,
    deletes: 0,
    setWorkout(id, data) {
      canonicalWorkouts[id] = data;
      version += 1;
    },
    seedResult(climbId, projection) {
      results.set(climbId, projection);
      version += 1;
    },
    readResult(climbId) {
      return results.get(climbId) ?? null;
    },
    async runTransaction(operation) {
      for (let retry = 0; retry < 20; retry += 1) {
        const readVersion = version;
        const workoutSnapshot = Object.entries(canonicalWorkouts).map(
          ([id, data]) => ({id, data})
        );
        const resultSnapshot = new Map(results);
        const mutation = {value: null};
        const outcome = await operation({
          async listUserWorkouts() {
            workoutListCalls += 1;
            await options.afterWorkoutList?.(workoutListCalls);
            return workoutSnapshot;
          },
          async getLandmarkResult(_userId, climbId) {
            return resultSnapshot.get(climbId) ?? null;
          },
          async writeLandmarkResult(_userId, climbId, projection) {
            mutation.value = {kind: "write", climbId, projection};
          },
          async deleteLandmarkResult(_userId, climbId) {
            mutation.value = {kind: "delete", climbId};
          },
        });

        if (version !== readVersion) {
          continue;
        }
        if (mutation.value?.kind === "write") {
          results.set(mutation.value.climbId, mutation.value.projection);
          this.writes += 1;
          version += 1;
        } else if (mutation.value?.kind === "delete") {
          results.delete(mutation.value.climbId);
          this.deletes += 1;
          version += 1;
        }
        return outcome;
      }
      throw new Error("fake transaction exceeded retry limit");
    },
  };
}

/** Creates a manually-resolvable promise for deterministic interleavings. */
function deferred() {
  let resolve;
  const promise = new Promise((fulfill) => {
    resolve = fulfill;
  });
  return {promise, resolve};
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
