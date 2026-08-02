import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  LeaderboardStatsSnapshot,
  LeaderboardStatsStore,
  leaderboardStatsTestHooks,
} from "../src/leaderboardStats.js";
import {
  LEADERBOARD_TIME_FRAMES,
  LeaderboardTimeFrame,
  currentPeriod,
  leaderboardDocumentId,
  previousPeriod,
} from "../src/leaderboardPeriod.js";

const {
  deriveLeaderboardRows,
  demographicsChanged,
  leaderboardDemographics,
  leaderboardIdentityFields,
  parseEligibleWorkout,
  periodBudgetSeconds,
  reconcileLeaderboardStats,
} = leaderboardStatsTestHooks;

const userId = "user-123";
// A Saturday, five days into its week and one day into its month, so a single
// workout lands in all five windows at once.
const NOW = new Date("2026-08-01T12:00:00.000Z");
const FORGED_TOTAL_STEPS = 2_000_000_000;
const STORAGE_PHOTO_URL =
  "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/" +
  `users%2F${userId}%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc123`;

interface PeriodKeyCase {
  name: string;
  date: string;
  weekly: string;
  monthly: string;
  yearly: string;
}

// Compiled output is CommonJS (see tsconfig NodeNext + no package "type"), so
// __dirname is the compiled lib/test directory; walk up to the repo root.
const periodKeyVector = JSON.parse(
  readFileSync(
    join(
      __dirname,
      "../../../SharedTestVectors/leaderboard-period-key-vector.json"
    ),
    "utf8"
  )
) as {cases: PeriodKeyCase[]};

// ---------------------------------------------------------------------------
// Period derivation - the fourth reader of the shared vector.
// ---------------------------------------------------------------------------

test("current period keys match the shared vector every other derivation reads",
  () => {
    for (const periodCase of periodKeyVector.cases) {
      const date = new Date(`${periodCase.date}T12:00:00.000Z`);
      assert.equal(
        currentPeriod("weekly", date).key,
        periodCase.weekly,
        `${periodCase.name} (weekly)`
      );
      assert.equal(
        currentPeriod("monthly", date).key,
        periodCase.monthly,
        `${periodCase.name} (monthly)`
      );
      assert.equal(
        currentPeriod("yearly", date).key,
        periodCase.yearly,
        `${periodCase.name} (yearly)`
      );
    }
  });

// The finalizer reads the closed period; the derivation writes the open one.
// If they ever disagreed about where a period ends, an award would be frozen
// from a window nobody's standing was written into.
test("a closed period ends exactly where the open period begins", () => {
  for (const timeFrame of ["weekly", "monthly", "yearly"] as const) {
    const open = currentPeriod(timeFrame, NOW);
    const closed = previousPeriod(timeFrame, NOW);
    assert.equal(
      closed.endAt.getTime(),
      open.startAt.getTime(),
      `${timeFrame} periods must abut`
    );
    assert.equal(currentPeriod(timeFrame, closed.startAt).key, closed.key);
  }
});

// ---------------------------------------------------------------------------
// Eligibility and the plausibility envelope.
// ---------------------------------------------------------------------------

test("a real session parses into the fields a standing counts", () => {
  const parsed = parseEligibleWorkout("w1", makeWorkout());

  assert.deepEqual(parsed, {
    workoutId: "w1",
    startedAtMillis: new Date("2026-08-01T06:00:00.000Z").getTime(),
    durationSeconds: 1800,
    steps: 3000,
    floors: 150,
  });
});

test("a session claiming a superhuman cadence is not counted", () => {
  // 220 steps a minute is the device's ceiling; the server applies it again
  // because it cannot know the device applied it.
  assert.ok(parseEligibleWorkout("w1", makeWorkout({
    steps: 220 * 30,
    durationSeconds: 1800,
  })));
  assert.equal(parseEligibleWorkout("w1", makeWorkout({
    steps: 220 * 30 + 1,
    durationSeconds: 1800,
  })), null);
});

test("a session with no duration cannot carry steps", () => {
  assert.equal(
    parseEligibleWorkout("w1", makeWorkout({durationSeconds: 0})),
    null
  );
  assert.equal(
    parseEligibleWorkout("w1", makeWorkout({durationSeconds: -60})),
    null
  );
});

test("a session longer than a day is not a session", () => {
  assert.ok(parseEligibleWorkout("w1", makeWorkout({
    durationSeconds: 24 * 60 * 60,
    steps: 0,
  })));
  assert.equal(parseEligibleWorkout("w1", makeWorkout({
    durationSeconds: 24 * 60 * 60 + 1,
    steps: 0,
  })), null);
});

test("an unrecognised workout origin is not counted", () => {
  assert.equal(
    parseEligibleWorkout("w1", makeWorkout({source: "totally_made_up"})),
    null
  );
});

// The device records what it concluded about its own data. The server derives
// the same conclusions itself, so an unverified session still counts and a
// verified-looking implausible one still does not.
test("the device's own integrity verdict changes nothing", () => {
  assert.ok(parseEligibleWorkout("w1", makeWorkout({
    integrityLevel: "unverified",
  })));
  assert.equal(parseEligibleWorkout("w1", makeWorkout({
    integrityLevel: "verified",
    steps: FORGED_TOTAL_STEPS,
    durationSeconds: 1800,
  })), null);
});

test("a period's sessions cannot total more time than the period contains",
  () => {
    // Twelve two-hour sessions all opening on the same UTC day: 24 hours of
    // climbing inside a day that has only had 12 of them so far.
    const dayStart = new Date("2026-08-01T00:00:00.000Z").getTime();
    const workouts = Array.from({length: 12}, (unused, index) => ({
      workoutId: `w${index}`,
      startedAtMillis: dayStart + index * 60_000,
      durationSeconds: 2 * 60 * 60,
      steps: 20_000,
      floors: 900,
    }));

    const rows = deriveLeaderboardRows(userId, workouts, NOW);

    assert.equal(
      rows.find((row) => row.timeFrame === "daily"),
      undefined,
      "the daily row overshoots its wall clock and must not be published"
    );
    assert.ok(
      rows.find((row) => row.timeFrame === "weekly"),
      "the same sessions fit inside the week, which is still honest"
    );
  });

test("one long session never trips its own period's budget", () => {
  // A four-hour session recorded a minute after the UTC day opened would
  // overshoot "time elapsed today" without the floor at the longest session.
  const workouts = [{
    workoutId: "w1",
    startedAtMillis: new Date("2026-08-01T00:01:00.000Z").getTime(),
    durationSeconds: 4 * 60 * 60,
    steps: 40_000,
    floors: 2_000,
  }];

  const period = currentPeriod("daily", new Date("2026-08-01T00:05:00.000Z"));
  assert.ok(periodBudgetSeconds(
    period,
    workouts,
    new Date("2026-08-01T00:05:00.000Z")
  ) >= 4 * 60 * 60);

  const rows = deriveLeaderboardRows(
    userId,
    workouts,
    new Date("2026-08-01T00:05:00.000Z")
  );
  assert.ok(rows.find((row) => row.timeFrame === "daily"));
});

// ---------------------------------------------------------------------------
// Derivation.
// ---------------------------------------------------------------------------

test("one honest session lands on every board window", () => {
  const rows = deriveLeaderboardRows(userId, [{
    workoutId: "w1",
    startedAtMillis: new Date("2026-08-01T06:00:00.000Z").getTime(),
    durationSeconds: 1800,
    steps: 3000,
    floors: 150,
  }], NOW);

  assert.deepEqual(
    rows.map((row) => row.timeFrame).sort(),
    [...LEADERBOARD_TIME_FRAMES].sort()
  );
  const weekly = rows.find((row) => row.timeFrame === "weekly");
  assert.deepEqual(weekly?.aggregate, {
    totalSteps: 3000,
    totalFloors: 150,
    totalWorkouts: 1,
    totalDuration: 1800,
    stepsPerMinute: 100,
  });
  assert.equal(weekly?.periodKey, "2026-W31");
  assert.equal(
    weekly?.documentId,
    leaderboardDocumentId(userId, "weekly", "2026-W31")
  );
});

// The board is deliberately open weekly and hours-old monthly on this date.
// A session before the month opened belongs to the week and not to the month.
test("a session from the previous month counts weekly and not monthly", () => {
  const rows = deriveLeaderboardRows(userId, [{
    workoutId: "w1",
    startedAtMillis: new Date("2026-07-28T06:00:00.000Z").getTime(),
    durationSeconds: 1800,
    steps: 3000,
    floors: 150,
  }], NOW);

  assert.equal(
    rows.find((row) => row.timeFrame === "weekly")?.aggregate.totalSteps,
    3000
  );
  assert.equal(rows.find((row) => row.timeFrame === "monthly"), undefined);
  assert.equal(
    rows.find((row) => row.timeFrame === "yearly")?.aggregate.totalSteps,
    3000
  );
});

test("a climber with nothing in the window gets no row at all", () => {
  const rows = deriveLeaderboardRows(userId, [], NOW);
  assert.deepEqual(rows, []);
});

// ---------------------------------------------------------------------------
// Reconciliation - the whole point of issue #307.
// ---------------------------------------------------------------------------

test("a forged standing is replaced by what the workouts actually show",
  async () => {
    const forgedDocumentId = leaderboardDocumentId(
      userId,
      "weekly",
      "2026-W31"
    );
    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout()}],
      existingRows: [derivedRow(forgedDocumentId)],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.deepEqual(outcome.deleted, []);
    assert.ok(outcome.written.includes(forgedDocumentId));
    assert.equal(store.writes.get(forgedDocumentId)?.totalSteps, 3000);
  });

test("a standing with no workouts behind it is removed entirely", async () => {
  const forgedDocumentId = leaderboardDocumentId(userId, "weekly", "2026-W31");
  const store = makeStore({
    workouts: [],
    existingRows: [derivedRow(forgedDocumentId)],
  });

  const outcome = await reconcileLeaderboardStats(store, userId, NOW);

  assert.deepEqual(outcome.written, []);
  assert.deepEqual(outcome.deleted, [forgedDocumentId]);
});

// This is the audit's scenario end to end: the number the device wrote is
// nowhere in the derived row, so the finalizer has nothing forged to freeze.
test("the server never reads the number a client put in the row", async () => {
  const store = makeStore({
    workouts: [{id: "w1", data: makeWorkout()}],
    // The row already exists carrying the forged total. The derivation never
    // reads a stored total - it only ever reads workouts.
    existingRows: [derivedRow(
      leaderboardDocumentId(userId, "weekly", "2026-W31")
    )],
  });

  await reconcileLeaderboardStats(store, userId, NOW);

  for (const written of store.writes.values()) {
    assert.notEqual(written.totalSteps, FORGED_TOTAL_STEPS);
  }
});

test("a rolled period leaves its closed row alone and opens a new one",
  async () => {
    const closedWeek = leaderboardDocumentId(userId, "weekly", "2026-W30");
    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout()}],
      existingRows: [derivedRow(closedWeek)],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.ok(outcome.written.includes(
      leaderboardDocumentId(userId, "weekly", "2026-W31")
    ));
    // The closed week has no evidence in the current derivation, so it goes.
    // The finalizer has already frozen it; what survives is the achievement.
    assert.deepEqual(outcome.deleted, [closedWeek]);
  });

test("an unpublished profile publishes a masked identity, not a blank one",
  () => {
    assert.deepEqual(leaderboardIdentityFields(userId, undefined), {
      displayName: "Anonymous Climber",
      photoURL: "",
      identityPolicyVersion: 1,
      identityChangedAt: null,
      identityState: "pending_public_profile",
    });
  });

test("a published profile carries its validated identity onto the row", () => {
  const identityChangedAt = new Date("2026-04-09T12:00:00.000Z");

  assert.deepEqual(leaderboardIdentityFields(userId, {
    displayName: "Rockstep",
    photoURL: STORAGE_PHOTO_URL,
    identityPolicyVersion: 1,
    identityChangedAt,
  }), {
    displayName: "Rockstep",
    photoURL: STORAGE_PHOTO_URL,
    identityPolicyVersion: 1,
    identityChangedAt,
    identityState: "published",
  });
});

// Every viewer's device fetches this URL off the row, so the leaderboard
// inherits the storage-host restriction the shared resolver enforces.
test("an off-host profile photo never reaches the row", () => {
  const identity = leaderboardIdentityFields(userId, {
    displayName: "Rockstep",
    photoURL: "https://example.com/p.jpg",
    identityPolicyVersion: 1,
    identityChangedAt: new Date("2026-04-09T12:00:00.000Z"),
  });

  assert.equal(identity.photoURL, "");
});

test("an identity from a retired policy version is masked", () => {
  const identity = leaderboardIdentityFields(userId, {
    displayName: "Rockstep",
    photoURL: "",
    identityPolicyVersion: 99,
    identityChangedAt: new Date(),
  });

  assert.equal(identity.identityState, "pending_public_profile");
  assert.equal(identity.displayName, "Anonymous Climber");
});

// A deleted account's mirror is anonymized rather than removed. Publishing it
// as "pending" would read as a climber who has not set a name yet, which is a
// different and wrong statement about a person who left.
test("a deleted account's standing stays deleted, not pending", () => {
  const identity = leaderboardIdentityFields(userId, {
    displayName: "Anonymous Climber",
    photoURL: "",
    identityPolicyVersion: 1,
    identityChangedAt: new Date(),
  });

  assert.equal(identity.identityState, "deleted");
});

test("only demographics inside the rules' bounds reach the row", () => {
  assert.deepEqual(leaderboardDemographics({
    age: 34,
    weight_kg: 78.5,
    location_city: "Portland",
    location_country: "US",
    location_region: "Oregon",
  }), {
    age: 34,
    weightKg: 78.5,
    locationCity: "Portland",
    locationCountry: "US",
    locationRegion: "Oregon",
  });

  assert.deepEqual(leaderboardDemographics({
    age: 4,
    weight_kg: 900,
    location_city: "",
    location_country: "United States",
    location_region: "  ",
  }), {
    age: null,
    weightKg: null,
    locationCity: null,
    locationCountry: null,
    locationRegion: null,
  });
});

test("only a demographic change reruns the derivation", () => {
  const base = {age: 34, weight_kg: 78.5, displayName: "Rockstep"};

  assert.equal(demographicsChanged(base, {...base, weight_kg: 79}), true);
  assert.equal(demographicsChanged(base, {...base, displayName: "New"}), false);
  assert.equal(demographicsChanged(undefined, base), true);
  assert.equal(demographicsChanged(base, undefined), true);
});

// Seeded competitors have a standing with no canonical workouts behind it, by
// design. The derivation deleting them would empty every dev and staging board
// the moment anything touched a persona's user document.
test("a seeded competitor's standing is neither rewritten nor removed",
  async () => {
    const seededDocumentId = leaderboardDocumentId(
      userId,
      "weekly",
      "2026-W31"
    );
    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout()}],
      existingRows: [{documentId: seededDocumentId, isSynthetic: true}],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.deepEqual(outcome.deleted, []);
    assert.deepEqual(outcome.skippedSynthetic, [seededDocumentId]);
    assert.equal(store.writes.has(seededDocumentId), false);
  });

// A seeded competitor has no workouts at all, so nothing is derived for them.
// The row still has to survive, and the report still has to say why.
test("a seeded competitor with no workouts is reported, not deleted",
  async () => {
    const seededDocumentId = leaderboardDocumentId(
      userId,
      "weekly",
      "2026-W31"
    );
    const store = makeStore({
      workouts: [],
      existingRows: [{documentId: seededDocumentId, isSynthetic: true}],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.deepEqual(outcome.deleted, []);
    assert.deepEqual(outcome.skippedSynthetic, [seededDocumentId]);
  });

function derivedRow(documentId: string) {
  return {documentId, isSynthetic: false};
}

function makeWorkout(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    userId,
    source: "headphone_motion",
    integrityLevel: "verified",
    startedAt: new Date("2026-08-01T06:00:00.000Z"),
    durationSeconds: 1800,
    steps: 3000,
    floors: 150,
    ...overrides,
  };
}

interface RecordingStore extends LeaderboardStatsStore {
  writes: Map<string, Record<string, unknown>>;
  deletes: string[];
}

function makeStore(options: {
  workouts: {id: string; data: Record<string, unknown>}[];
  existingRows: {documentId: string; isSynthetic: boolean}[];
  publicProfile?: Record<string, unknown>;
  user?: Record<string, unknown>;
}): RecordingStore {
  const writes = new Map<string, Record<string, unknown>>();
  const deletes: string[] = [];
  const snapshot: LeaderboardStatsSnapshot = {
    workouts: options.workouts,
    publicProfile: options.publicProfile,
    user: options.user,
    existingRows: options.existingRows,
  };

  return {
    writes,
    deletes,
    async runTransaction(operation) {
      return operation({
        async read() {
          return snapshot;
        },
        async write(documentId, data) {
          writes.set(documentId, data);
        },
        async delete(documentId) {
          deletes.push(documentId);
        },
      });
    },
  };
}

// Referenced so the compiler keeps the import used by the type annotation.
export type {LeaderboardTimeFrame};
