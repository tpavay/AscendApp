import test from "node:test";
import assert from "node:assert/strict";

import {
  describeAction,
  describeStatus,
  printReport,
  removalDecision,
} from "../backfill-leaderboard-stats.mjs";

function capture(run) {
  const lines = [];
  const original = console.log;
  console.log = (...parts) => lines.push(parts.join(" "));
  try {
    run();
  } finally {
    console.log = original;
  }
  return lines.join("\n");
}

function emptyReport(overrides = {}) {
  return {
    changed: [],
    removedNoEvidence: [],
    prunedClosedWindows: [],
    refusedRemovals: [],
    unresolvable: [],
    unchanged: 0,
    syntheticSkipped: 0,
    ...overrides,
  };
}

function closedDailyRow() {
  return {
    kind: "delete",
    reason: "prunedClosedWindow",
    documentId: "daily_2026-07-31_climber-1",
    timeFrame: "daily",
    periodKey: "2026-07-31",
    windowStart: new Date("2026-07-31T00:00:00.000Z"),
    windowEnd: new Date("2026-08-01T00:00:00.000Z"),
    closed: true,
    awardBearing: false,
    periodStatus: "not finalized",
    stored: {totalSteps: 3000},
    derived: null,
    derivedWorkoutCount: null,
    before: {totalSteps: 3000},
  };
}

function evidencelessWeeklyRow() {
  return {
    kind: "delete",
    reason: "noEvidence",
    documentId: "weekly_2026-W30_climber-1",
    timeFrame: "weekly",
    periodKey: "2026-W30",
    windowStart: new Date("2026-07-20T00:00:00.000Z"),
    windowEnd: new Date("2026-07-27T00:00:00.000Z"),
    closed: true,
    awardBearing: true,
    periodStatus: "not finalized",
    stored: {totalSteps: 2_000_000_000},
    derived: null,
    derivedWorkoutCount: 0,
    before: {totalSteps: 2_000_000_000},
  };
}

// A dry run that describes yesterday's legitimate daily row the way it
// describes a row with no evidence behind it defeats the point of the dry run.
test("a pruned row and an evidence-less row are described differently", () => {
  const pruned = describeAction(closedDailyRow());
  const evidenceless = describeAction(evidencelessWeeklyRow());

  assert.notEqual(pruned, evidenceless);
  assert.match(pruned, /PRUNE/);
  assert.match(pruned, /not examined/);
  assert.doesNotMatch(pruned, /no eligible workouts/);
  assert.match(evidenceless, /no eligible workouts/);
  assert.doesNotMatch(evidenceless, /PRUNE/);
});

test("a pruned row is never counted as an evidence failure", () => {
  const output = capture(() => printReport(
    emptyReport({prunedClosedWindows: [closedDailyRow()]}),
    {includeClosedPeriods: false, verbose: false}
  ));

  assert.match(output, /Closed daily rows pruned[^\n]*: 1/);
  assert.match(output, /Rows removed - window derived, no eligible workouts: 0/);
  assert.match(output, /routine housekeeping, NOT an evidence finding/);
  // "0 workouts" for a window nobody derived would be a finding nobody made.
  assert.doesNotMatch(output, /eligible workouts behind derived value/);
});

test("an evidence-less award-bearing row keeps its evidence count", () => {
  const output = capture(() => printReport(
    emptyReport({removedNoEvidence: [evidencelessWeeklyRow()]}),
    {includeClosedPeriods: true, verbose: false}
  ));

  assert.match(output, /Rows removed - window derived, no eligible workouts: 1/);
  assert.match(output, /eligible workouts behind derived value: 0/);
  assert.doesNotMatch(output, /Closed daily rows pruned[^\n]*: 1/);
});

// A daily row can never carry an award, so listing one in the award-bearing
// section buries the rows that section exists to surface.
test("only award-bearing time frames reach the closed-period detail", () => {
  const output = capture(() => printReport(
    emptyReport({prunedClosedWindows: [closedDailyRow()]}),
    {includeClosedPeriods: true, verbose: false}
  ));

  assert.doesNotMatch(output, /Closed award-bearing rows/);
  assert.doesNotMatch(output, /needs the award/);
});

test("the closed-period detail is capped rather than burying the report", () => {
  const many = Array.from({length: 25}, (unused, index) => ({
    ...evidencelessWeeklyRow(),
    documentId: `weekly_2026-W30_climber-${index}`,
  }));

  const output = capture(() => printReport(
    emptyReport({removedNoEvidence: many}),
    {includeClosedPeriods: true, verbose: false}
  ));

  assert.match(output, /\.\.\. and 5 more/);
});

// Cleaning a just-closed window BEFORE the nightly job runs is the whole reason
// --include-closed-periods exists, and the absence of the period document is the
// one positive signal that no award has been minted from it.
test("a period the awards job has not started is removable", () => {
  assert.deepEqual(
    removalDecision({exists: false, status: null}, false),
    {refused: false, refusal: null}
  );
  assert.deepEqual(removalDecision(undefined, false), {
    refused: false,
    refusal: null,
  });
});

// Deleting the record an award points at is not something to do by accident.
test("a finalized period's removal is refused without its own opt-in", () => {
  assert.equal(
    removalDecision({exists: true, status: "finalized"}, false).refused,
    true
  );
  assert.equal(
    removalDecision({exists: true, status: "finalized"}, true).refused,
    false
  );
});

// finalizeLeaderboardAchievements holds this status while it reads exactly
// these rows to mint awards. Deleting mid-read is a race, not a decision, so
// consent to losing provenance is not consent to this.
test("a finalizing period is refused even with the provenance opt-in", () => {
  for (const allowed of [false, true]) {
    const decision = removalDecision(
      {exists: true, status: "finalizing"},
      allowed
    );
    assert.equal(decision.refused, true);
    assert.equal(decision.refusal, "finalizing");
  }
});

// Refusal is the default branch, so a status this code has never seen can never
// permit a deletion.
test("a status this tool cannot reason about refuses the removal", () => {
  for (const status of [null, "", "reconciling", "FINALIZED", "done"]) {
    for (const allowed of [false, true]) {
      const decision = removalDecision({exists: true, status}, allowed);
      assert.equal(
        decision.refused,
        true,
        `status ${JSON.stringify(status)} must not permit a removal`
      );
      assert.equal(decision.refusal, "unrecognisedStatus");
    }
  }
});

test("the reported status distinguishes never-started from status-less", () => {
  assert.equal(describeStatus({exists: false, status: null}), "not started");
  assert.equal(describeStatus(undefined), "not started");
  assert.equal(
    describeStatus({exists: true, status: null}),
    "present, no status field"
  );
  assert.equal(describeStatus({exists: true, status: "finalizing"}),
    "finalizing");
});

test("a refused removal is reported with what it would have cost", () => {
  const refused = {
    ...evidencelessWeeklyRow(),
    kind: "refusedDelete",
    refusal: "finalized",
    periodStatus: "finalized",
  };

  const output = capture(() => printReport(
    emptyReport({refusedRemovals: [refused]}),
    {includeClosedPeriods: true, verbose: false}
  ));

  assert.match(output, /Removals refused \(award at stake\):    1/);
  assert.match(output, /Removals REFUSED - an award is at stake: 1/);
  assert.match(output, /pointing at a document that no longer/);
  assert.match(output, /--allow-finalized-provenance-loss/);
  assert.match(describeAction(refused), /REFUSED/);
});

// A refusal made mid-finalization has to say so rather than borrowing the
// finalized wording, because the operator's options differ: the flag clears one
// and cannot clear the other.
test("a refusal names which of the two reasons blocked it", () => {
  const mid = {
    ...evidencelessWeeklyRow(),
    kind: "refusedDelete",
    refusal: "finalizing",
    periodStatus: "finalizing",
  };

  const output = capture(() => printReport(
    emptyReport({refusedRemovals: [mid]}),
    {includeClosedPeriods: true, verbose: false}
  ));

  assert.match(output, /reading this period right now/);
  assert.match(describeAction(mid), /reading this period right now/);
  assert.doesNotMatch(
    describeAction(mid),
    /--allow-finalized-provenance-loss/
  );
});

// The legacy rows nothing sweeps any more. They still compete for awards, so a
// clean-looking run must not imply they were covered.
test("legacy rows get their own section stating a removal is final", () => {
  const output = capture(() => printReport(
    emptyReport({
      unresolvable: [{
        userId: "climber-1",
        documentId: "climber-1_weekly",
        action: "left in place (needs --include-closed-periods to remove)",
        timeFrame: "weekly",
        periodStartAt: "2026-07-20T00:00:00.000Z",
        lastUpdated: "2026-07-27T00:00:00.000Z",
        stored: {totalSteps: 2_000_000_000},
      }],
    }),
    {includeClosedPeriods: false, verbose: false}
  ));

  assert.match(output, /Legacy rows with no derivable period: 1/);
  assert.match(output, /CAN NEVER BE RE-DERIVED/);
  assert.match(output, /FINAL/);
  assert.match(output, /lastUpdated:    2026-07-27T00:00:00\.000Z/);
  assert.match(output, /periodStartAt:  2026-07-20T00:00:00\.000Z/);
  assert.match(output, /needs --include-closed-periods/);
});
