import test from "node:test";
import assert from "node:assert/strict";
import {
  HOME_TODAY_ACTIVITY_MAX_ROWS,
  HOME_TODAY_ACTIVITY_MAX_ROW_AGE_MILLIS,
  HomeTodayActivityProjection,
  HomeTodayActivityRow,
  HomeTodayActivityStore,
  HomeTodayActivityTransaction,
  candidatesEqual,
  mergeHomeTodayActivityRows,
  parseHomeTodayActivityCandidate,
  projectionFromData,
  reconcileHomeTodayActivity,
  refreshHomeTodayActivityIdentity,
  removeHomeTodayActivityRows,
} from "../src/homeTodayActivity.js";
import {PublicUserSnapshot} from "../src/liveReplayLeaderboard.js";

const ESB = "empire-state-building";
const STARTED_AT_MILLIS = 1_700_000_000_000;
/** An event time within the feed's day of the fixture workout's finish. */
const NOW_MILLIS = STARTED_AT_MILLIS + 900_000 + 5_000;
const DAY_MILLIS = HOME_TODAY_ACTIVITY_MAX_ROW_AGE_MILLIS;

// MARK: parsing

test("a completed Live Climb is a live_climb row on its landmark", () => {
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument()
  );
  assert.equal(candidate?.kind, "live_climb");
  assert.equal(candidate?.climbId, ESB);
  assert.equal(candidate?.steps, 2096);
  assert.equal(candidate?.durationSeconds, 900);
  assert.equal(candidate?.completedAtMillis, STARTED_AT_MILLIS + 900_000);
  assert.equal(candidate?.justClimbGoalKind, null);
});

test("an unfinished Live Climb attempt is not on the feed", () => {
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument({
      steps: 900,
      metadata: {
        climbId: ESB,
        trackingMode: "live_climb",
        stopReason: "user_stopped",
        targetStepCount: 2096,
        climbTargetStepCount: 2096,
      },
    })
  );
  assert.equal(candidate, null);
});

test("a legacy completion with no recorded target still counts", () => {
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument({
      steps: 2909,
      metadata: {
        climbId: "burj-khalifa",
        trackingMode: "live_climb",
        stopReason: "target_reached",
      },
    })
  );
  assert.equal(candidate?.kind, "live_climb");
  assert.equal(candidate?.climbId, "burj-khalifa");
});

test("a Just Climb keeps the goal it was set to", () => {
  const duration = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument({
      metadata: {
        trackingMode: "just_climb",
        stopReason: "target_reached",
        targetDurationSeconds: 1800,
      },
    })
  );
  assert.equal(duration?.kind, "just_climb");
  assert.equal(duration?.justClimbGoalKind, "duration");
  assert.equal(duration?.justClimbGoalValue, 30);

  const steps = parseHomeTodayActivityCandidate(
    "user-a",
    "w2",
    makeWorkoutDocument({
      metadata: {
        trackingMode: "just_climb",
        stopReason: "user_stopped",
        targetStepCount: 1500,
      },
    })
  );
  assert.equal(steps?.justClimbGoalKind, "steps");
  assert.equal(steps?.justClimbGoalValue, 1500);

  const open = parseHomeTodayActivityCandidate(
    "user-a",
    "w3",
    makeWorkoutDocument({
      metadata: {trackingMode: "just_climb", stopReason: "user_stopped"},
    })
  );
  assert.equal(open?.justClimbGoalKind, "open");
  assert.equal(open?.justClimbGoalValue, null);
});

test("a discarded or empty Just Climb is not on the feed", () => {
  assert.equal(
    parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument({
        metadata: {trackingMode: "just_climb", stopReason: "discarded"},
      })
    ),
    null
  );
  assert.equal(
    parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument({
        steps: 0,
        metadata: {trackingMode: "just_climb", stopReason: "user_stopped"},
      })
    ),
    null
  );
});

test("a finished catalog routine is a routine_template row", () => {
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument({
      metadata: {
        trackingMode: "routine",
        stopReason: "target_reached",
        routineTemplateId: "pyramid_climb",
      },
    })
  );
  assert.equal(candidate?.kind, "routine_template");
  assert.equal(candidate?.routineTemplateId, "pyramid_climb");
});

test("a personal routine is a routine row that names no template", () => {
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument({
      metadata: {
        trackingMode: "routine",
        stopReason: "target_reached",
        routineId: "8F1C2C0E-0000-4000-8000-000000000000",
      },
    })
  );
  assert.equal(candidate?.kind, "routine");
  assert.equal(candidate?.routineTemplateId, null);
});

test("a skipped routine and a non-sensor workout are not on the feed", () => {
  assert.equal(
    parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument({
        metadata: {
          trackingMode: "routine",
          stopReason: "skipped",
          routineTemplateId: "pyramid_climb",
        },
      })
    ),
    null
  );
  assert.equal(
    parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument({source: "manual"})
    ),
    null
  );
});

test("candidates compare on the facts the feed shows", () => {
  const lhs = parseHomeTodayActivityCandidate("u", "w", makeWorkoutDocument());
  const rhs = parseHomeTodayActivityCandidate("u", "w", makeWorkoutDocument());
  assert.ok(candidatesEqual(lhs, rhs));
  assert.ok(candidatesEqual(null, null));
  assert.ok(!candidatesEqual(lhs, null));
  assert.ok(
    !candidatesEqual(
      lhs,
      parseHomeTodayActivityCandidate(
        "u",
        "w",
        makeWorkoutDocument({steps: 2200})
      )
    )
  );
});

// MARK: merging

test("rows sort newest upload first and the list stays bounded", () => {
  const rows: HomeTodayActivityRow[] = [];
  for (let index = 0; index < HOME_TODAY_ACTIVITY_MAX_ROWS + 5; index += 1) {
    rows.push(makeRow({workoutId: `w${index}`, publishedAtMillis: index}));
  }
  let merged: HomeTodayActivityRow[] = [];
  for (const row of rows) {
    merged = mergeHomeTodayActivityRows(merged, row.workoutId, row, 1_000);
  }
  assert.equal(merged.length, HOME_TODAY_ACTIVITY_MAX_ROWS);
  assert.equal(merged[0].workoutId, `w${HOME_TODAY_ACTIVITY_MAX_ROWS + 4}`);
  assert.equal(
    merged[merged.length - 1].workoutId,
    "w5",
    "the oldest uploads fall off the end"
  );
});

test("merging the same workout twice keeps one row", () => {
  const first = makeRow({workoutId: "w1", steps: 100});
  const merged = mergeHomeTodayActivityRows(
    mergeHomeTodayActivityRows([], "w1", first, 1_000),
    "w1",
    {...first, steps: 120},
    1_000
  );
  assert.equal(merged.length, 1);
  assert.equal(merged[0].steps, 120);
});

test("merging null removes the workout's row", () => {
  const merged = mergeHomeTodayActivityRows(
    [makeRow({workoutId: "w1"}), makeRow({workoutId: "w2"})],
    "w1",
    null,
    1_000
  );
  assert.deepEqual(merged.map((row) => row.workoutId), ["w2"]);
});

test("rewriting the list drops rows published more than a day ago", () => {
  const now = 10 * DAY_MILLIS;
  const merged = mergeHomeTodayActivityRows(
    [
      makeRow({workoutId: "stale", publishedAtMillis: now - DAY_MILLIS - 1}),
      makeRow({workoutId: "edge", publishedAtMillis: now - DAY_MILLIS}),
      makeRow({workoutId: "fresh", publishedAtMillis: now - 60_000}),
    ],
    "new",
    makeRow({workoutId: "new", publishedAtMillis: now}),
    now
  );
  assert.deepEqual(
    merged.map((row) => row.workoutId),
    ["new", "fresh", "edge"],
    "a row exactly a day old stays, a row older than a day goes"
  );
});

// MARK: reconciliation

test("a new completion is written with the climber's public identity", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser({displayName: "Ada"}));

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument()
    ),
    nowMillis: 5_000,
  });

  assert.equal(outcome, "written");
  assert.equal(store.projection?.rows.length, 1);
  const row = store.projection?.rows[0];
  assert.equal(row?.displayName, "Ada");
  assert.equal(row?.identityState, "published");
  assert.equal(row?.isSynthetic, false);
  assert.equal(row?.publishedAtMillis, 5_000);
});

test("re-deriving a workout the feed knows keeps its publish time", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument()
    ),
    nowMillis: 5_000,
  });

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument({steps: 2200})
    ),
    nowMillis: 9_000,
  });

  assert.equal(outcome, "written");
  assert.equal(store.projection?.rows[0].steps, 2200);
  assert.equal(store.projection?.rows[0].publishedAtMillis, 5_000);
});

test("an unchanged re-run skips the write", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument()
  );
  await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate,
    nowMillis: 5_000,
  });
  const writesBefore = store.writes;

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate,
    nowMillis: 9_000,
  });

  assert.equal(outcome, "skipped");
  assert.equal(store.writes, writesBefore);
});

test("a deleted workout leaves the feed", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument()
    ),
    nowMillis: 5_000,
  });

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: null,
    nowMillis: 9_000,
  });

  assert.equal(outcome, "written");
  assert.deepEqual(store.projection?.rows, []);
});

test("deleting a workout the feed never held is a no-op", async () => {
  const store = makeFakeStore();

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: null,
    nowMillis: 9_000,
  });

  assert.equal(outcome, "skipped");
  assert.equal(store.writes, 0);
});

test("an older upload arriving at a full feed costs no identity read", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  store.projection = {
    schemaVersion: 1,
    rows: Array.from({length: HOME_TODAY_ACTIVITY_MAX_ROWS}, (_, index) =>
      makeRow({workoutId: `old${index}`, publishedAtMillis: 10_000 + index})
    ),
  };
  const identityReadsBefore = store.identityReads;

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "late",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "late",
      makeWorkoutDocument()
    ),
    nowMillis: 5_000,
  });

  assert.equal(outcome, "skipped");
  assert.equal(store.identityReads, identityReadsBefore);
});

test("a pending identity publishes as the anonymous climber", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", {
    avatarToken: "",
    displayName: "Anonymous Climber",
    identityState: "pending_public_profile",
    photoURL: null,
  });

  await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument()
    ),
    nowMillis: 5_000,
  });

  assert.equal(store.projection?.rows[0].displayName, "Anonymous Climber");
  assert.equal(
    store.projection?.rows[0].identityState,
    "pending_public_profile"
  );
});

test("a climb finished more than a day before the feed first sees it is not published", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "old",
    makeWorkoutDocument()
  );

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "old",
    candidate,
    nowMillis: (candidate?.completedAtMillis ?? 0) + DAY_MILLIS + 1,
  });

  assert.equal(outcome, "skipped");
  assert.equal(store.writes, 0);
  assert.equal(store.identityReads, 0, "history costs no identity read");
  assert.equal(store.projection, null);
});

test("a climb finished within the day is published, and a day-old one exactly at the bound too", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument()
  );

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate,
    nowMillis: (candidate?.completedAtMillis ?? 0) + DAY_MILLIS,
  });

  assert.equal(outcome, "written");
  assert.equal(store.projection?.rows[0].workoutId, "w1");
});

test("a workout the feed already holds keeps its row and publish time when re-derived", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  const candidate = parseHomeTodayActivityCandidate(
    "user-a",
    "w1",
    makeWorkoutDocument()
  );
  const completedAt = candidate?.completedAtMillis ?? 0;
  // Published near the end of its day, then re-derived after the completion
  // itself has aged past the bound.
  const publishedAt = completedAt + DAY_MILLIS - 60_000;
  await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate,
    nowMillis: publishedAt,
  });

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument({steps: 2200})
    ),
    nowMillis: completedAt + DAY_MILLIS + 60_000,
  });

  assert.equal(outcome, "written");
  assert.equal(store.projection?.rows.length, 1);
  assert.equal(store.projection?.rows[0].steps, 2200);
  assert.equal(store.projection?.rows[0].publishedAtMillis, publishedAt);
});

test("a rewrite prunes rows whose publish time has aged past the day", async () => {
  const store = makeFakeStore();
  store.publicUsers.set("user-a", makePublicUser());
  store.projection = {
    schemaVersion: 1,
    rows: [
      makeRow({
        workoutId: "yesterday",
        publishedAtMillis: NOW_MILLIS - DAY_MILLIS - 1,
      }),
      makeRow({
        workoutId: "earlier",
        publishedAtMillis: NOW_MILLIS - 3_600_000,
      }),
    ],
  };

  const outcome = await reconcileHomeTodayActivity(store, {
    workoutId: "w1",
    candidate: parseHomeTodayActivityCandidate(
      "user-a",
      "w1",
      makeWorkoutDocument()
    ),
    nowMillis: NOW_MILLIS,
  });

  assert.equal(outcome, "written");
  assert.deepEqual(
    store.projection?.rows.map((row) => row.workoutId),
    ["w1", "earlier"]
  );
});

// MARK: identity refresh and deletion

test("a renamed climber's rows pick up the new name, nobody else's move", async () => {
  const store = makeFakeStore();
  store.projection = {
    schemaVersion: 1,
    rows: [
      makeRow({workoutId: "w1", userId: "user-a", displayName: "Ada"}),
      makeRow({workoutId: "w2", userId: "user-b", displayName: "Bo"}),
      makeRow({workoutId: "w3", userId: "user-a", displayName: "Ada"}),
    ],
  };
  store.publicUsers.set("user-a", makePublicUser({displayName: "Adelaide"}));

  const changed = await refreshHomeTodayActivityIdentity(store, "user-a");

  assert.equal(changed, 2);
  assert.deepEqual(
    store.projection.rows.map((row) => row.displayName),
    ["Adelaide", "Bo", "Adelaide"]
  );
});

test("refreshing a climber with no rows reads no identity", async () => {
  const store = makeFakeStore();
  store.projection = {
    schemaVersion: 1,
    rows: [makeRow({workoutId: "w1", userId: "user-b"})],
  };

  const changed = await refreshHomeTodayActivityIdentity(store, "user-a");

  assert.equal(changed, 0);
  assert.equal(store.identityReads, 0);
  assert.equal(store.writes, 0);
});

test("a deleted account's rows are removed", async () => {
  const store = makeFakeStore();
  store.projection = {
    schemaVersion: 1,
    rows: [
      makeRow({workoutId: "w1", userId: "user-a"}),
      makeRow({workoutId: "w2", userId: "user-b"}),
    ],
  };

  const removed = await removeHomeTodayActivityRows(store, "user-a");

  assert.equal(removed, 1);
  assert.deepEqual(
    store.projection.rows.map((row) => row.workoutId),
    ["w2"]
  );
  assert.equal(await removeHomeTodayActivityRows(store, "user-a"), 0);
});

// MARK: stored shape

test("a stored document round-trips and a malformed row is dropped", () => {
  const stored = projectionFromData({
    schemaVersion: 1,
    rows: [
      {
        workoutId: "w1",
        userId: "user-a",
        kind: "just_climb",
        steps: 1200,
        durationSeconds: 600,
        completedAt: {toMillis: () => 2_000},
        publishedAt: {toMillis: () => 3_000},
        justClimbGoalKind: "steps",
        justClimbGoalValue: 1500,
        displayName: "Ada",
        avatarToken: "AE7",
        photoURL: "",
        identityState: "published",
        isSynthetic: false,
      },
      {workoutId: "broken"},
    ],
  });

  assert.equal(stored.rows.length, 1);
  const row = stored.rows[0];
  assert.equal(row.kind, "just_climb");
  assert.equal(row.climbId, null);
  assert.equal(row.justClimbGoalKind, "steps");
  assert.equal(row.justClimbGoalValue, 1500);
  assert.equal(row.completedAtMillis, 2_000);
  assert.equal(row.publishedAtMillis, 3_000);
  assert.equal(row.photoURL, null, "an empty photo URL reads as none");
});

// MARK: fixtures

interface WorkoutOverrides {
  source?: string;
  steps?: number;
  durationSeconds?: number;
  metadata?: Record<string, unknown>;
}

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
    startedAt: {toMillis: () => STARTED_AT_MILLIS},
    sourceMetadata: JSON.stringify(metadata),
  };
}

function makePublicUser(
  overrides: Partial<PublicUserSnapshot> = {}
): PublicUserSnapshot {
  return {
    avatarToken: "AE7",
    displayName: "Ada",
    identityState: "published",
    photoURL: null,
    ...overrides,
  };
}

function makeRow(
  overrides: Partial<HomeTodayActivityRow> = {}
): HomeTodayActivityRow {
  return {
    workoutId: "w",
    userId: "user-a",
    kind: "live_climb",
    climbId: ESB,
    routineTemplateId: null,
    steps: 2096,
    durationSeconds: 900,
    completedAtMillis: STARTED_AT_MILLIS + 900_000,
    justClimbGoalKind: null,
    justClimbGoalValue: null,
    publishedAtMillis: 1,
    displayName: "Ada",
    avatarToken: "AE7",
    photoURL: null,
    identityState: "published",
    isSynthetic: false,
    ...overrides,
  };
}

interface FakeStore extends HomeTodayActivityStore {
  projection: HomeTodayActivityProjection | null;
  publicUsers: Map<string, PublicUserSnapshot>;
  writes: number;
  identityReads: number;
}

function makeFakeStore(): FakeStore {
  const store: FakeStore = {
    projection: null,
    publicUsers: new Map(),
    writes: 0,
    identityReads: 0,
    async runTransaction<T>(
      operation: (transaction: HomeTodayActivityTransaction) => Promise<T>
    ): Promise<T> {
      return operation({
        async readProjection() {
          return store.projection ?
            {
              schemaVersion: store.projection.schemaVersion,
              rows: store.projection.rows.map((row) => ({...row})),
            } :
            null;
        },
        async readPublicUser(userId) {
          store.identityReads += 1;
          const publicUser = store.publicUsers.get(userId);
          if (!publicUser) {
            throw new Error(`no public user seeded for ${userId}`);
          }
          return publicUser;
        },
        async writeProjection(projection) {
          store.writes += 1;
          store.projection = projection;
        },
      });
    },
  };
  return store;
}
