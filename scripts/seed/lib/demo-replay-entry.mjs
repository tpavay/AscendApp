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
    // Every context type races `isBestForUser == true` now, and a demo user
    // publishes one attempt per context, so it is always their best. Omitting
    // it would leave the row unreachable to the live race - Firestore equality
    // never matches a missing field.
    isBestForUser: true,
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
