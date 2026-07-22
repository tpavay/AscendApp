#!/usr/bin/env node

/**
 * Backfills the replay-publishable shape onto strict-evidence legacy Live Climb
 * completions, so the Cloud Function's legacy-shape fallback publishes their
 * rows/finishers (h2 Finding 2). It pairs with the CF change: publication is
 * write-driven (onWorkoutReplaySplitsWritten), and legacy backups lack the
 * split curve the CF needs to parse, so this synthesizes a conservative
 * monotonic curve and writes it back onto the private workout, triggering the
 * CF to publish. The CF normalizes the curve and withholds First Ascent for
 * every legacy-recovered row.
 *
 * Strict evidence is the SHARED contract isRecoverableLegacyCompletion:
 * headphone-motion, non-empty climbId, and completed by the policy rule
 * (steps >= target when a target was recorded, else stopReason target_reached).
 * It deliberately NEVER adds a participation - a synthesized eligible
 * participation would let the CF's modern gate claim a First Ascent from
 * hand-derived data, which is permanent and unreclaimable. First Ascent stays
 * off for backfilled rows.
 *
 * Migration-runner discipline (data/design-migration-runner-f4/report.md):
 * dev/staging only, hard-refuses prod, dry-run by default, `_migrations`
 * ledger-gated, idempotent (workouts that already carry split data are skipped,
 * so a second apply plans zero writes). AUTHOR-ONLY in the PR - running it is
 * captain-gated ops, per env, after merge.
 *
 * Usage:
 *   node scripts/backfill-legacy-live-replay-completions.mjs --env dev            # plan (dry-run)
 *   node scripts/backfill-legacy-live-replay-completions.mjs --env dev --apply
 *   node scripts/backfill-legacy-live-replay-completions.mjs --env staging --apply
 *
 * Prerequisites: Node 20+, `cd scripts && npm install`, `gcloud auth application-default login`.
 */

import {FieldValue} from "firebase-admin/firestore";
import {
  resolveEnvironment,
  parseCommonArgs,
  initFirestore,
  beginRun,
} from "./lib/migration-discipline.mjs";
import {
  isRecoverableLegacyCompletionForWorkout,
} from "./lib/legacy-climb-completion.mjs";

const OPERATION_ID = "migration/legacy-live-replay-completions";
const OPERATION_VERSION = 1;
const SPLIT_INTERVAL_SECONDS = 10;
const MAX_SPLIT_CHECKPOINTS = 360;

const args = parseCommonArgs(process.argv);
if (args.rest.has("help")) {
  printUsageAndExit();
}

const environment = resolveEnvironment(args.env);
const db = await initFirestore(environment);

const plan = await planReconstructions(db);
console.log(
  [
    `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
    `Environment: ${environment.env} (${environment.projectId})`,
    `Mode: ${args.apply ? "apply" : "dry-run (plan only)"}`,
    `Workouts scanned: ${plan.scanned}`,
    `Recoverable legacy completions: ${plan.recoverable}`,
    `Already publishable (skipped): ${plan.alreadyPublishable}`,
    `Reconstructions planned: ${plan.reconstructions.length}`,
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
  const written = await applyReconstructions(db, plan.reconstructions);
  const verification = await planReconstructions(db);
  if (verification.reconstructions.length !== 0) {
    throw new Error(
      `Verification found ${verification.reconstructions.length} remaining; ` +
      "the backfill did not converge."
    );
  }
  await run.finish({workoutsReconstructed: written, scanned: plan.scanned});
  console.log(`\nReconstructed ${written} workouts. Verified convergent.`);
} catch (error) {
  await run.fail(error);
  throw error;
}

/**
 * Scans every private workout and plans a split-curve reconstruction for each
 * strict-evidence legacy completion that is not yet replay-publishable.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<{reconstructions: object[], scanned: number, recoverable: number, alreadyPublishable: number}>}
 *   The plan.
 */
async function planReconstructions(firestore) {
  const snapshot = await firestore.collectionGroup("workouts").get();
  const reconstructions = [];
  let recoverable = 0;
  let alreadyPublishable = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const metadata = parseMetadata(data.sourceMetadata);
    if (!metadata) {
      continue;
    }

    if (!isRecoverableLegacyCompletionForWorkout(data, metadata)) {
      continue;
    }
    recoverable += 1;

    // Modern backups already publish through the CF; only touch legacy shapes
    // that lack the split curve and have no climb-attempt participation.
    if (hasSplitCurve(metadata) || hasClimbAttemptParticipation(data)) {
      alreadyPublishable += 1;
      continue;
    }

    reconstructions.push({
      path: doc.ref.path,
      metadata: withSyntheticSplitCurve(metadata, data),
    });
  }

  reconstructions.sort((lhs, rhs) => lhs.path.localeCompare(rhs.path));
  return {
    reconstructions,
    scanned: snapshot.size,
    recoverable,
    alreadyPublishable,
  };
}

/**
 * Writes the reconstructed metadata back onto each workout, triggering the CF.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} reconstructions Planned reconstructions.
 * @return {Promise<number>} Count of workouts written.
 */
async function applyReconstructions(firestore, reconstructions) {
  let written = 0;
  for (const reconstruction of reconstructions) {
    const ref = firestore.doc(reconstruction.path);
    const snapshot = await ref.get();
    const metadata = parseMetadata(snapshot.get("sourceMetadata"));
    if (!metadata || hasSplitCurve(metadata)) {
      continue; // Converged already (concurrent run or rerun).
    }

    await ref.update({
      sourceMetadata: JSON.stringify(reconstruction.metadata),
      updatedAt: FieldValue.serverTimestamp(),
    });
    written += 1;
  }
  return written;
}

/**
 * Builds a conservative monotonic split curve for a legacy completion. The CF
 * re-normalizes it; this only needs to be a valid, monotonic, non-empty curve
 * ending at the workout's final steps.
 * @param {Record<string, unknown>} metadata Parsed metadata.
 * @param {Record<string, unknown>} data Workout data.
 * @return {Record<string, unknown>} Metadata carrying the synthetic curve.
 */
function withSyntheticSplitCurve(metadata, data) {
  const finalSteps = Math.max(integerValue(data.steps) ?? 0, 0);
  const durationSeconds = Math.max(
    Math.round(numberValue(data.durationSeconds) ?? 0),
    SPLIT_INTERVAL_SECONDS
  );
  const bucketCount = Math.min(
    Math.floor(durationSeconds / SPLIT_INTERVAL_SECONDS) + 1,
    MAX_SPLIT_CHECKPOINTS
  );

  const splitSteps = [];
  let lastStep = 0;
  for (let index = 0; index < bucketCount; index += 1) {
    const elapsed = index * SPLIT_INTERVAL_SECONDS;
    const progress = Math.min(elapsed / durationSeconds, 1);
    const projected = index === bucketCount - 1 ?
      finalSteps :
      Math.round(finalSteps * progress);
    lastStep = Math.min(Math.max(projected, lastStep), finalSteps);
    splitSteps.push(lastStep);
  }
  splitSteps[splitSteps.length - 1] = finalSteps;

  return {
    ...metadata,
    splitIntervalSeconds: SPLIT_INTERVAL_SECONDS,
    splitSteps,
  };
}

/**
 * Parses source metadata JSON.
 * @param {unknown} value Raw sourceMetadata value.
 * @return {Record<string, unknown> | null} Parsed metadata.
 */
function parseMetadata(value) {
  if (typeof value !== "string") {
    return null;
  }
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

/**
 * Whether metadata already carries a usable split curve.
 * @param {Record<string, unknown>} metadata Parsed metadata.
 * @return {boolean} True when a split curve is present.
 */
function hasSplitCurve(metadata) {
  return Array.isArray(metadata.splitSteps) &&
    metadata.splitSteps.length > 0 &&
    (integerValue(metadata.splitIntervalSeconds) ?? 0) > 0;
}

/**
 * Whether the workout carries any climb-attempt participation.
 * @param {Record<string, unknown>} data Workout data.
 * @return {boolean} True when a climb-attempt participation is present.
 */
function hasClimbAttemptParticipation(data) {
  return Array.isArray(data.participations) &&
    data.participations.some(
      (item) => item && typeof item === "object" &&
        item.contextType === "climb_attempt"
    );
}

function printUsageAndExit() {
  console.log(`
Backfills replay-publishable split curves onto legacy Live Climb completions.

Usage:
  node scripts/backfill-legacy-live-replay-completions.mjs --env dev
  node scripts/backfill-legacy-live-replay-completions.mjs --env dev --apply
  node scripts/backfill-legacy-live-replay-completions.mjs --env staging --apply

Options:
  --env <dev|staging>   Required. Production is refused.
  --apply               Write documents (default is dry-run plan only).
  --rerun               Apply again after a prior success (body is idempotent).
`);
  process.exit(0);
}

/**
 * Parses a finite number.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed number.
 */
function numberValue(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * Parses a non-negative integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer.
 */
function integerValue(value) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ?
    value :
    null;
}
