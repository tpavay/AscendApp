import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  PUBLIC_WEEKLY_STEPS_TOP_READ_LIMIT,
  PUBLIC_WEEKLY_STEPS_TOP_SCHEMA_VERSION,
  PublicWeeklyStepsTop,
  PublicWeeklyStepsTopStore,
  publicWeeklyStepsTopData,
  refreshPublicWeeklyStepsTop,
} from "../src/publicWeeklyStepsTop.js";
import {currentPeriod} from "../src/leaderboardPeriod.js";

// Wednesday 2026-11-04 - the week of Monday 2026-11-02 (UTC).
const NOW = new Date("2026-11-04T12:00:00.000Z");
const WEEK = currentPeriod("weekly", NOW);

function statsRow(
  id: string,
  totalSteps: number,
  overrides: Record<string, unknown> = {}
): {id: string; data: Record<string, unknown>} {
  return {
    id,
    data: {
      userId: id,
      totalSteps,
      totalWorkouts: 3,
      totalFloors: 10,
      lastUpdated: admin.firestore.Timestamp.fromDate(NOW),
      displayName: `Climber ${id}`,
      photoURL: "",
      identityPolicyVersion: 1,
      identityState: "published",
      identityChangedAt: admin.firestore.Timestamp.fromDate(NOW),
      isSynthetic: false,
      ...overrides,
    },
  };
}

class MemoryStore implements PublicWeeklyStepsTopStore {
  writes: PublicWeeklyStepsTop[] = [];
  requestedLimit: number | null = null;

  constructor(
    private readonly rows: Array<{id: string; data: Record<string, unknown>}>,
    private stored?: Record<string, unknown>
  ) {}

  async readTopRows(_period: unknown, limit: number) {
    this.requestedLimit = limit;
    return this.rows;
  }

  async readCurrent() {
    return this.stored;
  }

  async write(projection: PublicWeeklyStepsTop, now: Date) {
    this.writes.push(projection);
    this.stored = publicWeeklyStepsTopData(projection, now);
  }
}

test("the three highest climbers are published, ranked, with no uid", async () => {
  const store = new MemoryStore([
    statsRow("a", 38_891),
    statsRow("b", 12_335),
    statsRow("c", 9_720),
    statsRow("d", 4_000),
  ]);

  assert.equal(await refreshPublicWeeklyStepsTop(store, NOW), true);

  const [projection] = store.writes;
  assert.deepEqual(projection.rows.map((row) => row.rank), [1, 2, 3]);
  assert.deepEqual(
    projection.rows.map((row) => row.totalSteps),
    [38_891, 12_335, 9_720]
  );
  assert.equal(projection.periodKey, WEEK.key);
  assert.equal(projection.periodEndAt.getTime(), WEEK.endAt?.getTime());

  const data = publicWeeklyStepsTopData(projection, NOW);
  assert.equal(data.schemaVersion, PUBLIC_WEEKLY_STEPS_TOP_SCHEMA_VERSION);
  assert.ok(
    !JSON.stringify(data.rows).includes("userId"),
    "the public board must not carry a uid"
  );
});

test("fewer than three climbers is fewer rows, never a placeholder", async () => {
  const store = new MemoryStore([statsRow("a", 5_000), statsRow("b", 900)]);
  await refreshPublicWeeklyStepsTop(store, NOW);
  assert.equal(store.writes[0].rows.length, 2);
});

test("a week nobody has climbed yet publishes an empty board", async () => {
  const store = new MemoryStore([]);
  await refreshPublicWeeklyStepsTop(store, NOW);
  assert.deepEqual(store.writes[0].rows, []);
});

test("an unresolved or deleted identity is left out and never promotes anyone", async () => {
  const store = new MemoryStore([
    statsRow("a", 9_000, {identityState: "pending_public_profile"}),
    statsRow("b", 8_000),
    statsRow("c", 7_000, {identityState: "deleted"}),
    statsRow("d", 6_000),
  ]);

  await refreshPublicWeeklyStepsTop(store, NOW);

  assert.deepEqual(
    store.writes[0].rows.map((row) => [row.rank, row.totalSteps]),
    [[2, 8_000], [4, 6_000]]
  );
});

test("tied climbers share a rank, as the member board ranks them", async () => {
  const store = new MemoryStore([
    statsRow("a", 9_000),
    statsRow("b", 9_000),
    statsRow("c", 4_000),
  ]);

  await refreshPublicWeeklyStepsTop(store, NOW);

  assert.deepEqual(store.writes[0].rows.map((row) => row.rank), [1, 1, 3]);
});

test("a climber's duplicate legacy row counts once", async () => {
  const store = new MemoryStore([
    statsRow("a", 9_000, {
      lastUpdated: admin.firestore.Timestamp.fromDate(
        new Date("2026-11-04T11:00:00.000Z")
      ),
    }),
    {
      id: "a_weekly",
      data: statsRow("a", 8_500, {
        lastUpdated: admin.firestore.Timestamp.fromDate(
          new Date("2026-11-03T11:00:00.000Z")
        ),
      }).data,
    },
    statsRow("b", 1_000),
  ]);

  await refreshPublicWeeklyStepsTop(store, NOW);

  assert.deepEqual(
    store.writes[0].rows.map((row) => row.totalSteps),
    [9_000, 1_000]
  );
});

test("a row with no steps is not a standing", async () => {
  const store = new MemoryStore([statsRow("a", 0)]);
  await refreshPublicWeeklyStepsTop(store, NOW);
  assert.deepEqual(store.writes[0].rows, []);
});

test("the read is bounded", async () => {
  const store = new MemoryStore([]);
  await refreshPublicWeeklyStepsTop(store, NOW);
  assert.equal(store.requestedLimit, PUBLIC_WEEKLY_STEPS_TOP_READ_LIMIT);
});

test("an unchanged board is not rewritten, a changed one is", async () => {
  const rows = [statsRow("a", 5_000), statsRow("b", 900)];
  const store = new MemoryStore(rows);

  assert.equal(await refreshPublicWeeklyStepsTop(store, NOW), true);
  assert.equal(await refreshPublicWeeklyStepsTop(store, NOW), false);
  assert.equal(store.writes.length, 1);

  const changed = new MemoryStore(
    [statsRow("a", 5_200), statsRow("b", 900)],
    publicWeeklyStepsTopData(store.writes[0], NOW)
  );
  assert.equal(await refreshPublicWeeklyStepsTop(changed, NOW), true);
});

test("a new week rewrites the board even when the rows read the same", async () => {
  const rows = [statsRow("a", 5_000)];
  const store = new MemoryStore(rows);
  await refreshPublicWeeklyStepsTop(store, NOW);

  const nextWeek = new Date("2026-11-09T01:00:00.000Z");
  assert.equal(await refreshPublicWeeklyStepsTop(store, nextWeek), true);
  assert.notEqual(store.writes[0].periodKey, store.writes[1].periodKey);
});
