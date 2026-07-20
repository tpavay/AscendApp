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
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {
  deriveLandmarkResult,
  groupCompletions,
  parseCompletedLandmarkWorkout,
  shouldSkipLandmarkResultWrite,
} from "./lib/landmark-result-derivation.mjs";
import {
  BATCH_WRITE_LIMIT,
  packBatchSizes,
  planCaseVariantWorkoutMerges,
  plannedUnitSizes,
} from "./lib/workout-id-case-migration.mjs";

const OPERATION_ID = "migration/case-variant-workout-ids";
const OPERATION_VERSION = 1;

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
const plan = planCaseVariantWorkoutMerges(documents);
const affectedProjections = deriveAffectedLandmarkProjections(documents, plan.merges);
const batchSizes = packBatchSizes(plannedUnitSizes(plan.merges, affectedProjections));
const operationCount = batchSizes.reduce((sum, size) => sum + size, 0);

console.log([
  `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
  `Environment: ${environment.env} (${environment.projectId})`,
  `Mode: ${args.apply ? "apply" : "dry-run (plan only)"}`,
  `Workout documents scanned: ${documents.length}`,
  `Safe canonicalization groups: ${plan.merges.length}`,
  `Blocked conflicting groups: ${plan.conflicts.length}`,
  `Non-canonical documents to delete: ${plan.merges.reduce((sum, merge) => sum + merge.deleteWorkoutIds.length, 0)}`,
  `landmarkResults to rebuild: ${affectedProjections.length}`,
  `Firestore operations: ${operationCount} in ${batchSizes.length} batch(es) of at most ${BATCH_WRITE_LIMIT}`,
].join("\n"));

for (const merge of plan.merges) {
  console.log(
    `SAFE ${merge.userId}: ${merge.sourceWorkoutIds.join(", ")} -> ${merge.canonicalWorkoutId}`
  );
}
for (const conflict of plan.conflicts) {
  console.error(
    `BLOCKED ${conflict.userId}: ${conflict.sourceWorkoutIds.join(", ")} ` +
      `conflict in ${conflict.conflictingFields.join(", ")}`
  );
}

if (!args.apply) {
  console.log("\nDry-run only. Re-run with --apply after reviewing every planned merge.");
  process.exit(0);
}
if (plan.conflicts.length > 0) {
  throw new Error(
    `Refusing apply: ${plan.conflicts.length} case-variant group(s) contain conflicting payloads.`
  );
}

const run = await beginRun(db, {
  operationId: OPERATION_ID,
  operationVersion: OPERATION_VERSION,
  environment,
  rerun: args.rerun,
});

try {
  const deleted = await applyMerges(db, plan.merges, affectedProjections);
  const verificationDocuments = await readWorkoutDocuments(db);
  const verificationPlan = planCaseVariantWorkoutMerges(verificationDocuments);
  if (verificationPlan.merges.length > 0 || verificationPlan.conflicts.length > 0) {
    throw new Error("Verification still found case-variant workout document groups.");
  }
  await verifyLandmarkResults(db, affectedProjections);

  await run.finish({
    workoutDocumentsScanned: documents.length,
    duplicateGroupsMerged: plan.merges.length,
    aliasDocumentsDeleted: deleted,
    landmarkResultsWritten: affectedProjections.length,
  });
  console.log(
    `\nMerged ${plan.merges.length} group(s), deleted ${deleted} alias document(s), ` +
      `and verified ${affectedProjections.length} landmark projection(s).`
  );
} catch (error) {
  await run.fail(error);
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

async function applyMerges(firestore, merges, affectedProjections) {
  const units = [];
  let deleted = 0;
  for (const merge of merges) {
    const collection = firestore.collection("users").doc(merge.userId).collection("workouts");
    const unit = [{ref: collection.doc(merge.canonicalWorkoutId), data: merge.targetData}];
    for (const workoutId of merge.deleteWorkoutIds) {
      unit.push({ref: collection.doc(workoutId), data: null});
      deleted += 1;
    }
    units.push(unit);
  }
  for (const item of affectedProjections) {
    units.push([{
      ref: landmarkResultRef(firestore, item),
      data: toFirestoreProjection(item.projection),
    }]);
  }

  let unitIndex = 0;
  for (const batchSize of packBatchSizes(units.map((unit) => unit.length))) {
    const batch = firestore.batch();
    let written = 0;
    while (written < batchSize) {
      for (const operation of units[unitIndex]) {
        if (operation.data === null) {
          batch.delete(operation.ref);
        } else {
          batch.set(operation.ref, operation.data);
        }
      }
      written += units[unitIndex].length;
      unitIndex += 1;
    }
    await batch.commit();
  }
  return deleted;
}

function deriveAffectedLandmarkProjections(documents, merges) {
  const keys = new Map();
  const replacedDocumentKeys = new Set();
  for (const merge of merges) {
    for (const document of merge.sourceDocuments) {
      replacedDocumentKeys.add(`${document.userId}/${document.workoutId}`);
      const completion = parseCompletedLandmarkWorkout(document.workoutId, document.data);
      if (!completion) {
        continue;
      }
      keys.set(`${merge.userId}/${completion.climbId}`, {
        userId: merge.userId,
        climbId: completion.climbId,
      });
    }
  }

  const finalDocuments = documents.filter(
    (document) => !replacedDocumentKeys.has(`${document.userId}/${document.workoutId}`)
  );
  for (const merge of merges) {
    finalDocuments.push({
      userId: merge.userId,
      workoutId: merge.canonicalWorkoutId,
      data: merge.targetData,
    });
  }
  const grouped = groupCompletions(finalDocuments);

  return [...keys.values()].map((key) => {
    const completions = grouped.get(key.userId)?.get(key.climbId) ?? [];
    const projection = deriveLandmarkResult(key.climbId, completions);
    if (!projection) {
      throw new Error(`No surviving completion for ${key.userId}/${key.climbId}.`);
    }
    return {...key, projection};
  }).sort((lhs, rhs) => (
    lhs.userId.localeCompare(rhs.userId) || lhs.climbId.localeCompare(rhs.climbId)
  ));
}

async function verifyLandmarkResults(firestore, affectedProjections) {
  for (const item of affectedProjections) {
    const storedSnapshot = await landmarkResultRef(firestore, item).get();
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
