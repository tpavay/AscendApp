import test from "node:test";
import assert from "node:assert/strict";
import {
  climbCompletionsTestHooks,
  LandmarkResultProjection,
  LandmarkResultStore,
  LandmarkResultTransaction,
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
  const firstDocument = store.readLandmarkResult(ESB);

  // Second delivery of the same completion: the stored projection already
  // reflects the event, so the guard returns success without a duplicate write.
  const second = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(second, "skipped");
  assert.equal(store.writes, 1);
  assert.deepEqual(store.readLandmarkResult(ESB), firstDocument);
});

test("recompute reads only the affected climb's indexed workouts", async () => {
  const store = makeFakeStore({
    target: makeWorkoutDocument({steps: 2096}),
    other: makeWorkoutDocument({
      steps: 2610,
      metadata: {
        climbId: "cn-tower",
        stopReason: "target_reached",
        targetStepCount: 2610,
      },
    }),
    justClimb: makeWorkoutDocument({metadata: {stopReason: "user_stopped"}}),
  });

  assert.equal(await recomputeLandmarkResult(store, "u1", ESB), "written");
  assert.equal(store.lastQueryClimbId, ESB);
  assert.equal(store.lastQueryResultCount, 1);
  assert.equal(store.readLandmarkResult(ESB)?.attemptCount, 1);
});

test("recompute rewrites when a new completion arrives", async () => {
  const store = makeFakeStore({
    w1: makeWorkoutDocument({steps: 2096}),
  });
  await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(store.writes, 1);

  store.setWorkout(
    "w2",
    makeWorkoutDocument({steps: 2200, durationSeconds: 500})
  );
  const outcome = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(outcome, "written");
  assert.equal(store.writes, 2);
  const stored = store.readLandmarkResult(ESB);
  assert.equal(stored?.attemptCount, 2);
});

test("recompute deletes the projection when no completion left", async () => {
  const store = makeFakeStore({
    w1: makeWorkoutDocument({steps: 2096}),
  });
  await recomputeLandmarkResult(store, "u1", ESB);

  store.deleteWorkout("w1");
  const outcome = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(outcome, "deleted");
  assert.equal(store.readLandmarkResult(ESB), null);
});

test("recompute deletes an orphaned projection it cannot parse", async () => {
  const store = makeFakeStore({});
  store.seedUnparseableLandmarkResult(ESB);

  const outcome = await recomputeLandmarkResult(store, "u1", ESB);
  assert.equal(outcome, "deleted");
  assert.equal(store.landmarkResultExists(ESB), false);

  // And the now-empty identity settles: no perpetual delete loop.
  assert.equal(await recomputeLandmarkResult(store, "u1", ESB), "skipped");
});

test("recompute rebuilds over an unparseable projection", async () => {
  const store = makeFakeStore({w1: makeWorkoutDocument({steps: 2096})});
  store.seedUnparseableLandmarkResult(ESB);

  assert.equal(await recomputeLandmarkResult(store, "u1", ESB), "written");
  assert.equal(store.readLandmarkResult(ESB)?.attemptCount, 1);
});

test("concurrent completions cannot let the older snapshot win", async () => {
  const olderSnapshotRead = deferred<void>();
  const releaseOlderSnapshot = deferred<void>();
  const store = makeFakeStore(
    {w1: makeWorkoutDocument({steps: 2096, durationSeconds: 900})},
    {
      async afterWorkoutList(call) {
        if (call === 1) {
          olderSnapshotRead.resolve();
          await releaseOlderSnapshot.promise;
        }
      },
    }
  );

  const older = recomputeLandmarkResult(store, "u1", ESB);
  await olderSnapshotRead.promise;

  store.setWorkout(
    "w2",
    makeWorkoutDocument({
      steps: 2200,
      durationSeconds: 500,
      startedAtMillis: 1_700_000_100_000,
    })
  );
  const newer = await recomputeLandmarkResult(store, "u1", ESB);
  releaseOlderSnapshot.resolve();
  await older;

  const stored = store.readLandmarkResult(ESB);
  assert.equal(newer, "written");
  assert.equal(stored?.attemptCount, 2);
  assert.equal(stored?.bestWorkoutId, "w2");
  assert.equal(stored?.bestElapsedSeconds, 500);
});

test(
  "completion races converge regardless of which invocation resumes first",
  async () => {
    const newerFirst = await runCompletionRace(true);
    const olderFirst = await runCompletionRace(false);

    assert.deepEqual(olderFirst, newerFirst);
    assert.equal(newerFirst?.attemptCount, 2);
    assert.equal(newerFirst?.bestWorkoutId, "w2");
    assert.equal(newerFirst?.bestElapsedSeconds, 500);
  }
);

test("stale deletion cannot erase a concurrent completion", async () => {
  const emptySnapshotRead = deferred<void>();
  const releaseEmptySnapshot = deferred<void>();
  const store = makeFakeStore({}, {
    async afterWorkoutList(call) {
      if (call === 1) {
        emptySnapshotRead.resolve();
        await releaseEmptySnapshot.promise;
      }
    },
  });

  const staleDelete = recomputeLandmarkResult(store, "u1", ESB);
  await emptySnapshotRead.promise;
  store.setWorkout("w1", makeWorkoutDocument({steps: 2096}));
  await recomputeLandmarkResult(store, "u1", ESB);
  releaseEmptySnapshot.resolve();
  await staleDelete;

  const stored = store.readLandmarkResult(ESB);
  assert.equal(stored?.attemptCount, 1);
  assert.equal(stored?.bestWorkoutId, "w1");
});

test("concurrent duplicate delivery writes only once", async () => {
  const bothProjectionReads = deferred<void>();
  const releaseProjectionReads = deferred<void>();
  const store = makeFakeStore(
    {w1: makeWorkoutDocument({steps: 2096})},
    {
      async afterResultRead(call) {
        if (call === 2) {
          bothProjectionReads.resolve();
        }
        await releaseProjectionReads.promise;
      },
    }
  );

  const first = recomputeLandmarkResult(store, "u1", ESB);
  const duplicate = recomputeLandmarkResult(store, "u1", ESB);
  await bothProjectionReads.promise;
  releaseProjectionReads.resolve();
  const outcomes = await Promise.all([first, duplicate]);

  assert.equal(store.writes, 1);
  assert.deepEqual(outcomes.sort(), ["skipped", "written"]);
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
    climbId: typeof metadata.climbId === "string" ?
      metadata.climbId : undefined,
    steps: overrides.steps ?? 2096,
    durationSeconds: overrides.durationSeconds ?? 900,
    startedAt: {toMillis: () => overrides.startedAtMillis ?? 1_700_000_000_000},
    sourceMetadata: JSON.stringify(metadata),
  };
}

interface FakeStore extends LandmarkResultStore {
  writes: number;
  transactionAttempts: number;
  lastQueryClimbId: string | null;
  lastQueryResultCount: number;
  setWorkout(id: string, data: Record<string, unknown>): void;
  deleteWorkout(id: string): void;
  readLandmarkResult(climbId: string): LandmarkResultProjection | null;
  /** Seeds a stored document the normalizer cannot parse. */
  seedUnparseableLandmarkResult(climbId: string): void;
  landmarkResultExists(climbId: string): boolean;
}

interface FakeStoreOptions {
  afterWorkoutList?: (call: number) => Promise<void>;
  afterResultRead?: (call: number) => Promise<void>;
}

/**
 * An in-memory store that records how many writes occurred.
 * @param {Record<string, Record<string, unknown>>} workouts Seed workouts.
 * @param {FakeStoreOptions} options Deterministic interleaving hooks.
 * @return {FakeStore} Fake store.
 */
function makeFakeStore(
  workouts: Record<string, Record<string, unknown>>,
  options: FakeStoreOptions = {}
): FakeStore {
  const canonicalWorkouts = {...workouts};
  // A stored entry always exists as a document; `parsed` is null when the
  // document is present but the normalizer rejects it.
  const results = new Map<
    string,
    {parsed: LandmarkResultProjection | null}
  >();
  let workoutListCalls = 0;
  let resultReadCalls = 0;
  let version = 0;

  const store: FakeStore = {
    writes: 0,
    transactionAttempts: 0,
    lastQueryClimbId: null,
    lastQueryResultCount: 0,
    setWorkout(id, data) {
      canonicalWorkouts[id] = data;
      version += 1;
    },
    deleteWorkout(id) {
      delete canonicalWorkouts[id];
      version += 1;
    },
    readLandmarkResult(climbId) {
      return results.get(climbId)?.parsed ?? null;
    },
    seedUnparseableLandmarkResult(climbId) {
      results.set(climbId, {parsed: null});
      version += 1;
    },
    landmarkResultExists(climbId) {
      return results.has(climbId);
    },
    async runTransaction<T>(
      operation: (transaction: LandmarkResultTransaction) => Promise<T>
    ): Promise<T> {
      for (let retry = 0; retry < 20; retry += 1) {
        store.transactionAttempts += 1;
        const readVersion = version;
        const workoutSnapshot = Object.entries(canonicalWorkouts).map(
          ([id, data]) => ({id, data})
        );
        const resultSnapshot = new Map(results);
        const mutation: {value: {
            kind: "write" | "delete";
            climbId: string;
            projection?: LandmarkResultProjection;
          } | null} = {value: null};

        const outcome = await operation({
          async listLandmarkWorkouts(_userId: string, climbId: string) {
            workoutListCalls += 1;
            await options.afterWorkoutList?.(workoutListCalls);
            const matches = workoutSnapshot.filter(({data}) =>
              data.source === "headphone_motion" && data.climbId === climbId
            );
            store.lastQueryClimbId = climbId;
            store.lastQueryResultCount = matches.length;
            return matches;
          },
          async getLandmarkResult(_userId: string, climbId: string) {
            const snapshot = resultSnapshot.get(climbId);
            resultReadCalls += 1;
            await options.afterResultRead?.(resultReadCalls);
            return {
              exists: snapshot !== undefined,
              projection: snapshot?.parsed ?? null,
            };
          },
          async writeLandmarkResult(
            _userId: string,
            climbId: string,
            projection: LandmarkResultProjection
          ) {
            mutation.value = {kind: "write", climbId, projection};
          },
          async deleteLandmarkResult(_userId: string, climbId: string) {
            mutation.value = {kind: "delete", climbId};
          },
        });

        if (version !== readVersion) {
          continue;
        }
        const pending = mutation.value;
        if (pending?.kind === "write" && pending.projection) {
          results.set(pending.climbId, {parsed: pending.projection});
          store.writes += 1;
          version += 1;
        } else if (pending?.kind === "delete") {
          results.delete(pending.climbId);
          version += 1;
        }
        return outcome;
      }
      throw new Error("fake transaction exceeded retry limit");
    },
  };

  return store;
}

/**
 * Runs the same two completion events with either invocation released first.
 * @param {boolean} releaseNewerFirst Whether the newer read resumes first.
 * @return {Promise<LandmarkResultProjection | null>} Stored projection.
 */
async function runCompletionRace(
  releaseNewerFirst: boolean
): Promise<LandmarkResultProjection | null> {
  const olderRead = deferred<void>();
  const newerRead = deferred<void>();
  const releaseOlder = deferred<void>();
  const releaseNewer = deferred<void>();
  const store = makeFakeStore(
    {w1: makeWorkoutDocument({steps: 2096, durationSeconds: 900})},
    {
      async afterWorkoutList(call) {
        if (call === 1) {
          olderRead.resolve();
          await releaseOlder.promise;
        } else if (call === 2) {
          newerRead.resolve();
          await releaseNewer.promise;
        }
      },
    }
  );

  const older = recomputeLandmarkResult(store, "u1", ESB);
  await olderRead.promise;
  store.setWorkout(
    "w2",
    makeWorkoutDocument({
      steps: 2200,
      durationSeconds: 500,
      startedAtMillis: 1_700_000_100_000,
    })
  );
  const newer = recomputeLandmarkResult(store, "u1", ESB);
  await newerRead.promise;

  if (releaseNewerFirst) {
    releaseNewer.resolve();
    await newer;
    releaseOlder.resolve();
    await older;
  } else {
    releaseOlder.resolve();
    await older;
    releaseNewer.resolve();
    await newer;
  }

  return store.readLandmarkResult(ESB);
}

interface Deferred<T> {
  promise: Promise<T>;
  resolve: (value: T | PromiseLike<T>) => void;
}

/**
 * Creates a manually-resolvable promise for deterministic interleavings.
 * @return {Deferred<T>} Promise and resolver.
 */
function deferred<T>(): Deferred<T> {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((fulfill) => {
    resolve = fulfill;
  });
  return {promise, resolve};
}
