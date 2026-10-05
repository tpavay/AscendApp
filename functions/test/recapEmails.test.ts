import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  buildActiveRecapEmailPayload,
  buildCalendarCells,
  buildDeltaChip,
  buildFirstAscentBadge,
  buildHeldFirstAscentBadge,
  buildInactiveRecapEmailPayload,
  buildRankBadge,
  buildRecapDedupeKey,
  buildRecapDocumentId,
  buildStoredActiveRecap,
  buildStoredInactiveRecap,
  computeCurrentStreakWeeks,
  dedupeLandmarkNames,
  formatMonthlyPeriodLabel,
  formatRecapPeriodLabel,
  formatWeeklyPeriodLabel,
  monthsSince,
  parseStoredRecap,
  pickSuggestedClimb,
  planRecapCohorts,
  rankActiveCohort,
  percentileBand,
  shouldAwaitFinalization,
  weeksSince,
  type StoredRecapActive,
} from "../src/recapEmails.js";
import {currentPeriod, previousPeriod} from "../src/leaderboardPeriod.js";
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

test("the rank badge is Top 10 for any achievement rank 1-10", () => {
  assert.deepEqual(buildRankBadge(1), {
    detail: "globally",
    id: "top10",
    label: "Top 10",
  });
  assert.deepEqual(buildRankBadge(3), {
    detail: "globally",
    id: "top10",
    label: "Top 10",
  });
  assert.deepEqual(buildRankBadge(10), {
    detail: "globally",
    id: "top10",
    label: "Top 10",
  });
});

test("the rank badge is Top 100 for an achievement rank 11-100", () => {
  assert.deepEqual(buildRankBadge(11), {
    detail: "globally",
    id: "top100",
    label: "Top 100",
  });
  assert.deepEqual(buildRankBadge(100), {
    detail: "globally",
    id: "top100",
    label: "Top 100",
  });
});

const landmarkNames = new Map([
  ["eiffel", "Eiffel Tower"],
  ["burj-khalifa", "Burj Khalifa"],
]);

test("no First Ascent badge without any First Ascents", () => {
  assert.equal(buildFirstAscentBadge([], landmarkNames), undefined);
});

test("a single First Ascent badge is singular, with the landmark named", () => {
  assert.deepEqual(buildFirstAscentBadge(["eiffel", "eiffel"], landmarkNames), {
    detail: "Eiffel Tower",
    id: "first-ascent",
    label: "First Ascent",
  });
});

test("multiple First Ascents badge together, plural, every landmark named", () => {
  assert.deepEqual(
    buildFirstAscentBadge(["eiffel", "burj-khalifa"], landmarkNames),
    {
      detail: "Eiffel Tower, Burj Khalifa",
      id: "first-ascent",
      label: "First Ascents",
    }
  );
});

test("an unresolvable landmark keeps the badge but never prints a raw ID", () => {
  assert.deepEqual(
    buildFirstAscentBadge(["eiffel", "burj-khalifa"], new Map()),
    {id: "first-ascent", label: "First Ascents"}
  );
  assert.deepEqual(
    buildFirstAscentBadge(["eiffel", "unknown-tower"], landmarkNames),
    {id: "first-ascent", label: "First Ascents"}
  );
});

test("weekly period label is a concrete, dated range with the year", () => {
  const label = formatWeeklyPeriodLabel(closedWeek);
  // The common case: a week entirely inside one month, e.g. "Sep 15-21, 2026".
  assert.match(label, /^[A-Z][a-z]{2} \d{1,2}-\d{1,2}, \d{4}$/);
});

test("the weekly recap covers Monday 00:00 UTC to the next Monday 00:00 UTC",
  () => {
    // The founder's real week, checked against production on 2026-10-05:
    // 9,578 steps from climbs on Sep 29 and Oct 3. The recap is sent Monday
    // 13:00 UTC and composed Monday 00:30 UTC; both must name the same week.
    const week = previousPeriod("weekly", new Date("2026-10-05T13:00:00Z"));

    assert.equal(week.key, "2026-W40");
    assert.equal(week.startAt.toISOString(), "2026-09-28T00:00:00.000Z");
    assert.equal(week.endAt.toISOString(), "2026-10-05T00:00:00.000Z");
    assert.deepEqual(
      previousPeriod("weekly", new Date("2026-10-05T00:30:00Z")),
      week
    );
    assert.equal(formatWeeklyPeriodLabel(week), "Sep 28 - Oct 4, 2026");

    // The week a climb counts toward is the week its start instant falls
    // in, by the same derivation the leaderboard rows use.
    const weekOf = (instant: string): string =>
      currentPeriod("weekly", new Date(instant)).key;
    assert.equal(weekOf("2026-09-27T14:39:23Z"), "2026-W39");
    assert.equal(weekOf("2026-09-29T12:54:22Z"), "2026-W40");
    assert.equal(weekOf("2026-10-03T16:47:02Z"), "2026-W40");
    assert.equal(weekOf("2026-10-05T11:56:33Z"), "2026-W41");
  });

test("the week's first and last instants are in it, the next instant is not",
  () => {
    const weekOf = (instant: string): string =>
      currentPeriod("weekly", new Date(instant)).key;

    assert.equal(weekOf("2026-09-27T23:59:59.999Z"), "2026-W39");
    assert.equal(weekOf("2026-09-28T00:00:00.000Z"), "2026-W40");
    assert.equal(weekOf("2026-10-04T23:59:59.999Z"), "2026-W40");
    assert.equal(weekOf("2026-10-05T00:00:00.000Z"), "2026-W41");
  });

test("the week turns over at UTC midnight, whatever the climber's clock says",
  () => {
    // Weeks are UTC so every climber is ranked over the same seven days. In
    // US Central time the week therefore turns over at 7 PM on Sunday: a
    // climb at 6:59 PM is last week's, one at 7:00 PM is next week's.
    const weekOf = (instant: string): string =>
      currentPeriod("weekly", new Date(instant)).key;

    assert.equal(weekOf("2026-10-04T18:59:59-05:00"), "2026-W40");
    assert.equal(weekOf("2026-10-04T19:00:00-05:00"), "2026-W41");
    // And the same instants cannot land in different weeks for the send and
    // for the leaderboard row they are read from.
    assert.equal(
      previousPeriod("weekly", new Date("2026-10-05T13:00:00Z")).key,
      weekOf("2026-10-04T18:59:59-05:00")
    );
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

test("a recap document id names the cadence and the closed period", () => {
  assert.equal(buildRecapDocumentId("weekly", "2026-W38"), "weekly_2026-W38");
  assert.equal(buildRecapDocumentId("monthly", "2026-M09"), "monthly_2026-M09");
});

test("the period label follows the cadence", () => {
  assert.equal(
    formatRecapPeriodLabel("weekly", closedWeek),
    formatWeeklyPeriodLabel(closedWeek)
  );
  assert.equal(
    formatRecapPeriodLabel("monthly", closedMonth),
    formatMonthlyPeriodLabel(closedMonth)
  );
});

test("a held First Ascent badge names every landmark, singular or plural", () => {
  assert.equal(buildHeldFirstAscentBadge([]), undefined);
  assert.deepEqual(buildHeldFirstAscentBadge(["Eiffel Tower"]), {
    detail: "Eiffel Tower",
    id: "first-ascent",
    label: "First Ascent",
  });
  assert.deepEqual(
    buildHeldFirstAscentBadge(["Eiffel Tower", "Burj Khalifa"]),
    {
      detail: "Eiffel Tower, Burj Khalifa",
      id: "first-ascent",
      label: "First Ascents",
    }
  );
});

test("the cohort plan gives each climber exactly one variant, or none", () => {
  const activeRows = new Map([
    ["ranked", {totalSteps: 900}],
    ["zero-step", {totalSteps: 0}],
  ]);
  const plan = planRecapCohorts({
    activeRows,
    entitledUserIds: new Set(["ranked", "dormant", "zero-step", "brand-new"]),
    everActiveUserIds: new Set(["ranked", "dormant", "zero-step"]),
    standings: rankActiveCohort(activeRows),
  });

  assert.deepEqual(plan.active, ["ranked"]);
  assert.deepEqual(plan.inactive, ["dormant"]);
  assert.deepEqual(plan.neverClimbed, ["brand-new"]);
});

test("a zero-step session this period is never told it never climbed", () => {
  const activeRows = new Map([["zero-step", {totalSteps: 0}]]);
  const plan = planRecapCohorts({
    activeRows,
    entitledUserIds: new Set(["zero-step"]),
    everActiveUserIds: new Set(),
    standings: rankActiveCohort(activeRows),
  });

  assert.deepEqual(plan, {active: [], inactive: [], neverClimbed: []});
});

test("an untrusted lifetime cohort withholds every never_climbed recap", () => {
  const plan = planRecapCohorts({
    activeRows: new Map(),
    entitledUserIds: null,
    everActiveUserIds: new Set(["dormant"]),
    standings: new Map(),
  });

  assert.deepEqual(plan.inactive, ["dormant"]);
  assert.deepEqual(plan.neverClimbed, []);
});

test("compose waits for the finalizer only within the grace window", () => {
  const minutesAfterClose = (minutes: number): Date =>
    new Date(closedWeek.endAt.getTime() + minutes * 60 * 1000);

  assert.equal(
    shouldAwaitFinalization(false, closedWeek, minutesAfterClose(30)),
    true
  );
  assert.equal(
    shouldAwaitFinalization(false, closedWeek, minutesAfterClose(59)),
    true
  );
  assert.equal(
    shouldAwaitFinalization(false, closedWeek, minutesAfterClose(60)),
    false
  );
  assert.equal(
    shouldAwaitFinalization(true, closedWeek, minutesAfterClose(30)),
    false
  );
});

/**
 * A stored `active` map with every optional value present.
 * @param {Partial<StoredRecapActive>} overrides - Fields to change
 * @return {StoredRecapActive} The map
 */
function storedActive(
  overrides: Partial<StoredRecapActive> = {}
): StoredRecapActive {
  return {
    awardRank: 7,
    calendar: buildCalendarCells(closedWeek, new Map()),
    climberCount: 40,
    climbs: 4,
    currentStreakWeeks: 3,
    firstAscents: [{climbId: "eiffel", name: "Eiffel Tower"}],
    floors: 120,
    landmarksFinished: ["Eiffel Tower"],
    percentileBand: "Top 25%",
    previousClimbs: 2,
    previousFloors: 150,
    previousSteps: 5000,
    rank: 7,
    steps: 6000,
    ...overrides,
  };
}

test("the stored active recap keeps raw values, not email chips", () => {
  const stored = buildStoredActiveRecap({
    aggregate: {totalFloors: 120, totalSteps: 6000, totalWorkouts: 4},
    awardRank: 7,
    climbNameById: landmarkNames,
    completedClimbIds: ["eiffel", "unlisted", "eiffel"],
    currentStreakWeeks: 3,
    firstAscentClimbIds: ["eiffel", "unlisted"],
    period: closedWeek,
    previousTotals: {totalFloors: 150, totalSteps: 5000, totalWorkouts: 2},
    standing: {fieldSize: 40, rank: 7},
    stepsByDayKey: new Map(),
  });

  assert.deepEqual(stored, storedActive({
    firstAscents: [
      {climbId: "eiffel", name: "Eiffel Tower"},
      {climbId: "unlisted", name: null},
    ],
    landmarksFinished: ["Eiffel Tower", "unlisted"],
  }));
});

test("a field of one stores no climber count and no band", () => {
  const stored = buildStoredActiveRecap({
    aggregate: {totalFloors: 5, totalSteps: 100, totalWorkouts: 1},
    awardRank: null,
    climbNameById: landmarkNames,
    completedClimbIds: [],
    currentStreakWeeks: null,
    firstAscentClimbIds: [],
    period: closedMonth,
    previousTotals: null,
    standing: {fieldSize: 1, rank: 1},
    stepsByDayKey: new Map(),
  });

  assert.equal(stored.climberCount, null);
  assert.equal(stored.percentileBand, null);
  assert.equal(stored.previousSteps, null);
  assert.equal(stored.previousClimbs, null);
  assert.equal(stored.previousFloors, null);
  assert.equal(stored.currentStreakWeeks, null);
});

test("the active email is derived from the stored recap alone", () => {
  const payload = buildActiveRecapEmailPayload(
    "weekly",
    "Sep 21-27, 2026",
    storedActive()
  );

  assert.deepEqual(payload, {
    calendar: buildCalendarCells(closedWeek, new Map()),
    climbsCompleted: 4,
    climbsDelta: {direction: "up", label: "vs last week", value: "2"},
    ctaUrl: "https://apps.apple.com/app/id6757202987",
    currentStreakWeeks: 3,
    earnedBadges: [
      {detail: "globally", id: "top10", label: "Top 10"},
      {detail: "Eiffel Tower", id: "first-ascent", label: "First Ascent"},
    ],
    fieldSize: 40,
    floorsDelta: undefined,
    landmarksFinished: ["Eiffel Tower"],
    percentileBand: "Top 25%",
    periodLabel: "Sep 21-27, 2026",
    rank: 7,
    stepsDelta: {direction: "up", label: "vs last week", value: "1,000"},
    totalFloors: 120,
    totalSteps: 6000,
  });
});

test("a stored field of one is a field of one in the email", () => {
  const payload = buildActiveRecapEmailPayload(
    "monthly",
    "September 2026",
    storedActive({
      awardRank: null,
      climberCount: null,
      currentStreakWeeks: null,
      firstAscents: [],
      percentileBand: null,
      previousClimbs: null,
      previousFloors: null,
      previousSteps: null,
      rank: 1,
    })
  );

  assert.equal(payload.fieldSize, 1);
  assert.equal(payload.rank, 1);
  assert.equal(payload.percentileBand, undefined);
  assert.equal(payload.currentStreakWeeks, undefined);
  assert.equal(payload.stepsDelta, undefined);
  assert.equal(payload.climbsDelta, undefined);
  assert.deepEqual(payload.earnedBadges, []);
});

test("an unnamed period First Ascent keeps the badge without a raw id", () => {
  const payload = buildActiveRecapEmailPayload(
    "weekly",
    "Sep 21-27, 2026",
    storedActive({
      awardRank: null,
      firstAscents: [
        {climbId: "eiffel", name: "Eiffel Tower"},
        {climbId: "unlisted", name: null},
      ],
    })
  );

  assert.deepEqual(payload.earnedBadges, [
    {id: "first-ascent", label: "First Ascents"},
  ]);
});

test("the stored inactive recap names only First Ascents it can name", () => {
  const lastClimbAt = new Date(closedWeek.startAt.getTime() - 14 * 86400000);
  const composeAt = new Date(closedWeek.endAt.getTime() + 30 * 60 * 1000);
  const stored = buildStoredInactiveRecap({
    cadence: "weekly",
    climbNameById: landmarkNames,
    firstAscentClimbIds: ["eiffel", "unlisted"],
    lastClimbAt,
    now: composeAt,
    period: closedWeek,
    suggestedClimb: catalogClimb({id: "short", name: "Short Climb"}),
  });

  assert.deepEqual(stored, {
    firstAscentsHeld: ["Eiffel Tower"],
    gapCount: 3,
    lastClimbAt: admin.firestore.Timestamp.fromDate(lastClimbAt),
    suggestedClimbId: "short",
    suggestedClimbName: "Short Climb",
  });
});

test("an inactive recap with no workout found measures from the period", () => {
  const stored = buildStoredInactiveRecap({
    cadence: "monthly",
    climbNameById: new Map(),
    firstAscentClimbIds: [],
    lastClimbAt: null,
    now: new Date(closedMonth.endAt.getTime() + 30 * 60 * 1000),
    period: closedMonth,
    suggestedClimb: null,
  });

  assert.equal(stored.lastClimbAt, null);
  assert.equal(stored.gapCount, 1);
  assert.equal(stored.suggestedClimbId, null);
  assert.equal(stored.suggestedClimbName, null);
});

test("the inactive email is derived from the stored recap alone", () => {
  assert.deepEqual(
    buildInactiveRecapEmailPayload("Sep 21-27, 2026", {
      firstAscentsHeld: ["Eiffel Tower", "Burj Khalifa"],
      gapCount: 5,
      lastClimbAt: null,
      suggestedClimbId: "short",
      suggestedClimbName: "Short Climb",
    }),
    {
      ctaUrl: "https://apps.apple.com/app/id6757202987",
      earnedBadges: [{
        detail: "Eiffel Tower, Burj Khalifa",
        id: "first-ascent",
        label: "First Ascents",
      }],
      firstAscents: ["Eiffel Tower", "Burj Khalifa"],
      gapCount: 5,
      periodLabel: "Sep 21-27, 2026",
      suggestedClimbName: "Short Climb",
    }
  );
  assert.equal(
    buildInactiveRecapEmailPayload("Sep 21-27, 2026", {
      firstAscentsHeld: [],
      gapCount: 1,
      lastClimbAt: null,
      suggestedClimbId: null,
      suggestedClimbName: null,
    }).suggestedClimbName,
    undefined
  );
});

test("a stored recap reads back as exactly one variant", () => {
  const base = {
    cadence: "weekly",
    periodKey: "2026-W39",
    periodLabel: "Sep 21-27, 2026",
  };
  const active = storedActive();
  const inactive = {
    firstAscentsHeld: [],
    gapCount: 2,
    lastClimbAt: admin.firestore.Timestamp.fromMillis(0),
    suggestedClimbId: null,
    suggestedClimbName: null,
  };

  assert.deepEqual(
    parseStoredRecap({...base, active, inactive: null, variant: "active"}),
    {...base, active, inactive: null, variant: "active"}
  );
  assert.deepEqual(
    parseStoredRecap({...base, active: null, inactive, variant: "inactive"}),
    {...base, active: null, inactive, variant: "inactive"}
  );
  assert.deepEqual(
    parseStoredRecap({
      ...base,
      active: null,
      inactive: null,
      variant: "never_climbed",
    }),
    {...base, active: null, inactive: null, variant: "never_climbed"}
  );
});

test("a malformed stored recap is refused rather than half-sent", () => {
  const base = {
    cadence: "weekly",
    periodKey: "2026-W39",
    periodLabel: "Sep 21-27, 2026",
  };

  assert.equal(
    parseStoredRecap({...base, active: null, inactive: null, variant: "active"}),
    null
  );
  assert.equal(
    parseStoredRecap({
      ...base,
      active: storedActive(),
      inactive: null,
      variant: "never_climbed",
    }),
    null
  );
  assert.equal(
    parseStoredRecap({
      ...base,
      active: {...storedActive(), steps: "6000"},
      inactive: null,
      variant: "active",
    }),
    null
  );
  assert.equal(
    parseStoredRecap({
      ...base,
      active: {...storedActive(), calendar: [{dayOfMonth: 1, level: "hot"}]},
      inactive: null,
      variant: "active",
    }),
    null
  );
  assert.equal(
    parseStoredRecap({
      ...base,
      cadence: "yearly",
      active: null,
      inactive: null,
      variant: "never_climbed",
    }),
    null
  );
});
