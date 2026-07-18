import test from "node:test";
import assert from "node:assert/strict";
import {
  climbCompletionsTestHooks,
  LandmarkResultProjection,
  LandmarkResultStore,
} from "../src/climbCompletions.js";

const {
  parseCompletedLandmarkWorkout,
  deriveLandmarkResult,
  shouldSkipLandmarkResultWrite,
  recomputeLandmarkResult,
} = climbCompletionsTestHooks;

const ESB = "empire-state-building";

test("parses a modern target-reached landmark completion", () => {
  const parsed = parseCompletedLandmarkWorkout(
    "w1",
    makeWorkoutDocument({steps: 2096})
  );
  assert.equal(parsed?.climbId, ESB);
  assert.equal(parsed?.steps, 2096);
});

test("parses a legacy completion with no recorded target", () => {
  const parsed = parseCompletedLandmarkWorkout(
    "w1",
    makeWorkoutDocument({
      steps: 2909,
      metadata: {
        climbId: "burj-khalifa",
        stopReason: "target_reached",
      },
    })
  );
  assert.equal(parsed?.climbId, "burj-khalifa");
});

test("rejects a Just Climb, a short attempt, and non-headphone", () => {
  assert.equal(
    parseCompletedLandmarkWorkout(
      "w1",
      makeWorkoutDocument({metadata: {stopReason: "target_reached"}})
    ),
    null
  );
  assert.equal(
    parseCompletedLandmarkWorkout(
      "w1",
      makeWorkoutDocument({
        steps: 900,
        metadata: {
          climbId: "cn-tower",
          stopReason: "user_stopped",
          targetStepCount: 1000,
          climbTargetStepCount: 1000,
        },
      })
    ),
    null
  );
  assert.equal(
    parseCompletedLandmarkWorkout(
      "w1",
      makeWorkoutDocument({source: "manual"})
    ),
    null
  );
});

test("three completions of one climb derive one doc, attemptCount 3", () => {
  const climbId = "cn-tower";
  const completions = [
    completion({workoutId: "slow", elapsedSeconds: 1200, atMillis: 3e3}),
    completion({workoutId: "fast", elapsedSeconds: 600, atMillis: 1e3}),
    completion({workoutId: "mid", elapsedSeconds: 900, atMillis: 2e3}),
  ].map((c) => ({...c, climbId}));

  const result = deriveLandmarkResult(climbId, completions);
  assert.ok(result);
  assert.equal(result?.climbId, climbId);
  assert.equal(result?.attemptCount, 3);
  assert.equal(result?.bestWorkoutId, "fast");
  assert.equal(result?.bestElapsedSeconds, 600);
  assert.equal(result?.firstCompletedAtMillis, 1e3);
  assert.equal(result?.latestCompletedAtMillis, 3e3);
});

test("derivation is order-independent and deterministic", () => {
  const climbId = "cn-tower";
  const a = completion({workoutId: "a", elapsedSeconds: 600, atMillis: 1e3});
  const b = completion({workoutId: "b", elapsedSeconds: 900, atMillis: 2e3});
  const forward = deriveLandmarkResult(climbId, [
    {...a, climbId},
    {...b, climbId},
  ]);
  const reverse = deriveLandmarkResult(climbId, [
    {...b, climbId},
    {...a, climbId},
  ]);
  assert.deepEqual(forward, reverse);
});

test("the derived projection carries no First Ascent fields", () => {
  const result = deriveLandmarkResult("cn-tower", [
    completion({workoutId: "w1", climbId: "cn-tower"}),
  ]) as unknown as Record<string, unknown>;
  // The projection is a private restore signal; First Ascent stays owned by the
  // replay path. No FA-shaped field may leak into landmarkResults.
  for (const key of Object.keys(result)) {
    assert.ok(
      !/firstAscent/i.test(key),
      `unexpected First Ascent field ${key}`
    );
  }
});

test("recompute writes once, then skips the re-delivered event", async () => {
  const store = makeFakeStore({
    w1: makeWorkoutDocument({steps: 2096}),
  });

  const first = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(first, "written");
  assert.equal(store.writes, 1);

  // Second delivery of the same completion: the stored projection already
  // reflects the event, so the guard returns success without a duplicate write.
  const second = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(second, "skipped");
  assert.equal(store.writes, 1);
});

test("recompute rewrites when a new completion arrives", async () => {
  const store = makeFakeStore({
    w1: makeWorkoutDocument({steps: 2096}),
  });
  await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(store.writes, 1);

  store.workouts.w2 = makeWorkoutDocument({steps: 2200, durationSeconds: 500});
  const outcome = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(outcome, "written");
  assert.equal(store.writes, 2);
  const stored = await store.getLandmarkResult("u1", ESB);
  assert.equal(stored?.attemptCount, 2);
});

test("recompute deletes the projection when no completion left", async () => {
  const store = makeFakeStore({
    w1: makeWorkoutDocument({steps: 2096}),
  });
  await recomputeLandmarkResult(store, "u1", ESB);

  delete store.workouts.w1;
  const outcome = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(outcome, "deleted");
  assert.equal(await store.getLandmarkResult("u1", ESB), null);
});

test("shouldSkip is false when nothing is stored yet", () => {
  const next = deriveLandmarkResult("cn-tower", [
    completion({workoutId: "w1", climbId: "cn-tower"}),
  ]);
  assert.ok(next);
  assert.equal(
    shouldSkipLandmarkResultWrite(null, next as LandmarkResultProjection),
    false
  );
});

interface CompletionOverrides {
  workoutId?: string;
  climbId?: string;
  steps?: number;
  elapsedSeconds?: number;
  atMillis?: number;
}

/**
 * Builds a completed landmark workout for derivation tests.
 * @param {CompletionOverrides} overrides Field overrides.
 * @return {object} A completion.
 */
function completion(overrides: CompletionOverrides): {
  workoutId: string;
  climbId: string;
  steps: number;
  elapsedSeconds: number;
  completedAtMillis: number;
} {
  return {
    workoutId: overrides.workoutId ?? "w1",
    climbId: overrides.climbId ?? "cn-tower",
    steps: overrides.steps ?? 2000,
    elapsedSeconds: overrides.elapsedSeconds ?? 600,
    completedAtMillis: overrides.atMillis ?? 1e3,
  };
}

interface WorkoutOverrides {
  source?: string;
  steps?: number;
  durationSeconds?: number;
  startedAtMillis?: number;
  metadata?: Record<string, unknown>;
}

/**
 * Builds a raw workout document, a completed live-climb shape by default.
 * @param {WorkoutOverrides} overrides Field/metadata overrides.
 * @return {Record<string, unknown>} Raw workout document.
 */
function makeWorkoutDocument(
  overrides: WorkoutOverrides = {}
): Record<string, unknown> {
  const metadata = overrides.metadata ?? {
    climbId: ESB,
    trackingMode: "live_climb",
    stopReason: "target_reached",
    targetStepCount: 2096,
    climbTargetStepCount: 2096,
  };
  return {
    source: overrides.source ?? "headphone_motion",
    steps: overrides.steps ?? 2096,
    durationSeconds: overrides.durationSeconds ?? 900,
    startedAt: {toMillis: () => overrides.startedAtMillis ?? 1_700_000_000_000},
    sourceMetadata: JSON.stringify(metadata),
  };
}

interface FakeStore extends LandmarkResultStore {
  writes: number;
  workouts: Record<string, Record<string, unknown>>;
}

/**
 * An in-memory store that records how many writes occurred.
 * @param {Record<string, Record<string, unknown>>} workouts Seed workouts.
 * @return {FakeStore} Fake store.
 */
function makeFakeStore(
  workouts: Record<string, Record<string, unknown>>
): FakeStore {
  const results = new Map<string, LandmarkResultProjection>();

  const store: FakeStore = {
    writes: 0,
    workouts,
    async listUserWorkouts() {
      return Object.entries(store.workouts).map(([id, data]) => ({id, data}));
    },
    async getLandmarkResult(_userId: string, climbId: string) {
      return results.get(climbId) ?? null;
    },
    async writeLandmarkResult(
      _userId: string,
      climbId: string,
      projection: LandmarkResultProjection
    ) {
      store.writes += 1;
      results.set(climbId, projection);
    },
    async deleteLandmarkResult(_userId: string, climbId: string) {
      results.delete(climbId);
    },
  };

  return store;
}
