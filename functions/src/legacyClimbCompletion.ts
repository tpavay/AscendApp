/**
 * The single definition of "a legacy completion we trust enough to publish".
 *
 * This mirrors the Swift predicate in
 * AscendApp/Features/Climbs/Models/LegacyClimbCompletionPredicate.swift. The
 * same four conditions gate the client hydration guard, this replay
 * publication fallback, and the eventual Phase 3 migration, so they must never
 * drift. Both implementations are pinned by the shared vector at
 * SharedTestVectors/legacy-recoverable-completion-vector.json.
 *
 * A legacy completion is recoverable iff it is a headphone-motion capture,
 * names a landmark (non-empty climbId), and finished by the completion policy's
 * own rule: steps >= target when a step target was recorded, otherwise
 * stopReason === target_reached.
 *
 * This predicate decides publishability only. It never grants First Ascent. A
 * First Ascent is permanent and unreclaimable, so hand-derived or backfilled
 * data must never claim one - the caller withholds First Ascent for every row
 * that qualifies through this fallback.
 */

export const HEADPHONE_MOTION_SOURCE = "headphone_motion";
export const TARGET_REACHED_STOP_REASON = "target_reached";

export interface LegacyCompletionFields {
  source: string;
  climbId: string | null;
  stopReason: string;
  steps: number;
  /** Resolved target (climbTargetStepCount ?? targetStepCount), or null. */
  targetStepCount: number | null;
}

/**
 * Evaluates the shared legacy-completion contract on already-resolved fields.
 * @param {LegacyCompletionFields} fields Resolved predicate fields.
 * @return {boolean} True when the completion is a trusted legacy recovery.
 */
export function isRecoverableLegacyCompletion(
  fields: LegacyCompletionFields
): boolean {
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
