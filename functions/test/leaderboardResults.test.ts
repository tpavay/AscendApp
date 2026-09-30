import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {previousPeriod} from "../src/leaderboardPeriod.js";
import {
  MOST_CLIMBS_USER_LIMIT,
  RankedStanding,
  StandingRow,
  buildLeaderboardResult,
  dedupeStandings,
  leaderboardResultId,
  placingIdentity,
  rankStandings,
  standingRowFromData,
  summarizePeriodStandings,
} from "../src/leaderboardResults.js";

// Monday 2026-09-28 00:15 UTC: the finalizer closing 2026-W39.
const NOW = new Date("2026-09-28T00:15:00.000Z");
const WEEK = previousPeriod("weekly", NOW);
const CHANGED_AT = admin.firestore.Timestamp.fromDate(
  new Date("2026-04-09T12:00:00.000Z")
);

/**
 * Builds a stored stats row the way leaderboardStats.ts writes one.
 * @param {string} userId Owner.
 * @param {number} totalSteps Steps.
 * @param {Record<string, unknown>} overrides Field overrides.
 * @return {Record<string, unknown>} Stored fields.
 */
function statsData(
  userId: string,
  totalSteps: number,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    displayName: `Climber ${userId}`,
    identityChangedAt: CHANGED_AT,
    identityPolicyVersion: 1,
    identityState: "published",
    isSynthetic: false,
    lastUpdated: admin.firestore.Timestamp.fromDate(
      new Date("2026-09-27T20:00:00.000Z")
    ),
    photoURL: "",
    periodKey: WEEK.key,
    periodStartAt: admin.firestore.Timestamp.fromDate(WEEK.startAt),
    timeFrame: "weekly",
    totalFloors: Math.round(totalSteps / 20),
    totalSteps,
    totalWorkouts: 3,
    userId,
    ...overrides,
  };
}

/**
 * Parses a stored row, failing the test when it cannot stand on the board.
 * @param {string} userId Owner.
 * @param {number} totalSteps Steps.
 * @param {Record<string, unknown>} overrides Field overrides.
 * @return {StandingRow} The parsed row.
 */
function row(
  userId: string,
  totalSteps: number,
  overrides: Record<string, unknown> = {}
): StandingRow {
  const parsed = standingRowFromData(
    `weekly_${WEEK.key}_${userId}`,
    statsData(userId, totalSteps, overrides)
  );
  assert.ok(parsed, `${userId} should parse`);
  return parsed;
}

/**
 * Ranks rows the way the finalizer does.
 * @param {StandingRow[]} rows Rows in any order.
 * @return {RankedStanding[]} Every row ranked.
 */
function ranked(rows: StandingRow[]): RankedStanding[] {
  return rankStandings(dedupeStandings(rows));
}

test("a row with no owner or no steps never stands on the board", () => {
  assert.equal(
    standingRowFromData("a", statsData("user-a", 0)),
    null
  );
  assert.equal(
    standingRowFromData("a", statsData("user-a", -5)),
    null
  );
  assert.equal(
    standingRowFromData("a", statsData("", 1_000)),
    null
  );
  assert.equal(
    standingRowFromData("a", statsData("user-a", 1_000, {userId: 42})),
    null
  );

  const parsed = standingRowFromData(
    "weekly_x_user-a",
    statsData("user-a", 1_234.9, {totalWorkouts: 4.7, totalFloors: "9"})
  );
  assert.equal(parsed?.totalSteps, 1_234);
  assert.equal(parsed?.totalWorkouts, 4);
  assert.equal(parsed?.totalFloors, 0);
  assert.equal(parsed?.documentId, "weekly_x_user-a");
});

test("one row per climber, the most recently updated, in board order", () => {
  const older = row("user-a", 9_000, {
    lastUpdated: admin.firestore.Timestamp.fromDate(
      new Date("2026-09-20T00:00:00.000Z")
    ),
  });
  const newer = row("user-a", 4_000);
  const sameInstantLater = {...row("user-b", 7_000), documentId: "second"};
  const sameInstantFirst = {...row("user-b", 6_000), documentId: "first"};

  const rows = dedupeStandings([
    older,
    sameInstantFirst,
    row("user-c", 7_000),
    newer,
    sameInstantLater,
  ]);

  assert.deepEqual(
    rows.map((entry) => [entry.userId, entry.totalSteps]),
    [
      ["user-c", 7_000],
      ["user-b", 6_000],
      ["user-a", 4_000],
    ]
  );
  // A tie on lastUpdated keeps the row read first, as the award query always
  // has.
  assert.equal(rows[1].documentId, "first");
});

test("ranks by standard competition ranking and never by uid", () => {
  const rows = ranked([
    row("user-d", 5_000),
    row("user-b", 9_000),
    row("user-a", 9_000),
    row("user-c", 7_000),
  ]);

  assert.deepEqual(
    rows.map((entry) => [entry.userId, entry.rank]),
    [
      ["user-a", 1],
      ["user-b", 1],
      ["user-c", 3],
      ["user-d", 4],
    ]
  );
});

test("a tie at the rank limit keeps every tied climber", () => {
  const rows = [
    row("user-a", 10_000),
    row("user-b", 9_000),
    row("user-c", 9_000),
    row("user-d", 8_000),
  ];

  assert.deepEqual(
    rankStandings(dedupeStandings(rows), 2).map((entry) => entry.userId),
    ["user-a", "user-b", "user-c"]
  );
});

test("a period summary counts every climber the board ranks", () => {
  const summary = summarizePeriodStandings(dedupeStandings([
    row("user-a", 10_000, {totalWorkouts: 2, totalFloors: 500}),
    row("user-b", 8_000, {totalWorkouts: 7, totalFloors: 400}),
    row("user-c", 6_000, {totalWorkouts: 7, totalFloors: 300}),
    row("user-d", 4_000, {totalWorkouts: 1, totalFloors: 200}),
  ]));

  assert.equal(summary.climberCount, 4);
  assert.deepEqual(summary.community, {
    climbers: 4,
    climbs: 17,
    steps: 28_000,
    floors: 1_400,
  });
  assert.deepEqual(summary.mostClimbs, {
    count: 7,
    userIds: ["user-b", "user-c"],
  });
  assert.deepEqual(
    summary.mostClimbsLeaders.map((entry) => [entry.userId, entry.rank]),
    [["user-b", 2], ["user-c", 3]]
  );
});

test("the most-climbs leaders stop at ten, in board order", () => {
  const rows = Array.from({length: 14}, (_unused, index) =>
    row(`user-${String(index).padStart(2, "0")}`, 20_000 - index * 100, {
      totalWorkouts: 9,
    })
  );

  const summary = summarizePeriodStandings(dedupeStandings(rows));

  assert.equal(summary.mostClimbs?.count, 9);
  assert.equal(summary.mostClimbs?.userIds.length, MOST_CLIMBS_USER_LIMIT);
  assert.deepEqual(
    summary.mostClimbs?.userIds,
    rows.slice(0, MOST_CLIMBS_USER_LIMIT).map((entry) => entry.userId)
  );
});

test("nobody holds most climbs when no climb was counted", () => {
  const summary = summarizePeriodStandings(dedupeStandings([
    row("user-a", 3_000, {totalWorkouts: 0}),
  ]));

  assert.equal(summary.mostClimbs, null);
  assert.deepEqual(summary.mostClimbsLeaders, []);
  assert.equal(summary.climberCount, 1);
});

test("a published identity is frozen exactly as the stats row carries it",
  () => {
    const identity = placingIdentity(statsData("user-a", 1_000, {
      displayName: "Maya Chen",
      photoURL: "https://firebasestorage.googleapis.com/v0/b/x/o/y",
      isSynthetic: true,
    }));

    assert.deepEqual(identity, {
      displayName: "Maya Chen",
      photoURL: "https://firebasestorage.googleapis.com/v0/b/x/o/y",
      identityPolicyVersion: 1,
      identityState: "published",
      identityChangedAt: CHANGED_AT,
      isSynthetic: true,
    });
  });

test("an identity the client would refuse is frozen as pending anonymous",
  () => {
    const pending = {
      displayName: "Anonymous Climber",
      photoURL: "",
      identityPolicyVersion: 1,
      identityState: "pending_public_profile",
      identityChangedAt: null,
      isSynthetic: false,
    };

    // A published name with no change stamp, an unknown policy, and an
    // unknown state all fail the client's parse - and a placing that fails
    // it is a missing row on a past board.
    assert.deepEqual(
      placingIdentity(statsData("user-a", 1, {identityChangedAt: null})),
      pending
    );
    assert.deepEqual(
      placingIdentity(statsData("user-a", 1, {identityPolicyVersion: 2})),
      pending
    );
    assert.deepEqual(
      placingIdentity(statsData("user-a", 1, {identityState: "hidden"})),
      pending
    );
    assert.deepEqual(
      placingIdentity({userId: "user-a", totalSteps: 1}),
      pending
    );
  });

test("a deleted identity stays deleted on the placing", () => {
  const identity = placingIdentity(statsData("user-a", 1_000, {
    displayName: "Anonymous Climber",
    identityChangedAt: null,
    identityState: "deleted",
  }));

  assert.equal(identity.identityState, "deleted");
  assert.equal(identity.displayName, "Anonymous Climber");
  assert.equal(identity.identityChangedAt, null);
});

test("a result names every co-champion and the whole podium", () => {
  const rows = ranked([
    row("user-a", 9_000),
    row("user-b", 9_000),
    row("user-c", 7_000),
    row("user-d", 7_000),
    row("user-e", 5_000),
  ]);

  const {result, resultId} = buildLeaderboardResult({
    period: WEEK,
    placed: rows,
    summary: summarizePeriodStandings(dedupeStandings(rows)),
    source: "leaderboard_finalizer",
  });

  assert.equal(resultId, `weekly_${WEEK.key}`);
  assert.equal(resultId, leaderboardResultId("weekly", WEEK.key));
  assert.deepEqual(result.championUserIds, ["user-a", "user-b"]);
  assert.deepEqual(result.podiumUserIds, [
    "user-a",
    "user-b",
    "user-c",
    "user-d",
  ]);
  assert.equal(result.climberCount, 5);
});

test("a result carries exactly the contract's fields", () => {
  const rows = ranked([row("user-a", 9_000), row("user-b", 4_000)]);

  const {result, placings} = buildLeaderboardResult({
    period: WEEK,
    placed: rows,
    summary: summarizePeriodStandings(dedupeStandings(rows)),
    source: "leaderboard_finalizer",
  });

  assert.deepEqual(Object.keys(result).sort(), [
    "championUserIds",
    "climberCount",
    "community",
    "finalizedAt",
    "metric",
    "mostClimbs",
    "periodEndAt",
    "periodKey",
    "periodStartAt",
    "podiumUserIds",
    "reconstructed",
    "schemaVersion",
    "source",
    "timeFrame",
  ]);
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.metric, "steps");
  assert.equal(result.timeFrame, "weekly");
  assert.equal(result.periodKey, WEEK.key);
  assert.equal(result.source, "leaderboard_finalizer");
  assert.equal(result.reconstructed, false);
  assert.ok(
    (result.periodStartAt as admin.firestore.Timestamp).isEqual(
      admin.firestore.Timestamp.fromDate(WEEK.startAt)
    )
  );
  assert.ok(
    (result.periodEndAt as admin.firestore.Timestamp).isEqual(
      admin.firestore.Timestamp.fromDate(WEEK.endAt)
    )
  );
  assert.ok(
    (result.finalizedAt as admin.firestore.FieldValue).isEqual(
      admin.firestore.FieldValue.serverTimestamp()
    )
  );

  assert.deepEqual(Object.keys(placings[0].data).sort(), [
    "displayName",
    "identityChangedAt",
    "identityPolicyVersion",
    "identityState",
    "isSynthetic",
    "periodKey",
    "periodStartAt",
    "photoURL",
    "rank",
    "schemaVersion",
    "timeFrame",
    "totalSteps",
    "totalWorkouts",
    "userId",
  ]);
  assert.deepEqual(
    {...placings[0].data, periodStartAt: null, identityChangedAt: null},
    {
      displayName: "Climber user-a",
      identityChangedAt: null,
      identityPolicyVersion: 1,
      identityState: "published",
      isSynthetic: false,
      periodKey: WEEK.key,
      periodStartAt: null,
      photoURL: "",
      rank: 1,
      schemaVersion: 1,
      timeFrame: "weekly",
      totalSteps: 9_000,
      totalWorkouts: 3,
      userId: "user-a",
    }
  );
  assert.ok(
    (placings[0].data.identityChangedAt as admin.firestore.Timestamp)
      .isEqual(CHANGED_AT)
  );
});

test("a most-climbs leader outside the awarded set is placed at full rank",
  () => {
    const everyone = dedupeStandings([
      ...Array.from({length: 5}, (_unused, index) =>
        row(`top-${index}`, 50_000 - index * 1_000, {totalWorkouts: 2})
      ),
      row("grinder", 900, {totalWorkouts: 40}),
    ]);
    // Only the top three were awarded in this example.
    const placed = rankStandings(everyone, 3);

    const {result, placings} = buildLeaderboardResult({
      period: WEEK,
      placed,
      summary: summarizePeriodStandings(everyone),
      source: "leaderboard_finalizer",
    });

    assert.deepEqual(result.mostClimbs, {count: 40, userIds: ["grinder"]});
    assert.deepEqual(
      placings.map((placing) => [placing.userId, placing.data.rank]),
      [
        ["top-0", 1],
        ["top-1", 2],
        ["top-2", 3],
        ["grinder", 6],
      ]
    );
    assert.equal(placings[3].data.totalWorkouts, 40);
  });

test("a most-climbs leader already placed is placed once", () => {
  const everyone = dedupeStandings([
    row("user-a", 9_000, {totalWorkouts: 12}),
    row("user-b", 4_000, {totalWorkouts: 3}),
  ]);

  const {placings} = buildLeaderboardResult({
    period: WEEK,
    placed: rankStandings(everyone, 100),
    summary: summarizePeriodStandings(everyone),
    source: "leaderboard_finalizer",
  });

  assert.deepEqual(
    placings.map((placing) => placing.userId),
    ["user-a", "user-b"]
  );
});

test("an empty period still freezes a result", () => {
  const {result, placings} = buildLeaderboardResult({
    period: WEEK,
    placed: [],
    summary: summarizePeriodStandings([]),
    source: "leaderboard_finalizer",
  });

  assert.equal(result.climberCount, 0);
  assert.deepEqual(result.championUserIds, []);
  assert.deepEqual(result.podiumUserIds, []);
  assert.equal(result.mostClimbs, null);
  assert.deepEqual(result.community, {
    climbers: 0,
    climbs: 0,
    steps: 0,
    floors: 0,
  });
  assert.deepEqual(placings, []);
});

test("a backfilled result says it was reconstructed", () => {
  const {result} = buildLeaderboardResult({
    period: WEEK,
    placed: [],
    summary: summarizePeriodStandings([]),
    source: "backfill",
  });

  assert.equal(result.source, "backfill");
  assert.equal(result.reconstructed, true);
});

test("champions follow the ranks the result is given, in board order", () => {
  // The backfill corrects a rank to the one already awarded; the crown has to
  // follow that rank rather than the row's position.
  const rows = ranked([row("user-a", 9_000), row("user-b", 8_000)]);
  const corrected = [
    {...rows[0], rank: 2},
    {...rows[1], rank: 1},
  ];

  const {result, placings} = buildLeaderboardResult({
    period: WEEK,
    placed: corrected,
    summary: summarizePeriodStandings(dedupeStandings(rows)),
    source: "backfill",
  });

  assert.deepEqual(result.championUserIds, ["user-b"]);
  assert.deepEqual(
    placings.map((placing) => placing.userId),
    ["user-b", "user-a"]
  );
});
