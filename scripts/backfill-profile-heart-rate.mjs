#!/usr/bin/env node

/**
 * Backfills the heart-rate aggregates on every published profile:
 * `average_heart_rate_bpm` and `max_heart_rate_bpm` on `users/{uid}/profile_stats/current`.
 *
 * The iOS app derives and publishes them itself (`ProfileHeartRateSummary`) each time it
 * republishes a profile, so a climber on a build that knows the fields fills their own. This
 * covers everyone else: a climber whose installed build predates the fields, or who has not
 * opened the app since. Each climber's numbers are derived from their own synced workouts
 * (`users/{uid}/workouts`) by `scripts/lib/profile-heart-rate.mjs`, which is pinned to the
 * app's derivation by `SharedTestVectors/profile-heart-rate-summary-vector.json`.
 *
 * Only the two aggregates are written, and only onto a `profile_stats` document that already
 * exists: this never publishes a profile a climber has not published, and never copies a
 * sample or a per-climb heart rate anywhere cross-account.
 *
 * Run it only where `firestore.rules` already lists the two fields. `profile_stats` rules
 * validate the merged document with `hasOnly`, so a field written here onto an environment
 * running older rules would make every later publication from that climber fail - old builds
 * included. `docs/production-backend-rollout-runbook.md` owns the order, and `--apply` reads the
 * deployed Firestore ruleset first and refuses when it does not name both fields.
 *
 * Idempotent: a climber whose published fields already equal the derivation is left alone, so
 * a second run writes nothing and says so. A climber with no heart rate left has any published
 * aggregate removed rather than kept. Dry-run by default; `--apply` writes, gated by the
 * `_migrations` ledger (`scripts/lib/migration-discipline.mjs`). Production is refused unless
 * the exact project id is confirmed, and running it there is the captain's call.
 *
 * Usage:
 *   node scripts/backfill-profile-heart-rate.mjs --env dev
 *   node scripts/backfill-profile-heart-rate.mjs --env staging --apply
 *   node scripts/backfill-profile-heart-rate.mjs --env prod --confirm-production ascend-prod-9c8f2
 *
 * Prerequisites:
 *   Node.js 20+
 *   npm --prefix scripts ci
 *   gcloud auth application-default login
 *
 * The planning half is exported so scripts/test can run it against fixtures without a
 * Firestore; the run itself starts only when this file is the entrypoint.
 */

import {
  createBatchWriter,
  createProgressReporter,
  runPool,
  withRetry,
} from "./lib/firestore-bulk.mjs";
import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {
  beginRun,
  initFirestore,
  parseCommonArgs,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {
  PROFILE_HEART_RATE_FIELDS,
  deriveProfileHeartRateFromWorkoutDocuments,
} from "./lib/profile-heart-rate.mjs";

const OPERATION_ID = "migration/profile-heart-rate-aggregates";
const OPERATION_VERSION = 1;
const READ_CONCURRENCY = 32;

/** Marks a field the plan removes; the apply turns it into `FieldValue.delete()`. */
export const DELETE_FIELD = Symbol("delete-field");

if (isEntrypoint(import.meta.url)) {
  await main();
}

async function main() {
  const args = parseCommonArgs(process.argv);
  if (args.rest.has("help")) {
    printUsage();
    return;
  }

  const environment = resolveEnvironment(args.env, {
    allowProduction: true,
    productionConfirmation: args.rest.get("confirm-production"),
  });
  const db = await initFirestore(environment);
  const rulesAllowFields = deployedRulesAllowHeartRate(await readDeployedFirestoreRules());
  const climbers = await readClimbers(db);
  const plan = planProfileHeartRateBackfill(climbers.read);

  console.log([
    `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
    `Environment: ${environment.env} (${environment.projectId})`,
    `Mode: ${args.apply ? "apply" : "dry-run (plan only)"}`,
    `Published profiles scanned: ${climbers.read.length}`,
    `Profiles already current: ${plan.current}`,
    `Profiles to update: ${plan.updates.length}`,
    `  gaining heart rate: ${plan.updates.filter((update) => update.kind === "publish").length}`,
    `  changing heart rate: ${plan.updates.filter((update) => update.kind === "change").length}`,
    `  losing heart rate: ${plan.updates.filter((update) => update.kind === "clear").length}`,
    `Profiles that could not be read: ${climbers.failed.length}`,
    `Deployed rules accept the fields: ${rulesAllowFields ? "yes" : "NO"}`,
  ].join("\n"));
  for (const failure of climbers.failed) {
    console.log(`  ${failure.userId}: ${failure.message}`);
  }

  if (climbers.failed.length > 0) {
    // A climber skipped would read as backfilled on the ledger, so a partial read is a failure.
    process.exitCode = 1;
  }

  if (!args.apply) {
    console.log("\nDry-run only. Re-run with --apply to write these fields.");
    return;
  }
  if (climbers.failed.length > 0) {
    throw new Error("Refusing to apply while any profile could not be read.");
  }
  if (!rulesAllowFields) {
    throw new Error(
      "Refusing to apply: the deployed Firestore rules do not list the heart-rate fields, so " +
      "writing them would make every later profile publication fail. Deploy firestore:rules first."
    );
  }

  const run = await beginRun(db, {
    operationId: OPERATION_ID,
    operationVersion: OPERATION_VERSION,
    environment,
    rerun: args.rerun,
  });

  try {
    await applyUpdates(db, plan.updates);
    const verification = planProfileHeartRateBackfill((await readClimbers(db)).read);
    if (verification.updates.length !== 0) {
      throw new Error(`Verification found ${verification.updates.length} profiles still pending.`);
    }
    await run.finish({
      scanned: climbers.read.length,
      profilesUpdated: plan.updates.length,
    });
    console.log(`\nUpdated ${plan.updates.length} profiles. Verified.`);
  } catch (error) {
    await run.fail(error);
    throw error;
  }
}

/**
 * Decides which published profiles need their heart-rate aggregates written.
 * @param {{userId: string, stats: object, workouts: object[]}[]} climbers
 *   Each climber's published `profile_stats` data and their private workout documents.
 * @return {{current: number, updates: {userId: string, kind: string, fields: object}[]}}
 */
export function planProfileHeartRateBackfill(climbers) {
  let current = 0;
  const updates = [];

  for (const climber of climbers) {
    const derived = deriveProfileHeartRateFromWorkoutDocuments(climber.workouts);
    const fields = {};
    for (const [key, field] of Object.entries(PROFILE_HEART_RATE_FIELDS)) {
      const published = climber.stats[field] ?? null;
      const wanted = derived[key];
      if (published === wanted) continue;
      fields[field] = wanted === null ? DELETE_FIELD : wanted;
    }

    if (Object.keys(fields).length === 0) {
      current += 1;
      continue;
    }

    const hadAny = Object.values(PROFILE_HEART_RATE_FIELDS)
      .some((field) => (climber.stats[field] ?? null) !== null);
    const willHaveAny = derived.averageBpm !== null || derived.maxBpm !== null;
    const kind = !hadAny ? "publish" : willHaveAny ? "change" : "clear";
    updates.push({userId: climber.userId, kind, fields});
  }

  return {current, updates};
}

/**
 * Whether a deployed `firestore.rules` source lets `profile_stats` carry both aggregates.
 * @param {string} rulesSource The deployed ruleset's source.
 * @return {boolean} True when both field names are listed.
 */
export function deployedRulesAllowHeartRate(rulesSource) {
  return Object.values(PROFILE_HEART_RATE_FIELDS)
    .every((field) => rulesSource.includes(`"${field}"`));
}

async function readDeployedFirestoreRules() {
  const {getSecurityRules} = await import("firebase-admin/security-rules");
  const ruleset = await withRetry(
    () => getSecurityRules().getFirestoreRuleset(),
    {description: "read the deployed Firestore ruleset"}
  );
  return ruleset.source.map((file) => file.content).join("\n");
}

async function readClimbers(db) {
  const statsSnapshot = await withRetry(
    () => db.collectionGroup("profile_stats").get(),
    {description: "collectionGroup(profile_stats)"}
  );
  const statsDocuments = statsSnapshot.docs.filter((document) =>
    document.id === "current" && document.ref.parent.parent?.parent.id === "users"
  );
  const progress = createProgressReporter({
    label: "read workouts",
    total: statsDocuments.length,
    unit: "climbers",
  });
  const read = [];
  const failed = [];

  await runPool(statsDocuments, READ_CONCURRENCY, async (document) => {
    const userRef = document.ref.parent.parent;
    try {
      const workouts = await withRetry(
        () => userRef.collection("workouts")
          .select("durationSeconds", "avgHeartRateBpm", "maxHeartRateBpm")
          .get(),
        {
          description: `read ${userRef.path}/workouts`,
          onRetry: () => progress.retried(),
        }
      );
      read.push({
        userId: userRef.id,
        stats: document.data(),
        workouts: workouts.docs.map((workout) => workout.data()),
      });
    } catch (error) {
      // Logged the moment it happens, and named again in the summary.
      console.error(`Could not read ${userRef.path}: ${error.message}`);
      failed.push({userId: userRef.id, message: error.message});
    }
    progress.advance(1);
  });

  progress.finish();
  return {read, failed};
}

async function applyUpdates(db, updates) {
  const {FieldValue} = await import("firebase-admin/firestore");
  const progress = createProgressReporter({
    label: "write heart rate",
    total: updates.length,
    unit: "profiles",
  });
  const writer = createBatchWriter(db, {progress});

  for (const update of updates) {
    const data = {};
    for (const [field, value] of Object.entries(update.fields)) {
      data[field] = value === DELETE_FIELD ? FieldValue.delete() : value;
    }
    writer.update(
      db.collection("users").doc(update.userId).collection("profile_stats").doc("current"),
      data
    );
  }

  await writer.drain();
  progress.finish();
}

function printUsage() {
  console.log([
    "Usage: node scripts/backfill-profile-heart-rate.mjs --env <dev|staging|prod> [--apply] [--rerun]",
    "       [--confirm-production ascend-prod-9c8f2]",
    "",
    "Dry-run by default. --apply writes average_heart_rate_bpm / max_heart_rate_bpm onto",
    "existing profile_stats documents from each climber's synced workouts.",
  ].join("\n"));
}
