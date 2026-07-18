#!/usr/bin/env node

/**
 * Materializes the server-derived `landmarkResults` projection for existing
 * users FROM their durable private workouts (Phase 1 · Slice 1, Change 6).
 *
 * The canonical record of a completed climb is the private `Workout` (1:1 with
 * the completion). This backfill runs the SAME derivation the live Cloud
 * Function runs (scripts/lib/landmark-result-derivation.mjs mirrors
 * functions/src/climbCompletions.ts) over each user's completed landmark
 * workouts and writes `users/{uid}/landmarkResults/{climbId}`. It is the
 * migration trigger of the one Projection Builder (CANONICAL §1), and it goes
 * through the same validate-before-write guard, so the live trigger, a rerun,
 * and this backfill all converge on byte-identical docs -> idempotent, no
 * duplicates.
 *
 * Completion evidence is the SHARED, vector-pinned contract
 * isRecoverableLegacyCompletion (scripts/lib/legacy-climb-completion.mjs) - the
 * same one the client hydration guard, the replay fallback, and the CF use. No
 * fourth copy.
 *
 * Publication-safe: it writes ONLY the private landmarkResults projection. It
 * never writes a replay row, never claims a First Ascent, never synthesizes a
 * synced participation (same boundary as #229). First Ascent stays owned by the
 * live-session-gated replay path.
 *
 * Migration-runner discipline (data/design-migration-runner-f4/report.md):
 * dev/staging only, HARD-refuses prod (ascend-prod-9c8f2) and unknown projects,
 * dry-run by default, `_migrations` ledger-gated, idempotent (a second apply
 * writes nothing). AUTHOR-ONLY in the PR - running it is captain-gated ops, per
 * env, after the rules + CF deploy. Prod is empty, so it is a no-op there.
 *
 * Usage:
 *   node scripts/backfill-landmark-results.mjs --env dev            # plan (dry-run)
 *   node scripts/backfill-landmark-results.mjs --env dev --apply
 *   node scripts/backfill-landmark-results.mjs --env staging --apply
 *
 * Prerequisites: Node 20+, `cd scripts && npm install`,
 * `gcloud auth application-default login`.
 */

import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  resolveEnvironment,
  parseCommonArgs,
  initFirestore,
  beginRun,
} from "./lib/migration-discipline.mjs";
import {
  groupCompletions,
  deriveLandmarkResult,
  shouldSkipLandmarkResultWrite,
} from "./lib/landmark-result-derivation.mjs";

const OPERATION_ID = "migration/landmark-results";
const OPERATION_VERSION = 1;

const args = parseCommonArgs(process.argv);
if (args.rest.has("help")) {
  printUsageAndExit();
}

const environment = resolveEnvironment(args.env);
const db = initFirestore(environment);

const plan = await planMaterializations(db);
console.log(
  [
    `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
    `Environment: ${environment.env} (${environment.projectId})`,
    `Mode: ${args.apply ? "apply" : "dry-run (plan only)"}`,
    `Workouts scanned: ${plan.scanned}`,
    `Users with completions: ${plan.userCount}`,
    `Distinct landmark results: ${plan.projections.length}`,
    `Writes needed (not already materialized): ${plan.pendingWrites}`,
  ].join("\n")
);

if (!args.apply) {
  console.log("\nDry-run only. Re-run with --apply to write these documents.");
  process.exit(0);
}

const run = await beginRun(db, {
  operationId: OPERATION_ID,
  operationVersion: OPERATION_VERSION,
  environment,
  rerun: args.rerun,
});

try {
  const written = await applyMaterializations(db, plan.projections);
  const verification = await planMaterializations(db);
  if (verification.pendingWrites !== 0) {
    throw new Error(
      `Verification found ${verification.pendingWrites} pending writes; ` +
      "the backfill did not converge."
    );
  }
  await run.finish({
    landmarkResultsWritten: written,
    distinctLandmarkResults: plan.projections.length,
    scanned: plan.scanned,
  });
  console.log(`\nWrote ${written} landmarkResults. Verified convergent.`);
} catch (error) {
  await run.fail(error);
  throw error;
}

/**
 * Scans every private workout, groups completed landmark workouts per user and
 * landmark, and derives the projection each one should hold. A projection whose
 * stored doc already reflects it (validate-before-write) is not a pending write.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<{projections: object[], scanned: number, userCount: number, pendingWrites: number}>}
 *   The plan.
 */
async function planMaterializations(firestore) {
  const snapshot = await firestore.collectionGroup("workouts").get();
  const workouts = [];
  for (const doc of snapshot.docs) {
    const userId = doc.ref.parent.parent?.id;
    if (!userId) {
      continue;
    }
    workouts.push({userId, workoutId: doc.id, data: doc.data()});
  }

  const byUser = groupCompletions(workouts);
  const projections = [];
  for (const [userId, byClimb] of byUser) {
    for (const [climbId, completions] of byClimb) {
      const projection = deriveLandmarkResult(climbId, completions);
      if (projection) {
        projections.push({userId, climbId, projection});
      }
    }
  }
  projections.sort((lhs, rhs) => (
    lhs.userId.localeCompare(rhs.userId) ||
    lhs.climbId.localeCompare(rhs.climbId)
  ));

  let pendingWrites = 0;
  for (const item of projections) {
    const existing = await readStoredProjection(firestore, item);
    if (!shouldSkipLandmarkResultWrite(existing, item.projection)) {
      pendingWrites += 1;
    }
  }

  return {
    projections,
    scanned: snapshot.size,
    userCount: byUser.size,
    pendingWrites,
  };
}

/**
 * Writes each planned projection, skipping any already materialized.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} projections Planned projections.
 * @return {Promise<number>} Count of documents written.
 */
async function applyMaterializations(firestore, projections) {
  let written = 0;
  for (const item of projections) {
    const existing = await readStoredProjection(firestore, item);
    if (shouldSkipLandmarkResultWrite(existing, item.projection)) {
      continue; // Already materialized (rerun / concurrent / live trigger).
    }
    await landmarkResultRef(firestore, item).set(
      toFirestoreProjection(item.projection)
    );
    written += 1;
  }
  return written;
}

/**
 * Reads the stored projection and normalizes timestamps back to millis so the
 * shared validate-before-write guard compares like with like.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {{userId: string, climbId: string}} item The plan item.
 * @return {Promise<object|null>} Comparable stored projection.
 */
async function readStoredProjection(firestore, item) {
  const snapshot = await landmarkResultRef(firestore, item).get();
  if (!snapshot.exists) {
    return null;
  }
  const data = snapshot.data();
  return {
    climbId: item.climbId,
    completed: true,
    firstCompletedAtMillis: millis(data.firstCompletedAt),
    latestCompletedAtMillis: millis(data.latestCompletedAt),
    attemptCount: data.attemptCount,
    bestWorkoutId: data.bestWorkoutId,
    bestElapsedSeconds: data.bestElapsedSeconds,
    schemaVersion: data.schemaVersion,
    computedThroughEvent: data.computedThroughEvent,
  };
}

/**
 * Builds the landmark-result document reference.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {{userId: string, climbId: string}} item The plan item.
 * @return {FirebaseFirestore.DocumentReference} The reference.
 */
function landmarkResultRef(firestore, item) {
  return firestore
    .collection("users")
    .doc(item.userId)
    .collection("landmarkResults")
    .doc(item.climbId);
}

/**
 * Converts the comparable (millis) projection into the stored Firestore shape.
 * @param {object} projection Derived projection.
 * @return {Record<string, unknown>} Firestore document data.
 */
function toFirestoreProjection(projection) {
  return {
    climbId: projection.climbId,
    completed: projection.completed,
    firstCompletedAt: Timestamp.fromMillis(projection.firstCompletedAtMillis),
    latestCompletedAt: Timestamp.fromMillis(projection.latestCompletedAtMillis),
    attemptCount: projection.attemptCount,
    bestWorkoutId: projection.bestWorkoutId,
    bestElapsedSeconds: projection.bestElapsedSeconds,
    schemaVersion: projection.schemaVersion,
    computedThroughEvent: projection.computedThroughEvent,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Reads epoch millis from a Firestore Timestamp.
 * @param {unknown} value Raw value.
 * @return {number|null} Epoch millis.
 */
function millis(value) {
  if (value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  return typeof value === "number" ? value : null;
}

/**
 * Prints usage and exits.
 */
function printUsageAndExit() {
  console.log(`
Materializes the landmarkResults projection from durable workouts.

Usage:
  node scripts/backfill-landmark-results.mjs --env dev
  node scripts/backfill-landmark-results.mjs --env dev --apply
  node scripts/backfill-landmark-results.mjs --env staging --apply

Options:
  --env <dev|staging>   Required. Production is refused.
  --apply               Write documents (default is dry-run plan only).
  --rerun               Apply again after a prior success (body is idempotent).
`);
  process.exit(0);
}
