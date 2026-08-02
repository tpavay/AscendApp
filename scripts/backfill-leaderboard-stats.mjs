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
 * Usage:
 *   node scripts/backfill-leaderboard-stats.mjs --project dev --dry-run
 *   node scripts/backfill-leaderboard-stats.mjs --project dev
 *   node scripts/backfill-leaderboard-stats.mjs --project staging --dry-run --verbose
 *   node scripts/backfill-leaderboard-stats.mjs --project staging --dry-run --include-closed-periods
 */

import {createRequire} from "node:module";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {existsSync} from "node:fs";

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

export function parseArgs(argv) {
  const args = {
    project: null,
    dryRun: false,
    verbose: false,
    // Widening ownership to closed periods puts the rows the nightly finalizer
    // reads in reach of a rewrite, so it never happens because someone forgot a
    // flag - only because they passed one.
    includeClosedPeriods: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--dry-run") args.dryRun = true;
    else if (value === "--verbose") args.verbose = true;
    else if (value === "--include-closed-periods") {
      args.includeClosedPeriods = true;
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

  const userIds = await leaderboardUserIds(db);
  console.log(`Climbers with a standing or a workout: ${userIds.length}`);

  const report = {
    changed: [],
    deleted: [],
    unchanged: 0,
    syntheticSkipped: 0,
  };

  for (const userId of userIds) {
    const store = makeReportingStore(
      db,
      derivation,
      period,
      userId,
      now,
      args.dryRun
    );
    const outcome = await derivation.reconcileLeaderboardStats(
      store,
      userId,
      now,
      {ownership}
    );
    report.syntheticSkipped += outcome.skippedSynthetic.length;

    for (const change of store.changes) {
      if (change.kind === "unchanged") {
        report.unchanged += 1;
        continue;
      }
      report[change.kind === "delete" ? "deleted" : "changed"].push(change);
    }
  }

  await annotateFinalizationStatus(db, report);
  printReport(report, args);

  if (args.dryRun) {
    console.log("\nDry run: nothing was written.");
  }
}

/**
 * Marks each closed-period change with the finalization status of its period.
 *
 * A repair only rewrites the standing. If the period is already finalized the
 * achievement was minted from the old number and is still sitting in
 * users/{uid}/achievements, so the operator has to be told the difference rather
 * than left to assume the repair covered it.
 */
async function annotateFinalizationStatus(db, report) {
  const closed = [...report.changed, ...report.deleted].filter(
    (change) => change.closed && change.timeFrame && change.periodKey
  );
  const periodIds = new Set(
    closed.map((change) => `${change.timeFrame}_${change.periodKey}`)
  );
  const statuses = new Map();

  for (const periodId of periodIds) {
    const snapshot = await db
      .collection(LEADERBOARD_PERIODS_COLLECTION)
      .doc(periodId)
      .get();
    statuses.set(periodId, snapshot.get("status") ?? "not finalized");
  }

  for (const change of closed) {
    change.periodStatus = statuses.get(
      `${change.timeFrame}_${change.periodKey}`
    );
  }
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
function makeReportingStore(db, derivation, period, userId, now, dryRun) {
  const adminStore = derivation.makeAdminLeaderboardStatsStore();
  const openIds = derivation.openPeriodDocumentIds(userId, now);
  const changes = [];
  let existingById = new Map();

  return {
    changes,
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
            const change = {
              kind: delta === null ? "unchanged" : "write",
              userId,
              documentId,
              delta,
              stored: summarize(before),
              derived: summarize(data),
              derivedWorkoutCount: numberOrNull(data.totalWorkouts) ?? 0,
              ...describeWindow(period, data, before, documentId, openIds),
            };
            changes.push(change);
            if (!dryRun) {
              await transaction.write(documentId, data);
            }
          },
          async delete(documentId) {
            const before = existingById.get(documentId);
            changes.push({
              kind: "delete",
              userId,
              documentId,
              before: summarize(before),
              stored: summarize(before),
              derived: null,
              // Nothing was derived for this window, which is the whole reason
              // the row is going.
              derivedWorkoutCount: 0,
              ...describeWindow(period, undefined, before, documentId, openIds),
            });
            if (!dryRun) {
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

  if (timeFrame === null || startMillis === null) {
    return {
      timeFrame,
      periodKey: typeof source.periodKey === "string" ?
        source.periodKey :
        null,
      windowStart: null,
      windowEnd: null,
      closed,
    };
  }

  const window = period.currentPeriod(timeFrame, new Date(startMillis));
  return {
    timeFrame,
    periodKey: window.key,
    windowStart: window.startAt,
    windowEnd: window.endAt,
    closed,
  };
}

function timestampMillis(value) {
  if (value && typeof value === "object") {
    if (typeof value.toMillis === "function") return value.toMillis();
    if (typeof value.getTime === "function") return value.getTime();
  }
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function numberOrNull(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
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

function printReport(report, args) {
  console.log("");
  console.log(`Rows already correct:      ${report.unchanged}`);
  console.log(`Rows rewritten:            ${report.changed.length}`);
  console.log(`Rows removed (no workouts): ${report.deleted.length}`);
  console.log(`Seeded rows left alone:    ${report.syntheticSkipped}`);

  const closed = [...report.changed, ...report.deleted]
    .filter((change) => change.closed);
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
  printClosedPeriodDetail(closed);

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
    for (const change of inflated.slice(0, 20)) {
      const steps = change.delta.fields.totalSteps;
      console.log(
        `  ${change.documentId}: ${steps.before} -> ${steps.after}`
      );
    }
    if (inflated.length > 20) {
      console.log(`  ... and ${inflated.length - 20} more`);
    }
  }

  if (report.deleted.length > 0) {
    console.log("");
    console.log("Removed standings:");
    for (const change of report.deleted.slice(0, 20)) {
      console.log(
        `  ${change.documentId}: was ${JSON.stringify(change.before)}`
      );
    }
    if (report.deleted.length > 20) {
      console.log(`  ... and ${report.deleted.length - 20} more`);
    }
  }

  if (args.verbose) {
    console.log("");
    console.log("Every rewritten row:");
    for (const change of report.changed) {
      console.log(`  ${change.documentId}: ${JSON.stringify(change.delta)}`);
    }
  }
}

/**
 * Prints enough about each closed-period row to tell forgery from drift.
 *
 * Zero eligible workouts behind a large stored total is the signature of a row
 * a client wrote. A small delta with real workouts behind it is a legitimate row
 * that drifted. Nobody should have to guess which one they are approving.
 */
function printClosedPeriodDetail(closed) {
  if (closed.length === 0) {
    return;
  }

  console.log("");
  console.log(`Closed-period rows this run would touch: ${closed.length}`);
  console.log(
    "Repairing a row does NOT unwind an achievement already minted from the " +
    "old number. Any row below whose period reads 'finalized' needs the award " +
    "in users/{uid}/achievements looked at separately."
  );

  for (const change of closed) {
    console.log("");
    console.log(`  ${change.documentId}`);
    console.log(`    window:            ${windowLabel(change)}`);
    console.log(
      `    period status:     ${change.periodStatus ?? "not finalized"}`
    );
    console.log(
      `    action:            ${change.kind === "delete" ?
        "REMOVE (no eligible workouts in this window)" :
        "REWRITE"}`
    );
    console.log(
      `    eligible workouts behind derived value: ` +
      `${change.derivedWorkoutCount}`
    );
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
}

if (resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
