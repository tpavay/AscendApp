const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Returns the one Firestore document-id representation used for workouts.
 * @param {string} rawValue UUID string in any letter case.
 * @return {string} Uppercase canonical UUID string.
 */
export function canonicalWorkoutDocumentId(rawValue) {
  if (typeof rawValue !== "string" || !UUID_PATTERN.test(rawValue)) {
    throw new Error(`Invalid workout UUID: ${String(rawValue)}`);
  }
  return rawValue.toUpperCase();
}

/**
 * Document ids an earlier run wrote for the same entity before ids were canonicalized.
 * Anything keyed by workout document id must delete these, or a ghost row survives
 * alongside the canonical one.
 * @param {string} canonicalId Uppercase canonical UUID document id.
 * @return {string[]} Stale ids to delete, empty when none can exist.
 */
export function staleWorkoutDocumentIds(canonicalId) {
  return [canonicalWorkoutDocumentId(canonicalId).toLowerCase()]
    .filter((id) => id !== canonicalId);
}

/**
 * The number of climbers a replay context has once a seed run replaces its stale
 * case-variant rows with one canonical row.
 *
 * Stale rows are deleted, so they never count. The canonical row always exists
 * afterwards, so it adds one unless it is already present.
 * @param {string[]} bucketZeroDocumentIds Existing bucket-zero entry document ids.
 * @param {string} canonicalWorkoutId Canonical document id this run seeds.
 * @return {number} Post-seed completed climber count.
 */
export function seededReplayCompletedCount(bucketZeroDocumentIds, canonicalWorkoutId) {
  const staleIds = new Set(staleWorkoutDocumentIds(canonicalWorkoutId));
  const survivingCount = bucketZeroDocumentIds.filter((id) => !staleIds.has(id)).length;
  const hasCanonicalRow = bucketZeroDocumentIds.includes(canonicalWorkoutId);
  return survivingCount + (hasCanonicalRow ? 0 : 1);
}
