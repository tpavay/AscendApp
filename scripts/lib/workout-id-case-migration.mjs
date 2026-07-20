import {canonicalWorkoutDocumentId} from "./workout-document-id.mjs";

export const BATCH_WRITE_LIMIT = 500;

/**
 * Write counts per atomic unit. A canonicalization group must land in one batch so a
 * workout can never lose its non-canonical document without gaining its canonical one;
 * each rebuilt landmarkResult stands alone.
 * @param {object[]} merges Planned canonicalization groups.
 * @param {object[]} affectedProjections Landmark projections to rebuild.
 * @return {number[]} Write count for each atomic unit, in apply order.
 */
export function plannedUnitSizes(merges, affectedProjections) {
  return [
    ...merges.map((merge) => 1 + merge.deleteWorkoutIds.length),
    ...affectedProjections.map(() => 1),
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

  for (const document of ordered.slice(1)) {
    const candidate = canonicalizeEmbeddedReferences(document.data, canonicalWorkoutId);
    for (const [key, value] of Object.entries(candidate)) {
      if (key === "updatedAt") {
        if (timestampMillis(value) > timestampMillis(targetData.updatedAt)) {
          targetData.updatedAt = value;
        }
        continue;
      }

      if (!(key in targetData)) {
        targetData[key] = value;
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
    sourceDocuments: group.map(({userId, workoutId, data}) => ({userId, workoutId, data})),
  };
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
