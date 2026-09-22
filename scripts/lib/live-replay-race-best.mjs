/**
 * The race-best rule for the seeding scripts.
 *
 * Mirrors functions/src/liveReplayRaceBest.ts. The seeds write the entries the
 * app reads, and a live window over the global Just Climb board filters on
 * `isBestForUser` (no goal: the most steps) or on a goal key inside
 * `bestForGoals` (a step goal: the fastest run to that count; a duration goal:
 * the most steps within it). A seeded rival whose rows spell a key differently
 * from the server, or pick a different winner, is simply absent from the race
 * - the failure looks like an empty board, not like a bug. Both sides are
 * pinned against SharedTestVectors/live-replay-race-best-vector.json; add a
 * case there rather than editing one side alone.
 *
 * Settled by the captain on 2026-09-22. `ascend-leaderboards` owns the rule;
 * this file states only the mechanism the seeds need.
 */

export const RACE_STEP_GOAL_INCREMENT = 100;
export const RACE_STEP_GOAL_MIN = 100;
export const RACE_STEP_GOAL_MAX = 20000;
export const RACE_DURATION_GOAL_INCREMENT_SECONDS = 300;
export const RACE_DURATION_GOAL_MIN_SECONDS = 300;
export const RACE_DURATION_GOAL_MAX_SECONDS = 10800;

const ROUTINE_TEMPLATE_CONTEXT_TYPE = "routine_template";
const JUST_CLIMB_CONTEXT_TYPE = "just_climb";

/**
 * Mirrors `ATTEMPT_CURVES_COLLECTION` in functions/src/liveReplayLeaderboard.ts:
 * the server-only subcollection under a board that holds one split curve per
 * attempt, keyed by workout id.
 */
export const ATTEMPT_CURVES_COLLECTION = "attemptCurves";

/**
 * Mirrors `raceBestOnSteps` in functions/src/liveReplayLeaderboard.ts: whether
 * a board's live race collapses a climber's attempts on steps rather than
 * time. Not the ranking metric - a Just Climb still ranks its standings on
 * the clock while its race best is the most steps.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when the most steps is the race best.
 */
export function raceBestOnSteps(contextType) {
  return contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE ||
    contextType === JUST_CLIMB_CONTEXT_TYPE;
}

/**
 * Mirrors `contextRacesGoals`: only the global Just Climb board carries
 * `bestForGoals`.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when entries carry goal keys.
 */
export function contextRacesGoals(contextType) {
  return contextType === JUST_CLIMB_CONTEXT_TYPE;
}

export function stepGoalKey(steps) {
  return `steps:${steps}`;
}

export function durationGoalKey(seconds) {
  return `duration:${seconds}`;
}

export function raceStepGoals() {
  return rangeInclusive(RACE_STEP_GOAL_MIN, RACE_STEP_GOAL_MAX, RACE_STEP_GOAL_INCREMENT);
}

export function raceDurationGoals() {
  return rangeInclusive(
    RACE_DURATION_GOAL_MIN_SECONDS,
    RACE_DURATION_GOAL_MAX_SECONDS,
    RACE_DURATION_GOAL_INCREMENT_SECONDS
  );
}

/**
 * Mirrors `attemptCurveWrite`: the fields the server stores for one attempt's
 * curve, so a seeded curve reads back exactly as a published one and neither
 * the trigger nor the backfill ever rebuilds a differently anchored curve
 * from the seeded bucket entries.
 * @param {string} userId Owner user ID.
 * @param {object} curve Attempt curve with `splitSteps[i]` at
 *   `(i + 1) * splitIntervalSeconds`.
 * @param {unknown} updatedAt Write timestamp.
 * @return {object} Fields to write.
 */
export function attemptCurveWrite(userId, curve, updatedAt) {
  return {
    finalDurationSeconds: curve.finalDurationSeconds,
    finalSteps: curve.finalSteps,
    schemaVersion: 1,
    splitIntervalSeconds: curve.splitIntervalSeconds,
    splitSteps: curve.splitSteps,
    updatedAt,
    userId,
    workoutId: curve.workoutId,
  };
}

/**
 * Mirrors `prepareRaceAttemptCurve`: builds an attempt's polyline once so
 * every one of the 236 goals reads it rather than rebuilding it.
 * @param {object} attempt Attempt curve, prepared or not.
 * @return {object} The attempt with its `points` built.
 */
export function prepareRaceAttemptCurve(attempt) {
  if ("points" in attempt) {
    return attempt;
  }
  return {
    workoutId: attempt.workoutId,
    finalSteps: attempt.finalSteps,
    finalDurationSeconds: attempt.finalDurationSeconds,
    points: curvePoints(attempt),
  };
}

/**
 * The cumulative steps an attempt had reached `seconds` in: piecewise linear
 * through the origin, every checkpoint and the finish, and the finish itself
 * for any later moment.
 * @param {object} curve Attempt curve, prepared or not.
 * @param {number} seconds Elapsed seconds.
 * @return {number} Steps reached by then.
 */
export function stepsAtElapsed(curve, seconds) {
  const points = prepareRaceAttemptCurve(curve).points;
  const finish = points[points.length - 1];

  if (seconds <= 0) {
    return 0;
  }
  if (seconds >= finish.seconds) {
    return finish.steps;
  }

  let previous = {seconds: 0, steps: 0};
  for (const point of points) {
    if (seconds <= point.seconds) {
      return Math.round(interpolate(previous, point, seconds));
    }
    previous = point;
  }

  return finish.steps;
}

/**
 * How long an attempt took to first reach `steps`, or null when it never did.
 * @param {object} curve Attempt curve, prepared or not.
 * @param {number} steps Step count.
 * @return {number | null} Seconds, or null.
 */
export function secondsToReach(curve, steps) {
  if (steps <= 0) {
    return 0;
  }
  if (steps > curve.finalSteps) {
    return null;
  }

  let previous = {seconds: 0, steps: 0};
  for (const point of prepareRaceAttemptCurve(curve).points) {
    if (point.steps >= steps) {
      if (point.steps === previous.steps) {
        return point.seconds;
      }
      const fraction = (steps - previous.steps) / (point.steps - previous.steps);
      return previous.seconds + (point.seconds - previous.seconds) * fraction;
    }
    previous = point;
  }

  return curve.finalDurationSeconds;
}

export function mostStepsAttemptId(attempts) {
  return winner(attempts, (attempt) => attempt.finalSteps, "highest");
}

export function fastestToStepsAttemptId(attempts, steps) {
  return winner(attempts, (attempt) => secondsToReach(attempt, steps), "lowest");
}

export function mostStepsWithinAttemptId(attempts, seconds) {
  return winner(attempts, (attempt) => stepsAtElapsed(attempt, seconds), "highest");
}

/**
 * Every goal key each attempt wins, sorted, keyed by workout id - an attempt
 * that wins nothing maps to an empty list.
 * @param {object[]} attempts One climber's attempts.
 * @return {Map<string, string[]>} Goal keys by workout id.
 */
export function raceGoalKeysByWorkoutId(attempts) {
  const prepared = attempts.map(prepareRaceAttemptCurve);
  const keys = new Map(prepared.map((attempt) => [attempt.workoutId, []]));
  const award = (workoutId, key) => {
    if (workoutId !== null) {
      keys.get(workoutId)?.push(key);
    }
  };

  for (const steps of raceStepGoals()) {
    award(fastestToStepsAttemptId(prepared, steps), stepGoalKey(steps));
  }
  for (const seconds of raceDurationGoals()) {
    award(mostStepsWithinAttemptId(prepared, seconds), durationGoalKey(seconds));
  }

  for (const list of keys.values()) {
    list.sort();
  }

  return keys;
}

function curvePoints(curve) {
  const interval = Math.max(curve.splitIntervalSeconds, 1);
  const finishSeconds = Math.max(curve.finalDurationSeconds, 0);
  const finishSteps = Math.max(curve.finalSteps, 0);
  const points = [];
  let lastSteps = 0;

  for (let index = 0; index < curve.splitSteps.length; index += 1) {
    const seconds = (index + 1) * interval;
    if (seconds >= finishSeconds) {
      break;
    }
    lastSteps = Math.min(Math.max(curve.splitSteps[index], lastSteps, 0), finishSteps);
    points.push({seconds, steps: lastSteps});
  }

  points.push({seconds: finishSeconds, steps: finishSteps});
  return points;
}

function interpolate(from, to, seconds) {
  if (to.seconds === from.seconds) {
    return to.steps;
  }
  const fraction = (seconds - from.seconds) / (to.seconds - from.seconds);
  return from.steps + (to.steps - from.steps) * fraction;
}

function winner(attempts, value, wins) {
  let best = null;

  for (const attempt of attempts) {
    const candidate = value(attempt);
    if (candidate === null) {
      continue;
    }

    const isBetter = best === null ||
      (wins === "highest" ? candidate > best.value : candidate < best.value);
    const breaksTie = best !== null &&
      candidate === best.value &&
      attempt.workoutId < best.workoutId;

    if (isBetter || breaksTie) {
      best = {workoutId: attempt.workoutId, value: candidate};
    }
  }

  return best?.workoutId ?? null;
}

function rangeInclusive(from, to, step) {
  const values = [];
  for (let value = from; value <= to; value += step) {
    values.push(value);
  }
  return values;
}
