#!/usr/bin/env node

/**
 * Promotes sourceMetadata.climbId onto existing private workout documents so
 * landmarkResults recomputes can use the indexed source + climbId query.
 *
 * Run the index deployment first, apply this migration second, and deploy the
 * narrowed Cloud Function third. The script is dry-run by default, idempotent,
 * ledger-recorded, and requires the exact project id to target production.
 * Every remote apply remains a captain-gated operation.
 *
 * Usage:
 *   node scripts/backfill-workout-climb-ids.mjs --env dev
 *   node scripts/backfill-workout-climb-ids.mjs --env dev --apply
 */

import {
  beginRun,
  initFirestore,
  parseCommonArgs,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {promotedWorkoutClimbId} from "./lib/workout-query-fields.mjs";

const OPERATION_ID = "migration/workout-climb-query-fields";
const OPERATION_VERSION = 1;
const BATCH_WRITE_LIMIT = 450;

const args = parseCommonArgs(process.argv);
if (args.rest.has("help")) {
  printUsageAndExit();
}

const environment = resolveEnvironment(args.env, {
  allowProduction: true,
  productionConfirmation: args.rest.get("confirm-production"),
});
const db = await initFirestore(environment);
const plan = await planPromotions(db);

console.log([
  `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
  `Environment: ${environment.env} (${environment.projectId})`,
  `Mode: ${args.apply ? "apply" : "dry-run (plan only)"}`,
  `Workout documents scanned: ${plan.scanned}`,
  `Workout climb ids already promoted: ${plan.current}`,
  `Workout climb ids to promote: ${plan.pending.length}`,
].join("\n"));

if (!args.apply) {
  console.log("\nDry-run only. Re-run with --apply to write these fields.");
  process.exit(0);
}

const run = await beginRun(db, {
  operationId: OPERATION_ID,
  operationVersion: OPERATION_VERSION,
  environment,
  rerun: args.rerun,
});

try {
  await applyPromotions(db, plan.pending);
  const verification = await planPromotions(db);
  if (verification.pending.length !== 0) {
    throw new Error(
      `Verification found ${verification.pending.length} workout climb ids ` +
      "still pending."
    );
  }
  await run.finish({
    scanned: plan.scanned,
    workoutClimbIdsPromoted: plan.pending.length,
  });
  console.log(`\nPromoted ${plan.pending.length} workout climb ids. Verified.`);
} catch (error) {
  await run.fail(error);
  throw error;
}

/**
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<{scanned: number, current: number, pending: object[]}>}
 */
async function planPromotions(firestore) {
  const snapshot = await firestore.collectionGroup("workouts").get();
  const pending = [];
  let current = 0;

  for (const document of snapshot.docs) {
    const userReference = document.ref.parent.parent;
    if (!userReference || userReference.parent.id !== "users") {
      continue;
    }
    const data = document.data();
    const climbId = promotedWorkoutClimbId(data);
    if (!climbId) {
      continue;
    }
    if (data.climbId === climbId) {
      current += 1;
      continue;
    }
    pending.push({reference: document.ref, climbId});
  }

  return {scanned: snapshot.size, current, pending};
}

/**
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {{reference: FirebaseFirestore.DocumentReference, climbId: string}[]} pending
 *   Planned promotions.
 */
async function applyPromotions(firestore, pending) {
  for (let offset = 0; offset < pending.length; offset += BATCH_WRITE_LIMIT) {
    const batch = firestore.batch();
    for (const item of pending.slice(offset, offset + BATCH_WRITE_LIMIT)) {
      batch.set(item.reference, {climbId: item.climbId}, {merge: true});
    }
    await batch.commit();
  }
}

function printUsageAndExit() {
  console.log(`
Promotes sourceMetadata.climbId to an indexed workout field.

Usage:
  node scripts/backfill-workout-climb-ids.mjs --env dev
  node scripts/backfill-workout-climb-ids.mjs --env dev --apply
  node scripts/backfill-workout-climb-ids.mjs --env staging --apply
  node scripts/backfill-workout-climb-ids.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply

Options:
  --env <dev|staging|prod>  Required named environment.
  --confirm-production <id> Required for prod; must equal ascend-prod-9c8f2.
  --apply               Write fields (default is dry-run plan only).
  --rerun               Apply again after a prior successful run.
`);
  process.exit(0);
}
