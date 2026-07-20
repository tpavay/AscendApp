import {
  deriveLandmarkResult,
  groupCompletions,
  parseCompletedLandmarkWorkout,
} from "./landmark-result-derivation.mjs";
import {canonicalWorkoutDocumentId} from "./workout-document-id.mjs";

export const BATCH_WRITE_LIMIT = 500;
const REPLAY_COLLECTION = "live_replay_leaderboards";

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
 * @param {{userId: string, workoutId: string, data: Record<string, unknown>}[]} documents
 *   Raw private workout documents.
 * @return {{merges: object[], conflicts: object[]}} Safe merges and blocked groups.
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
  for (const group of groups.values()) {
    const sourceIDs = [...new Set(group.map((document) => document.workoutId))];
    if (sourceIDs.every((workoutId) => workoutId === group[0].canonicalWorkoutId)) {
      continue;
    }

    const result = mergeGroup(group);
    if (result.conflictingFields.length > 0) {
      conflicts.push(result);
    } else {
      merges.push(result);
    }
  }

  return {merges, conflicts};
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
 * A run that dies between its move batches and its summary batch leaves the ledger holding
 * the final counts it had already proven, while live state now shows fewer duplicates than
 * it started with. The ledger target wins there: the rows it counted are gone, not
 * uncounted. A live delta is only allowed to push the target lower, for duplicates that
 * appeared after the ledger was written, so a rerun converges on the original target
 * instead of stopping one short of it.
 *
 * A summary that cannot absorb the delta - missing, non-integer, or smaller than the number
 * of rows removed - is reported and left untouched, and a count is never raised. Completion
 * orders and the point-in-time rank snapshots derived from them are never rewritten; they
 * are permanent.
 * @param {object[]} moves Planned reference moves.
 * @param {object[]} references Scanned workout-id references.
 * @param {{contextKey: string, completedCount: number, totalClimbers: number}[]} carriedRepairs
 *   Expected counts an earlier unfinished run owes.
 * @return {{summaryUpdates: object[], owedRepairs: object[], notes: object[]}}
 *   Planned decrements, what to record on the ledger, and contexts left for an operator.
 */
export function planReplaySummaryRepairs(moves, references, carriedRepairs = []) {
  const droppedRowsByContext = new Map();
  for (const move of moves) {
    const contextKey = bucketZeroEntriesContextKey(move.parentPath);
    if (move.duplicate && contextKey) {
      droppedRowsByContext.set(contextKey, (droppedRowsByContext.get(contextKey) ?? 0) + 1);
    }
  }

  const carriedByContext = new Map(
    carriedRepairs.map((carried) => [carried.contextKey, carried])
  );
  const summaries = new Map();
  for (const reference of references) {
    if (reference.parentPath === REPLAY_COLLECTION) {
      summaries.set(reference.documentId, reference);
    }
  }

  const summaryUpdates = [];
  const owedRepairs = [];
  const notes = [];
  const contextKeys = [...new Set([
    ...droppedRowsByContext.keys(),
    ...carriedByContext.keys(),
  ])].sort();

  for (const contextKey of contextKeys) {
    const droppedRows = droppedRowsByContext.get(contextKey) ?? 0;
    const carried = carriedByContext.get(contextKey) ?? null;
    const summary = summaries.get(contextKey);
    if (!summary) {
      notes.push({
        contextKey,
        reason: droppedRows > 0 ?
          `${droppedRows} duplicate row(s) removed but no leaderboard summary exists` :
          "leaderboard summary owed a decrement no longer exists",
      });
      if (carried) {
        owedRepairs.push(carried);
      }
      continue;
    }

    const target = replaySummaryTarget(summary.data, droppedRows, carried);
    if (!target) {
      notes.push({
        contextKey,
        reason: `completedCount ${String(summary.data.completedCount)} / totalClimbers ` +
          `${String(summary.data.totalClimbers)} cannot absorb ${droppedRows} removed ` +
          `row(s)${carried ? " or the counts owed on the ledger" : ""} - left for the ` +
          "replay backfill",
      });
      if (carried) {
        owedRepairs.push(carried);
      }
      continue;
    }

    owedRepairs.push({contextKey, ...target});
    if (
      summary.data.completedCount !== target.completedCount ||
      summary.data.totalClimbers !== target.totalClimbers
    ) {
      summaryUpdates.push({
        contextKey,
        updates: target,
        droppedRows,
        fromLedger: Boolean(carried),
      });
    }
  }

  return {
    summaryUpdates: summaryUpdates.sort((lhs, rhs) => lhs.contextKey.localeCompare(rhs.contextKey)),
    owedRepairs: owedRepairs.sort((lhs, rhs) => lhs.contextKey.localeCompare(rhs.contextKey)),
    notes: notes.sort((lhs, rhs) => lhs.contextKey.localeCompare(rhs.contextKey)),
  };
}

function replaySummaryTarget(data, droppedRows, carried) {
  const completedCount = nonNegativeIntegerOrNull(data.completedCount);
  const totalClimbers = nonNegativeIntegerOrNull(data.totalClimbers);
  if (completedCount === null || totalClimbers === null) {
    return null;
  }

  const candidates = [];
  if (droppedRows > 0 && completedCount >= droppedRows && totalClimbers >= droppedRows) {
    candidates.push({
      completedCount: completedCount - droppedRows,
      totalClimbers: totalClimbers - droppedRows,
    });
  }
  if (carried) {
    const carriedCompleted = nonNegativeIntegerOrNull(carried.completedCount);
    const carriedTotal = nonNegativeIntegerOrNull(carried.totalClimbers);
    const fitsWithoutRaising = carriedCompleted !== null &&
      carriedTotal !== null &&
      carriedCompleted <= completedCount &&
      carriedTotal <= totalClimbers;
    if (fitsWithoutRaising) {
      candidates.push({completedCount: carriedCompleted, totalClimbers: carriedTotal});
    }
  }
  if (candidates.length === 0) {
    return null;
  }

  return {
    completedCount: Math.min(...candidates.map((candidate) => candidate.completedCount)),
    totalClimbers: Math.min(...candidates.map((candidate) => candidate.totalClimbers)),
  };
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
