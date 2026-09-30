import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  leaderboardAchievementsTestHooks,
} from "../src/leaderboardAchievements.js";

const {
  achievementType,
  finalizeClosedPeriods,
  maxWritesPerCommit,
  packCommitUnits,
  profileStatsIncrement,
  previousPeriod,
  rankedQualifiers,
} = leaderboardAchievementsTestHooks;

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

/**
 * Lists the profile band counters a finish at the given rank increments.
 * @param {number} rank Final leaderboard rank for the closed period.
 * @return {string[]} Sorted profile_stats field names, minus lastUpdated.
 */
function incrementedBands(rank: number): string[] {
  return Object.keys(profileStatsIncrement(rank))
    .filter((key) => key !== "lastUpdated")
    .sort();
}

test("a top 1 finish counts cumulatively through every band", () => {
  assert.deepEqual(incrementedBands(1), [
    "top_100_finishes",
    "top_10_finishes",
    "top_1_finishes",
    "top_3_finishes",
  ]);
});

test("a top 3 finish does not count toward top 1", () => {
  assert.deepEqual(incrementedBands(3), [
    "top_100_finishes",
    "top_10_finishes",
    "top_3_finishes",
  ]);
});

test("a top 10 finish counts only toward top 10 and top 100", () => {
  assert.deepEqual(incrementedBands(10), [
    "top_100_finishes",
    "top_10_finishes",
  ]);
});

test("a top 100 finish counts only toward top 100", () => {
  assert.deepEqual(incrementedBands(100), ["top_100_finishes"]);
});

test("a finish outside the top 100 counts toward no band", () => {
  assert.deepEqual(incrementedBands(101), []);
});

test("profile stat counters never write the misnamed _weeks fields", () => {
  for (const rank of [1, 3, 10, 100]) {
    const written = Object.keys(profileStatsIncrement(rank));
    const misnamed = written.filter((key) => key.endsWith("_weeks"));
    assert.deepEqual(misnamed, [], `rank ${rank} wrote ${misnamed.join(", ")}`);
  }
});

/**
 * Reads a vector date as the UTC noon instant inside the window it names.
 * @param {string} date A YYYY-MM-DD date from the shared vector.
 * @return {Date} Noon UTC on that date.
 */
function vectorInstant(date: string): Date {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day, 12));
}

// The finalizer closes the period *before* the run instant, so each vector date
// is reached by running it one period later. That exercises the real
// previousPeriod -- and through it weekInfoUTC -- rather than a restatement of
// it: this is the derivation that decides which periodKey the achievement rows
// are written under, and it must spell the key exactly as the client reads it.
test("the finalizer derives the same period keys as the shared vector", () => {
  assert.ok(periodKeyVector.cases.length >= 9, "vector carries every shape");

  for (const testCase of periodKeyVector.cases) {
    const instant = vectorInstant(testCase.date);

    const oneWeekLater = new Date(instant.getTime());
    oneWeekLater.setUTCDate(oneWeekLater.getUTCDate() + 7);
    const weekly = previousPeriod("weekly", oneWeekLater);
    assert.equal(
      weekly.key,
      testCase.weekly,
      `weekly key for ${testCase.date} - ${testCase.name}`
    );
    assert.equal(weekly.startAt.getUTCDay(), 1, "weeks open on Monday UTC");
    assert.ok(
      weekly.startAt <= instant && instant < weekly.endAt,
      `${testCase.date} should fall inside its own weekly window`
    );

    const nextMonth = new Date(
      Date.UTC(instant.getUTCFullYear(), instant.getUTCMonth() + 1, 15, 12)
    );
    assert.equal(
      previousPeriod("monthly", nextMonth).key,
      testCase.monthly,
      `monthly key for ${testCase.date} - ${testCase.name}`
    );

    const nextYear = new Date(
      Date.UTC(instant.getUTCFullYear() + 1, 5, 15, 12)
    );
    assert.equal(
      previousPeriod("yearly", nextYear).key,
      testCase.yearly,
      `yearly key for ${testCase.date} - ${testCase.name}`
    );
  }
});

test("achievement records stay namespaced per time frame and band", () => {
  // The time frame lives here, on the record, and nowhere else. The profile
  // band counters are deliberately frame-agnostic -- badges show one total per
  // band with no period noun -- so a monthly or yearly finish lands on the same
  // counter as a weekly one. The history sheet reads the frame off these
  // records. If that ever needs to change, it is a product decision about what
  // a badge counts, not a bug in the counters.
  assert.equal(achievementType("weekly", 1), "weekly_top_1");
  assert.equal(achievementType("monthly", 2), "monthly_top_3");
  assert.equal(achievementType("yearly", 10), "yearly_top_10");
  assert.equal(achievementType("weekly", 42), "weekly_top_100");
});

test("a normal period finalizes in one commit", () => {
  const units = [
    ["award-a", "counter-a"],
    ["award-b", "counter-b"],
    ["placing-a"],
    ["placing-b"],
    ["result", "period-finalized"],
  ];

  assert.deepEqual(packCommitUnits(units, maxWritesPerCommit), [
    [
      "award-a",
      "counter-a",
      "award-b",
      "counter-b",
      "placing-a",
      "placing-b",
      "result",
      "period-finalized",
    ],
  ]);
});

test("a pathological tie splits commits without splitting an award", () => {
  // 250 climbers tied for first: the award query's whole read is awarded, so
  // 500 award writes, 250 placings, and the result with the period status.
  const units: string[][] = [];
  for (let index = 0; index < 250; index += 1) {
    units.push([`award-${index}`, `counter-${index}`]);
  }
  for (let index = 0; index < 250; index += 1) {
    units.push([`placing-${index}`]);
  }
  units.push(["result", "period-finalized"]);

  const commits = packCommitUnits(units, maxWritesPerCommit);

  assert.ok(maxWritesPerCommit < 500, "headroom under Firestore's 500");
  assert.ok(commits.length > 1);
  for (const commit of commits) {
    assert.ok(commit.length <= maxWritesPerCommit);
    // An award and its profile counter always share a commit, so a retry
    // that skips the existing award also skips its increment.
    for (let index = 0; index < commit.length; index += 1) {
      if (commit[index].startsWith("award-")) {
        assert.equal(
          commit[index + 1],
          commit[index].replace("award-", "counter-")
        );
      }
    }
  }
  // The result and the finalized status land last, together: a crash part-way
  // leaves the period unfinalized and resultless.
  const last = commits[commits.length - 1];
  assert.deepEqual(last.slice(-2), ["result", "period-finalized"]);
  assert.equal(
    commits.slice(0, -1).flat().some((write) =>
      write === "result" || write === "period-finalized"
    ),
    false
  );
  assert.equal(commits.flat().length, 752);
});

test("a unit larger than a commit is refused rather than split", () => {
  assert.throws(
    () => packCommitUnits([["a", "b", "c"]], 2),
    /3-write unit cannot fit a 2-write commit/
  );
});

test("every climber tied at the award cutoff is awarded", () => {
  const lastUpdated = new Date("2026-09-27T00:00:00.000Z");
  const identity = {
    displayName: "Climber",
    photoURL: "",
    identityPolicyVersion: 1,
    identityState: "published",
    identityChangedAt: null,
    isSynthetic: false,
  };
  const rows = Array.from({length: 102}, (_unused, index) => ({
    documentId: `row-${index}`,
    userId: `user-${String(index).padStart(3, "0")}`,
    // Ranks 1-99 are distinct; the last three tie at rank 100.
    totalSteps: index < 99 ? 100_000 - index : 1_000,
    totalWorkouts: 1,
    totalFloors: 0,
    lastUpdated,
    identity,
  }));

  const awarded = rankedQualifiers(rows);

  assert.equal(awarded.length, 102);
  assert.deepEqual(
    awarded.slice(-3).map((row) => row.rank),
    [100, 100, 100]
  );
  assert.equal(
    rankedQualifiers([
      ...rows,
      {...rows[0], userId: "user-late", totalSteps: 10, documentId: "late"},
    ]).length,
    102
  );
});

test("a frame that fails to finalize never skips the frames after it", async () => {
  const attempted: string[] = [];
  await assert.rejects(
    finalizeClosedPeriods(
      new Date("2026-10-01T00:15:00.000Z"),
      async (timeFrame) => {
        attempted.push(timeFrame);
        if (timeFrame === "weekly") {
          throw new Error("4 DEADLINE_EXCEEDED");
        }
      }
    ),
    /Finalizing failed for weekly/
  );
  assert.deepEqual(attempted, ["weekly", "monthly", "yearly"]);
});
