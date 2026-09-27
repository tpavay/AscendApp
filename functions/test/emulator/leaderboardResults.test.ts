/**
 * The finalizer's frozen result, against a real Firestore.
 *
 * The unit suite proves the ranking, the summary arithmetic and the commit
 * packing in isolation. This suite runs `finalizeMostRecentClosedPeriod`
 * itself: the award query and the paged period read over real rows, the
 * achievements and the result landing together, a tie too large for one
 * commit, and a retry after a run that died part-way.
 *
 * Lives under test/emulator/ so `npm test` does not pick it up without a
 * Firestore behind it. `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  leaderboardAchievementsTestHooks,
} from "../../src/leaderboardAchievements.js";
import {
  leaderboardDocumentId,
  previousPeriod,
} from "../../src/leaderboardPeriod.js";
import {
  readAwardStandings,
  readPeriodStandings,
} from "../../src/leaderboardResults.js";

const PROJECT_ID = "demo-ascend-leaderboard-derivation";
// Monday 00:15 UTC, the finalizer's own schedule: closes 2026-W39 and 2026-M08
// is long closed, so the monthly board below is simply empty.
const NOW = new Date("2026-09-28T00:15:00.000Z");
const WEEK = previousPeriod("weekly", NOW);
const WEEK_RESULT = `leaderboard_results/weekly_${WEEK.key}`;
const IDENTITY_CHANGED_AT = admin.firestore.Timestamp.fromDate(
  new Date("2026-04-09T12:00:00.000Z")
);
const ROW_UPDATED_AT = admin.firestore.Timestamp.fromDate(
  new Date("2026-09-27T20:00:00.000Z")
);

const {finalizeMostRecentClosedPeriod} = leaderboardAchievementsTestHooks;

let db: admin.firestore.Firestore;

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  admin.initializeApp({projectId: PROJECT_ID});
  db = admin.firestore();
});

beforeEach(async () => {
  await clearFirestore();
});

interface SeedRow {
  userId: string;
  totalSteps: number;
  totalWorkouts: number;
  overrides?: Record<string, unknown>;
  documentId?: string;
}

/**
 * The board every full-run test seeds: 300 climbers, so the period is wider
 * than both the 100 awarded ranks and the 250 rows the award query reads.
 *
 * - u000 and u001 tie for first.
 * - u250 climbs most often but ranks 251st, outside the award query entirely.
 * - u003's stored identity is one the client would refuse.
 * - u004 is a seeded rival.
 * - u005 also owns an older legacy row with more steps, which must lose.
 * - `zero` has climbs but no steps, so it stands on no board.
 * @return {SeedRow[]} Rows to write.
 */
function standardBoard(): SeedRow[] {
  const rows: SeedRow[] = [];
  for (let index = 0; index < 300; index += 1) {
    const userId = `u${String(index).padStart(3, "0")}`;
    rows.push({
      userId,
      totalSteps: index <= 1 ? 100_000 : 100_000 - index * 10,
      totalWorkouts: userId === "u250" ? 30 : 2,
      overrides: userId === "u003" ?
        {identityChangedAt: null} :
        userId === "u004" ? {isSynthetic: true} : {},
    });
  }
  rows.push({
    userId: "u005",
    totalSteps: 200_000,
    totalWorkouts: 9,
    documentId: "u005_weekly",
    overrides: {
      lastUpdated: admin.firestore.Timestamp.fromDate(
        new Date("2026-09-22T00:00:00.000Z")
      ),
    },
  });
  rows.push({userId: "zero", totalSteps: 0, totalWorkouts: 50});
  return rows;
}

test("a closed week freezes its result beside its awards", async () => {
  const board = standardBoard();
  await seedRows(board);

  await finalizeMostRecentClosedPeriod("weekly", NOW);

  const result = (await db.doc(WEEK_RESULT).get()).data();
  assert.ok(result, "the result must exist");
  const canonical = board.filter(
    (row) => row.documentId === undefined && row.totalSteps > 0
  );
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.timeFrame, "weekly");
  assert.equal(result.periodKey, WEEK.key);
  assert.equal(result.metric, "steps");
  assert.equal(result.source, "leaderboard_finalizer");
  assert.equal(result.reconstructed, false);
  assert.ok(result.finalizedAt instanceof admin.firestore.Timestamp);
  assert.equal(result.periodStartAt.toMillis(), WEEK.startAt.getTime());
  assert.equal(result.periodEndAt.toMillis(), WEEK.endAt.getTime());
  assert.deepEqual(result.championUserIds, ["u000", "u001"]);
  assert.deepEqual(result.podiumUserIds, ["u000", "u001", "u002"]);
  // Every climber in the period, not the 250 the award query reads - and the
  // legacy duplicate and the stepless row are not climbers on this board.
  assert.equal(result.climberCount, 300);
  assert.deepEqual(result.community, {
    climbers: 300,
    climbs: sum(canonical.map((row) => row.totalWorkouts)),
    steps: sum(canonical.map((row) => row.totalSteps)),
    floors: sum(canonical.map((row) => Math.round(row.totalSteps / 20))),
  });
  assert.deepEqual(result.mostClimbs, {count: 30, userIds: ["u250"]});

  const placings = await db.collection(`${WEEK_RESULT}/placings`)
    .orderBy("rank")
    .get();
  // Ranks 1-100 plus the most-climbs leader from rank 251.
  assert.equal(placings.size, 101);
  const byUser = new Map(
    placings.docs.map((document) => [document.id, document.data()])
  );
  assert.equal(byUser.get("u000")?.rank, 1);
  assert.equal(byUser.get("u001")?.rank, 1);
  assert.equal(byUser.get("u099")?.rank, 100);
  assert.equal(byUser.has("u100"), false);
  assert.equal(byUser.get("u250")?.rank, 251);
  assert.equal(byUser.get("u250")?.totalWorkouts, 30);
  assert.equal(byUser.get("u005")?.totalSteps, 100_000 - 50);

  const champion = byUser.get("u000");
  assert.equal(champion?.schemaVersion, 1);
  assert.equal(champion?.userId, "u000");
  assert.equal(champion?.timeFrame, "weekly");
  assert.equal(champion?.periodKey, WEEK.key);
  assert.equal(champion?.periodStartAt.toMillis(), WEEK.startAt.getTime());
  assert.equal(champion?.totalSteps, 100_000);
  assert.equal(champion?.totalWorkouts, 2);
  assert.equal(champion?.displayName, "Climber u000");
  assert.equal(champion?.photoURL, "");
  assert.equal(champion?.identityPolicyVersion, 1);
  assert.equal(champion?.identityState, "published");
  assert.ok(champion?.identityChangedAt.isEqual(IDENTITY_CHANGED_AT));
  assert.equal(champion?.isSynthetic, false);
  assert.equal(byUser.get("u004")?.isSynthetic, true);
  assert.equal(byUser.get("u003")?.displayName, "Anonymous Climber");
  assert.equal(byUser.get("u003")?.identityState, "pending_public_profile");
  assert.equal(byUser.get("u003")?.identityChangedAt, null);

  // The awards are exactly what they were before results existed.
  const achievement = (await db
    .doc(`users/u000/achievements/global_steps_weekly_${WEEK.key}`)
    .get()).data();
  assert.equal(achievement?.type, "weekly_top_1");
  assert.equal(achievement?.rank, 1);
  assert.equal(achievement?.value, 100_000);
  assert.equal(
    achievement?.leaderboardStatsId,
    leaderboardDocumentId("u000", "weekly", WEEK.key)
  );
  assert.equal(
    (await db.doc("users/u250/achievements/" +
      `global_steps_weekly_${WEEK.key}`).get()).exists,
    false,
    "a most-climbs placing is not an award"
  );
  const profileStats = (await db.doc("users/u001/profile_stats/current")
    .get()).data();
  assert.equal(profileStats?.top_1_finishes, 1);
  assert.equal(profileStats?.top_100_finishes, 1);

  const periodDocument = (await db
    .doc(`leaderboard_periods/weekly_${WEEK.key}`)
    .get()).data();
  assert.equal(periodDocument?.status, "finalized");
  assert.equal(periodDocument?.achievementCount, 100);
});

test("a finalized period is never finalized twice", async () => {
  await seedRows(standardBoard());
  await finalizeMostRecentClosedPeriod("weekly", NOW);
  await db.doc(`${WEEK_RESULT}/placings/u000`).update({rank: 99});

  await finalizeMostRecentClosedPeriod("weekly", NOW);

  const profileStats = (await db.doc("users/u000/profile_stats/current")
    .get()).data();
  assert.equal(profileStats?.top_1_finishes, 1);
  assert.equal(
    (await db.doc(`${WEEK_RESULT}/placings/u000`).get()).data()?.rank,
    99,
    "a second run must not have written anything"
  );
});

test("a run that died part-way completes without counting twice",
  async () => {
    await seedRows(standardBoard());
    // What a crash after an earlier commit leaves: an award already minted,
    // its counter already incremented, and a lock older than 30 minutes.
    await db.doc(`users/u002/achievements/global_steps_weekly_${WEEK.key}`)
      .set({rank: 3, type: "weekly_top_3"});
    await db.doc("users/u002/profile_stats/current")
      .set({top_3_finishes: 1});
    await db.doc(`leaderboard_periods/weekly_${WEEK.key}`).set({
      status: "finalizing",
      finalizingStartedAt: admin.firestore.Timestamp.fromDate(
        new Date(NOW.getTime() - 60 * 60 * 1000)
      ),
    });

    await finalizeMostRecentClosedPeriod("weekly", NOW);

    assert.deepEqual(
      (await db.doc("users/u002/profile_stats/current").get()).data(),
      {top_3_finishes: 1}
    );
    const placing = (await db.doc(`${WEEK_RESULT}/placings/u002`).get())
      .data();
    assert.equal(placing?.rank, 3);
    const periodDocument = (await db
      .doc(`leaderboard_periods/weekly_${WEEK.key}`)
      .get()).data();
    assert.equal(periodDocument?.status, "finalized");
    assert.equal(periodDocument?.achievementCount, 99);
  });

test("a tie too large for one commit still lands whole", async () => {
  // 240 climbers tied for first: 480 award writes, 240 placings, and the
  // result with the period status - more than one commit can hold.
  const rows: SeedRow[] = Array.from({length: 240}, (_unused, index) => ({
    userId: `tie${String(index).padStart(3, "0")}`,
    totalSteps: 5_000,
    totalWorkouts: 2,
  }));
  await seedRows(rows);

  await finalizeMostRecentClosedPeriod("weekly", NOW);

  const result = (await db.doc(WEEK_RESULT).get()).data();
  assert.equal(result?.championUserIds.length, 240);
  assert.equal(result?.podiumUserIds.length, 240);
  assert.equal(
    (await db.collection(`${WEEK_RESULT}/placings`).count().get())
      .data().count,
    240
  );
  assert.equal(
    (await db.collectionGroup("achievements").count().get()).data().count,
    240
  );
  const periodDocument = (await db
    .doc(`leaderboard_periods/weekly_${WEEK.key}`)
    .get()).data();
  assert.equal(periodDocument?.status, "finalized");
  assert.equal(periodDocument?.achievementCount, 240);
});

test("a period nobody climbed still freezes an empty result", async () => {
  await finalizeMostRecentClosedPeriod("monthly", NOW);

  const monthly = previousPeriod("monthly", NOW);
  const result = (await db
    .doc(`leaderboard_results/monthly_${monthly.key}`)
    .get()).data();
  assert.ok(result);
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
  assert.equal(
    (await db.collection(`leaderboard_results/monthly_${monthly.key}/placings`)
      .count().get()).data().count,
    0
  );
});

test("the paged period read agrees with one unbounded page", async () => {
  await seedRows(standardBoard());

  const paged = await readPeriodStandings(db, WEEK, {pageSize: 7});
  const whole = await readPeriodStandings(db, WEEK, {pageSize: 1_000});

  assert.equal(paged.length, 300);
  assert.deepEqual(
    paged.map((row) => [row.userId, row.totalSteps, row.documentId]),
    whole.map((row) => [row.userId, row.totalSteps, row.documentId])
  );
  // The award query reads 250 rows, one of them u005's losing legacy row.
  assert.equal((await readAwardStandings(db, WEEK)).length, 249);
});

test("a period past the page bound refuses to freeze a partial count",
  async () => {
    await seedRows(standardBoard());

    await assert.rejects(
      readPeriodStandings(db, WEEK, {pageSize: 100, maxPages: 2}),
      /exceeded 2 pages of 100; refusing to freeze a partial count/
    );
  });

/**
 * Writes stats rows the way leaderboardStats.ts writes them.
 * @param {SeedRow[]} rows Rows to write.
 */
async function seedRows(rows: SeedRow[]): Promise<void> {
  for (let start = 0; start < rows.length; start += 400) {
    const batch = db.batch();
    for (const row of rows.slice(start, start + 400)) {
      const documentId = row.documentId ??
        leaderboardDocumentId(row.userId, "weekly", WEEK.key);
      batch.set(db.collection("leaderboard_stats").doc(documentId), {
        displayName: `Climber ${row.userId}`,
        identityChangedAt: IDENTITY_CHANGED_AT,
        identityPolicyVersion: 1,
        identityState: "published",
        isSynthetic: false,
        lastUpdated: ROW_UPDATED_AT,
        periodKey: WEEK.key,
        periodStartAt: admin.firestore.Timestamp.fromDate(WEEK.startAt),
        photoURL: "",
        schemaVersion: 2,
        stepsPerMinute: 100,
        timeFrame: "weekly",
        totalDuration: 600,
        totalFloors: Math.round(row.totalSteps / 20),
        totalSteps: row.totalSteps,
        totalWorkouts: row.totalWorkouts,
        userId: row.userId,
        ...row.overrides,
      });
    }
    await batch.commit();
  }
}

function sum(values: number[]): number {
  return values.reduce((total, value) => total + value, 0);
}

async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}` +
      "/databases/(default)/documents",
    {method: "DELETE"}
  );
  assert.ok(response.ok, `emulator reset failed: ${response.status}`);
}
