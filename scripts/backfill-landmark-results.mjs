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
 * through the same transaction and validate-before-write guard, so the live
 * trigger, a rerun, and this backfill all converge on byte-identical docs ->
 * idempotent, no duplicates or stale-plan overwrites.
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
 * Version 2 also scans stored projection identities, allowing an authorized run
 * to delete an orphaned result left by the pre-fix race.
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
  recomputeLandmarkResult,
  shouldSkipLandmarkResultWrite,
} from "./lib/landmark-result-derivation.mjs";
import {HEADPHONE_MOTION_SOURCE} from "./lib/legacy-climb-completion.mjs";

const OPERATION_ID = "migration/landmark-results";
const OPERATION_VERSION = 2;

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
    `Stored landmark results scanned: ${plan.storedResultCount}`,
    `Canonical landmark results: ${plan.canonicalResultCount}`,
    `Candidate reconciliations: ${plan.candidates.length}`,
    `Writes needed: ${plan.pendingWrites}`,
    `Deletes needed: ${plan.pendingDeletes}`,
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
  const applied = await applyMaterializations(db, plan.candidates);
  const verification = await planMaterializations(db);
  if (
    verification.pendingWrites !== 0 ||
    verification.pendingDeletes !== 0
  ) {
    throw new Error(
      `Verification found ${verification.pendingWrites} pending writes and ` +
      `${verification.pendingDeletes} pending deletes; ` +
      "the backfill did not converge."
    );
  }
  await run.finish({
    landmarkResultsWritten: applied.written,
    landmarkResultsDeleted: applied.deleted,
    candidateReconciliations: plan.candidates.length,
    canonicalLandmarkResults: plan.canonicalResultCount,
    scanned: plan.scanned,
  });
  console.log(
    `\nWrote ${applied.written} and deleted ${applied.deleted} ` +
    "landmarkResults. Verified convergent."
  );
} catch (error) {
  await run.fail(error);
  throw error;
}

/**
 * Scans canonical workouts and stored landmark results. The union of their
 * user/climb identities is the repair set: canonical-only identities need a
 * write, stored-only identities need deletion, and shared identities reconcile.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<{candidates: object[], scanned: number, userCount: number,
 *   storedResultCount: number, canonicalResultCount: number,
 *   pendingWrites: number, pendingDeletes: number}>}
 *   The plan.
 */
async function planMaterializations(firestore) {
  const [snapshot, storedResultsSnapshot] = await Promise.all([
    firestore.collectionGroup("workouts").get(),
    firestore.collectionGroup("landmarkResults").get(),
  ]);
  const workouts = [];
  for (const doc of snapshot.docs) {
    const userId = doc.ref.parent.parent?.id;
    if (!userId) {
      continue;
    }
    workouts.push({userId, workoutId: doc.id, data: doc.data()});
  }

  const byUser = groupCompletions(workouts);
  const candidatesByKey = new Map();
  for (const [userId, byClimb] of byUser) {
    for (const [climbId, completions] of byClimb) {
      const projection = deriveLandmarkResult(climbId, completions);
      if (projection) {
        const item = {userId, climbId, projection, existing: null};
        candidatesByKey.set(candidateKey(item), item);
      }
    }
  }

  for (const document of storedResultsSnapshot.docs) {
    const userReference = document.ref.parent.parent;
    if (!userReference || userReference.parent.id !== "users") {
      continue;
    }
    const identity = {userId: userReference.id, climbId: document.id};
    const key = candidateKey(identity);
    const existingItem = candidatesByKey.get(key);
    candidatesByKey.set(key, {
      ...identity,
      projection: existingItem?.projection ?? null,
      existing: normalizeStoredProjection(identity, document),
    });
  }

  const candidates = [...candidatesByKey.values()];
  candidates.sort((lhs, rhs) => (
    lhs.userId.localeCompare(rhs.userId) ||
    lhs.climbId.localeCompare(rhs.climbId)
  ));

  let pendingWrites = 0;
  let pendingDeletes = 0;
  for (const item of candidates) {
    if (!item.projection) {
      pendingDeletes += 1;
    } else if (
      !shouldSkipLandmarkResultWrite(item.existing, item.projection)
    ) {
      pendingWrites += 1;
    }
  }

  return {
    candidates,
    scanned: snapshot.size,
    userCount: byUser.size,
    storedResultCount: storedResultsSnapshot.size,
    canonicalResultCount: [...candidatesByKey.values()]
      .filter((item) => item.projection !== null).length,
    pendingWrites,
    pendingDeletes,
  };
}

/**
 * Atomically reconciles each planned projection from the current workouts.
 * The plan identifies candidate user/climb pairs only. Re-deriving inside the
 * transaction prevents a stale plan from overwriting a concurrent live trigger.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} candidates Planned user/climb identities.
 * @return {Promise<{written: number, deleted: number}>} Mutation counts.
 */
async function applyMaterializations(firestore, candidates) {
  let written = 0;
  let deleted = 0;
  const store = makeTransactionalStore(firestore);
  for (const item of candidates) {
    const outcome = await recomputeLandmarkResult(
      store,
      item.userId,
      item.climbId
    );
    if (outcome === "written") {
      written += 1;
    } else if (outcome === "deleted") {
      deleted += 1;
    }
  }
  return {written, deleted};
}

/**
 * Adapts the Admin SDK to the shared transactional derivation boundary.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {object} Transactional landmark-result store.
 */
function makeTransactionalStore(firestore) {
  return {
    async runTransaction(operation) {
      return firestore.runTransaction(async (transaction) => operation({
        async listUserWorkouts(userId) {
          // Narrowed to the only source the derivation can accept, matching the
          // Cloud Function so both keep the same transactional lock range.
          const query = firestore
            .collection("users")
            .doc(userId)
            .collection("workouts")
            .where("source", "==", HEADPHONE_MOTION_SOURCE);
          const snapshot = await transaction.get(query);
          return snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()}));
        },
        async getLandmarkResult(userId, climbId) {
          const item = {userId, climbId};
          const snapshot = await transaction.get(
            landmarkResultRef(firestore, item)
          );
          return {
            exists: snapshot.exists,
            projection: normalizeStoredProjection(item, snapshot),
          };
        },
        async writeLandmarkResult(userId, climbId, projection) {
          transaction.set(
            landmarkResultRef(firestore, {userId, climbId}),
            toFirestoreProjection(projection)
          );
        },
        async deleteLandmarkResult(userId, climbId) {
          transaction.delete(
            landmarkResultRef(firestore, {userId, climbId})
          );
        },
      }));
    },
  };
}

/**
 * Normalizes a stored snapshot into the derivation's comparable millis shape.
 * @param {{climbId: string}} item Projection identity.
 * @param {FirebaseFirestore.DocumentSnapshot} snapshot Stored document.
 * @return {object|null} Comparable projection.
 */
function normalizeStoredProjection(item, snapshot) {
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
 * Builds a collision-safe in-memory key for one user/climb identity.
 * @param {{userId: string, climbId: string}} item Projection identity.
 * @return {string} Candidate map key.
 */
function candidateKey(item) {
  return JSON.stringify([item.userId, item.climbId]);
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
