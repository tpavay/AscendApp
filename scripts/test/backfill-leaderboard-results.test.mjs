import test from "node:test";
import assert from "node:assert/strict";

import {
  PRODUCTION_PROJECT_ID,
  closedPeriodFromDocument,
  createResultOnce,
  describePeriodPlan,
  parseArgs,
  reconcileWithAwards,
  renderSummary,
  resolveTarget,
  uidPrefix,
} from "../backfill-leaderboard-results.mjs";

const WEEK_START = new Date("2026-09-14T00:00:00.000Z");
const WEEK_END = new Date("2026-09-21T00:00:00.000Z");

// Enough of the compiled period module to name one window, without making a
// script test depend on functions/lib being built.
const periodModule = {
  currentPeriod(timeFrame, date) {
    assert.equal(timeFrame, "weekly");
    assert.equal(date.getTime(), WEEK_START.getTime());
    return {timeFrame, key: "2026-W38", startAt: WEEK_START, endAt: WEEK_END};
  },
};

function periodDocument(overrides = {}) {
  return {
    status: "finalized",
    timeFrame: "weekly",
    periodKey: "2026-W38",
    periodStartAt: {toDate: () => WEEK_START},
    periodEndAt: {toDate: () => WEEK_END},
    ...overrides,
  };
}

function ranked(userId, rank) {
  return {userId, rank, totalSteps: 10_000 - rank, documentId: `weekly_2026-W38_${userId}`};
}

test("dry run is the default and --commit is the only way to write", () => {
  assert.equal(parseArgs(["node", "script", "--env", "dev"]).commit, false);
  assert.equal(parseArgs(["node", "script", "--env", "dev", "--commit"]).commit, true);
  assert.equal(
    parseArgs(["node", "script", "--env", "dev", "--period", "weekly_2026-W38"]).period,
    "weekly_2026-W38"
  );
  assert.throws(() => parseArgs(["node", "script", "--dry-run"]), /Unknown argument: --dry-run/);
  assert.throws(() => parseArgs(["node", "script", "--env"]), /--env requires a value/);
});

test("a run names its environment, and production must be confirmed by id", () => {
  assert.throws(() => resolveTarget({}), /No target/);
  assert.throws(() => resolveTarget({env: "production"}), /Unknown environment/);
  assert.equal(resolveTarget({env: "dev"}).projectId, "ascend-f2e4f");
  assert.equal(resolveTarget({env: "staging"}).projectId, "ascend-staging-fa7d5");
  assert.throws(
    () => resolveTarget({env: "prod"}),
    /Production requires --confirm-production ascend-prod-9c8f2/
  );
  assert.throws(
    () => resolveTarget({env: "prod", confirmProduction: "ascend-staging-fa7d5"}),
    /Production requires --confirm-production/
  );
  assert.equal(
    resolveTarget({env: "prod", confirmProduction: PRODUCTION_PROJECT_ID}).projectId,
    PRODUCTION_PROJECT_ID
  );
});

test("a finalized period document names its closed window", () => {
  const {period, error} = closedPeriodFromDocument(
    "weekly_2026-W38",
    periodDocument(),
    periodModule
  );

  assert.equal(error, undefined);
  assert.deepEqual(period, {
    timeFrame: "weekly",
    key: "2026-W38",
    startAt: WEEK_START,
    endAt: WEEK_END,
  });
});

test("a period document whose fields disagree with its id is refused", () => {
  assert.match(
    closedPeriodFromDocument("weekly_2026-W39", periodDocument(), periodModule).error,
    /does not match its id/
  );
  assert.match(
    closedPeriodFromDocument(
      "weekly_2026-W38",
      periodDocument({periodKey: "2026-W39"}),
      periodModule
    ).error,
    /does not match its id/
  );
  assert.match(
    closedPeriodFromDocument(
      "weekly_2026-W38",
      periodDocument({periodEndAt: {toDate: () => new Date("2026-09-22T00:00:00.000Z")}}),
      periodModule
    ).error,
    /does not match its id/
  );
  assert.match(
    closedPeriodFromDocument("daily_2026-09-14", periodDocument({timeFrame: "daily"}), periodModule).error,
    /unrecognised timeFrame "daily"/
  );
  assert.match(
    closedPeriodFromDocument("weekly_2026-W38", periodDocument({periodStartAt: null}), periodModule).error,
    /missing periodStartAt/
  );
});

test("a board whose awards agree is placed exactly as ranked", () => {
  const computed = [ranked("aaaa-1", 1), ranked("bbbb-2", 2), ranked("cccc-3", 3)];
  const awards = new Map([["aaaa-1", 1], ["bbbb-2", 2], ["cccc-3", 3]]);

  const {placed, mismatches} = reconcileWithAwards({
    computed,
    everyone: [...computed, ranked("dddd-4", 101)],
    awards: new Map([...awards, ["dddd-4", null]]),
  });

  assert.deepEqual(placed, computed);
  assert.deepEqual(mismatches, []);
});

test("the awarded rank wins where the recomputed board moved", () => {
  // The champion's account is gone, so the runner-up recomputes to #1 - but
  // their award says #2, and the frozen board must not promote them.
  const computed = [ranked("bbbb-2", 1), ranked("cccc-3", 2)];

  const {placed, mismatches} = reconcileWithAwards({
    computed,
    everyone: computed,
    awards: new Map([["bbbb-2", 2], ["cccc-3", 3]]),
  });

  assert.deepEqual(placed.map((row) => [row.userId, row.rank]), [
    ["bbbb-2", 2],
    ["cccc-3", 3],
  ]);
  assert.deepEqual(mismatches, [
    {userId: "bbbb-2", computedRank: 1, awardedRank: 2},
    {userId: "cccc-3", computedRank: 2, awardedRank: 3},
  ]);
});

test("a finish nobody was awarded is reported and never placed", () => {
  // Two champions deleted their accounts, so #101 and #102 recompute into the
  // top 100 - but the finalizer never ranked them there.
  const computed = [ranked("cccc-3", 1), ranked("hhhh-8", 99), ranked("iiii-9", 100)];

  const {placed, mismatches} = reconcileWithAwards({
    computed,
    everyone: computed,
    awards: new Map([["cccc-3", 3], ["hhhh-8", null], ["iiii-9", null]]),
  });

  assert.deepEqual(placed.map((row) => [row.userId, row.rank]), [["cccc-3", 3]]);
  assert.deepEqual(mismatches, [
    {userId: "cccc-3", computedRank: 1, awardedRank: 3},
    {userId: "hhhh-8", computedRank: 99, awardedRank: null},
    {userId: "iiii-9", computedRank: 100, awardedRank: null},
  ]);
});

test("an award held outside the recomputed top 100 is placed at its rank", () => {
  const computed = [ranked("aaaa-1", 1)];
  const slipped = ranked("ffff-6", 140);

  const {placed, mismatches} = reconcileWithAwards({
    computed,
    everyone: [...computed, slipped, ranked("gggg-7", 141)],
    awards: new Map([["aaaa-1", 1], ["ffff-6", 57], ["gggg-7", null]]),
  });

  assert.deepEqual(placed.map((row) => [row.userId, row.rank]), [
    ["aaaa-1", 1],
    ["ffff-6", 57],
  ]);
  assert.deepEqual(mismatches, [{userId: "ffff-6", computedRank: 140, awardedRank: 57}]);
});

test("the dry run names champions by a four-character uid prefix", () => {
  assert.equal(uidPrefix("Xq9r2bQnF4hS0k"), "Xq9r");

  const lines = describePeriodPlan({
    resultId: "weekly_2026-W38",
    climberCount: 42,
    championUserIds: ["Xq9r2bQnF4hS0k", "Ab12cdEF"],
    podiumUserIds: ["Xq9r2bQnF4hS0k", "Ab12cdEF", "Zz99yy"],
    placingCount: 43,
    mostClimbs: {count: 9, userIds: ["Zz99yy"]},
    mismatches: [],
  });

  assert.equal(lines.length, 1);
  assert.match(lines[0], /weekly_2026-W38: 42 climber\(s\)/);
  assert.match(lines[0], /champion\(s\) \[Xq9r, Ab12\]/);
  assert.match(lines[0], /43 placing\(s\)/);
  assert.match(lines[0], /most climbs 9 \[Zz99\]/);
  assert.match(lines[0], /award ranks agree/);
  assert.doesNotMatch(lines.join("\n"), /Xq9r2b/);
});

test("the dry run spells out every disagreement and an empty throne", () => {
  const lines = describePeriodPlan({
    resultId: "weekly_2026-W38",
    climberCount: 12,
    championUserIds: [],
    podiumUserIds: ["bbbb-2", "cccc-3"],
    placingCount: 11,
    mostClimbs: null,
    mismatches: [
      {userId: "bbbb-2", computedRank: 1, awardedRank: 2},
      {userId: "eeee-5", computedRank: 5, awardedRank: null},
    ],
  });

  assert.match(lines[0], /champion\(s\) \[none\]/);
  assert.match(lines[0], /most climbs none/);
  assert.match(lines[0], /award ranks DISAGREE \(2\)/);
  assert.match(lines[1], /bbbb: recomputed #1, awarded #2 - using #2/);
  assert.match(lines[2], /eeee: recomputed #5, no award record - not placed/);
  assert.match(lines[3], /nobody holds #1/);
});

test("the summary says a dry run wrote nothing", () => {
  const outcomes = [
    {resultId: "weekly_2026-W37", status: "exists"},
    {resultId: "weekly_2026-W38", status: "planned", mismatches: 1},
    {resultId: "weekly_2026-W39", status: "planned", mismatches: 0},
    {resultId: "weekly_bad", status: "skipped"},
  ];

  const dryRun = renderSummary(outcomes, {commit: false});
  assert.match(dryRun, /already holding a result: 1/);
  assert.match(dryRun, /would be written: 2/);
  assert.match(dryRun, /disagree with the recomputed board: 1/);
  assert.match(dryRun, /Skipped \(malformed period document\): 1/);
  assert.match(dryRun, /Dry run: nothing was written/);

  const committed = renderSummary(
    [{resultId: "weekly_2026-W38", status: "written", mismatches: 0}],
    {commit: true}
  );
  assert.match(committed, /Results written: 1/);
  assert.doesNotMatch(committed, /Dry run/);
});

test("a result is created, never replacing one that appeared meanwhile", async () => {
  const created = [];
  const fresh = {path: "leaderboard_results/weekly_2026-W38", create: async (data) => created.push(data)};
  await createResultOnce(fresh, {source: "backfill"});
  assert.deepEqual(created, [{source: "backfill"}]);

  const taken = {
    path: "leaderboard_results/weekly_2026-W38",
    create: async () => {
      throw Object.assign(new Error("6 ALREADY_EXISTS"), {code: 6});
    },
  };
  await assert.rejects(
    createResultOnce(taken, {source: "backfill"}),
    /leaderboard_results\/weekly_2026-W38 appeared during the run; left untouched/
  );
});

test("a result create that hangs is cut off by its deadline", async () => {
  const hanging = {path: "leaderboard_results/weekly_2026-W38", create: () => new Promise(() => {})};
  await assert.rejects(createResultOnce(hanging, {}, {timeoutMs: 20}), /create leaderboard_results\/weekly_2026-W38/);
});
