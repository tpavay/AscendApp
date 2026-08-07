/**
 * Builds one demo-user replay entry with the server-owned context contract.
 * @param {object} input Entry inputs.
 * @return {object} Firestore replay entry fields.
 */
export function buildDemoReplayEntry({
  context,
  identityState,
  schemaVersion,
  splitIndex,
  splitIntervalSeconds,
  updatedAt,
  user,
}) {
  return {
    avatarToken: user.avatarToken,
    completionDurationSeconds: context.durationSeconds,
    contextId: context.contextId,
    contextType: context.contextType,
    displayName: user.displayName,
    finalSteps: context.finalSteps,
    ...(context.contextType === "live_climb" ? {isBestForUser: true} : {}),
    identityState,
    isPersonalBest: true,
    isSynthetic: false,
    photoURL: user.photoURL,
    schemaVersion,
    splitBucketCount: context.splitSteps.length,
    splitIntervalSeconds,
    stepsAtBucket: context.splitSteps[splitIndex],
    updatedAt,
    userId: user.uid,
    workoutId: context.workoutId,
  };
}
