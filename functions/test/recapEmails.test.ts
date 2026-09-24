import test from "node:test";
import assert from "node:assert/strict";
import {
  achievementTierLabel,
  buildCalendarCells,
  buildDeltaChip,
  buildRecapDedupeKey,
  computeCurrentStreakWeeks,
  dedupeLandmarkNames,
  formatMonthlyPeriodLabel,
  formatWeeklyPeriodLabel,
  pickMilestoneText,
  pickSuggestedClimb,
  rankActiveCohort,
  percentileLabel,
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

test("ranking the active cohort uses standard competition ranking (1,2,2,4)", () => {
  const cohort = new Map([
    ["a", {totalSteps: 500}],
    ["b", {totalSteps: 700}],
    ["c", {totalSteps: 700}],
    ["d", {totalSteps: 100}],
  ]);

  const standings = rankActiveCohort(cohort);

  assert.deepEqual(standings.get("b"), {fieldSize: 4, rank: 1});
  assert.deepEqual(standings.get("c"), {fieldSize: 4, rank: 1});
  assert.deepEqual(standings.get("a"), {fieldSize: 4, rank: 3});
  assert.deepEqual(standings.get("d"), {fieldSize: 4, rank: 4});
});

test("ranking ties break deterministically by user id", () => {
  const cohort = new Map([
    ["zzz", {totalSteps: 500}],
    ["aaa", {totalSteps: 500}],
  ]);

  // Both tie at rank 1 regardless of id order, but the sort that produces the
  // ranking must be stable - assert the ranks themselves, not iteration order.
  const standings = rankActiveCohort(cohort);
  assert.equal(standings.get("aaa")?.rank, 1);
  assert.equal(standings.get("zzz")?.rank, 1);
});

test("percentile band names the locked ladder (1/5/10/25/50%)", () => {
  assert.equal(percentileLabel(5, 1000), "Top 1% of climbers");
  assert.equal(percentileLabel(40, 1000), "Top 5% of climbers");
  assert.equal(percentileLabel(90, 1000), "Top 10% of climbers");
  assert.equal(percentileLabel(200, 1000), "Top 25% of climbers");
  assert.equal(percentileLabel(480, 1000), "Top 50% of climbers");
});

test("percentile falls back to an explicit rank below the top half", () => {
  assert.equal(percentileLabel(900, 1000), "#900 of 1000 climbers");
});

test("a top-3 finish states the exact position, never a percentile band", () => {
  // In a field of 3, rank 1 is honestly only the top 33rd percentile -
  // "Top 50% of climbers" would undersell a literal first place.
  assert.equal(percentileLabel(1, 3), "#1 of 3 climbers");
  assert.equal(percentileLabel(2, 3), "#2 of 3 climbers");
  assert.equal(percentileLabel(3, 3), "#3 of 3 climbers");
  // Even in a huge field, a top-3 finish states the position, not "Top 1%".
  assert.equal(percentileLabel(1, 10000), "#1 of 10000 climbers");
});

test("a number nobody can lose is not a result - no percentile for a field of one", () => {
  assert.equal(percentileLabel(1, 1), undefined);
  assert.equal(percentileLabel(1, 0), undefined);
});

test("a delta chip only ever reports a genuine improvement", () => {
  assert.deepEqual(buildDeltaChip(1200, 1000, "vs last week"), {
    direction: "up",
    label: "vs last week",
    value: "200",
  });
});

test("a decline or a flat period gets no delta chip - never a scolding", () => {
  assert.equal(buildDeltaChip(800, 1000, "vs last week"), undefined);
  assert.equal(buildDeltaChip(1000, 1000, "vs last week"), undefined);
  assert.equal(buildDeltaChip(1000, null, "vs last week"), undefined);
});

test("the milestone prefers a finished landmark over everything else", () => {
  assert.equal(
    pickMilestoneText("weekly", ["Eiffel Tower"], 5, 3),
    "You finished Eiffel Tower."
  );
});

test("multiple finished landmarks are summarized, not all named", () => {
  assert.equal(
    pickMilestoneText("weekly", ["Eiffel Tower", "Burj Khalifa", "CN Tower"], undefined, 200),
    "You finished Eiffel Tower and 2 more landmarks."
  );
});

test("with no landmark, the milestone falls back to a weekly streak", () => {
  assert.equal(
    pickMilestoneText("weekly", [], 3, 200),
    "3 weeks running. That is a streak."
  );
});

test("a one-week streak is not a milestone on its own", () => {
  assert.equal(pickMilestoneText("weekly", [], 1, 200), undefined);
});

test("with no landmark or streak, a Top 100 finish is the milestone", () => {
  assert.equal(
    pickMilestoneText("weekly", [], undefined, 7),
    "You placed Top 10 globally last week."
  );
  assert.equal(
    pickMilestoneText("monthly", [], undefined, 1),
    "You placed Top 1 globally last month."
  );
});

test("nothing notable means no milestone callout at all", () => {
  assert.equal(pickMilestoneText("weekly", [], undefined, 500), undefined);
});

test("a weekly calendar is exactly 7 filled cells, Monday first, no blanks", () => {
  const cells = buildCalendarCells(closedWeek, new Map());
  assert.equal(cells.length, 7);
  assert.ok(cells.every((cell) => cell.level === "none"));
  assert.deepEqual(cells.map((cell) => cell.dayOfMonth), [
    closedWeek.startAt.getUTCDate(),
    ...Array.from({length: 6}, (_, i) =>
      new Date(closedWeek.startAt.getTime() + (i + 1) * 86400000).getUTCDate()),
  ]);
});

test("the peak day is the single highest-step day, everything else active", () => {
  const dayKey = (offset: number): string => {
    const date = new Date(closedWeek.startAt.getTime() + offset * 86400000);
    const pad = (value: number): string => String(value).padStart(2, "0");
    return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
  };
  const stepsByDayKey = new Map([
    [dayKey(0), 1000],
    [dayKey(2), 5000],
  ]);

  const cells = buildCalendarCells(closedWeek, stepsByDayKey);
  assert.equal(cells[0].level, "active");
  assert.equal(cells[2].level, "peak");
  assert.equal(cells[1].level, "none");
});

test("a monthly calendar aligns to its starting weekday with leading blanks", () => {
  // September 2026 opens on a Tuesday (2026-09-01), so exactly one blank
  // leading cell (Monday) is needed before day 1.
  const september = previousPeriod("monthly", new Date("2026-10-01T00:00:00Z"));
  const cells = buildCalendarCells(september, new Map());

  assert.equal(cells[0].level, "blank");
  assert.equal(cells[0].dayOfMonth, null);
  assert.equal(cells[1].dayOfMonth, 1);
  assert.equal(cells.length % 7, 0);
});
