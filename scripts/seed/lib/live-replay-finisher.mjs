/**
 * The finisher document a seeded replay board writes beside its entry rows.
 *
 * A publish writes a finisher in the same transaction as the row it stands for,
 * and the rank frozen on a finished climb counts finisher documents - one per
 * climber, the same population the summary's `completedCount` counts. A seeded
 * board carrying entries but no finishers reads as an empty field, which would
 * freeze a mid-field climber at "1st of 84".
 */

/**
 * The finisher field holding a climber's standing best on each metric. A
 * finisher written without the metric its board ranks on is invisible to the
 * inequality the frozen rank counts through.
 */
export const DURATION_BEST_METRIC = "bestCompletionDurationSeconds";
export const STEPS_BEST_METRIC = "bestFinalSteps";

const ROUTINE_TEMPLATE_CONTEXT_TYPE = "routine_template";

/**
 * Builds one synthetic finisher document.
 *
 * Every synthetic attempt is its own climber, so its own attempt is its best.
 * @param {object} attempt Generated attempt.
 * @param {string} attempt.id Attempt workout ID.
 * @param {string} attempt.userId Synthetic climber ID.
 * @param {string} attempt.displayName Synthetic display name.
 * @param {string} attempt.avatarToken Synthetic avatar token.
 * @param {string | null} attempt.photoURL Synthetic avatar URL.
 * @param {number} attempt.completionDurationSeconds Attempt clock.
 * @param {number} attempt.finalSteps Attempt steps.
 * @param {object} context Finisher context.
 * @param {string} context.contextType Replay context type.
 * @param {number} context.globalCompletionOrder Permanent finisher order.
 * @param {string} context.identityState Projection identity lifecycle state.
 * @param {number} context.schemaVersion Replay schema version.
 * @param {string} context.seedPackId Seed pack ID.
 * @param {object} context.updatedAt Server timestamp sentinel.
 * @return {object} Finisher document fields.
 */
export function syntheticFinisherWrite(attempt, context) {
  return {
    avatarToken: attempt.avatarToken,
    bestWorkoutId: attempt.id,
    contextType: context.contextType,
    displayName: attempt.displayName,
    firstWorkoutId: attempt.id,
    globalCompletionOrder: context.globalCompletionOrder,
    identityState: context.identityState,
    isSynthetic: true,
    photoURL: attempt.photoURL ?? "",
    schemaVersion: context.schemaVersion,
    seedPackId: context.seedPackId,
    updatedAt: context.updatedAt,
    userId: attempt.userId,
    ...bestMetricField(attempt, context.contextType),
  };
}

/**
 * The single best field a context's board ranks its finishers on.
 *
 * A climb fixes the step target and lets the clock vary; a routine fixes the
 * clock and lets the steps vary. Storing both would leave a routine finisher
 * carrying a "best duration" that reads as a time to beat on a board where
 * every finisher spends the same time.
 * @param {object} attempt Generated attempt.
 * @param {string} contextType Replay context type.
 * @return {object} The one best-metric field for this context.
 */
function bestMetricField(attempt, contextType) {
  return contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE ?
    {[STEPS_BEST_METRIC]: attempt.finalSteps} :
    {[DURATION_BEST_METRIC]: attempt.completionDurationSeconds};
}
