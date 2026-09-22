import {
  contextRacesGoals,
  raceGoalKeysByWorkoutId,
} from "../../lib/live-replay-race-best.mjs";

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
    // A Just Climb run against a goal filters on `bestForGoals`, and a demo
    // user's one attempt per context is their best under every goal it
    // reached. The curve is re-anchored to the end of each interval the way
    // the server publishes it (index 0 here is the start line).
    ...(contextRacesGoals(context.contextType) ?
      {
        bestForGoals: raceGoalKeysByWorkoutId([{
          workoutId: context.workoutId,
          finalSteps: context.finalSteps,
          finalDurationSeconds: context.durationSeconds,
          splitIntervalSeconds,
          splitSteps: context.splitSteps.slice(1),
        }]).get(context.workoutId) ?? [],
      } :
      {}),
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
