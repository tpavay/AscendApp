import {createHash} from "node:crypto";
import {
  deriveLandmarkResult,
  groupCompletions,
  parseCompletedLandmarkWorkout,
} from "./landmark-result-derivation.mjs";
import {canonicalWorkoutDocumentId} from "./workout-document-id.mjs";

export const BATCH_WRITE_LIMIT = 500;
export const WORKOUT_ID_RENAME_REPAIR_KIND = "workoutIdRename";
export const REPLAY_SUMMARY_REPAIR_KIND = "replaySummaryRowObligation";
const REPLAY_COLLECTION = "live_replay_leaderboards";
const TWIN_READ_CHUNK = 100;
const REFERENCE_COLLECTION_GROUPS = Object.freeze([
  "entries",
  "completionSnapshots",
  "finishers",
  "userBestAttempts",
  "liveClimbPublishStatuses",
  "profile_workouts",
]);

/**
 * Plans the landmarkResults this migration must rewrite, from the post-merge document set.
 *
 * Keys come from two places. This run's merges contribute the climbs whose completions are
 * about to change document id; a completion always survives that, so a null derivation
 * there means the plan is wrong and the run must stop. Carried repairs come from an earlier
 * unfinished run's ledger entry and are re-validated against live data that may have moved
 * on - if nothing completes that climb any more, the projection is stale rather than
 * unexpected, so it is planned for deletion, matching what onWorkoutWritten does with the
 * same null derivation in functions/src/climbCompletions.ts.
 * @param {object[]} documents Raw private workout documents, pre-merge.
 * @param {object[]} merges Planned canonicalization groups.
 * @param {{userId: string, climbId: string}[]} carriedRepairs Repairs owed by an earlier run.
 * @return {{userId: string, climbId: string, projection: object|null}[]} Projections to write,
 *   or to delete when the projection is null.
 */
export function planAffectedLandmarkProjections(documents, merges, carriedRepairs = []) {
  const keys = new Map();
  for (const repair of carriedRepairs) {
    keys.set(`${repair.userId}/${repair.climbId}`, {
      userId: repair.userId,
      climbId: repair.climbId,
      fromMerge: false,
    });
  }
  for (const merge of merges) {
    for (const document of merge.sourceDocuments) {
      const completion = parseCompletedLandmarkWorkout(document.workoutId, document.data);
      if (!completion) {
        continue;
      }
      keys.set(`${merge.userId}/${completion.climbId}`, {
        userId: merge.userId,
        climbId: completion.climbId,
        fromMerge: true,
      });
    }
  }

  const grouped = groupCompletions(finalWorkoutDocuments(documents, merges));

  return [...keys.values()].map(({userId, climbId, fromMerge}) => {
    const completions = grouped.get(userId)?.get(climbId) ?? [];
    const projection = deriveLandmarkResult(climbId, completions);
    if (!projection && fromMerge) {
      throw new Error(`No surviving completion for ${userId}/${climbId}.`);
    }
    return {userId, climbId, projection};
  }).sort((lhs, rhs) => (
    lhs.userId.localeCompare(rhs.userId) || lhs.climbId.localeCompare(rhs.climbId)
  ));
}

/**
 * The private workout documents that exist once the planned merges are applied.
 * @param {object[]} documents Raw private workout documents, pre-merge.
 * @param {object[]} merges Planned canonicalization groups.
 * @return {{userId: string, workoutId: string, data: object}[]} Post-merge documents.
 */
export function finalWorkoutDocuments(documents, merges) {
  const replacedKeys = new Set(
    merges.flatMap((merge) => merge.sourceDocuments.map(
      (document) => `${document.userId}/${document.workoutId}`
    ))
  );
  const surviving = documents
    .filter((document) => !replacedKeys.has(`${document.userId}/${document.workoutId}`))
    .map(({userId, workoutId, data}) => ({userId, workoutId, data}));

  return [
    ...surviving,
    ...merges.map((merge) => ({
      userId: merge.userId,
      workoutId: merge.canonicalWorkoutId,
      data: merge.targetData,
    })),
  ];
}

/**
 * Packs atomic units into Firestore batches without ever splitting a unit.
 * @param {number[]} unitSizes Write count for each atomic unit, in apply order.
 * @return {number[]} Write count for each batch, in commit order.
 */
export function packBatchSizes(unitSizes) {
  const batches = [];
  let current = 0;
  for (const size of unitSizes) {
    if (size > BATCH_WRITE_LIMIT) {
      throw new Error(
        `Refusing apply: one group needs ${size} atomic writes, ` +
          `above Firestore's ${BATCH_WRITE_LIMIT}-write batch limit.`
      );
    }
    if (current + size > BATCH_WRITE_LIMIT) {
      batches.push(current);
      current = 0;
    }
    current += size;
  }
  if (current > 0) {
    batches.push(current);
  }
  return batches;
}

/**
 * Plans conservative canonicalizations for workout documents stored under a non-canonical
 * UUID id. Case-variant twins are merged into the canonical id; a lone non-canonical
 * document is renamed onto it, so a later app write cannot recreate the twin.
 * Documents with conflicting payload fields are reported and never planned for deletion.
 * The newest payload decides which fields exist; a field only the older twin carries is
 * reported as dropped rather than merged back in.
 *
 * A group whose `heartRateSeries.storagePath` names anything but the canonical id is
 * blocked too. That pointer is a Cloud Storage object this migration cannot move, and
 * `isValidWorkoutDocument` requires the path to spell the document id exactly, so
 * rewriting the pointer alone would orphan the object and rewriting neither would make
 * every later client update of that workout fail.
 * @param {{userId: string, workoutId: string, data: Record<string, unknown>}[]} documents
 *   Raw private workout documents.
 * @return {{merges: object[], conflicts: object[], heartRateBlocked: object[]}} Safe merges,
 *   payload-conflicting groups, and groups carrying an unmovable heart-rate pointer.
 */
export function planCaseVariantWorkoutMerges(documents) {
  const groups = new Map();

  for (const document of documents) {
    let canonicalWorkoutId;
    try {
      canonicalWorkoutId = canonicalWorkoutDocumentId(document.workoutId);
    } catch {
      continue;
    }

    const key = `${document.userId}/${canonicalWorkoutId}`;
    const group = groups.get(key) ?? [];
    group.push({...document, canonicalWorkoutId});
    groups.set(key, group);
  }

  const merges = [];
  const conflicts = [];
  const heartRateBlocked = [];
  for (const group of groups.values()) {
    const sourceIDs = [...new Set(group.map((document) => document.workoutId))];
    if (sourceIDs.every((workoutId) => workoutId === group[0].canonicalWorkoutId)) {
      continue;
    }

    const result = mergeGroup(group);
    if (result.conflictingFields.length > 0) {
      conflicts.push(result);
    } else if (result.staleHeartRateStoragePaths.length > 0) {
      heartRateBlocked.push(result);
    } else {
      merges.push(result);
    }
  }

  return {merges, conflicts, heartRateBlocked};
}

/**
 * The heart-rate storage pointers in a group that would stop naming their own document.
 *
 * Conservative on purpose: anything that is not exactly the canonical document's path
 * counts, including a malformed or absolute-looking value, because the only safe repair
 * moves a Cloud Storage object this migration deliberately does not touch.
 * @param {object} data Private workout payload.
 * @param {string} canonicalWorkoutId Canonical document id the group merges onto.
 * @return {string[]} Storage paths that block the group, empty when none do.
 */
function staleHeartRateStoragePaths(data, canonicalWorkoutId) {
  const storagePath = data?.heartRateSeries?.storagePath;
  if (typeof storagePath !== "string" || storagePath.length === 0) {
    return [];
  }
  return storagePath.endsWith(`/${canonicalWorkoutId}.json.gz`) ? [] : [storagePath];
}

function mergeGroup(group) {
  const canonicalWorkoutId = group[0].canonicalWorkoutId;
  const ordered = [...group].sort((lhs, rhs) => (
    timestampMillis(rhs.data.updatedAt) - timestampMillis(lhs.data.updatedAt) ||
    Number(rhs.workoutId === canonicalWorkoutId) - Number(lhs.workoutId === canonicalWorkoutId) ||
    lhs.workoutId.localeCompare(rhs.workoutId)
  ));
  const targetData = canonicalizeEmbeddedReferences(ordered[0].data, canonicalWorkoutId);
  const conflictingFields = new Set();
  const droppedFields = new Set();

  for (const document of ordered.slice(1)) {
    const candidate = canonicalizeEmbeddedReferences(document.data, canonicalWorkoutId);
    for (const [key, value] of Object.entries(candidate)) {
      if (key === "updatedAt") {
        if (timestampMillis(value) > timestampMillis(targetData.updatedAt)) {
          targetData.updatedAt = value;
        }
        continue;
      }

      // The newest payload is a full client replace, so a key it omits was dropped on
      // purpose. Carrying the older twin's value forward would resurrect a deleted field
      // and can push the document outside the rules allowlist.
      if (!(key in targetData)) {
        droppedFields.add(key);
      } else if (!firestoreValuesEqual(targetData[key], value)) {
        conflictingFields.add(key);
      }
    }
  }

  return {
    userId: group[0].userId,
    canonicalWorkoutId,
    sourceWorkoutIds: [...new Set(group.map((document) => document.workoutId))].sort(),
    deleteWorkoutIds: [...new Set(
      group
        .map((document) => document.workoutId)
        .filter((workoutId) => workoutId !== canonicalWorkoutId)
    )].sort(),
    targetData,
    conflictingFields: [...conflictingFields].sort(),
    droppedFields: [...droppedFields].sort(),
    staleHeartRateStoragePaths: [...new Set(
      group.flatMap((document) => staleHeartRateStoragePaths(document.data, canonicalWorkoutId))
    )].sort(),
    sourceDocuments: group.map(({userId, workoutId, data}) => ({userId, workoutId, data})),
  };
}

/**
 * Every collection outside `users/{uid}/workouts` that keys a document on a private
 * workout document id, or stores one in a field. Canonicalizing a workout id without
 * these leaves live replay rows pointing at a document that no longer exists.
 *
 * `segments` matches a full Firestore document path, `*` matching one segment.
 * `recencyFields` names the timestamps that collection actually writes, in the order to
 * trust them; two rows that disagree can only be resolved through one of these.
 * `plannerFields` names the non-workout-id fields the planner reads, so a scan can drop
 * everything else from a row it will never rewrite wholesale.
 */
export const WORKOUT_ID_REFERENCE_SHAPES = Object.freeze([
  Object.freeze({
    segments: Object.freeze(["live_replay_leaderboards", "*"]),
    keyedByWorkoutId: false,
    workoutIdFields: Object.freeze(["firstAscentWorkoutId"]),
    recencyFields: Object.freeze([]),
    plannerFields: Object.freeze(["completedCount", "totalClimbers"]),
  }),
  Object.freeze({
    segments: Object.freeze([
      "live_replay_leaderboards", "*", "splitBuckets", "*", "entries", "*",
    ]),
    keyedByWorkoutId: true,
    workoutIdFields: Object.freeze(["workoutId"]),
    recencyFields: Object.freeze(["updatedAt"]),
    plannerFields: Object.freeze(["userId"]),
  }),
  Object.freeze({
    segments: Object.freeze(["live_replay_leaderboards", "*", "completionSnapshots", "*"]),
    keyedByWorkoutId: true,
    workoutIdFields: Object.freeze(["workoutId"]),
    recencyFields: Object.freeze(["rankedAt"]),
    plannerFields: Object.freeze([]),
  }),
  Object.freeze({
    segments: Object.freeze(["live_replay_leaderboards", "*", "finishers", "*"]),
    keyedByWorkoutId: false,
    workoutIdFields: Object.freeze(["bestWorkoutId", "firstWorkoutId"]),
    recencyFields: Object.freeze(["updatedAt"]),
    plannerFields: Object.freeze([]),
  }),
  Object.freeze({
    segments: Object.freeze(["live_replay_leaderboards", "*", "userBestAttempts", "*"]),
    keyedByWorkoutId: false,
    workoutIdFields: Object.freeze(["workoutId"]),
    recencyFields: Object.freeze(["updatedAt"]),
    plannerFields: Object.freeze([]),
  }),
  Object.freeze({
    segments: Object.freeze(["users", "*", "liveClimbPublishStatuses", "*"]),
    keyedByWorkoutId: true,
    workoutIdFields: Object.freeze(["workoutId", "rankSnapshotId"]),
    recencyFields: Object.freeze(["updatedAt", "publishedAt"]),
    plannerFields: Object.freeze([]),
  }),
  Object.freeze({
    segments: Object.freeze(["users", "*", "profile_workouts", "*"]),
    keyedByWorkoutId: true,
    workoutIdFields: Object.freeze([]),
    recencyFields: Object.freeze(["lastUpdated"]),
    plannerFields: Object.freeze([]),
  }),
]);

/**
 * Matches a document path against the known workout-id reference shapes.
 * @param {string} path Full Firestore document path.
 * @return {object|null} The matching shape, or null when the path holds no workout id.
 */
export function matchWorkoutIdReferenceShape(path) {
  const segments = path.split("/");
  return WORKOUT_ID_REFERENCE_SHAPES.find((shape) => (
    shape.segments.length === segments.length &&
    shape.segments.every((segment, index) => segment === "*" || segment === segments[index])
  )) ?? null;
}

/**
 * Reads every document outside `users/{uid}/workouts` that keys on, or stores, a private
 * workout document id, so canonicalizing an id can move each of them with it.
 *
 * `entries` alone holds one document per climber per split bucket, so the scan streams and
 * keeps a whole payload only for the rows that can actually be rewritten wholesale - the
 * ones spelled non-canonically. Every other row is trimmed to the fields the planner reads.
 * A trimmed row that turns out to be the canonical twin of a stale one is re-read in full
 * afterwards, because deciding between twins compares their entire payloads.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @return {Promise<object[]>} Scanned references, in shape-planner form.
 */
export async function scanWorkoutIdReferences(firestore) {
  const references = [];
  const queries = [
    firestore.collection(REPLAY_COLLECTION),
    ...REFERENCE_COLLECTION_GROUPS.map((collectionId) => firestore.collectionGroup(collectionId)),
  ];

  for (const query of queries) {
    for await (const document of query.stream()) {
      const shape = matchWorkoutIdReferenceShape(document.ref.path);
      if (shape) {
        references.push(scannedReference(document, shape));
      }
    }
  }

  await restoreCanonicalTwinPayloads(firestore, references);
  return references;
}

function scannedReference(document, shape) {
  const data = document.data();
  const complete = shape.keyedByWorkoutId && !isCanonicalDocumentId(document.id);
  return {
    parentPath: document.ref.parent.path,
    documentId: document.id,
    keyedByWorkoutId: shape.keyedByWorkoutId,
    workoutIdFields: shape.workoutIdFields,
    recencyFields: shape.recencyFields,
    partial: !complete,
    versionToken: documentVersionToken(document),
    data: complete ? data : plannerFieldsOnly(data, shape),
  };
}

/**
 * The Firestore version of a scanned document, as a string.
 *
 * A duplicate-removal obligation names one row at one version, so a row recreated at the
 * same path later is a different obligation rather than one an old marker silently settles.
 * @param {FirebaseFirestore.DocumentSnapshot} document Scanned snapshot.
 * @return {string} Version token, or "unknown" when the snapshot carries no update time.
 */
function documentVersionToken(document) {
  const millis = timestampMillis(document?.updateTime);
  return Number.isFinite(millis) ? String(millis) : "unknown";
}

function plannerFieldsOnly(data, shape) {
  const retained = {};
  for (const field of [...shape.workoutIdFields, ...shape.recencyFields, ...shape.plannerFields]) {
    if (field in data) {
      retained[field] = data[field];
    }
  }
  return retained;
}

function isCanonicalDocumentId(documentId) {
  try {
    return canonicalWorkoutDocumentId(documentId) === documentId;
  } catch {
    return false;
  }
}

async function restoreCanonicalTwinPayloads(firestore, references) {
  const byLocation = new Map(
    references.map((reference) => [`${reference.parentPath}/${reference.documentId}`, reference])
  );
  const twins = new Set();
  for (const reference of references) {
    if (!reference.keyedByWorkoutId || reference.partial) {
      continue;
    }
    const canonicalId = canonicalTwinId(reference.documentId);
    if (canonicalId && byLocation.has(`${reference.parentPath}/${canonicalId}`)) {
      twins.add(`${reference.parentPath}/${canonicalId}`);
    }
  }

  const locations = [...twins];
  for (let index = 0; index < locations.length; index += TWIN_READ_CHUNK) {
    const chunk = locations.slice(index, index + TWIN_READ_CHUNK);
    const snapshots = await firestore.getAll(...chunk.map((path) => firestore.doc(path)));
    for (const snapshot of snapshots) {
      const reference = byLocation.get(snapshot.ref.path);
      if (reference && snapshot.exists) {
        reference.data = snapshot.data();
        reference.partial = false;
        reference.versionToken = documentVersionToken(snapshot);
      }
    }
  }
}

function canonicalTwinId(documentId) {
  try {
    const canonical = canonicalWorkoutDocumentId(documentId);
    return canonical === documentId ? null : canonical;
  } catch {
    return null;
  }
}

/**
 * Derives the workout id renames this migration must propagate into replay references.
 *
 * Three sources feed it. This run's merges name the ids about to change; an earlier
 * unfinished run's ledger names the ones it never finished propagating; and live data
 * itself names any reference still spelled non-canonically whose canonical workout
 * document already exists, so a lost ledger cannot leave a rename half-applied forever.
 * @param {object[]} merges Planned canonicalization groups.
 * @param {{workoutId: string, canonicalWorkoutId: string}[]} carriedRenames Ledger renames.
 * @param {object[]} references Scanned workout-id references.
 * @param {{userId: string, workoutId: string}[]} finalDocuments Post-merge workout documents.
 * @return {{workoutId: string, canonicalWorkoutId: string}[]} Renames to propagate.
 */
export function planWorkoutIdReferenceRenames(
  merges,
  carriedRenames,
  references,
  finalDocuments
) {
  const renames = new Map();
  for (const merge of merges) {
    for (const workoutId of merge.deleteWorkoutIds) {
      renames.set(workoutId, merge.canonicalWorkoutId);
    }
  }
  for (const rename of carriedRenames) {
    renames.set(rename.workoutId, rename.canonicalWorkoutId);
  }

  const survivingIds = new Set(finalDocuments.map((document) => document.workoutId));
  for (const reference of references) {
    for (const workoutId of referencedWorkoutIds(reference)) {
      const canonicalWorkoutId = nonCanonicalWorkoutId(workoutId);
      if (canonicalWorkoutId && survivingIds.has(canonicalWorkoutId)) {
        renames.set(workoutId, canonicalWorkoutId);
      }
    }
  }

  return [...renames.entries()]
    .map(([workoutId, canonicalWorkoutId]) => ({workoutId, canonicalWorkoutId}))
    .sort((lhs, rhs) => lhs.workoutId.localeCompare(rhs.workoutId));
}

/**
 * Plans the reference repairs that keep replay rows pointing at canonicalized workouts.
 *
 * A row keyed on a renamed id moves onto the canonical id; when the canonical row already
 * exists, an identical payload lets the stale twin be dropped and a differing one is
 * settled by that collection's recency field, leaving a blocking conflict only where no
 * timestamp proves a winner. A row that merely stores a renamed id is rewritten in place.
 * Ids that stay non-canonical with no surviving workout document are reported, never
 * guessed at.
 * @param {{workoutId: string, canonicalWorkoutId: string}[]} renames Renames to propagate.
 * @param {object[]} references Scanned workout-id references.
 * @return {{moves: object[], fieldUpdates: object[], conflicts: object[], unresolved: object[]}}
 *   Planned repairs, blocked rows, and references nothing can reconcile.
 */
export function planWorkoutIdReferenceRepairs(renames, references) {
  const renameMap = new Map(renames.map((rename) => [rename.workoutId, rename.canonicalWorkoutId]));
  const byLocation = new Map(
    references.map((reference) => [referenceLocation(reference), reference])
  );
  const moves = [];
  const fieldUpdates = [];
  const conflicts = [];
  const unresolved = [];

  for (const reference of references) {
    const updates = canonicalFieldUpdates(reference, renameMap);
    for (const workoutId of unresolvedWorkoutIds(reference, renameMap)) {
      unresolved.push({path: referenceLocation(reference), workoutId});
    }

    const canonicalDocumentId = reference.keyedByWorkoutId ?
      renameMap.get(reference.documentId) ?? null :
      null;
    if (!canonicalDocumentId) {
      if (Object.keys(updates).length > 0) {
        fieldUpdates.push({
          parentPath: reference.parentPath,
          documentId: reference.documentId,
          updates,
        });
      }
      continue;
    }

    const target = byLocation.get(`${reference.parentPath}/${canonicalDocumentId}`);
    assertCompleteSource(reference);
    const data = {...reference.data, ...updates};
    if (!target) {
      moves.push({
        parentPath: reference.parentPath,
        fromDocumentId: reference.documentId,
        fromVersionToken: reference.versionToken ?? "unknown",
        toDocumentId: canonicalDocumentId,
        data,
        duplicate: false,
      });
      continue;
    }

    assertCompleteSource(target);
    const targetData = {...target.data, ...canonicalFieldUpdates(target, renameMap)};
    const resolution = resolveDuplicateReference(data, targetData, reference.recencyFields);
    if (resolution === "conflict") {
      conflicts.push({
        path: referenceLocation(reference),
        canonicalPath: referenceLocation(target),
      });
      continue;
    }
    moves.push({
      parentPath: reference.parentPath,
      fromDocumentId: reference.documentId,
      fromVersionToken: reference.versionToken ?? "unknown",
      toDocumentId: canonicalDocumentId,
      data: resolution === "adopt-stale" ? data : null,
      duplicate: true,
    });
  }

  return {
    moves: moves.sort(compareByPlannedPath),
    fieldUpdates: fieldUpdates.sort(compareByPlannedPath),
    conflicts: conflicts.sort((lhs, rhs) => lhs.path.localeCompare(rhs.path)),
    unresolved: unresolved.sort((lhs, rhs) => (
      lhs.path.localeCompare(rhs.path) || lhs.workoutId.localeCompare(rhs.workoutId)
    )),
  };
}

/**
 * Decides what to do with a stale row whose canonical twin already exists.
 *
 * Identical payloads make the stale row pure duplication, so it is simply dropped. When
 * they differ, the newer row wins, read through the recency field that collection actually
 * writes - `updatedAt` for leaderboard rows, `rankedAt` for completion snapshots,
 * `lastUpdated` for profile summaries. Without a comparable timestamp there is no rule that
 * picks a survivor, so the row is a conflict and blocks the apply rather than being
 * resolved by guesswork.
 * @param {object} staleData Canonicalized payload of the non-canonical row.
 * @param {object} canonicalData Canonicalized payload of the canonical row.
 * @param {string[]} recencyFields Timestamp fields this collection writes, most trusted first.
 * @return {"drop-stale"|"adopt-stale"|"conflict"} Resolution.
 */
function resolveDuplicateReference(staleData, canonicalData, recencyFields = []) {
  if (firestoreValuesEqual(staleData, canonicalData)) {
    return "drop-stale";
  }

  for (const field of recencyFields) {
    const staleMillis = timestampMillis(staleData[field]);
    const canonicalMillis = timestampMillis(canonicalData[field]);
    if (!Number.isFinite(staleMillis) || !Number.isFinite(canonicalMillis)) {
      continue;
    }
    return staleMillis > canonicalMillis ? "adopt-stale" : "drop-stale";
  }

  return "conflict";
}

/**
 * The stable identity of one removed duplicate row's decrement obligation.
 *
 * The unit is a single row occurrence - one context, one document path, one document
 * version - rather than a set of rows. A rerun that only committed part of a run's deletes
 * re-derives exactly the same id for the rows it still sees, so a carried obligation and a
 * replanned one collapse instead of stacking into a double decrement. Including the version
 * keeps the id an occurrence rather than a location: a duplicate genuinely recreated at a
 * path whose obligation was already applied gets a new id and its own decrement.
 * @param {string} contextKey Replay context the row belongs to.
 * @param {string} rowPath Full document path of the removed duplicate row.
 * @param {string} versionToken Firestore version the row was scanned at.
 * @return {string} Deterministic obligation id.
 */
export function replaySummaryObligationId(contextKey, rowPath, versionToken) {
  return createHash("sha256")
    .update([contextKey, rowPath, String(versionToken)].join("\n"))
    .digest("hex")
    .slice(0, 32);
}

/**
 * Splits a ledger's pending repairs into the kinds this operation knows how to replan.
 *
 * The ledger only helps if owed work survives, so anything this version cannot interpret -
 * an entry from an older operation version, a renamed kind, a malformed record - is
 * reported rather than filtered away. The caller refuses the apply on those instead of
 * overwriting the list and losing them.
 * @param {object[]} pendingRepairs Raw `pendingRepairs` from the ledger.
 * @return {{landmarkResults: object[], renames: object[], summaryObligations: object[],
 *   unrecognized: object[]}} Classified repairs.
 */
export function classifyPendingRepairs(pendingRepairs) {
  const landmarkResults = [];
  const renames = [];
  const summaryObligations = [];
  const unrecognized = [];

  for (const repair of pendingRepairs) {
    if (!repair || typeof repair !== "object") {
      unrecognized.push(repair);
      continue;
    }
    if (repair.kind === undefined) {
      const valid = isNonEmptyString(repair.userId) && isNonEmptyString(repair.climbId);
      (valid ? landmarkResults : unrecognized).push(repair);
    } else if (repair.kind === WORKOUT_ID_RENAME_REPAIR_KIND) {
      const valid = isNonEmptyString(repair.workoutId) &&
        isNonEmptyString(repair.canonicalWorkoutId);
      (valid ? renames : unrecognized).push(repair);
    } else if (repair.kind === REPLAY_SUMMARY_REPAIR_KIND) {
      const valid = isNonEmptyString(repair.contextKey) &&
        isNonEmptyString(repair.obligationId) &&
        isNonEmptyString(repair.rowPath) &&
        isNonEmptyString(repair.versionToken);
      (valid ? summaryObligations : unrecognized).push(repair);
    } else {
      unrecognized.push(repair);
    }
  }

  return {landmarkResults, renames, summaryObligations, unrecognized};
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

/**
 * Plans the leaderboard-summary repair owed by dropping duplicate split-bucket rows.
 *
 * Deleting a stale twin removes a bucket-zero row the summary already counted, so the only
 * change this migration can prove is that exact removal: each dropped duplicate lowers the
 * owning context's `completedCount` and `totalClimbers` by one. Nothing is recomputed from
 * scratch - the synthetic replay seed writes summaries with no finishers at all and keeps
 * `totalClimbers` above `completedCount` on purpose, so any total inferred from another
 * collection would overwrite real fixture data. A move that merely renames a row onto its
 * canonical id changes no count and is ignored here.
 *
 * The unit carried across runs is one obligation per removed row, never an absolute target
 * and never a set of rows. A run that dies partway leaves every row it did not decrement
 * still owed, and the rerun re-derives the identical id for each row it can still see, so a
 * carried obligation and a replanned one collapse rather than stacking into a double
 * decrement. Whatever survives is applied against the counts the summary reads at that
 * moment, so climbers who finished in between are preserved. Applying twice is prevented by
 * the marker recorded with each row, not by comparing counts.
 *
 * A summary that cannot absorb the obligations - missing, non-integer, or smaller than the
 * number of rows removed - is reported and left untouched, and a count is never raised. The
 * obligations stay owed. Completion orders and the point-in-time rank snapshots derived from
 * them are never rewritten; they are permanent.
 * @param {object[]} moves Planned reference moves.
 * @param {object[]} references Scanned workout-id references.
 * @param {{contextKey: string, obligationId: string, rowPath: string, versionToken: string}[]}
 *   carriedObligations Row obligations an earlier unfinished run recorded.
 * @param {string[]} appliedObligationIds Obligation ids whose marker already exists.
 * @return {{decrements: object[], owedObligations: object[], settledObligations: object[],
 *   notes: object[]}} Planned decrements, what to record on the ledger, obligations already
 *   proven applied, and contexts left for an operator.
 */
export function planReplaySummaryRepairs(
  moves,
  references,
  carriedObligations = [],
  appliedObligationIds = []
) {
  const obligations = new Map();
  for (const carried of carriedObligations) {
    obligations.set(carried.obligationId, {
      contextKey: carried.contextKey,
      obligationId: carried.obligationId,
      rowPath: carried.rowPath,
      versionToken: carried.versionToken,
    });
  }
  for (const move of moves) {
    const contextKey = bucketZeroEntriesContextKey(move.parentPath);
    if (!move.duplicate || !contextKey) {
      continue;
    }
    const rowPath = `${move.parentPath}/${move.fromDocumentId}`;
    const versionToken = move.fromVersionToken ?? "unknown";
    const obligationId = replaySummaryObligationId(contextKey, rowPath, versionToken);
    obligations.set(obligationId, {contextKey, obligationId, rowPath, versionToken});
  }

  const applied = new Set(appliedObligationIds);
  const owedObligations = [];
  const settledObligations = [];
  for (const obligation of obligations.values()) {
    (applied.has(obligation.obligationId) ? settledObligations : owedObligations)
      .push(obligation);
  }

  const summaries = new Map();
  for (const reference of references) {
    if (reference.parentPath === REPLAY_COLLECTION) {
      summaries.set(reference.documentId, reference);
    }
  }

  const decrements = [];
  const notes = [];
  const owedByContext = new Map();
  for (const obligation of owedObligations) {
    const owed = owedByContext.get(obligation.contextKey) ?? [];
    owed.push(obligation);
    owedByContext.set(obligation.contextKey, owed);
  }

  for (const contextKey of [...owedByContext.keys()].sort()) {
    const owed = owedByContext.get(contextKey).sort(
      (lhs, rhs) => lhs.obligationId.localeCompare(rhs.obligationId)
    );
    const droppedRows = owed.length;
    const summary = summaries.get(contextKey);
    if (!summary) {
      notes.push({
        contextKey,
        obligationIds: owed.map((obligation) => obligation.obligationId),
        reason: `${droppedRows} duplicate row(s) owe a decrement but no leaderboard ` +
          "summary exists",
      });
      continue;
    }

    const completedCount = nonNegativeIntegerOrNull(summary.data.completedCount);
    const totalClimbers = nonNegativeIntegerOrNull(summary.data.totalClimbers);
    if (
      completedCount === null ||
      totalClimbers === null ||
      completedCount < droppedRows ||
      totalClimbers < droppedRows
    ) {
      notes.push({
        contextKey,
        obligationIds: owed.map((obligation) => obligation.obligationId),
        reason: `completedCount ${String(summary.data.completedCount)} / totalClimbers ` +
          `${String(summary.data.totalClimbers)} cannot absorb the ${droppedRows} row(s) ` +
          "owed - left for the replay backfill",
      });
      continue;
    }

    decrements.push({
      contextKey,
      obligations: owed.map(({obligationId, rowPath}) => ({obligationId, rowPath})),
      droppedRows,
      currentCounts: {completedCount, totalClimbers},
      projectedCounts: {
        completedCount: completedCount - droppedRows,
        totalClimbers: totalClimbers - droppedRows,
      },
    });
  }

  return {
    decrements,
    owedObligations: owedObligations.sort(compareByObligation),
    settledObligations: settledObligations.sort(compareByObligation),
    notes: notes.sort((lhs, rhs) => lhs.contextKey.localeCompare(rhs.contextKey)),
  };
}

/**
 * Decides what one context's summary transaction must write, under the transaction's own
 * read of the summary and of the markers.
 *
 * The decrement is relative, so a count that grew between the plan and the transaction keeps
 * that growth. Each obligation names one row, and only distinct unsettled ones count, so an
 * obligation already marked applied contributes nothing - which is what makes a rerun after
 * a committed transaction a no-op rather than a second decrement.
 * @param {object} summaryData Summary payload read inside the transaction.
 * @param {string[]} appliedObligationIds Obligation ids the marker document already holds.
 * @param {{obligationId: string}[]} obligations Row obligations to discharge.
 * @return {{droppedRows: number, obligationIds: string[], updates: object|null}} What to
 *   write; a null `updates` means every obligation was already applied.
 */
export function resolveReplaySummaryDecrement(
  summaryData,
  appliedObligationIds,
  obligations
) {
  const applied = new Set(appliedObligationIds);
  const pendingIds = [...new Set(
    obligations
      .map((obligation) => obligation.obligationId)
      .filter((obligationId) => !applied.has(obligationId))
  )];
  if (pendingIds.length === 0) {
    return {droppedRows: 0, obligationIds: [], updates: null};
  }

  const droppedRows = pendingIds.length;
  const completedCount = nonNegativeIntegerOrNull(summaryData?.completedCount);
  const totalClimbers = nonNegativeIntegerOrNull(summaryData?.totalClimbers);
  if (
    completedCount === null ||
    totalClimbers === null ||
    completedCount < droppedRows ||
    totalClimbers < droppedRows
  ) {
    throw new Error(
      `Refusing decrement: completedCount ${String(summaryData?.completedCount)} / ` +
        `totalClimbers ${String(summaryData?.totalClimbers)} cannot absorb the ` +
        `${droppedRows} duplicate row(s) owed.`
    );
  }

  return {
    droppedRows,
    obligationIds: pendingIds,
    updates: {
      completedCount: completedCount - droppedRows,
      totalClimbers: totalClimbers - droppedRows,
    },
  };
}

function compareByObligation(lhs, rhs) {
  return lhs.contextKey.localeCompare(rhs.contextKey) ||
    lhs.obligationId.localeCompare(rhs.obligationId);
}

function bucketZeroEntriesContextKey(parentPath) {
  const segments = parentPath.split("/");
  const isBucketZeroEntriesPath = segments.length === 5 &&
    segments[0] === REPLAY_COLLECTION &&
    segments[2] === "splitBuckets" &&
    segments[3] === "0" &&
    segments[4] === "entries";
  return isBucketZeroEntriesPath ? segments[1] : null;
}

function nonNegativeIntegerOrNull(value) {
  return Number.isInteger(value) && value >= 0 ? value : null;
}

function assertCompleteSource(reference) {
  if (reference.partial) {
    throw new Error(
      `Reference ${referenceLocation(reference)} was scanned without its full payload, ` +
        "so it cannot take part in a canonical-id move."
    );
  }
}

function compareByPlannedPath(lhs, rhs) {
  return lhs.parentPath.localeCompare(rhs.parentPath) ||
    (lhs.fromDocumentId ?? lhs.documentId).localeCompare(rhs.fromDocumentId ?? rhs.documentId);
}

function referenceLocation(reference) {
  return `${reference.parentPath}/${reference.documentId}`;
}

function referencedWorkoutIds(reference) {
  const ids = reference.keyedByWorkoutId ? [reference.documentId] : [];
  for (const field of reference.workoutIdFields) {
    const value = reference.data?.[field];
    if (typeof value === "string" && value.length > 0) {
      ids.push(value);
    }
  }
  return ids;
}

function canonicalFieldUpdates(reference, renameMap) {
  const updates = {};
  for (const field of reference.workoutIdFields) {
    const value = reference.data?.[field];
    if (typeof value === "string" && renameMap.has(value)) {
      updates[field] = renameMap.get(value);
    }
  }
  return updates;
}

function unresolvedWorkoutIds(reference, renameMap) {
  return [...new Set(
    referencedWorkoutIds(reference)
      .filter((workoutId) => !renameMap.has(workoutId) && nonCanonicalWorkoutId(workoutId))
  )].sort();
}

function nonCanonicalWorkoutId(workoutId) {
  try {
    const canonical = canonicalWorkoutDocumentId(workoutId);
    return canonical === workoutId ? null : canonical;
  } catch {
    return null;
  }
}

function canonicalizeEmbeddedReferences(data, canonicalWorkoutId) {
  const result = {...data};
  if (!Array.isArray(data.participations)) {
    return result;
  }

  result.participations = data.participations.map((participation) => {
    if (!participation || typeof participation !== "object") {
      return participation;
    }

    try {
      if (canonicalWorkoutDocumentId(participation.workoutId) === canonicalWorkoutId) {
        return {...participation, workoutId: canonicalWorkoutId};
      }
    } catch {
      // A malformed nested id is a payload conflict, not something to normalize here.
    }
    return participation;
  });
  return result;
}

function firestoreValuesEqual(lhs, rhs) {
  if (Object.is(lhs, rhs)) {
    return true;
  }
  if (lhs == null || rhs == null) {
    return false;
  }
  if (typeof lhs?.toMillis === "function" && typeof rhs?.toMillis === "function") {
    return lhs.toMillis() === rhs.toMillis();
  }
  if (lhs instanceof Date && rhs instanceof Date) {
    return lhs.getTime() === rhs.getTime();
  }
  if (Array.isArray(lhs) || Array.isArray(rhs)) {
    return Array.isArray(lhs) && Array.isArray(rhs) &&
      lhs.length === rhs.length &&
      lhs.every((value, index) => firestoreValuesEqual(value, rhs[index]));
  }
  if (typeof lhs === "object" && typeof rhs === "object") {
    const lhsKeys = Object.keys(lhs).sort();
    const rhsKeys = Object.keys(rhs).sort();
    return lhsKeys.length === rhsKeys.length &&
      lhsKeys.every((key, index) => (
        key === rhsKeys[index] && firestoreValuesEqual(lhs[key], rhs[key])
      ));
  }
  return false;
}

function timestampMillis(value) {
  if (typeof value?.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  return Number.NEGATIVE_INFINITY;
}
