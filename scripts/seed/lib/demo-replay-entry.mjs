import {
  attemptCurveWrite,
  contextRacesGoals,
  raceGoalKeysByWorkoutId,
} from "../../lib/live-replay-race-best.mjs";

/**
 * The split curve behind one demo-user attempt, as the server stores it.
 *
 * Re-anchored to the end of each interval the way the server publishes it:
 * `context.splitSteps[0]` is the start line on the bucket entries, so the
 * curve drops it and `splitSteps[i]` sits at `(i + 1) * splitIntervalSeconds`.
 * The entry's goal keys and the stored curve document both derive from this
 * one value, so the trigger and the backfill read back the curve the keys
 * were judged on rather than rebuilding a differently anchored one.
 * @param {object} input Curve inputs.
 * @return {object} Race attempt curve.
 */
export function buildDemoReplayCurve({context, splitIntervalSeconds}) {
  return {
    workoutId: context.workoutId,
    finalSteps: context.finalSteps,
    finalDurationSeconds: context.durationSeconds,
    splitIntervalSeconds,
    splitSteps: context.splitSteps.slice(1),
  };
}

/**
 * The `attemptCurves/{workoutId}` document a demo Just Climb attempt stores
 * beside its bucket entries, or null off a goal-racing board.
 * @param {object} input Curve inputs.
 * @return {object | null} Firestore curve fields, or null.
 */
export function buildDemoAttemptCurveWrite({
  context,
  splitIntervalSeconds,
  updatedAt,
  user,
}) {
  if (!contextRacesGoals(context.contextType)) {
    return null;
  }
  return attemptCurveWrite(
    user.uid,
    buildDemoReplayCurve({context, splitIntervalSeconds}),
    updatedAt
  );
}

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
    // reached, judged on the same curve `buildDemoAttemptCurveWrite` stores.
    ...(contextRacesGoals(context.contextType) ?
      {
        bestForGoals: raceGoalKeysByWorkoutId([
          buildDemoReplayCurve({context, splitIntervalSeconds}),
        ]).get(context.workoutId) ?? [],
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
