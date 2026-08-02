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
 * Usage:
 *   node scripts/backfill-leaderboard-stats.mjs --project dev --dry-run
 *   node scripts/backfill-leaderboard-stats.mjs --project dev
 *   node scripts/backfill-leaderboard-stats.mjs --project staging --dry-run --verbose
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
const COMPARED_FIELDS = [
  "totalSteps",
  "totalFloors",
  "totalWorkouts",
  "totalDuration",
  "stepsPerMinute",
];

function parseArgs(argv) {
  const args = {project: null, dryRun: false, verbose: false};

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--dry-run") args.dryRun = true;
    else if (value === "--verbose") args.verbose = true;
    else if (value === "--help" || value === "-h") args.help = true;
    else throw new Error(`Unknown argument: ${value}`);
  }

  if (!args.help && !args.project) {
    throw new Error("--project is required (e.g. --project dev)");
  }
  return args;
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

Run the dry run first and read the deltas. A row that changes is a row whose
published total did not match the workouts behind it.
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
    admin: requireFromFunctions("firebase-admin"),
  };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    return;
  }

  const {derivation, admin} = loadDerivation();
  const projectId = resolveProjectId(args.project, REPO_ROOT);
  assertSeedableProject(projectId, "backfill");

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
  const db = admin.firestore();
  const now = new Date();

  console.log(`Project: ${projectId}`);
  console.log(`Mode: ${args.dryRun ? "dry run" : "APPLY"}`);
  console.log(`Reference instant: ${now.toISOString()}`);

  const userIds = await leaderboardUserIds(db);
  console.log(`Climbers with a standing or a workout: ${userIds.length}`);

  const report = {
    changed: [],
    deleted: [],
    unchanged: 0,
    syntheticSkipped: 0,
  };

  for (const userId of userIds) {
    const store = makeReportingStore(db, derivation, userId, args.dryRun);
    const outcome = await derivation.reconcileLeaderboardStats(
      store,
      userId,
      now
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

  printReport(report, args);

  if (args.dryRun) {
    console.log("\nDry run: nothing was written.");
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
function makeReportingStore(db, derivation, userId, dryRun) {
  const adminStore = derivation.makeAdminLeaderboardStatsStore();
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
            if (delta === null) {
              changes.push({kind: "unchanged", userId, documentId});
            } else {
              changes.push({kind: "write", userId, documentId, delta});
            }
            if (!dryRun) {
              await transaction.write(documentId, data);
            }
          },
          async delete(documentId) {
            changes.push({
              kind: "delete",
              userId,
              documentId,
              before: summarize(existingById.get(documentId)),
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

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
