#!/usr/bin/env node

/**
 * Reconciles every climber's global standing against their canonical workouts.
 *
 * `leaderboard_stats` used to be written by the device (issue #307). Every row
 * that predates the server-side derivation was authored by a client and has
 * never been checked against evidence, so this is the tool that replaces those
 * rows with derived ones - and the tool that shows you, before it writes
 * anything, exactly which rows disagreed and by how much.
 *
 * It runs the SAME derivation the Cloud Function trigger runs, imported from
 * the compiled function bundle rather than reimplemented. A second copy of
 * "what does this climber's week add up to" would become a second answer.
 * Build it first: cd functions && npm run build
 *
 * By default it owns only the five currently open periods, exactly as the Cloud
 * Function triggers do. `--include-closed-periods` widens that to every period a
 * stored row already names, which is the only way to reach the client-authored
 * rows sitting in the window the nightly finalizer is about to freeze permanent
 * awards from. That is opt-in because it is a supervised operation: run the dry
 * run, read every closed-period row it lists, then apply.
 *
 * The report distinguishes outcomes that look identical in the data and are not
 * the same statement. A window that was derived and came back empty is a
 * finding; a window that was never derived is not, and reporting the second as
 * the first would make yesterday's honest daily row read exactly like a forged
 * one - which is the distinction the dry run exists to draw.
 *
 * Usage:
 *   node scripts/backfill-leaderboard-stats.mjs --project dev --dry-run
 *   node scripts/backfill-leaderboard-stats.mjs --project dev
 *   node scripts/backfill-leaderboard-stats.mjs --project staging --dry-run --verbose
 *   node scripts/backfill-leaderboard-stats.mjs --project staging --dry-run --include-closed-periods
 */

import {createRequire} from "node:module";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {existsSync, realpathSync} from "node:fs";

import {
  assertSeedableProject,
  resolveProjectId,
} from "./seed/lib/environments.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const FUNCTIONS_DIR = resolve(REPO_ROOT, "functions");
const DERIVATION_PATH = resolve(
  FUNCTIONS_DIR,
  "lib/src/leaderboardStats.js"
);
const PERIOD_PATH = resolve(
  FUNCTIONS_DIR,
  "lib/src/leaderboardPeriod.js"
);
const LEADERBOARD_PERIODS_COLLECTION = "leaderboard_periods";
const COMPARED_FIELDS = [
  "totalSteps",
  "totalFloors",
  "totalWorkouts",
  "totalDuration",
  "stepsPerMinute",
];
const DETAIL_LIMIT = 20;

export function parseArgs(argv) {
  const args = {
    project: null,
    dryRun: false,
    verbose: false,
    // Widening ownership to closed periods puts the rows the nightly finalizer
    // reads in reach of a rewrite, so it never happens because someone forgot a
    // flag - only because they passed one.
    includeClosedPeriods: false,
    // Deleting a row a minted achievement points at is a separate, harsher act
    // than repairing one, so it needs its own consent rather than riding along
    // on the broader flag.
    allowFinalizedProvenanceLoss: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--dry-run") args.dryRun = true;
    else if (value === "--verbose") args.verbose = true;
    else if (value === "--include-closed-periods") {
      args.includeClosedPeriods = true;
    } else if (value === "--allow-finalized-provenance-loss") {
      args.allowFinalizedProvenanceLoss = true;
    } else if (value === "--help" || value === "-h") args.help = true;
    else throw new Error(`Unknown argument: ${value}`);
  }

  if (!args.help && !args.project) {
    throw new Error("--project is required (e.g. --project dev)");
  }
  return args;
}

export const OWNERSHIP_OPEN_ONLY = "openPeriodsOnly";
export const OWNERSHIP_INCLUDING_CLOSED = "openAndStoredPeriods";

export function ownershipFor(args) {
  return args.includeClosedPeriods ?
    OWNERSHIP_INCLUDING_CLOSED :
    OWNERSHIP_OPEN_ONLY;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value`);
  return value;
}

function printHelp() {
  console.log(`
Usage:
  node scripts/backfill-leaderboard-stats.mjs --project dev --dry-run
  node scripts/backfill-leaderboard-stats.mjs --project dev
  node scripts/backfill-leaderboard-stats.mjs --project staging --dry-run --verbose
  node scripts/backfill-leaderboard-stats.mjs --project staging --dry-run --include-closed-periods

Flags:
  --project <alias>          dev or staging. Production is refused.
  --dry-run                  Report what would change and write nothing.
  --verbose                  Print every rewritten row, not just the summary.
  --include-closed-periods   Also own periods that have already closed.
  --allow-finalized-provenance-loss
                             Permit REMOVING a row whose period is already
                             finalized. Off by default and NOT implied by
                             --include-closed-periods.

Run the dry run first and read the deltas. A row that changes is a row whose
published total did not match the workouts behind it.

--include-closed-periods is off by default. Without it this reconciles only the
five currently open periods, which is exactly what the Cloud Function triggers
do. With it, every period a stored row names is re-derived from the canonical
workouts - the only way to repair the client-authored rows sitting in the window
finalizeLeaderboardAchievements freezes permanent awards from.

Repairing a row for a period that is ALREADY FINALIZED does not unwind an
achievement minted from the old number. The dry run reports each closed period's
finalization status for exactly that reason: a finalized period needs the award
in users/{uid}/achievements looked at separately.

REMOVING a row for an already-finalized period is worse than repairing one: the
permanent achievement survives, but the record its leaderboardStatsId points at
as provenance is gone, and that is not reversible. Such removals are refused and
reported unless --allow-finalized-provenance-loss is passed as well.

Legacy {uid}_{timeFrame} rows CAN NEVER BE RE-DERIVED - their identifier encodes
no period, so there is no window to sum workouts over and nothing to rebuild
them from. Removing one is FINAL. They are reported in their own section on
every run, and removed only with --include-closed-periods. They are not inert:
finalizeLeaderboardAchievements matches rows on timeFrame + periodStartAt with
no constraint on document id and breaks ties by newest lastUpdated, so a legacy
client-authored row can still win a permanent award, and this branch deleted the
only sweeper that used to remove them.
`);
}

/**
 * Loads the derivation and the exact firebase-admin instance it will call.
 *
 * The compiled bundle resolves `firebase-admin` inside functions/, so the app
 * must be initialized on that module instance. Initializing a second copy from
 * the repo root leaves the derivation calling `admin.firestore()` on an
 * uninitialized default app, which fails at the first read.
 */
function loadDerivation() {
  if (!existsSync(DERIVATION_PATH)) {
    throw new Error(
      "functions/lib is not built. Run: cd functions && npm run build"
    );
  }
  const requireFromFunctions = createRequire(
    resolve(FUNCTIONS_DIR, "package.json")
  );
  return {
    derivation: requireFromFunctions(DERIVATION_PATH),
    period: requireFromFunctions(PERIOD_PATH),
    admin: requireFromFunctions("firebase-admin"),
  };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    return;
  }

  const {derivation, period, admin} = loadDerivation();
  const projectId = resolveProjectId(args.project, REPO_ROOT);
  assertSeedableProject(projectId, "backfill");

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
  const db = admin.firestore();
  const now = new Date();
  const ownership = ownershipFor(args);

  console.log(`Project: ${projectId}`);
  console.log(`Mode: ${args.dryRun ? "dry run" : "APPLY"}`);
  console.log(`Reference instant: ${now.toISOString()}`);
  console.log(
    `Ownership: ${args.includeClosedPeriods ?
      "open periods PLUS every period a stored row names" :
      "currently open periods only"}`
  );

  // Read up front rather than per row: a removal has to know whether its period
  // is finalized at the moment it decides, not after the run is over.
  const periodStatuses = await finalizationStatuses(db);
  const userIds = await leaderboardUserIds(db);
  console.log(`Climbers with a standing or a workout: ${userIds.length}`);

  const report = {
    changed: [],
    removedNoEvidence: [],
    prunedClosedWindows: [],
    refusedRemovals: [],
    unresolvable: [],
    unchanged: 0,
    syntheticSkipped: 0,
  };

  for (const userId of userIds) {
    const store = makeReportingStore({
      db,
      derivation,
      period,
      userId,
      now,
      periodStatuses,
      dryRun: args.dryRun,
      allowFinalizedProvenanceLoss: args.allowFinalizedProvenanceLoss,
    });
    const outcome = await derivation.reconcileLeaderboardStats(
      store,
      userId,
      now,
      {ownership}
    );
    report.syntheticSkipped += outcome.skippedSynthetic.length;
    collect(report, store, outcome, userId);
  }

  printReport(report, args);

  if (args.dryRun) {
    console.log("\nDry run: nothing was written.");
  }
}

/**
 * Routes one climber's changes into the counters that describe them honestly.
 *
 * A pruned closed window and a window that was derived and came back empty are
 * different statements about a row, so they never share a bucket.
 */
function collect(report, store, outcome, userId) {
  const changeById = new Map(
    store.changes.map((change) => [change.documentId, change])
  );

  for (const change of store.changes) {
    if (change.reason === "unresolvableWindow") {
      continue;
    }
    if (change.kind === "unchanged") {
      report.unchanged += 1;
    } else if (change.kind === "write") {
      report.changed.push(change);
    } else if (change.kind === "refusedDelete") {
      report.refusedRemovals.push(change);
    } else if (change.reason === "prunedClosedWindow") {
      report.prunedClosedWindows.push(change);
    } else {
      report.removedNoEvidence.push(change);
    }
  }

  for (const documentId of outcome.unresolvableRows) {
    const change = changeById.get(documentId);
    report.unresolvable.push({
      userId,
      documentId,
      action: describeUnresolvableAction(change),
      ...store.legacyFacts(documentId),
    });
  }
}

function describeUnresolvableAction(change) {
  if (change === undefined) {
    return "left in place (needs --include-closed-periods to remove)";
  }
  if (change.kind === "refusedDelete") {
    return "REMOVAL REFUSED (period is finalized)";
  }
  return "REMOVE - final, nothing can rebuild it";
}

/**
 * Every leaderboard period's finalization status, keyed the way the finalizer
 * names its documents.
 */
async function finalizationStatuses(db) {
  const snapshot = await db
    .collection(LEADERBOARD_PERIODS_COLLECTION)
    .select("status")
    .get();
  return new Map(
    snapshot.docs.map((document) => [
      document.id,
      document.get("status") ?? "not finalized",
    ])
  );
}

/**
 * Every uid that either holds a standing today or has a workout to derive one
 * from. Reading both keeps an orphan row - a standing whose owner has no
 * workouts at all - inside the sweep instead of invisible to it.
 */
async function leaderboardUserIds(db) {
  const userIds = new Set();

  const standings = await db
    .collection("leaderboard_stats")
    .select("userId")
    .get();
  for (const document of standings.docs) {
    const userId = document.get("userId");
    if (typeof userId === "string" && userId.length > 0) {
      userIds.add(userId);
    }
  }

  const users = await db.collection("users").select().get();
  for (const document of users.docs) {
    userIds.add(document.id);
  }

  return [...userIds].sort();
}

/**
 * Wraps the production store so a dry run reports what it would have done and
 * an apply run reports what it did. Reads always hit Firestore, so the derived
 * numbers are the real ones either way.
 */
function makeReportingStore(options) {
  const {
    db,
    derivation,
    period,
    userId,
    now,
    periodStatuses,
    dryRun,
    allowFinalizedProvenanceLoss,
  } = options;
  const adminStore = derivation.makeAdminLeaderboardStatsStore();
  const openIds = derivation.openPeriodDocumentIds(userId, now);
  const changes = [];
  let existingById = new Map();

  return {
    changes,
    legacyFacts(documentId) {
      return legacyFacts(existingById.get(documentId));
    },
    async runTransaction(operation) {
      return adminStore.runTransaction(async (transaction) => {
        // A retry re-runs the whole callback, so the change log has to start
        // empty each attempt or a contended user reports its deltas twice.
        changes.length = 0;
        return operation({
          async read(readUserId) {
            const snapshot = await transaction.read(readUserId);
            const documents = await Promise.all(
              snapshot.existingRows.map((row) =>
                db.collection("leaderboard_stats").doc(row.documentId).get()
              )
            );
            existingById = new Map(
              documents.map((document) => [document.id, document.data()])
            );
            return snapshot;
          },
          async write(documentId, data) {
            const before = existingById.get(documentId);
            const delta = fieldDelta(before, data);
            const window = describeWindow(
              period,
              data,
              before,
              documentId,
              openIds
            );
            changes.push({
              kind: delta === null ? "unchanged" : "write",
              reason: null,
              userId,
              documentId,
              delta,
              stored: summarize(before),
              derived: summarize(data),
              derivedWorkoutCount: numberOrNull(data.totalWorkouts) ?? 0,
              periodStatus: window.timeFrame && window.periodKey ?
                periodStatuses.get(`${window.timeFrame}_${window.periodKey}`) ??
                  "not finalized" :
                "not finalized",
              ...window,
            });
            if (!dryRun) {
              await transaction.write(documentId, data);
            }
          },
          async delete(documentId, reason) {
            const before = existingById.get(documentId);
            const window = describeWindow(
              period,
              undefined,
              before,
              documentId,
              openIds
            );
            const periodStatus = window.timeFrame && window.periodKey ?
              periodStatuses.get(`${window.timeFrame}_${window.periodKey}`) ??
                "not finalized" :
              "not finalized";
            const refused = shouldRefuseRemoval(
              periodStatus,
              allowFinalizedProvenanceLoss
            );
            changes.push({
              kind: refused ? "refusedDelete" : "delete",
              reason,
              userId,
              documentId,
              before: summarize(before),
              stored: summarize(before),
              // A window that was never derived has no derived value, and
              // printing a zero here would assert a finding nobody made.
              derived: null,
              derivedWorkoutCount: reason === "noEvidence" ? 0 : null,
              periodStatus,
              ...window,
            });
            if (!refused && !dryRun) {
              await transaction.delete(documentId);
            }
          },
        });
      });
    },
  };
}

/**
 * Names the window a row belongs to, from the row's own stored fields.
 *
 * Reuses the one Cloud Functions period derivation rather than parsing the
 * document id, so the window a report shows is the window the derivation used.
 */
function describeWindow(period, derived, stored, documentId, openIds) {
  const source = derived ?? stored ?? {};
  const timeFrame = typeof source.timeFrame === "string" ?
    source.timeFrame :
    null;
  const startMillis = timestampMillis(source.periodStartAt);
  const closed = !openIds.has(documentId);
  // Only the time frames the finalizer freezes awards from can ever carry one,
  // so only those belong in the section an operator reads before approving.
  const awardBearing = period.FINALIZED_TIME_FRAMES.includes(timeFrame);

  if (timeFrame === null || startMillis === null) {
    return {
      timeFrame,
      periodKey: typeof source.periodKey === "string" ?
        source.periodKey :
        null,
      windowStart: null,
      windowEnd: null,
      closed,
      awardBearing,
    };
  }

  const window = period.currentPeriod(timeFrame, new Date(startMillis));
  return {
    timeFrame,
    periodKey: window.key,
    windowStart: window.startAt,
    windowEnd: window.endAt,
    closed,
    awardBearing,
  };
}

function timestampMillis(value) {
  if (value && typeof value === "object") {
    if (typeof value.toMillis === "function") return value.toMillis();
    if (typeof value.getTime === "function") return value.getTime();
  }
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * Whether a removal must be refused because it would orphan award provenance.
 *
 * The achievement stores `leaderboardStatsId` pointing back at the row. Deleting
 * it leaves a permanent award pointing at a document that no longer exists, the
 * award itself is not unwound, and no rerun can put the row back.
 */
export function shouldRefuseRemoval(periodStatus, allowFinalizedProvenanceLoss) {
  return periodStatus === "finalized" && !allowFinalizedProvenanceLoss;
}

function numberOrNull(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * What a human needs to judge a legacy row.
 *
 * `lastUpdated` matters most: finalizeLeaderboardAchievements breaks ties by
 * newest, so it is what decides whether this row beats the canonical one for a
 * permanent award.
 */
function legacyFacts(stored) {
  return {
    timeFrame: typeof stored?.timeFrame === "string" ? stored.timeFrame : null,
    periodStartAt: isoOrNull(timestampMillis(stored?.periodStartAt)),
    lastUpdated: isoOrNull(timestampMillis(stored?.lastUpdated)),
    stored: summarize(stored),
  };
}

function isoOrNull(millis) {
  return millis === null ? null : new Date(millis).toISOString();
}

function windowLabel(change) {
  const start = change.windowStart ?
    change.windowStart.toISOString().slice(0, 10) :
    "?";
  const end = change.windowEnd ?
    change.windowEnd.toISOString().slice(0, 10) :
    "open-ended";
  return `${change.timeFrame ?? "?"} ${change.periodKey ?? "?"} ` +
    `[${start} -> ${end})`;
}

function fieldDelta(before, after) {
  if (before === undefined) {
    return {created: true, after: summarize(after)};
  }

  const changed = COMPARED_FIELDS.filter(
    (field) => roundedValue(before[field]) !== roundedValue(after[field])
  );
  if (changed.length === 0) {
    return null;
  }

  return {
    created: false,
    fields: Object.fromEntries(changed.map((field) => [
      field,
      {before: roundedValue(before[field]), after: roundedValue(after[field])},
    ])),
  };
}

function summarize(data) {
  if (data === undefined) return null;
  return Object.fromEntries(
    COMPARED_FIELDS.map((field) => [field, roundedValue(data[field])])
  );
}

function roundedValue(value) {
  return typeof value === "number" ? Math.round(value * 1000) / 1000 : null;
}

export function printReport(report, args) {
  console.log("");
  console.log(`Rows already correct:            ${report.unchanged}`);
  console.log(`Rows rewritten:                  ${report.changed.length}`);
  console.log(
    "Rows removed - window derived, no eligible workouts: " +
    `${report.removedNoEvidence.length}`
  );
  console.log(
    "Closed daily rows pruned - window not examined, nothing reads them: " +
    `${report.prunedClosedWindows.length}`
  );
  console.log(
    `Legacy rows with no derivable period: ${report.unresolvable.length}`
  );
  console.log(
    `Removals refused (finalized period):  ${report.refusedRemovals.length}`
  );
  console.log(`Seeded rows left alone:          ${report.syntheticSkipped}`);

  if (report.prunedClosedWindows.length > 0) {
    console.log("");
    console.log(
      "Pruned rows are routine housekeeping, NOT an evidence finding. Daily " +
      "windows are never finalized and the app only ever queries the current " +
      "period, so a closed daily row is dead weight. This run did not derive " +
      "those windows, so it makes no claim about what was behind them."
    );
  }

  printLegacyRowDetail(report.unresolvable, args);
  printRefusedRemovals(report.refusedRemovals);

  if (!args.includeClosedPeriods) {
    console.log(
      "\nClosed weekly, monthly and yearly rows were left untouched: without " +
      "--include-closed-periods this run owns only the currently open " +
      "periods. Those closed rows are what finalizeLeaderboardAchievements " +
      "freezes permanent achievements from, so any client-authored one still " +
      "sitting there is still reachable by the next finalizer run. Re-run " +
      "with --dry-run --include-closed-periods to see them."
    );
  }
  printAwardBearingDetail([
    ...report.changed,
    ...report.removedNoEvidence,
    ...report.refusedRemovals,
  ]);

  const inflated = report.changed.filter((change) =>
    change.delta.fields?.totalSteps !== undefined &&
    change.delta.fields.totalSteps.before > change.delta.fields.totalSteps.after
  );
  if (inflated.length > 0) {
    console.log("");
    console.log(
      `${inflated.length} row(s) published MORE steps than their workouts ` +
      "account for. Read every one before applying - an inflated standing is " +
      "either forged or a defect in what the device counted."
    );
    for (const change of inflated.slice(0, DETAIL_LIMIT)) {
      const steps = change.delta.fields.totalSteps;
      console.log(
        `  ${change.documentId}: ${steps.before} -> ${steps.after}`
      );
    }
    printOverflow(inflated.length);
  }

  if (report.removedNoEvidence.length > 0) {
    console.log("");
    console.log("Removed for no eligible evidence in the derived window:");
    for (const change of report.removedNoEvidence.slice(0, DETAIL_LIMIT)) {
      console.log(
        `  ${change.documentId}: was ${JSON.stringify(change.before)}`
      );
    }
    printOverflow(report.removedNoEvidence.length);
  }

  if (args.verbose) {
    console.log("");
    console.log("Every rewritten row:");
    for (const change of report.changed) {
      console.log(`  ${change.documentId}: ${JSON.stringify(change.delta)}`);
    }
  }
}

function printOverflow(total) {
  if (total > DETAIL_LIMIT) {
    console.log(`  ... and ${total - DETAIL_LIMIT} more`);
  }
}

/**
 * Lists the legacy rows this derivation cannot name a window for.
 *
 * Its own section rather than folded into the repair counts, because it is the
 * one class of row the tool cannot fix and the operator has to decide about.
 */
function printLegacyRowDetail(rows, args) {
  if (rows.length === 0) {
    return;
  }

  console.log("");
  console.log(`Legacy rows with no derivable period: ${rows.length}`);
  console.log(
    "These carry timeFrame and periodStartAt but their document id encodes no " +
    "period, so they CAN NEVER BE RE-DERIVED - there is nothing to rebuild " +
    "them from and a removal here is FINAL. They are not inert: " +
    "finalizeLeaderboardAchievements matches on timeFrame + periodStartAt " +
    "with no constraint on document id and breaks ties by newest lastUpdated, " +
    "so one of these can still win a permanent award."
  );
  if (!args.includeClosedPeriods) {
    console.log(
      "This run left them in place. Removing them needs " +
      "--include-closed-periods."
    );
  }

  for (const row of rows.slice(0, DETAIL_LIMIT)) {
    console.log("");
    console.log(`  ${row.documentId}`);
    console.log(`    action:         ${row.action}`);
    console.log(`    timeFrame:      ${row.timeFrame ?? "?"}`);
    console.log(`    periodStartAt:  ${row.periodStartAt ?? "?"}`);
    console.log(`    lastUpdated:    ${row.lastUpdated ?? "?"}`);
    console.log(`    stored totals:  ${JSON.stringify(row.stored)}`);
  }
  printOverflow(rows.length);
}

function printRefusedRemovals(refused) {
  if (refused.length === 0) {
    return;
  }

  console.log("");
  console.log(`Removals REFUSED - period already finalized: ${refused.length}`);
  console.log(
    "Deleting one of these would leave the permanent achievement in place " +
    "with its leaderboardStatsId pointing at a document that no longer " +
    "exists, and that is not reversible. Pass " +
    "--allow-finalized-provenance-loss as well if that is genuinely intended."
  );
  for (const change of refused.slice(0, DETAIL_LIMIT)) {
    console.log(`  ${change.documentId}: ${windowLabel(change)}`);
  }
  printOverflow(refused.length);
}

/**
 * Prints enough about each award-bearing closed-period row to tell forgery from
 * drift.
 *
 * Scoped to the time frames finalizeLeaderboardAchievements actually freezes
 * awards from. A daily row can never carry an award, so listing one here would
 * bury the rows this section exists to surface under noise that cannot matter.
 *
 * Zero eligible workouts behind a large stored total is the signature of a row
 * a client wrote. A small delta with real workouts behind it is a legitimate row
 * that drifted. Nobody should have to guess which one they are approving.
 */
function printAwardBearingDetail(changes) {
  const closed = changes.filter(
    (change) => change.closed && change.awardBearing
  );
  if (closed.length === 0) {
    return;
  }

  console.log("");
  console.log(
    `Closed award-bearing rows this run would touch: ${closed.length}`
  );
  console.log(
    "Repairing a row does NOT unwind an achievement already minted from the " +
    "old number. Any row below whose period reads 'finalized' needs the award " +
    "in users/{uid}/achievements looked at separately."
  );

  for (const change of closed.slice(0, DETAIL_LIMIT)) {
    console.log("");
    console.log(`  ${change.documentId}`);
    console.log(`    window:            ${windowLabel(change)}`);
    console.log(
      `    period status:     ${change.periodStatus ?? "not finalized"}`
    );
    console.log(`    action:            ${describeAction(change)}`);
    if (change.derivedWorkoutCount !== null) {
      console.log(
        "    eligible workouts behind derived value: " +
        `${change.derivedWorkoutCount}`
      );
    } else {
      console.log("    this window was not derived, so nothing was examined");
    }
    for (const field of COMPARED_FIELDS) {
      const stored = change.stored?.[field] ?? null;
      const derived = change.derived?.[field] ?? null;
      if (stored === derived) {
        continue;
      }
      const delta = typeof stored === "number" && typeof derived === "number" ?
        ` (delta ${roundedValue(derived - stored)})` :
        "";
      console.log(
        `    ${field}: stored ${stored} -> derived ${derived}${delta}`
      );
    }
  }
  printOverflow(closed.length);
}

export function describeAction(change) {
  if (change.kind === "refusedDelete") {
    return "REMOVAL REFUSED (period is finalized)";
  }
  if (change.kind !== "delete") {
    return "REWRITE";
  }
  if (change.reason === "prunedClosedWindow") {
    return "PRUNE (window closed, nothing reads it; not examined)";
  }
  if (change.reason === "unresolvableWindow") {
    return "REMOVE (no derivable period; final)";
  }
  return "REMOVE (window derived, no eligible workouts)";
}

// Node leaves argv[1] unresolved through symlinks while the ESM loader
// realpaths the module URL, so a plain compare makes this whole tool a
// silent no-op that exits 0 whenever it is invoked through a linked path.
if (isEntrypoint()) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

function isEntrypoint() {
  const invoked = process.argv[1];
  if (!invoked) {
    return false;
  }
  try {
    return realpathSync(invoked) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}
