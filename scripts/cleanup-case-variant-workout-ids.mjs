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
 * already exists is dropped when the payloads agree and otherwise resolved newest-first
 * through that collection's own recency field; a pair no timestamp can order blocks the
 * apply instead of being guessed at, and a non-canonical id with no surviving workout is
 * reported, never rewritten. Dropping a duplicate bucket-zero row removes a climber the
 * leaderboard summary already counted, so that context's completedCount and totalClimbers
 * drop by exactly the number of rows removed - nothing is recounted from another
 * collection, and permanent completion orders and rank snapshots are never touched. That
 * decrement is applied relative to whatever the summary reads at commit time, inside a
 * transaction that records its obligation markers atomically, so climbers who finished
 * between two runs keep their counts and a rerun can never decrement twice. Each removed
 * row owes its own obligation, identified by context, document path, and the version the
 * row was scanned at, so a rerun that only partly landed re-derives the same ids for the
 * rows it still sees instead of stacking a second decrement on top of the carried ones.
 *
 * A group whose heartRateSeries pointer names a non-canonical workout id blocks the apply.
 * The pointer addresses a Cloud Storage object this migration does not move, and the rules
 * require it to spell its own document id, so canonicalizing the document alone would
 * orphan the object and break every later client update of that workout. Moving it is
 * manual, captain-gated remediation.
 *
 * Writes are chunked, so a run can die with the workout renames committed and the
 * reference repairs, leaderboard decrements, or landmarkResults rebuild outstanding. The
 * projections, the renames, and the exact duplicate-row obligations this run owes each
 * summary are all recorded on the ledger before the first write and cleared only once
 * discharged, so the next run folds them back into its own plan and cannot report success
 * on a vacuous verification. Reference repairs are also re-derived from live data - any id
 * still spelled non-canonically whose canonical workout exists is repaired - so a lost
 * ledger cannot strand them either. If a run fails and the operator will not re-run it,
 * `scripts/backfill-landmark-results.mjs` rebuilds the same projections. A carried repair
 * whose climb no longer has any surviving completion is deleted rather than rebuilt - the
 * same disposal onWorkoutWritten applies to that case - so a workout removed between runs
 * cannot wedge the operation. A pending repair this operation version cannot interpret -
 * one an older version left behind, or a malformed record - blocks the apply rather than
 * being filtered out, because finishing would overwrite the list and lose the owed work.
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
  operationDocumentRef,
  parseCommonArgs,
  readPendingRepairs,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {shouldSkipLandmarkResultWrite} from "./lib/landmark-result-derivation.mjs";
import {
  BATCH_WRITE_LIMIT,
  REPLAY_SUMMARY_REPAIR_KIND,
  WORKOUT_ID_RENAME_REPAIR_KIND,
  classifyPendingRepairs,
  finalWorkoutDocuments,
  packBatchSizes,
  planAffectedLandmarkProjections,
  planCaseVariantWorkoutMerges,
  planReplaySummaryRepairs,
  planWorkoutIdReferenceRenames,
  planWorkoutIdReferenceRepairs,
  resolveReplaySummaryDecrement,
  scanWorkoutIdReferences,
} from "./lib/workout-id-case-migration.mjs";

const OPERATION_ID = "migration/case-variant-workout-ids";
const OPERATION_VERSION = 4;
const SUMMARY_MARKER_COLLECTION = "replaySummaryObligationMarkers";

const args = parseCommonArgs(process.argv);
if (args.rest.has("help")) {
  printUsageAndExit();
}
if (args.contextKey || args.rest.size > 0) {
  throw new Error("This migration accepts only --env, --apply, --rerun, and --help.");
}

const environment = resolveEnvironment(args.env);
const db = await initFirestore(environment);
const documents = await readWorkoutDocuments(db);
const references = await scanWorkoutIdReferences(db);
const plan = planCaseVariantWorkoutMerges(documents);
const pendingRepairs = await readPendingRepairs(db, OPERATION_ID);
const carried = classifyPendingRepairs(pendingRepairs);
const carriedRepairs = carried.landmarkResults;
const carriedRenames = carried.renames;
const carriedSummaryObligations = carried.summaryObligations
  .map(({contextKey, obligationId, rowPath, versionToken}) => ({
    contextKey,
    obligationId,
    rowPath,
    versionToken,
  }));
const appliedObligationIds = await readAppliedObligationIds(db);
const deleteCount = plan.merges.reduce((sum, merge) => sum + merge.deleteWorkoutIds.length, 0);
const renames = planWorkoutIdReferenceRenames(
  plan.merges,
  carriedRenames,
  references,
  finalWorkoutDocuments(documents, plan.merges)
);
const referencePlan = planWorkoutIdReferenceRepairs(renames, references);
const summaryPlan = planReplaySummaryRepairs(
  referencePlan.moves,
  references,
  carriedSummaryObligations,
  appliedObligationIds
);

console.log([
  `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
  `Environment: ${environment.env} (${environment.projectId})`,
  `Mode: ${args.apply ? "apply" : "dry-run (plan only)"}`,
  `Workout documents scanned: ${documents.length}`,
  `Workout-id references scanned: ${references.length}`,
  `Safe canonicalization groups: ${plan.merges.length}`,
  `Blocked conflicting groups: ${plan.conflicts.length}`,
  `Blocked heart-rate pointer groups: ${plan.heartRateBlocked.length}`,
  `Non-canonical documents to delete: ${deleteCount}`,
  `Workout ids to propagate into references: ${renames.length}`,
  `Reference rows to move onto a canonical id: ${referencePlan.moves.length}`,
  `Reference fields to rewrite: ${referencePlan.fieldUpdates.length}`,
  `Blocked conflicting reference rows: ${referencePlan.conflicts.length}`,
  `Leaderboard summaries to decrement: ${summaryPlan.decrements.length}`,
  `landmarkResults owed by an earlier unfinished run: ${carriedRepairs.length}`,
  `Workout id renames owed by an earlier unfinished run: ${carriedRenames.length}`,
  `Summary obligations owed by an earlier unfinished run: ${carriedSummaryObligations.length}`,
  `Summary obligations already marked applied: ${summaryPlan.settledObligations.length}`,
  `Unrecognized ledger repairs: ${carried.unrecognized.length}`,
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
for (const obligation of summaryPlan.owedObligations) {
  console.log(
    `SUMMARY OBLIGATION ${obligation.contextKey} ${obligation.obligationId}: -1 row ` +
      `${obligation.rowPath} @ version ${obligation.versionToken}, no applied marker yet`
  );
}
for (const obligation of summaryPlan.settledObligations) {
  console.log(
    `SUMMARY OBLIGATION ${obligation.contextKey} ${obligation.obligationId}: already ` +
      `applied (marker recorded) for ${obligation.rowPath} @ version ` +
      `${obligation.versionToken}, skipped`
  );
}
for (const decrement of summaryPlan.decrements) {
  console.log(
    `SUMMARY ${decrement.contextKey}: -${decrement.droppedRows} duplicate row(s) applied ` +
      `relative to the counts read in the transaction (now completedCount ` +
      `${decrement.currentCounts.completedCount} -> ` +
      `${decrement.projectedCounts.completedCount}, totalClimbers ` +
      `${decrement.currentCounts.totalClimbers} -> ` +
      `${decrement.projectedCounts.totalClimbers}), marking ` +
      decrement.obligations.map((obligation) => obligation.obligationId).join(", ")
  );
}
for (const note of summaryPlan.notes) {
  console.log(
    `SUMMARY UNCHANGED ${note.contextKey}: ${note.reason} ` +
      `(obligations still owed: ${note.obligationIds.join(", ")})`
  );
}
for (const item of referencePlan.unresolved) {
  console.log(
    `UNRESOLVED ${item.path} references non-canonical ${item.workoutId} ` +
      "with no surviving workout document - left untouched"
  );
}
for (const repair of carried.unrecognized) {
  console.error(
    "BLOCKED LEDGER REPAIR this operation version cannot interpret, left on the ledger " +
      `untouched: ${JSON.stringify(repair)}`
  );
}
for (const conflict of plan.conflicts) {
  console.error(
    `BLOCKED ${conflict.userId}: ${conflict.sourceWorkoutIds.join(", ")} ` +
      `conflict in ${conflict.conflictingFields.join(", ")}`
  );
}
for (const blocked of plan.heartRateBlocked) {
  console.error(
    `BLOCKED HEART RATE ${blocked.userId}: ${blocked.sourceWorkoutIds.join(", ")} -> ` +
      `${blocked.canonicalWorkoutId} carries heartRateSeries.storagePath ` +
      `${blocked.staleHeartRateStoragePaths.join(", ")}, which names a non-canonical ` +
      "workout id. Canonicalizing the document without moving the Cloud Storage object " +
      "would orphan the object and make every later client update of this workout fail. " +
      "Remediation is manual and captain-gated: copy " +
      `users/${blocked.userId}/workout_heart_rate/<old-id>.json.gz to ` +
      `users/${blocked.userId}/workout_heart_rate/${blocked.canonicalWorkoutId}.json.gz, ` +
      "delete the old object, rewrite heartRateSeries.storagePath to match, then re-run " +
      "this migration."
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
const units = buildMigrationUnits(
  db,
  plan.merges,
  referencePlan,
  affectedProjections
);
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
if (carried.unrecognized.length > 0) {
  throw new Error(
    `Refusing apply: the ledger holds ${carried.unrecognized.length} pending repair(s) ` +
      `this operation version (v${OPERATION_VERSION}) cannot interpret. Finishing would ` +
      "overwrite pendingRepairs and discard owed work. Discharge or remove them by hand " +
      "first - see the BLOCKED LEDGER REPAIR lines above."
  );
}
if (plan.conflicts.length > 0) {
  throw new Error(
    `Refusing apply: ${plan.conflicts.length} case-variant group(s) contain conflicting payloads.`
  );
}
if (plan.heartRateBlocked.length > 0) {
  throw new Error(
    `Refusing apply: ${plan.heartRateBlocked.length} case-variant group(s) carry a ` +
      "heartRateSeries.storagePath naming a non-canonical workout id. Move the Cloud " +
      "Storage objects by hand first - see the BLOCKED HEART RATE lines above."
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
    ...summaryPlan.owedObligations.map((obligation) => ({
      kind: REPLAY_SUMMARY_REPAIR_KIND,
      ...obligation,
    })),
  ]);
  await commitUnits(db, units, batchSizes);
  await applyReplaySummaryDecrements(db, summaryPlan.decrements);
  const verificationDocuments = await readWorkoutDocuments(db);
  const verificationPlan = planCaseVariantWorkoutMerges(verificationDocuments);
  if (
    verificationPlan.merges.length > 0 ||
    verificationPlan.conflicts.length > 0 ||
    verificationPlan.heartRateBlocked.length > 0
  ) {
    throw new Error("Verification still found case-variant workout document groups.");
  }
  await verifyWorkoutIdReferences(db, renames);
  await verifyReplaySummaryObligations(db, summaryPlan);
  await verifyLandmarkResults(db, affectedProjections);

  const undischargedObligations = summaryPlan.notes.flatMap((note) => (
    summaryPlan.owedObligations.filter(
      (obligation) => note.obligationIds.includes(obligation.obligationId)
    )
  ));
  await run.finish(
    {
      workoutDocumentsScanned: documents.length,
      duplicateGroupsMerged: plan.merges.length,
      aliasDocumentsDeleted: deleteCount,
      referenceRowsMoved: referencePlan.moves.length,
      referenceFieldsRewritten: referencePlan.fieldUpdates.length,
      unresolvedReferences: referencePlan.unresolved.length,
      replaySummariesDecremented: summaryPlan.decrements.length,
      replaySummaryObligationsDischarged: summaryPlan.decrements.reduce(
        (sum, decrement) => sum + decrement.obligations.length,
        0
      ),
      replaySummaryObligationsStillOwed: undischargedObligations.length,
      landmarkResultsWritten: affectedProjections.length - staleProjections.length,
      landmarkResultsDeleted: staleProjections.length,
    },
    undischargedObligations.map((obligation) => ({
      kind: REPLAY_SUMMARY_REPAIR_KIND,
      ...obligation,
    }))
  );
  console.log(
    `\nMerged ${plan.merges.length} group(s), deleted ${deleteCount} alias document(s), ` +
      `repaired ${referencePlan.moves.length + referencePlan.fieldUpdates.length} ` +
      `workout-id reference(s), and verified ${affectedProjections.length} landmark ` +
      `projection(s) (${staleProjections.length} removed as stale).`
  );
} catch (error) {
  await run.fail(error);
  console.error(
    `\nThis run did not finish. ${affectedProjections.length} landmarkResult(s), ` +
      `${renames.length} workout id rename(s), and ` +
      `${summaryPlan.owedObligations.length} leaderboard decrement obligation(s) are ` +
      "recorded as owed on the ledger; re-run this migration with --apply to finish " +
      "them, or run " +
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
 * Builds every write this migration will make, grouped into atomic units. A
 * canonicalization group must land in one batch so a workout can never lose its
 * non-canonical document without gaining its canonical one, and a reference row move is
 * atomic for the same reason; each rewritten field and each rebuilt landmarkResult stands
 * alone. The reported plan and the committed plan are both derived from this one list so
 * they cannot drift. Leaderboard decrements are deliberately absent: they are relative
 * writes that must be paired with their obligation marker, so they run as transactions
 * afterwards rather than as batched absolute sets.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} merges Planned canonicalization groups.
 * @param {object} referencePlan Planned workout-id reference repairs.
 * @param {object[]} affectedProjections Landmark projections to rebuild.
 * @return {{ref: FirebaseFirestore.DocumentReference, data: object|null, merge?: boolean}[][]}
 *   Atomic units; a null payload means delete.
 */
function buildMigrationUnits(
  firestore,
  merges,
  referencePlan,
  affectedProjections
) {
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
  const references = await scanWorkoutIdReferences(firestore);
  const verificationPlan = planWorkoutIdReferenceRepairs(renames, references);
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

function summaryMarkerRef(firestore, contextKey) {
  return operationDocumentRef(firestore, OPERATION_ID)
    .collection(SUMMARY_MARKER_COLLECTION)
    .doc(contextKey);
}

async function readAppliedObligationIds(firestore) {
  const snapshot = await operationDocumentRef(firestore, OPERATION_ID)
    .collection(SUMMARY_MARKER_COLLECTION)
    .get();
  return snapshot.docs.flatMap((document) => {
    const ids = document.get("appliedObligationIds");
    return Array.isArray(ids) ? ids : [];
  });
}

/**
 * Discharges each context's owed duplicate-row obligations.
 *
 * The decrement and the marker that proves it landed are written in one transaction, so a
 * crash either leaves the whole obligation owed or leaves it unambiguously settled - never
 * a decrement nobody can tell apart from an outstanding one. The subtraction happens on the
 * counts read inside the transaction, so finishers who arrived since the plan was built
 * survive it.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object[]} decrements Planned per-context decrements.
 * @return {Promise<void>} Resolves once every decrement is settled.
 */
async function applyReplaySummaryDecrements(firestore, decrements) {
  for (const decrement of decrements) {
    const summaryRef = firestore
      .collection("live_replay_leaderboards")
      .doc(decrement.contextKey);
    const markerRef = summaryMarkerRef(firestore, decrement.contextKey);

    const outcome = await firestore.runTransaction(async (transaction) => {
      const [summarySnapshot, markerSnapshot] = await transaction.getAll(summaryRef, markerRef);
      if (!summarySnapshot.exists) {
        throw new Error(
          `Replay summary ${decrement.contextKey} disappeared before its decrement.`
        );
      }
      const appliedIds = markerSnapshot.get("appliedObligationIds");
      const resolution = resolveReplaySummaryDecrement(
        summarySnapshot.data(),
        Array.isArray(appliedIds) ? appliedIds : [],
        decrement.obligations
      );
      if (!resolution.updates) {
        return resolution;
      }

      transaction.set(summaryRef, resolution.updates, {merge: true});
      transaction.set(
        markerRef,
        {
          contextKey: decrement.contextKey,
          appliedObligationIds: FieldValue.arrayUnion(...resolution.obligationIds),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      return resolution;
    });

    console.log(
      outcome.updates ?
        `SUMMARY APPLIED ${decrement.contextKey}: -${outcome.droppedRows} row(s) -> ` +
          `completedCount ${outcome.updates.completedCount}, totalClimbers ` +
          `${outcome.updates.totalClimbers}, marked ${outcome.obligationIds.join(", ")}` :
        `SUMMARY ALREADY APPLIED ${decrement.contextKey}: every obligation was already ` +
          "marked, nothing decremented"
    );
  }
}

async function verifyReplaySummaryObligations(firestore, summaryPlan) {
  const applied = new Set(await readAppliedObligationIds(firestore));
  const missing = summaryPlan.decrements.flatMap((decrement) => (
    decrement.obligations
      .filter((obligation) => !applied.has(obligation.obligationId))
      .map((obligation) => `${decrement.contextKey}/${obligation.obligationId}`)
  ));
  if (missing.length > 0) {
    throw new Error(
      `Verification found ${missing.length} replay summary obligation(s) with no applied ` +
        `marker: ${missing.join(", ")}.`
    );
  }

  for (const note of summaryPlan.notes) {
    console.log(
      `SUMMARY STILL OWED ${note.contextKey}: ${note.obligationIds.join(", ")} - ` +
        "recorded on the ledger for the next run or the replay backfill"
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
