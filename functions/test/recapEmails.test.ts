import test from "node:test";
import assert from "node:assert/strict";
import {
  achievementTierLabel,
  buildBestRankLabel,
  buildComparisonNote,
  buildRecapDedupeKey,
  computeCurrentStreakWeeks,
  dedupeLandmarkNames,
  formatMonthlyPeriodLabel,
  formatWeeklyPeriodLabel,
  pickSuggestedClimb,
} from "../src/recapEmails.js";
import {previousPeriod} from "../src/leaderboardPeriod.js";
import type {CatalogClimb} from "../src/climbDropNotifications.js";

const closedWeek = previousPeriod("weekly", new Date("2026-09-24T00:00:00Z"));
const closedMonth = previousPeriod(
  "monthly",
  new Date("2026-09-24T00:00:00Z")
);

test("recap dedupe keys are namespaced by cadence, variant, period, and user", () => {
  assert.equal(
    buildRecapDedupeKey("weekly", "active", "2026-W38", "user_1"),
    "weekly-recap-active:2026-W38:user_1"
  );
  assert.equal(
    buildRecapDedupeKey("monthly", "inactive", "2026-M09", "user_1"),
    "monthly-recap-inactive:2026-M09:user_1"
  );
  assert.notEqual(
    buildRecapDedupeKey("weekly", "active", "2026-W38", "user_1"),
    buildRecapDedupeKey("weekly", "inactive", "2026-W38", "user_1")
  );
});

test("achievement tier boundaries follow the locked Top 1/3/10/100 ladder", () => {
  assert.equal(achievementTierLabel(1), "Top 1");
  assert.equal(achievementTierLabel(2), "Top 3");
  assert.equal(achievementTierLabel(3), "Top 3");
  assert.equal(achievementTierLabel(4), "Top 10");
  assert.equal(achievementTierLabel(10), "Top 10");
  assert.equal(achievementTierLabel(11), "Top 100");
  assert.equal(achievementTierLabel(100), "Top 100");
});

test("best rank label names the cadence and the exact rank", () => {
  assert.equal(
    buildBestRankLabel("weekly", 7),
    "You placed Top 10 globally this week - #7."
  );
  assert.equal(
    buildBestRankLabel("monthly", 1),
    "You placed Top 1 globally this month - #1."
  );
});

test("weekly period label formats a Monday-to-Sunday date range", () => {
  const label = formatWeeklyPeriodLabel(closedWeek);
  assert.match(label, /^[A-Z][a-z]{2} \d{1,2} – [A-Z][a-z]{2} \d{1,2}$/);
});

test("monthly period label formats a full month and year", () => {
  const label = formatMonthlyPeriodLabel(closedMonth);
  assert.match(label, /^[A-Z][a-z]+ \d{4}$/);
});

test("landmark names dedupe by climb id in first-seen order", () => {
  const climbNameById = new Map([
    ["eiffel", "Eiffel Tower"],
    ["burj", "Burj Khalifa"],
  ]);

  assert.deepEqual(
    dedupeLandmarkNames(["eiffel", "burj", "eiffel"], climbNameById),
    ["Eiffel Tower", "Burj Khalifa"]
  );
});

test("a landmark not in the catalogue falls back to its raw climb id", () => {
  assert.deepEqual(
    dedupeLandmarkNames(["retired-climb"], new Map()),
    ["retired-climb"]
  );
});

function catalogClimb(overrides: Partial<CatalogClimb>): CatalogClimb {
  return {
    city: null,
    id: "climb",
    name: "Climb",
    realStairCount: null,
    releaseState: "available",
    totalSteps: 1000,
    ...overrides,
  };
}

test("the suggested climb is the shortest currently available one", () => {
  const climbs = [
    catalogClimb({id: "tall", name: "Tall Tower", totalSteps: 5000}),
    catalogClimb({id: "short", name: "Short Climb", totalSteps: 400}),
    catalogClimb({id: "hidden", name: "Hidden", releaseState: "hidden", totalSteps: 1}),
  ];

  const suggested = pickSuggestedClimb(climbs);
  assert.equal(suggested?.id, "short");
});

test("ties on step count are broken deterministically by climb id", () => {
  const climbs = [
    catalogClimb({id: "zzz", totalSteps: 1000}),
    catalogClimb({id: "aaa", totalSteps: 1000}),
  ];

  assert.equal(pickSuggestedClimb(climbs)?.id, "aaa");
});

test("no available climb suggests nothing", () => {
  assert.equal(
    pickSuggestedClimb([catalogClimb({releaseState: "hidden"})]),
    null
  );
});

test("the current streak counts consecutive active weeks from the closed one", async () => {
  const activeWeeks = new Set([
    closedWeek.key,
    previousPeriod("weekly", closedWeek.startAt).key,
  ]);

  const streak = await computeCurrentStreakWeeks(
    closedWeek,
    async (periodKey) => activeWeeks.has(periodKey)
  );

  assert.equal(streak, 2);
});

test("the streak stops at the first gap rather than skipping it", async () => {
  const streak = await computeCurrentStreakWeeks(
    closedWeek,
    async (periodKey) => periodKey === closedWeek.key
  );

  assert.equal(streak, 1);
});

test("zero activity in the closed week itself is a zero streak", async () => {
  const streak = await computeCurrentStreakWeeks(closedWeek, async () => false);
  assert.equal(streak, 0);
});

test("the streak walk never reads more than the lookback bound", async () => {
  let reads = 0;
  const streak = await computeCurrentStreakWeeks(
    closedWeek,
    async () => {
      reads += 1;
      return true;
    },
    5
  );

  assert.equal(streak, 5);
  assert.equal(reads, 5);
});

test("comparison note reports a percent change against the prior period", () => {
  assert.equal(buildComparisonNote(1200, 1000), "Up 20% from last month.");
  assert.equal(buildComparisonNote(800, 1000), "Down 20% from last month.");
  assert.equal(buildComparisonNote(1000, 1000), "Even with last month.");
});

test("comparison note is omitted with no prior period to compare against", () => {
  assert.equal(buildComparisonNote(1000, null), undefined);
  assert.equal(buildComparisonNote(1000, 0), undefined);
});
