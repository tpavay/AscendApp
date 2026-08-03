import test from "node:test";
import assert from "node:assert/strict";

import {
  collect,
  makeReportingStore,
} from "../backfill-leaderboard-stats.mjs";

const userId = "climber-1";
const NOW = new Date("2026-08-01T12:00:00.000Z");
const WEEK_START = new Date("2026-07-20T00:00:00.000Z");
const WEEKLY_ROW_ID = `weekly_2026-W30_${userId}`;
const LEGACY_ROW_ID = `${userId}_weekly`;

// Enough of the compiled period module for the store to name a window, without
// making a script test depend on functions/lib being built.
const period = {
  FINALIZED_TIME_FRAMES: ["weekly", "monthly", "yearly"],
  currentPeriod(timeFrame, date) {
    assert.equal(timeFrame, "weekly");
    assert.equal(date.getTime(), WEEK_START.getTime());
    return {
      key: "2026-W30",
      startAt: WEEK_START,
      endAt: new Date("2026-07-27T00:00:00.000Z"),
    };
  },
};

function storedRow(documentId) {
  return {
    userId,
    isSynthetic: false,
    timeFrame: "weekly",
    periodKey: "2026-W30",
    periodStartAt: WEEK_START,
    lastUpdated: new Date("2026-07-27T09:00:00.000Z"),
    totalSteps: 2_000_000_000,
    documentId,
  };
}

/**
 * A derivation double whose period status is read through a live getter, so a
 * test can change it between the run starting and the removal happening.
 */
function makeEnvironment({documentId, finalization, allow = false}) {
  const stored = storedRow(documentId);
  const passedThrough = [];
  const periodReads = [];

  const db = {
    collection() {
      return {
        doc(id) {
          return {
            async get() {
              return {id, data: () => stored};
            },
          };
        },
      };
    },
  };

  const derivation = {
    openPeriodDocumentIds() {
      return new Set([`weekly_2026-W31_${userId}`]);
    },
    makeAdminLeaderboardStatsStore() {
      return {
        async runTransaction(operation) {
          return operation({
            async read() {
              return {
                workouts: [],
                publicProfile: undefined,
                user: undefined,
                existingRows: [{
                  documentId,
                  isSynthetic: false,
                  timeFrame: "weekly",
                  periodStartAtMillis: WEEK_START.getTime(),
                }],
              };
            },
            async readPeriodFinalization(periodDocumentId) {
              periodReads.push(periodDocumentId);
              return finalization();
            },
            async write() {},
            async delete(id) {
              passedThrough.push(id);
            },
          });
        },
      };
    },
  };

  const store = makeReportingStore({
    db,
    derivation,
    period,
    userId,
    now: NOW,
    dryRun: false,
    allowFinalizedProvenanceLoss: allow,
  });

  return {store, passedThrough, periodReads};
}

async function runRemoval(environment, reason = "noEvidence") {
  return environment.store.runTransaction(async (transaction) => {
    await transaction.read(userId);
    await transaction.delete(environment.targetId, reason);
    return {
      written: [],
      deleted: [environment.targetId],
      skippedSynthetic: [],
      unresolvableRows: environment.unresolvable ?? [],
    };
  });
}

function environmentFor(options) {
  const environment = makeEnvironment(options);
  environment.targetId = options.documentId;
  environment.unresolvable = options.unresolvable;
  return environment;
}

// The status has to come from a read inside the transaction that performs the
// removal. A value captured before the run cannot see a thirty-minute lock that
// starts afterwards, which is exactly how this class of bug survives a guard.
test("the guard honours the status read at removal time, not at run start",
  async () => {
    let status = {exists: false, status: null};
    const environment = environmentFor({
      documentId: WEEKLY_ROW_ID,
      finalization: () => status,
    });

    // The awards job takes its lock after the run began.
    status = {exists: true, status: "finalizing"};
    await runRemoval(environment);

    assert.deepEqual(
      environment.periodReads,
      ["weekly_2026-W30"],
      "the period document is read through the transaction"
    );
    assert.deepEqual(
      environment.passedThrough,
      [],
      "a removal must not reach Firestore while the awards job is reading"
    );
    assert.equal(environment.store.changes[0].kind, "refusedDelete");
    assert.equal(environment.store.changes[0].refusal, "finalizing");
  });

test("a period with no finalization document is removed", async () => {
  const environment = environmentFor({
    documentId: WEEKLY_ROW_ID,
    finalization: () => ({exists: false, status: null}),
  });

  await runRemoval(environment);

  assert.deepEqual(environment.passedThrough, [WEEKLY_ROW_ID]);
  assert.equal(environment.store.changes[0].kind, "delete");
});

test("a finalized period is removed only with the provenance opt-in",
  async () => {
    const refused = environmentFor({
      documentId: WEEKLY_ROW_ID,
      finalization: () => ({exists: true, status: "finalized"}),
    });
    await runRemoval(refused);
    assert.deepEqual(refused.passedThrough, []);
    assert.equal(refused.store.changes[0].refusal, "finalized");

    const allowed = environmentFor({
      documentId: WEEKLY_ROW_ID,
      finalization: () => ({exists: true, status: "finalized"}),
      allow: true,
    });
    await runRemoval(allowed);
    assert.deepEqual(allowed.passedThrough, [WEEKLY_ROW_ID]);
  });

test("a status this tool does not recognise blocks the removal", async () => {
  const environment = environmentFor({
    documentId: WEEKLY_ROW_ID,
    finalization: () => ({exists: true, status: "reconciling"}),
    allow: true,
  });

  await runRemoval(environment);

  assert.deepEqual(environment.passedThrough, []);
  assert.equal(environment.store.changes[0].refusal, "unrecognisedStatus");
});

// A headline that undercounts refusals teaches an operator to trust a number
// that is wrong.
test("a refused legacy-row removal reaches the counter and the refused list",
  async () => {
    const environment = environmentFor({
      documentId: LEGACY_ROW_ID,
      finalization: () => ({exists: true, status: "finalized"}),
      unresolvable: [LEGACY_ROW_ID],
    });
    const outcome = await runRemoval(environment, "unresolvableWindow");

    const report = {
      changed: [],
      removedNoEvidence: [],
      prunedClosedWindows: [],
      refusedRemovals: [],
      unresolvable: [],
      unchanged: 0,
      syntheticSkipped: 0,
    };
    collect(report, environment.store, outcome, userId);

    assert.equal(report.refusedRemovals.length, 1);
    assert.equal(report.refusedRemovals[0].documentId, LEGACY_ROW_ID);
    assert.equal(
      report.unresolvable.length,
      1,
      "it still belongs in the legacy section too"
    );
    assert.match(report.unresolvable[0].action, /REFUSED/);
    assert.deepEqual(environment.passedThrough, []);
  });
