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
