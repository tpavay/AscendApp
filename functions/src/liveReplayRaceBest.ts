/*
 * Which of a climber's published attempts is their best on the global Just
 * Climb board, and the goal keys that say so on every bucket entry.
 *
 * A live race is a field of climbers, one row per climber, and the `BEST`
 * marker inside the viewer's own row is their previous best. On a tower or a
 * routine template "best" is the board's own ranking metric. On a Just Climb
 * it is not: the captain settled on 2026-09-22 that a Just Climb's previous
 * best depends on the goal the climber set for THIS session -
 *
 *   - no goal:       their most steps, all time;
 *   - a step goal:   their fastest time to reach that count across every
 *                    previous climb, a longer climb counting through its
 *                    split at that count;
 *   - a duration:    the most steps they had reached within that duration,
 *                    a climb that ended earlier counting at its final steps.
 *
 * "Previous climbs" is every climb published to `just_climb__global`, of every
 * context type - a landmark Live Climb counts as much as an open session.
 * Rivals follow the same rule, so the field a goal session races is one row
 * per climber on that climber's best *for that goal*.
 *
 * One stored flag cannot express a goal-dependent best, so a Just Climb entry
 * carries `bestForGoals`: the goal keys under which its attempt is that
 * climber's best. The goal space is exactly what the setup sheet offers -
 * step goals from 100 to 20,000 in hundreds and durations from five minutes
 * to three hours in five-minute steps - so a live window filters with a
 * single `array-contains` on the viewer's goal key. The no-goal best stays on
 * `isBestForUser`, the flag every board carries.
 *
 * Every rule here is pinned on three sides by
 * `SharedTestVectors/live-replay-race-best-vector.json`: this module, the
 * iOS `LiveReplayRaceGoal`, and the seeds'
 * `scripts/lib/live-replay-race-best.mjs`.
 */

/** The step goals the Just Climb setup sheet offers, in steps. */
export const RACE_STEP_GOAL_INCREMENT = 100;
export const RACE_STEP_GOAL_MIN = 100;
export const RACE_STEP_GOAL_MAX = 20000;

/** The duration goals the Just Climb setup sheet offers, in seconds. */
export const RACE_DURATION_GOAL_INCREMENT_SECONDS = 300;
export const RACE_DURATION_GOAL_MIN_SECONDS = 300;
export const RACE_DURATION_GOAL_MAX_SECONDS = 10800;

/**
 * One published attempt as the race-best rules see it: its split curve and
 * the two numbers that close it.
 *
 * `splitSteps[i]` is the cumulative step count at
 * `(i + 1) * splitIntervalSeconds` - the anchoring
 * `liveReplaySplitNormalization.ts` states - and the curve may stop short of
 * the finish (`MAX_REPLAY_SPLIT_CHECKPOINTS`), in which case the finish itself
 * is the last known point.
 */
export interface RaceAttemptCurve {
  workoutId: string;
  finalSteps: number;
  finalDurationSeconds: number;
  splitIntervalSeconds: number;
  splitSteps: number[];
}

/** One point on an attempt's polyline. */
export interface CurvePoint {
  seconds: number;
  steps: number;
}

/**
 * An attempt with its polyline already built.
 *
 * Every goal evaluation walks the same polyline, and a climber's history is
 * judged against 236 goals, so the points are built once per attempt and the
 * interpolators read them rather than rebuilding the curve per goal.
 */
export interface PreparedRaceAttemptCurve {
  workoutId: string;
  finalSteps: number;
  finalDurationSeconds: number;
  points: CurvePoint[];
}

export type RaceAttempt = RaceAttemptCurve | PreparedRaceAttemptCurve;

/**
 * Builds an attempt's polyline once so every goal can read it.
 * @param {RaceAttempt} attempt Attempt curve, prepared or not.
 * @return {PreparedRaceAttemptCurve} The attempt with its points built.
 */
export function prepareRaceAttemptCurve(
  attempt: RaceAttempt
): PreparedRaceAttemptCurve {
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
 * The entry filter key for one step goal.
 * @param {number} steps Step goal.
 * @return {string} Goal key.
 */
export function stepGoalKey(steps: number): string {
  return `steps:${steps}`;
}

/**
 * The entry filter key for one duration goal.
 * @param {number} seconds Duration goal in seconds.
 * @return {string} Goal key.
 */
export function durationGoalKey(seconds: number): string {
  return `duration:${seconds}`;
}

/**
 * Every step goal the setup sheet can produce.
 * @return {number[]} Step goals, ascending.
 */
export function raceStepGoals(): number[] {
  return rangeInclusive(
    RACE_STEP_GOAL_MIN,
    RACE_STEP_GOAL_MAX,
    RACE_STEP_GOAL_INCREMENT
  );
}

/**
 * Every duration goal the setup sheet can produce, in seconds.
 * @return {number[]} Duration goals, ascending.
 */
export function raceDurationGoals(): number[] {
  return rangeInclusive(
    RACE_DURATION_GOAL_MIN_SECONDS,
    RACE_DURATION_GOAL_MAX_SECONDS,
    RACE_DURATION_GOAL_INCREMENT_SECONDS
  );
}

/**
 * The cumulative steps an attempt had reached `seconds` into its climb.
 *
 * Piecewise linear through the origin, every checkpoint, and the finish. A
 * moment past the finish reads the finish: a climb that ended before the
 * duration counts at its final steps.
 * @param {RaceAttempt} curve Attempt curve, prepared or not.
 * @param {number} seconds Elapsed seconds into the attempt.
 * @return {number} Steps reached by then.
 */
export function stepsAtElapsed(
  curve: RaceAttempt,
  seconds: number
): number {
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
 *
 * The inverse of `stepsAtElapsed` on the same polyline: the first checkpoint
 * at or past the count closes the segment, and the crossing is interpolated
 * inside it. A flat stretch is never divided through - the segment that
 * crosses the count always rises.
 * @param {RaceAttempt} curve Attempt curve, prepared or not.
 * @param {number} steps Step count to reach.
 * @return {number | null} Seconds to reach it, or null when unreached.
 */
export function secondsToReach(
  curve: RaceAttempt,
  steps: number
): number | null {
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
      const fraction =
        (steps - previous.steps) / (point.steps - previous.steps);
      return previous.seconds + (point.seconds - previous.seconds) * fraction;
    }
    previous = point;
  }

  return curve.finalDurationSeconds;
}

/**
 * The climber's best with no goal set: their most steps, all time.
 * @param {RaceAttempt[]} attempts One climber's published attempts.
 * @return {string | null} Winning workout id, or null with no attempts.
 */
export function mostStepsAttemptId(
  attempts: RaceAttempt[]
): string | null {
  return winner(attempts, (attempt) => attempt.finalSteps, "highest");
}

/**
 * The climber's best for a step goal: their fastest time to reach it, across
 * every attempt that reached it.
 * @param {RaceAttempt[]} attempts One climber's published attempts.
 * @param {number} steps Step goal.
 * @return {string | null} Winning workout id, or null when none reached it.
 */
export function fastestToStepsAttemptId(
  attempts: RaceAttempt[],
  steps: number
): string | null {
  return winner(attempts, (attempt) => secondsToReach(attempt, steps), "lowest");
}

/**
 * The climber's best for a duration goal: the most steps they had reached
 * within it, a climb that ended earlier counting at its final steps.
 * @param {RaceAttempt[]} attempts One climber's published attempts.
 * @param {number} seconds Duration goal in seconds.
 * @return {string | null} Winning workout id, or null with no attempts.
 */
export function mostStepsWithinAttemptId(
  attempts: RaceAttempt[],
  seconds: number
): string | null {
  return winner(attempts, (attempt) => stepsAtElapsed(attempt, seconds), "highest");
}

/**
 * Every goal key each of a climber's attempts wins, sorted, for every attempt
 * - an attempt that wins nothing maps to an empty list, so a diff against
 * stored entries sees every attempt.
 *
 * A step goal nobody reached is nobody's, so the arrays stay bounded by what
 * the climber has actually climbed.
 * @param {RaceAttempt[]} attempts One climber's published attempts.
 * @return {Map<string, string[]>} Goal keys by workout id.
 */
export function raceGoalKeysByWorkoutId(
  attempts: RaceAttempt[]
): Map<string, string[]> {
  const prepared = attempts.map(prepareRaceAttemptCurve);
  const keys = new Map<string, string[]>(
    prepared.map((attempt) => [attempt.workoutId, []])
  );
  const award = (workoutId: string | null, key: string) => {
    if (workoutId !== null) {
      keys.get(workoutId)?.push(key);
    }
  };

  for (const steps of raceStepGoals()) {
    award(fastestToStepsAttemptId(prepared, steps), stepGoalKey(steps));
  }
  for (const seconds of raceDurationGoals()) {
    award(
      mostStepsWithinAttemptId(prepared, seconds),
      durationGoalKey(seconds)
    );
  }

  for (const list of keys.values()) {
    list.sort();
  }

  return keys;
}

/**
 * Whether two sorted goal key lists say the same thing.
 * @param {string[]} stored Keys an entry carries.
 * @param {string[]} derived Keys it should carry.
 * @return {boolean} True when nothing needs writing.
 */
export function sameGoalKeys(stored: string[], derived: string[]): boolean {
  return stored.length === derived.length &&
    stored.every((key, index) => key === derived[index]);
}

/**
 * The attempt's checkpoints as a monotonic polyline ending at the finish.
 *
 * Checkpoints past the finish clock (a curve normalised longer than the run)
 * are dropped, and the finish is appended so a truncated curve still ends
 * where the climb did.
 * @param {RaceAttemptCurve} curve Attempt curve.
 * @return {CurvePoint[]} Points strictly increasing in time.
 */
function curvePoints(curve: RaceAttemptCurve): CurvePoint[] {
  const interval = Math.max(curve.splitIntervalSeconds, 1);
  const finishSeconds = Math.max(curve.finalDurationSeconds, 0);
  const finishSteps = Math.max(curve.finalSteps, 0);
  const points: CurvePoint[] = [];
  let lastSteps = 0;

  for (let index = 0; index < curve.splitSteps.length; index += 1) {
    const seconds = (index + 1) * interval;
    if (seconds >= finishSeconds) {
      break;
    }
    lastSteps = Math.min(
      Math.max(curve.splitSteps[index], lastSteps, 0),
      finishSteps
    );
    points.push({seconds, steps: lastSteps});
  }

  points.push({seconds: finishSeconds, steps: finishSteps});
  return points;
}

/**
 * Linear interpolation between two points on the time axis.
 * @param {CurvePoint} from Earlier point.
 * @param {CurvePoint} to Later point.
 * @param {number} seconds Moment between them.
 * @return {number} Steps at that moment.
 */
function interpolate(
  from: CurvePoint,
  to: CurvePoint,
  seconds: number
): number {
  if (to.seconds === from.seconds) {
    return to.steps;
  }
  const fraction = (seconds - from.seconds) / (to.seconds - from.seconds);
  return from.steps + (to.steps - from.steps) * fraction;
}

/**
 * The attempt with the best value, ties resolved on workout id so every
 * caller - the publish seed, the reconciliation, the seeds - picks the same
 * winner. An attempt whose value is null is out of the running.
 * @param {RaceAttempt[]} attempts Candidates.
 * @param {(attempt: RaceAttempt) => number | null} value Measure.
 * @param {"highest" | "lowest"} wins Which direction is better.
 * @return {string | null} Winning workout id, or null when nobody qualifies.
 */
function winner(
  attempts: RaceAttempt[],
  value: (attempt: RaceAttempt) => number | null,
  wins: "highest" | "lowest"
): string | null {
  let best: {workoutId: string; value: number} | null = null;

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

/**
 * Integers from `from` to `to` inclusive, `step` apart.
 * @param {number} from First value.
 * @param {number} to Last value.
 * @param {number} step Increment.
 * @return {number[]} The range.
 */
function rangeInclusive(from: number, to: number, step: number): number[] {
  const values: number[] = [];
  for (let value = from; value <= to; value += step) {
    values.push(value);
  }
  return values;
}
