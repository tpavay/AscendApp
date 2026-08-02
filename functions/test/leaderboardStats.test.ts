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
  LeaderboardPeriod,
  LeaderboardTimeFrame,
  currentPeriod,
  leaderboardDocumentId,
  previousPeriod,
} from "../src/leaderboardPeriod.js";

const {
  deriveLeaderboardRows,
  demographicsChanged,
  leaderboardDemographics,
  leaderboardEvidenceChanged,
  leaderboardIdentityFields,
  openPeriods,
  ownedPeriods,
  parseEligibleWorkout,
  resolvedPeriodForRow,
  periodBudgetSeconds,
  reconcileLeaderboardStats,
} = leaderboardStatsTestHooks;

/** The UTC day before the one containing `date`. */
function previousDailyPeriod(date: Date): LeaderboardPeriod {
  return currentPeriod(
    "daily",
    new Date(currentPeriod("daily", date).startAt.getTime() - 1)
  );
}

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
    // Thirteen two-hour sessions all opening on the same UTC day: 26 hours of
    // climbing inside a day that only contains 24.
    const dayStart = new Date("2026-08-01T00:00:00.000Z").getTime();
    const workouts = Array.from({length: 13}, (unused, index) => ({
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

// The budget is the period's FULL length, not the part of it that has elapsed.
// Where bounding an abuser and protecting a real climber pull apart, the real
// climber wins: a loose bound beats one that erases an honest standing.
test("two overlapping sessions early in the day still make the daily board",
  () => {
    // The same 45-minute climb reaching Ascend twice - a Hevy record and its
    // Apple Health twin carry different identifiers, so per-source dedupe keeps
    // both. Ninety minutes of sessions, twenty minutes into the UTC day.
    const workouts = [
      {
        workoutId: "hevy-1",
        startedAtMillis: new Date("2026-08-01T00:05:00.000Z").getTime(),
        durationSeconds: 45 * 60,
        steps: 6_000,
        floors: 300,
      },
      {
        workoutId: "apple-health-1",
        startedAtMillis: new Date("2026-08-01T00:10:00.000Z").getTime(),
        durationSeconds: 45 * 60,
        steps: 6_000,
        floors: 300,
      },
    ];
    const evaluatedAt = new Date("2026-08-01T00:20:00.000Z");

    const rows = deriveLeaderboardRows(userId, workouts, evaluatedAt);

    const daily = rows.find((row) => row.timeFrame === "daily");
    assert.ok(
      daily,
      "an honest climber must not vanish from the board for climbing early"
    );
    assert.equal(daily?.aggregate.totalDuration, 90 * 60);
  });

test("a closed period's budget is its whole length, not what has elapsed",
  () => {
    const period = currentPeriod("daily", new Date("2026-08-01T00:20:00.000Z"));

    assert.equal(
      periodBudgetSeconds(
        period,
        [{
          workoutId: "w1",
          startedAtMillis: new Date("2026-08-01T00:05:00.000Z").getTime(),
          durationSeconds: 45 * 60,
          steps: 6_000,
          floors: 300,
        }],
        new Date("2026-08-01T00:20:00.000Z")
      ),
      24 * 60 * 60
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
      existingRows: [storedRow(currentPeriod("weekly", NOW))],
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
    existingRows: [storedRow(currentPeriod("weekly", NOW))],
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
    existingRows: [storedRow(currentPeriod("weekly", NOW))],
  });

  await reconcileLeaderboardStats(store, userId, NOW);

  for (const written of store.writes.values()) {
    assert.notEqual(written.totalSteps, FORGED_TOTAL_STEPS);
  }
});

test("a rolled period leaves its closed row alone and opens a new one",
  async () => {
    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout()}],
      existingRows: [storedRow(previousPeriod("weekly", NOW))],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.ok(outcome.written.includes(
      leaderboardDocumentId(userId, "weekly", "2026-W31")
    ));
    assert.deepEqual(
      outcome.deleted,
      [],
      "the closed week is the finalizer's evidence, not this derivation's"
    );
    assert.deepEqual(store.deletes, []);
  });

// The window this covers is the one that costs a real climber a real award:
// a period closes at 00:00 UTC, finalizeLeaderboardAchievements freezes it from
// the closed period's rows at 00:15 UTC, and any workout backed up in between
// used to erase the row before the finalizer could read it. The derivation owns
// the five currently OPEN period documents and nothing else.
for (const rollCase of [
  {
    timeFrame: "weekly" as const,
    label: "a Monday, minutes into the new week",
    now: new Date("2026-08-03T00:05:00.000Z"),
    workoutStartedAt: new Date("2026-08-03T00:02:00.000Z"),
  },
  {
    timeFrame: "monthly" as const,
    label: "the 1st, minutes into the new month",
    now: new Date("2026-09-01T00:05:00.000Z"),
    workoutStartedAt: new Date("2026-09-01T00:02:00.000Z"),
  },
  {
    timeFrame: "yearly" as const,
    label: "Jan 1, minutes into the new year",
    now: new Date("2027-01-01T00:05:00.000Z"),
    workoutStartedAt: new Date("2027-01-01T00:02:00.000Z"),
  },
]) {
  test(
    `a workout saved on ${rollCase.label} leaves the closed ` +
    `${rollCase.timeFrame} row - and its permanent award - intact`,
    async () => {
      const closed = previousPeriod(rollCase.timeFrame, rollCase.now);
      const closedRowId = leaderboardDocumentId(
        userId,
        rollCase.timeFrame,
        closed.key
      );
      const openRowId = leaderboardDocumentId(
        userId,
        rollCase.timeFrame,
        currentPeriod(rollCase.timeFrame, rollCase.now).key
      );
      const store = makeStore({
        workouts: [{id: "w1", data: makeWorkout({
          startedAt: rollCase.workoutStartedAt,
          durationSeconds: 600,
          steps: 1_000,
        })}],
        existingRows: [storedRow(closed)],
      });

      const outcome = await reconcileLeaderboardStats(
        store,
        userId,
        rollCase.now
      );

      assert.equal(
        store.deletes.includes(closedRowId),
        false,
        "the finalizer reads this row at 00:15 UTC to freeze the award"
      );
      assert.equal(outcome.deleted.includes(closedRowId), false);
      assert.equal(
        store.writes.has(closedRowId),
        false,
        "a closed period is a historical record, not a document to rewrite"
      );
      assert.ok(
        outcome.written.includes(openRowId),
        "the new period still opens"
      );
    }
  );
}

// The open-period rule cannot be satisfied by simply never deleting: a standing
// whose evidence disappeared inside the OPEN window must still go.
test("an open period with no evidence left is still cleared", async () => {
  const openWeek = leaderboardDocumentId(userId, "weekly", "2026-W31");
  const store = makeStore({
    workouts: [],
    existingRows: [
      storedRow(currentPeriod("weekly", NOW)),
      storedRow(previousPeriod("weekly", NOW)),
    ],
  });

  const outcome = await reconcileLeaderboardStats(store, userId, NOW);

  assert.deepEqual(outcome.deleted, [openWeek]);
});

// ---------------------------------------------------------------------------
// Retention - what still READS the row, not whether its period closed.
// ---------------------------------------------------------------------------

// A closed daily row is not finalized into an achievement and the client only
// ever queries the current period, so nothing reads it again. Kept forever it
// would add one dead document per active climber per day to a per-user read
// that is already unpaginated.
test("a closed daily row is removed because nothing reads it again",
  async () => {
    const closedDay = previousDailyPeriod(NOW);
    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout()}],
      existingRows: [storedRow(closedDay)],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    const closedDayId = leaderboardDocumentId(userId, "daily", closedDay.key);
    assert.deepEqual(outcome.deleted, [closedDayId]);
    // The trigger never derived that window, so calling this an evidence
    // failure would state a finding nobody made.
    assert.equal(store.deleteReasons.get(closedDayId), "prunedClosedWindow");
  });

// A pruned window and an examined-but-empty window look identical in the data
// and mean opposite things about the row. A dry run that describes a legitimate
// daily row the way it describes a forged one is worthless.
test("pruning a closed window and finding no evidence are different verdicts",
  async () => {
    const closedDay = previousDailyPeriod(NOW);
    const openWeek = currentPeriod("weekly", NOW);
    const store = makeStore({
      workouts: [],
      existingRows: [storedRow(closedDay), storedRow(openWeek)],
    });

    await reconcileLeaderboardStats(store, userId, NOW);

    assert.equal(
      store.deleteReasons.get(
        leaderboardDocumentId(userId, "daily", closedDay.key)
      ),
      "prunedClosedWindow"
    );
    assert.equal(
      store.deleteReasons.get(
        leaderboardDocumentId(userId, "weekly", openWeek.key)
      ),
      "noEvidence"
    );
  });

for (const timeFrame of ["weekly", "monthly", "yearly"] as const) {
  test(
    `a closed ${timeFrame} row survives because an award points back at it`,
    async () => {
      const closed = previousPeriod(timeFrame, NOW);
      const store = makeStore({
        workouts: [{id: "w1", data: makeWorkout()}],
        existingRows: [storedRow(closed)],
      });

      const outcome = await reconcileLeaderboardStats(store, userId, NOW);

      assert.deepEqual(outcome.deleted, []);
      assert.deepEqual(store.deletes, []);
    }
  );
}

// The window has to come off the stored fields. A row that does not say which
// period it belongs to cannot be judged by a trigger, and the safe answer is to
// leave it - but never to say nothing about it.
test("a row whose window cannot be established is never removed by a trigger",
  async () => {
    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout()}],
      existingRows: [{
        documentId: "daily_2026-07-31_" + userId,
        isSynthetic: false,
        timeFrame: null,
        periodStartAtMillis: null,
      }],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.deepEqual(outcome.deleted, []);
  });

// The legacy `{uid}_{timeFrame}` documents. This branch deleted their only
// sweeper, and the finalizer matches rows on timeFrame + periodStartAt with no
// constraint on document id, so one can still win a permanent award. Leaving
// them out of the report would hide that.
test("a legacy row with no derivable period is reported, not skipped silently",
  async () => {
    const legacyId = `${userId}_weekly`;
    const legacyRow = {
      documentId: legacyId,
      isSynthetic: false,
      timeFrame: "weekly" as const,
      periodStartAtMillis: previousPeriod("weekly", NOW).startAt.getTime(),
    };

    assert.equal(resolvedPeriodForRow(userId, legacyRow), null);

    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout()}],
      existingRows: [legacyRow],
    });
    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.deepEqual(outcome.unresolvableRows, [legacyId]);
    assert.deepEqual(outcome.deleted, [], "a trigger must not make it final");
  });

test("a legacy row is removable only under the operator ownership", async () => {
  const legacyId = `${userId}_weekly`;
  const legacyRow = {
    documentId: legacyId,
    isSynthetic: false,
    timeFrame: "weekly" as const,
    periodStartAtMillis: previousPeriod("weekly", NOW).startAt.getTime(),
  };
  const store = makeStore({
    workouts: [{id: "w1", data: makeWorkout()}],
    existingRows: [legacyRow],
  });

  const outcome = await reconcileLeaderboardStats(
    store,
    userId,
    NOW,
    {ownership: "openAndStoredPeriods"}
  );

  assert.deepEqual(outcome.deleted, [legacyId]);
  assert.deepEqual(outcome.unresolvableRows, [legacyId]);
  assert.equal(store.deleteReasons.get(legacyId), "unresolvableWindow");
});

// ---------------------------------------------------------------------------
// Ownership - the trigger owns the open windows, the operator can own more.
// ---------------------------------------------------------------------------

test("the trigger ownership owns exactly the five open windows", () => {
  const closed = previousPeriod("weekly", NOW);

  assert.deepEqual(
    ownedPeriods(userId, NOW, [storedRow(closed)], "openPeriodsOnly")
      .map((period) => period.key)
      .sort(),
    openPeriods(NOW).map((period) => period.key).sort()
  );
});

test("the operator ownership additionally owns every stored window", () => {
  const closed = previousPeriod("weekly", NOW);

  const keys = ownedPeriods(
    userId,
    NOW,
    [storedRow(closed)],
    "openAndStoredPeriods"
  ).map((period) => period.key);

  assert.ok(keys.includes(closed.key));
  for (const period of openPeriods(NOW)) {
    assert.ok(keys.includes(period.key));
  }
  assert.equal(new Set(keys).size, keys.length, "windows must not repeat");
});

// The stored fields and the document id are two spellings of one window. When
// they disagree the row is malformed, and rewriting it under a window it does
// not claim would move a standing rather than repair it.
test("a stored window that does not round-trip to its own id is not owned",
  () => {
    const closed = previousPeriod("weekly", NOW);
    const mismatched = {
      ...storedRow(closed),
      documentId: leaderboardDocumentId(userId, "weekly", "1999-W01"),
    };

    const keys = ownedPeriods(
      userId,
      NOW,
      [mismatched],
      "openAndStoredPeriods"
    ).map((period) => period.key);

    assert.equal(keys.includes(closed.key), false);
  });

// This is what the backfill exists for: the client-authored rows sitting in the
// window the nightly finalizer is about to freeze permanent awards from.
test("the operator ownership repairs a closed period's forged total",
  async () => {
    const closed = previousPeriod("weekly", NOW);
    const closedId = leaderboardDocumentId(userId, "weekly", closed.key);
    const store = makeStore({
      workouts: [{id: "w1", data: makeWorkout({
        startedAt: new Date(closed.startAt.getTime() + 6 * 60 * 60 * 1000),
      })}],
      existingRows: [storedRow(closed)],
    });

    const outcome = await reconcileLeaderboardStats(
      store,
      userId,
      NOW,
      {ownership: "openAndStoredPeriods"}
    );

    assert.ok(outcome.written.includes(closedId));
    assert.equal(store.writes.get(closedId)?.totalSteps, 3000);
    assert.equal(store.writes.get(closedId)?.periodKey, closed.key);
  });

test("the operator ownership removes a closed row with no evidence behind it",
  async () => {
    const closed = previousPeriod("weekly", NOW);
    const store = makeStore({
      workouts: [],
      existingRows: [storedRow(closed)],
    });

    const outcome = await reconcileLeaderboardStats(
      store,
      userId,
      NOW,
      {ownership: "openAndStoredPeriods"}
    );

    const closedId = leaderboardDocumentId(userId, "weekly", closed.key);
    assert.deepEqual(outcome.deleted, [closedId]);
    assert.equal(store.deleteReasons.get(closedId), "noEvidence");
  });

// The wider ownership is the operator's, not the trigger's. Defaulting to it
// would put an unattended trigger back in the finalizer's way.
test("reconciliation defaults to the trigger ownership", async () => {
  const closed = previousPeriod("weekly", NOW);
  const store = makeStore({
    workouts: [],
    existingRows: [storedRow(closed)],
  });

  const outcome = await reconcileLeaderboardStats(store, userId, NOW);

  assert.deepEqual(outcome.deleted, []);
});

test("a seeded competitor stays exempt under the operator ownership",
  async () => {
    const closed = previousPeriod("weekly", NOW);
    const seededId = leaderboardDocumentId(userId, "weekly", closed.key);
    const store = makeStore({
      workouts: [],
      existingRows: [storedRow(closed, true)],
    });

    const outcome = await reconcileLeaderboardStats(
      store,
      userId,
      NOW,
      {ownership: "openAndStoredPeriods"}
    );

    assert.deepEqual(outcome.deleted, []);
    assert.deepEqual(outcome.skippedSynthetic, [seededId]);
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

// Reconciliation re-reads the climber's whole workout collection and rewrites
// five documents. A photo upload completing must not pay that cost.
test("only a change to the evidence reruns the derivation", () => {
  const before = makeWorkout();

  assert.equal(
    leaderboardEvidenceChanged(before, makeWorkout({steps: 3_001})),
    true
  );
  assert.equal(
    leaderboardEvidenceChanged(before, makeWorkout({floors: 151})),
    true
  );
  assert.equal(
    leaderboardEvidenceChanged(before, makeWorkout({durationSeconds: 1_801})),
    true
  );
  assert.equal(
    leaderboardEvidenceChanged(before, makeWorkout({source: "apple_health"})),
    true
  );
  assert.equal(
    leaderboardEvidenceChanged(before, makeWorkout({
      startedAt: new Date("2026-08-01T07:00:00.000Z"),
    })),
    true
  );

  assert.equal(
    leaderboardEvidenceChanged(before, makeWorkout({
      photoURL: "https://example.com/p.jpg",
      notes: "Brutal.",
      heartRateSeriesPath: "users/u/hr/w1.json",
      averageHeartRate: 148,
      calories: 410,
      met: 8.8,
      integrityLevel: "unverified",
    })),
    false,
    "a photo, a note, heart rate, calories or MET changes no total"
  );

  // A create and a delete always carry evidence in or out.
  assert.equal(leaderboardEvidenceChanged(undefined, before), true);
  assert.equal(leaderboardEvidenceChanged(before, undefined), true);
});

// The two images can carry the same instant in different shapes, and a
// structural comparison would rederive on every touch of an unchanged workout.
test("the same start instant in a different shape is not a change", () => {
  const millis = new Date("2026-08-01T06:00:00.000Z").getTime();

  assert.equal(
    leaderboardEvidenceChanged(
      makeWorkout({startedAt: new Date(millis)}),
      makeWorkout({startedAt: {toMillis: () => millis}})
    ),
    false
  );
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
      existingRows: [storedRow(currentPeriod("weekly", NOW), true)],
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
      existingRows: [storedRow(currentPeriod("weekly", NOW), true)],
    });

    const outcome = await reconcileLeaderboardStats(store, userId, NOW);

    assert.deepEqual(outcome.deleted, []);
    assert.deepEqual(outcome.skippedSynthetic, [seededDocumentId]);
  });

/**
 * A stored row, described by the window it belongs to rather than by a bare id.
 * The derivation reads `timeFrame` and `periodStartAt` off the document to
 * decide what it owns, so a fixture without them tests nothing.
 */
function storedRow(period: LeaderboardPeriod, isSynthetic = false) {
  return {
    documentId: leaderboardDocumentId(userId, period.timeFrame, period.key),
    isSynthetic,
    timeFrame: period.timeFrame,
    periodStartAtMillis: period.startAt.getTime(),
  };
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
  deleteReasons: Map<string, string>;
}

function makeStore(options: {
  workouts: {id: string; data: Record<string, unknown>}[];
  existingRows: {
    documentId: string;
    isSynthetic: boolean;
    timeFrame?: LeaderboardTimeFrame | null;
    periodStartAtMillis?: number | null;
  }[];
  publicProfile?: Record<string, unknown>;
  user?: Record<string, unknown>;
}): RecordingStore {
  const writes = new Map<string, Record<string, unknown>>();
  const deletes: string[] = [];
  const deleteReasons = new Map<string, string>();
  const snapshot: LeaderboardStatsSnapshot = {
    workouts: options.workouts,
    publicProfile: options.publicProfile,
    user: options.user,
    existingRows: options.existingRows.map((row) => ({
      timeFrame: null,
      periodStartAtMillis: null,
      ...row,
    })),
  };

  return {
    writes,
    deletes,
    deleteReasons,
    async runTransaction(operation) {
      return operation({
        async read() {
          return snapshot;
        },
        async readPeriodFinalization() {
          return {exists: false, status: null};
        },
        async write(documentId, data) {
          writes.set(documentId, data);
        },
        async delete(documentId, reason) {
          deletes.push(documentId);
          deleteReasons.set(documentId, reason);
        },
      });
    },
  };
}

// Referenced so the compiler keeps the import used by the type annotation.
export type {LeaderboardTimeFrame};
