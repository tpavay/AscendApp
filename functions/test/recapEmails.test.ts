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
  monthsSince,
  pickSuggestedClimb,
  rankActiveCohort,
  percentileBand,
  weeksSince,
} from "../src/recapEmails.js";
import {previousPeriod} from "../src/leaderboardPeriod.js";
import type {CatalogClimb} from "../src/climbDropNotifications.js";

const closedWeek = previousPeriod("weekly", new Date("2026-09-24T00:00:00Z"));
const closedMonth = previousPeriod(
  "monthly",
  new Date("2026-09-24T00:00:00Z")
);

test("recap dedupe keys are namespaced by cadence, period, and user", () => {
  assert.equal(
    buildRecapDedupeKey("weekly", "2026-W38", "user_1"),
    "weekly-recap:2026-W38:user_1"
  );
  assert.equal(
    buildRecapDedupeKey("monthly", "2026-M09", "user_1"),
    "monthly-recap:2026-M09:user_1"
  );
  assert.notEqual(
    buildRecapDedupeKey("weekly", "2026-W38", "user_1"),
    buildRecapDedupeKey("monthly", "2026-W38", "user_1")
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

test("weekly period label is a concrete, dated range with the year", () => {
  const label = formatWeeklyPeriodLabel(closedWeek);
  // The common case: a week entirely inside one month, e.g. "Sep 15-21, 2026".
  assert.match(label, /^[A-Z][a-z]{2} \d{1,2}-\d{1,2}, \d{4}$/);
});

test("a week straddling a month boundary names both months", () => {
  // 2026-08-31 is a Monday, so that UTC-Monday week runs Aug 31 - Sep 6.
  const straddlingWeek = previousPeriod(
    "weekly",
    new Date("2026-09-07T00:00:00Z")
  );
  assert.equal(
    formatWeeklyPeriodLabel(straddlingWeek),
    "Aug 31 - Sep 6, 2026"
  );
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

test("a landmark not in the catalogue keeps its raw climb id so it still counts", () => {
  assert.deepEqual(
    dedupeLandmarkNames(
      ["retired-climb", "eiffel"],
      new Map([["eiffel", "Eiffel Tower"]])
    ),
    ["retired-climb", "Eiffel Tower"]
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

test("ranking the active cohort drops zero-step rows from rank and field size", () => {
  const cohort = new Map([
    ["a", {totalSteps: 500}],
    ["b", {totalSteps: 0}],
  ]);

  const standings = rankActiveCohort(cohort);

  assert.deepEqual(standings.get("a"), {fieldSize: 1, rank: 1});
  assert.equal(standings.has("b"), false);
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
  assert.equal(percentileBand(5, 1000), "Top 1%");
  assert.equal(percentileBand(40, 1000), "Top 5%");
  assert.equal(percentileBand(90, 1000), "Top 10%");
  assert.equal(percentileBand(200, 1000), "Top 25%");
  assert.equal(percentileBand(480, 1000), "Top 50%");
});

test("no percentile band below the top half - the concrete rank carries it instead", () => {
  assert.equal(percentileBand(900, 1000), undefined);
});

test("a number nobody can lose is not a result - no percentile for a field of one", () => {
  assert.equal(percentileBand(1, 1), undefined);
  assert.equal(percentileBand(1, 0), undefined);
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

test("weeks since floors at 1 - a zero-activity climber is gone at least a week", () => {
  const now = new Date("2026-09-24T00:00:00Z");
  assert.equal(weeksSince(new Date("2026-09-20T00:00:00Z"), now), 1);
  assert.equal(weeksSince(new Date("2026-09-17T00:00:00Z"), now), 1);
  assert.equal(weeksSince(new Date("2026-08-01T00:00:00Z"), now), 8);
  // Even "last active right now" reports as 1 week, never 0.
  assert.equal(weeksSince(now, now), 1);
});

test("months since counts elapsed months, floored at 1", () => {
  const now = new Date("2026-09-24T00:00:00Z");
  assert.equal(monthsSince(new Date("2026-09-01T00:00:00Z"), now), 1);
  assert.equal(monthsSince(new Date("2026-07-15T00:00:00Z"), now), 2);
  assert.equal(monthsSince(new Date("2025-09-24T00:00:00Z"), now), 12);
  assert.equal(monthsSince(now, now), 1);
  // Aug 31 late to the Oct 1 sweep is one month and a few hours, not two.
  assert.equal(
    monthsSince(
      new Date("2026-08-31T23:00:00Z"),
      new Date("2026-10-01T13:00:00Z")
    ),
    1
  );
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
