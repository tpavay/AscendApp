/**
 * The single Node/ESM copy of the "a landmark completion we trust" contract,
 * mirroring the Swift predicate
 * (AscendApp/Features/Climbs/Models/LegacyClimbCompletionPredicate.swift) and
 * the TypeScript predicate (functions/src/legacyClimbCompletion.ts). The same
 * conditions gate the client hydration guard, the replay publication fallback,
 * the landmarkResults derivation, and the backfills, so they must never drift.
 * Every copy is pinned by the shared vector at
 * SharedTestVectors/legacy-recoverable-completion-vector.json - the parity
 * mechanism across languages is that vector, not shared code.
 *
 * Before this module the scripts had their own inline fourth copy (flagged in
 * the #229 review at backfill-legacy-live-replay-completions.mjs:175); both
 * backfills now import from here so there is one mjs definition, vector-pinned.
 *
 * A completion is trusted iff it is a headphone-motion capture, names a landmark
 * (non-empty climbId), and finished by the completion policy's own rule: steps
 * >= target when a step target was recorded, otherwise stopReason
 * target_reached. This covers both modern completions (a target recorded, steps
 * >= target) and legacy ones (no target recorded, target_reached).
 */

export const HEADPHONE_MOTION_SOURCE = "headphone_motion";
export const TARGET_REACHED_STOP_REASON = "target_reached";

/**
 * Evaluates the shared contract on already-resolved predicate fields.
 * @param {object} fields Resolved fields.
 * @param {string} fields.source Workout source.
 * @param {string|null} fields.climbId Landmark id.
 * @param {string} fields.stopReason Session stop reason.
 * @param {number} fields.steps Recorded steps.
 * @param {number|null} fields.targetStepCount Resolved step target, or null.
 * @return {boolean} True when the completion is trusted.
 */
export function isRecoverableLegacyCompletion(fields) {
  if (fields.source !== HEADPHONE_MOTION_SOURCE) {
    return false;
  }
  if (!fields.climbId) {
    return false;
  }
  if (fields.targetStepCount !== null && fields.targetStepCount > 0) {
    return fields.steps >= fields.targetStepCount;
  }
  return fields.stopReason === TARGET_REACHED_STOP_REASON;
}

/**
 * Convenience over a raw workout document + parsed metadata: resolves the
 * predicate fields (target = climbTargetStepCount ?? targetStepCount) and
 * evaluates the shared contract.
 * @param {Record<string, unknown>} data Raw workout document data.
 * @param {Record<string, unknown>} metadata Parsed source metadata.
 * @return {boolean} True when this is a trusted completion.
 */
export function isRecoverableLegacyCompletionForWorkout(data, metadata) {
  const target = positiveInteger(metadata.climbTargetStepCount) ??
    positiveInteger(metadata.targetStepCount);
  return isRecoverableLegacyCompletion({
    source: nonEmptyString(metadata.source) ?? nonEmptyString(data.source),
    climbId: nonEmptyString(metadata.climbId),
    stopReason: nonEmptyString(metadata.stopReason) ?? "",
    steps: nonNegativeInteger(data.steps) ?? 0,
    targetStepCount: target,
  });
}

/**
 * Parses a non-empty trimmed string, else null.
 * @param {unknown} value Raw value.
 * @return {string|null} Parsed string.
 */
export function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

/**
 * Parses a non-negative integer, else null.
 * @param {unknown} value Raw value.
 * @return {number|null} Parsed integer.
 */
export function nonNegativeInteger(value) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ?
    value :
    null;
}

/**
 * Parses a positive integer, else null.
 * @param {unknown} value Raw value.
 * @return {number|null} Parsed integer.
 */
export function positiveInteger(value) {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ?
    value :
    null;
}
