#!/usr/bin/env node

/**
 * Canonicalizes existing dev/staging private workout document ids to uppercase UUIDs.
 *
 * Only groups whose payloads can be merged without conflicting fields are eligible.
 * A payload conflict blocks the entire apply before any workout is changed. The
 * canonical document is written and non-canonical ids are deleted atomically per
 * group; a workout that only exists under a non-canonical id is renamed the same way,
 * so a later app write cannot recreate a case-variant twin. Affected landmarkResults
 * are then rebuilt through the existing shared derivation so removing a non-canonical
 * document cannot leave attemptCount inflated.
 *
 * Renaming a workout moves every id that names it. Live replay rows keyed on the workout
 * id are moved onto the canonical id and the fields that store one - firstAscentWorkoutId,
 * finisher best/first ids, userBestAttempts, publish statuses - are rewritten, so nothing
 * is left pointing at a document this migration deleted. A stale row whose canonical twin
 * already exists is dropped when the payloads agree and otherwise resolved newest-first;
 * a pair with no comparable updatedAt blocks the apply instead of being guessed at, and a
 * non-canonical id with no surviving workout is reported, never rewritten.
 *
 * Writes are chunked, so a run can die with the workout renames committed and the
 * reference repairs or landmarkResults rebuild outstanding. Both the projections and the
 * renames this run owes are recorded on the ledger before the first write and cleared only
 * on success, so the next run folds them back into its own plan and cannot report success
 * on a vacuous verification. Reference repairs are also re-derived from live data - any id
 * still spelled non-canonically whose canonical workout exists is repaired - so a lost
 * ledger cannot strand them either. If a run fails and the operator will not re-run it,
 * `scripts/backfill-landmark-results.mjs` rebuilds the same projections. A carried repair
 * whose climb no longer has any surviving completion is deleted rather than rebuilt - the
 * same disposal onWorkoutWritten applies to that case - so a workout removed between runs
 * cannot wedge the operation.
 *
 * This migration is author-only. Running it is captain-gated operations work.
 *
 * Usage:
 *   node scripts/cleanup-case-variant-workout-ids.mjs --env dev
 *   node scripts/cleanup-case-variant-workout-ids.mjs --env staging
 *   node scripts/cleanup-case-variant-workout-ids.mjs --env staging --apply
 *
 * Dry-run is the default. Production and unknown environments are refused.
 */

import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  beginRun,
  initFirestore,
  parseCommonArgs,
  readPendingRepairs,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {shouldSkipLandmarkResultWrite} from "./lib/landmark-result-derivation.mjs";
import {
  BATCH_WRITE_LIMIT,
  finalWorkoutDocuments,
  matchWorkoutIdReferenceShape,
  packBatchSizes,
  planAffectedLandmarkProjections,
  planCaseVariantWorkoutMerges,
  planWorkoutIdReferenceRenames,
  planWorkoutIdReferenceRepairs,
} from "./lib/workout-id-case-migration.mjs";

const OPERATION_ID = "migration/case-variant-workout-ids";
const OPERATION_VERSION = 2;
const REFERENCE_COLLECTION_GROUPS = Object.freeze([
  "entries",
  "completionSnapshots",
  "finishers",
  "userBestAttempts",
  "liveClimbPublishStatuses",
  "profile_workouts",
]);
const WORKOUT_ID_RENAME_REPAIR_KIND = "workoutIdRename";

const args = parseCommonArgs(process.argv);
if (args.rest.has("help")) {
  printUsageAndExit();
}
if (args.contextKey || args.rest.size > 0) {
  throw new Error("This migration accepts only --env, --apply, --rerun, and --help.");
}

const environment = resolveEnvironment(args.env);
const db = initFirestore(environment);
const documents = await readWorkoutDocuments(db);
const references = await readWorkoutIdReferences(db);
const plan = planCaseVariantWorkoutMerges(documents);
const pendingRepairs = await readPendingRepairs(db, OPERATION_ID);
const carriedRepairs = pendingRepairs.filter(
  (repair) => repair.kind !== WORKOUT_ID_RENAME_REPAIR_KIND
);
const carriedRenames = pendingRepairs.filter(
  (repair) => repair.kind === WORKOUT_ID_RENAME_REPAIR_KIND
);
const deleteCount = plan.merges.reduce((sum, merge) => sum + merge.deleteWorkoutIds.length, 0);
const renames = planWorkoutIdReferenceRenames(
  plan.merges,
  carriedRenames,
  references,
  finalWorkoutDocuments(documents, plan.merges)
);
const referencePlan = planWorkoutIdReferenceRepairs(renames, references);

console.log([
  `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
  `Environment: ${environment.env} (${environment.projectId})`,
  `Mode: ${args.apply ? "apply" : "dry-run (plan only)"}`,
  `Workout documents scanned: ${documents.length}`,
  `Workout-id references scanned: ${references.length}`,
  `Safe canonicalization groups: ${plan.merges.length}`,
  `Blocked conflicting groups: ${plan.conflicts.length}`,
  `Non-canonical documents to delete: ${deleteCount}`,
  `Workout ids to propagate into references: ${renames.length}`,
  `Reference rows to move onto a canonical id: ${referencePlan.moves.length}`,
  `Reference fields to rewrite: ${referencePlan.fieldUpdates.length}`,
  `Blocked conflicting reference rows: ${referencePlan.conflicts.length}`,
  `landmarkResults owed by an earlier unfinished run: ${carriedRepairs.length}`,
  `Workout id renames owed by an earlier unfinished run: ${carriedRenames.length}`,
].join("\n"));

for (const merge of plan.merges) {
  console.log(
    `SAFE ${merge.userId}: ${merge.sourceWorkoutIds.join(", ")} -> ${merge.canonicalWorkoutId}`
  );
  if (merge.droppedFields.length > 0) {
    console.log(
      `  DROPPED fields absent from the newest payload: ${merge.droppedFields.join(", ")}`
    );
  }
}
for (const repair of carriedRepairs) {
  console.log(`CARRIED landmarkResult ${repair.userId}/${repair.climbId}`);
}
for (const rename of carriedRenames) {
  console.log(`CARRIED rename ${rename.workoutId} -> ${rename.canonicalWorkoutId}`);
}
for (const move of referencePlan.moves) {
  console.log(
    `REFERENCE ${move.parentPath}/${move.fromDocumentId} -> ${move.toDocumentId}` +
      `${move.data ? "" : " (canonical row already exists, deleting stale twin)"}`
  );
}
for (const update of referencePlan.fieldUpdates) {
  console.log(
    `REFERENCE FIELD ${update.parentPath}/${update.documentId}: ` +
      Object.entries(update.updates).map(([field, value]) => `${field}=${value}`).join(", ")
  );
}
for (const item of referencePlan.unresolved) {
  console.log(
    `UNRESOLVED ${item.path} references non-canonical ${item.workoutId} ` +
      "with no surviving workout document - left untouched"
  );
}
for (const conflict of plan.conflicts) {
  console.error(
    `BLOCKED ${conflict.userId}: ${conflict.sourceWorkoutIds.join(", ")} ` +
      `conflict in ${conflict.conflictingFields.join(", ")}`
  );
}
for (const conflict of referencePlan.conflicts) {
  console.error(
    `BLOCKED reference ${conflict.path} cannot be reconciled with ${conflict.canonicalPath}`
  );
}

const affectedProjections = planAffectedLandmarkProjections(
  documents,
  plan.merges,
  carriedRepairs
);
const staleProjections = affectedProjections.filter((item) => !item.projection);
const units = buildMigrationUnits(db, plan.merges, referencePlan, affectedProjections);
const batchSizes = packBatchSizes(units.map((unit) => unit.length));
const operationCount = batchSizes.reduce((sum, size) => sum + size, 0);

for (const item of staleProjections) {
  console.log(
    `STALE landmarkResult ${item.userId}/${item.climbId} - no completion remains, will delete`
  );
}
console.log([
  `landmarkResults to rebuild: ${affectedProjections.length - staleProjections.length}`,
  `landmarkResults to delete as stale: ${staleProjections.length}`,
  `Firestore operations: ${operationCount} in ${batchSizes.length} batch(es) of at most ${BATCH_WRITE_LIMIT}`,
].join("\n"));

if (!args.apply) {
  console.log("\nDry-run only. Re-run with --apply after reviewing every planned merge.");
  process.exit(0);
}
if (plan.conflicts.length > 0) {
  throw new Error(
    `Refusing apply: ${plan.conflicts.length} case-variant group(s) contain conflicting payloads.`
  );
}
if (referencePlan.conflicts.length > 0) {
  throw new Error(
    `Refusing apply: ${referencePlan.conflicts.length} replay reference row(s) cannot be ` +
      "reconciled with the canonical row they would move onto."
  );
}

const run = await beginRun(db, {
  operationId: OPERATION_ID,
  operationVersion: OPERATION_VERSION,
  environment,
  rerun: args.rerun,
});

try {
  await run.recordPending([
    ...affectedProjections.map(({userId, climbId}) => ({userId, climbId})),
    ...renames.map(({workoutId, canonicalWorkoutId}) => ({
      kind: WORKOUT_ID_RENAME_REPAIR_KIND,
      workoutId,
      canonicalWorkoutId,
    })),
  ]);
  await commitUnits(db, units, batchSizes);
  const verificationDocuments = await readWorkoutDocuments(db);
  const verificationPlan = planCaseVariantWorkoutMerges(verificationDocuments);
  if (verificationPlan.merges.length > 0 || verificationPlan.conflicts.length > 0) {
    throw new Error("Verification still found case-variant workout document groups.");
  }
  await verifyWorkoutIdReferences(db, renames);
  await verifyLandmarkResults(db, affectedProjections);

  await run.finish({
    workoutDocumentsScanned: documents.length,
    duplicateGroupsMerged: plan.merges.length,
    aliasDocumentsDeleted: deleteCount,
    referenceRowsMoved: referencePlan.moves.length,
    referenceFieldsRewritten: referencePlan.fieldUpdates.length,
    unresolvedReferences: referencePlan.unresolved.length,
    landmarkResultsWritten: affectedProjections.length - staleProjections.length,
    landmarkResultsDeleted: staleProjections.length,
  });
  console.log(
    `\nMerged ${plan.merges.length} group(s), deleted ${deleteCount} alias document(s), ` +
      `repaired ${referencePlan.moves.length + referencePlan.fieldUpdates.length} ` +
      `workout-id reference(s), and verified ${affectedProjections.length} landmark ` +
      `projection(s) (${staleProjections.length} removed as stale).`
  );
} catch (error) {
  await run.fail(error);
  console.error(
    `\nThis run did not finish. ${affectedProjections.length} landmarkResult(s) and ` +
      `${renames.length} workout id rename(s) are recorded as owed on the ledger; re-run ` +
      "this migration with --apply to finish them, or run " +
      "scripts/backfill-landmark-results.mjs for the projections. Do not treat the " +
      "operation as complete until one of those succeeds."
  );
  throw error;
}

async function readWorkoutDocuments(firestore) {
  const snapshot = await firestore.collectionGroup("workouts").get();
  return snapshot.docs.flatMap((document) => {
    const segments = document.ref.path.split("/");
    if (segments.length !== 4 || segments[0] !== "users" || segments[2] !== "workouts") {
      return [];
    }
    return [{userId: segments[1], workoutId: document.id, data: document.data()}];
  });
}

/**
 * Reads every document outside `users/{uid}/workouts` that keys on, or stores, a private
 * workout document id, so canonicalizing an id can move each of them with it.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<object[]>} Scanned references, in shape-planner form.
 */
async function readWorkoutIdReferences(firestore) {
  const snapshots = await Promise.all([
    firestore.collection("live_replay_leaderboards").get(),
    ...REFERENCE_COLLECTION_GROUPS.map((collectionId) =>
      firestore.collectionGroup(collectionId).get()
    ),
  ]);

  return snapshots.flatMap((snapshot) => snapshot.docs).flatMap((document) => {
    const shape = matchWorkoutIdReferenceShape(document.ref.path);
    if (!shape) {
      return [];
    }
    return [{
      parentPath: document.ref.parent.path,
      documentId: document.id,
      keyedByWorkoutId: shape.keyedByWorkoutId,
      workoutIdFields: shape.workoutIdFields,
      data: document.data(),
    }];
  });
}

/**
 * Builds every write this migration will make, grouped into atomic units. A
 * canonicalization group must land in one batch so a workout can never lose its
 * non-canonical document without gaining its canonical one, and a reference row move is
 * atomic for the same reason; each rewritten field and each rebuilt landmarkResult stands
 * alone. The reported plan and the committed plan are both derived from this one list so
 * they cannot drift.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} merges Planned canonicalization groups.
 * @param {object} referencePlan Planned workout-id reference repairs.
 * @param {object[]} affectedProjections Landmark projections to rebuild.
 * @return {{ref: FirebaseFirestore.DocumentReference, data: object|null, merge?: boolean}[][]}
 *   Atomic units; a null payload means delete.
 */
function buildMigrationUnits(firestore, merges, referencePlan, affectedProjections) {
  const units = [];
  for (const merge of merges) {
    const collection = firestore.collection("users").doc(merge.userId).collection("workouts");
    const unit = [{ref: collection.doc(merge.canonicalWorkoutId), data: merge.targetData}];
    for (const workoutId of merge.deleteWorkoutIds) {
      unit.push({ref: collection.doc(workoutId), data: null});
    }
    units.push(unit);
  }
  for (const move of referencePlan.moves) {
    const collection = firestore.collection(move.parentPath);
    const unit = [{ref: collection.doc(move.fromDocumentId), data: null}];
    if (move.data) {
      unit.unshift({ref: collection.doc(move.toDocumentId), data: move.data});
    }
    units.push(unit);
  }
  for (const update of referencePlan.fieldUpdates) {
    units.push([{
      ref: firestore.collection(update.parentPath).doc(update.documentId),
      data: update.updates,
      merge: true,
    }]);
  }
  for (const item of affectedProjections) {
    units.push([{
      ref: landmarkResultRef(firestore, item),
      data: item.projection ? toFirestoreProjection(item.projection) : null,
    }]);
  }
  return units;
}

async function commitUnits(firestore, units, batchSizes) {
  let unitIndex = 0;
  for (const batchSize of batchSizes) {
    const batch = firestore.batch();
    let written = 0;
    while (written < batchSize) {
      for (const operation of units[unitIndex]) {
        if (operation.data === null) {
          batch.delete(operation.ref);
        } else if (operation.merge) {
          batch.set(operation.ref, operation.data, {merge: true});
        } else {
          batch.set(operation.ref, operation.data);
        }
      }
      written += units[unitIndex].length;
      unitIndex += 1;
    }
    await batch.commit();
  }
}

async function verifyWorkoutIdReferences(firestore, renames) {
  const verificationPlan = planWorkoutIdReferenceRepairs(
    renames,
    await readWorkoutIdReferences(firestore)
  );
  const outstanding = verificationPlan.moves.length +
    verificationPlan.fieldUpdates.length +
    verificationPlan.conflicts.length;
  if (outstanding > 0) {
    throw new Error(
      `Verification still found ${outstanding} workout-id reference(s) naming a ` +
        "non-canonical document id."
    );
  }
}

async function verifyLandmarkResults(firestore, affectedProjections) {
  for (const item of affectedProjections) {
    const storedSnapshot = await landmarkResultRef(firestore, item).get();
    if (!item.projection) {
      if (storedSnapshot.exists) {
        throw new Error(
          `Stale landmarkResult still present for ${item.userId}/${item.climbId}.`
        );
      }
      continue;
    }

    const stored = storedSnapshot.exists ?
      comparableProjection(storedSnapshot.data(), item.climbId) : null;
    if (!shouldSkipLandmarkResultWrite(stored, item.projection)) {
      throw new Error(`landmarkResults verification failed for ${item.userId}/${item.climbId}.`);
    }
  }
}

function landmarkResultRef(firestore, key) {
  return firestore
    .collection("users")
    .doc(key.userId)
    .collection("landmarkResults")
    .doc(key.climbId);
}

function toFirestoreProjection(projection) {
  return {
    climbId: projection.climbId,
    completed: true,
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

function comparableProjection(data, climbId) {
  return {
    climbId,
    completed: data.completed,
    firstCompletedAtMillis: data.firstCompletedAt?.toMillis?.() ?? null,
    latestCompletedAtMillis: data.latestCompletedAt?.toMillis?.() ?? null,
    attemptCount: data.attemptCount,
    bestWorkoutId: data.bestWorkoutId,
    bestElapsedSeconds: data.bestElapsedSeconds,
    schemaVersion: data.schemaVersion,
    computedThroughEvent: data.computedThroughEvent,
  };
}

function printUsageAndExit() {
  console.log(`
Canonicalizes case-variant private workout document ids in dev or staging.

Usage:
  node scripts/cleanup-case-variant-workout-ids.mjs --env dev
  node scripts/cleanup-case-variant-workout-ids.mjs --env staging
  node scripts/cleanup-case-variant-workout-ids.mjs --env staging --apply

Options:
  --env <dev|staging>   Required. Production is refused.
  --apply               Write documents (default is dry-run plan only).
  --rerun               Apply again after a prior success (body is idempotent).
`);
  process.exit(0);
}
