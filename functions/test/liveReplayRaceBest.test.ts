import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  RACE_DURATION_GOAL_INCREMENT_SECONDS,
  RACE_DURATION_GOAL_MAX_SECONDS,
  RACE_DURATION_GOAL_MIN_SECONDS,
  RACE_STEP_GOAL_INCREMENT,
  RACE_STEP_GOAL_MAX,
  RACE_STEP_GOAL_MIN,
  RaceAttemptCurve,
  durationGoalKey,
  fastestToStepsAttemptId,
  mostStepsAttemptId,
  mostStepsWithinAttemptId,
  prepareRaceAttemptCurve,
  raceDurationGoals,
  raceGoalKeysByWorkoutId,
  raceStepGoals,
  sameGoalKeys,
  secondsToReach,
  stepGoalKey,
  stepsAtElapsed,
} from "../src/liveReplayRaceBest.js";

interface VectorGoal {
  kind: "open" | "steps" | "duration";
  steps?: number;
  seconds?: number;
}

interface VectorCurve {
  finalSteps: number;
  finalDurationSeconds: number;
  splitIntervalSeconds: number;
  splitSteps: number[];
}

interface RaceBestVector {
  goalKeys: {
    stepIncrement: number;
    stepMin: number;
    stepMax: number;
    durationIncrementSeconds: number;
    durationMinSeconds: number;
    durationMaxSeconds: number;
  };
  keyCases: {name: string; goal: VectorGoal; key: string | null}[];
  curveCases: {
    name: string;
    curve: VectorCurve;
    stepsAtElapsed: {seconds: number; steps: number}[];
    secondsToReach: {steps: number; seconds: number | null}[];
  }[];
  attempts: Record<string, VectorCurve>;
  selectionCases: {
    name: string;
    attemptIds: string[];
    goal: VectorGoal;
    winner: string | null;
  }[];
}

// Compiled output is CommonJS (see tsconfig NodeNext + no package "type"), so
// __dirname is the compiled lib/test directory; walk up to the repo root.
const vector = JSON.parse(
  readFileSync(
    join(
      __dirname,
      "../../../SharedTestVectors/live-replay-race-best-vector.json"
    ),
    "utf8"
  )
) as RaceBestVector;

/**
 * The vector's attempts by id, as the module reads them.
 * @param {string[]} ids Attempt ids from a selection case.
 * @return {RaceAttemptCurve[]} Curves in the case's order.
 */
function attempts(ids: string[]): RaceAttemptCurve[] {
  return ids.map((workoutId) => ({workoutId, ...vector.attempts[workoutId]}));
}

/**
 * The key the module would filter a live window on for a vector goal.
 * @param {VectorGoal} goal Vector goal.
 * @return {string | null} Goal key, or null for an open session.
 */
function keyFor(goal: VectorGoal): string | null {
  switch (goal.kind) {
  case "open":
    return null;
  case "steps":
    return stepGoalKey(goal.steps ?? 0);
  case "duration":
    return durationGoalKey(goal.seconds ?? 0);
  }
}

/**
 * The winner the module picks for a vector goal.
 * @param {RaceAttemptCurve[]} candidates Attempts.
 * @param {VectorGoal} goal Vector goal.
 * @return {string | null} Winning workout id.
 */
function winnerFor(
  candidates: RaceAttemptCurve[],
  goal: VectorGoal
): string | null {
  switch (goal.kind) {
  case "open":
    return mostStepsAttemptId(candidates);
  case "steps":
    return fastestToStepsAttemptId(candidates, goal.steps ?? 0);
  case "duration":
    return mostStepsWithinAttemptId(candidates, goal.seconds ?? 0);
  }
}

test("the goal space is exactly what the Just Climb setup sheet offers", () => {
  assert.equal(RACE_STEP_GOAL_INCREMENT, vector.goalKeys.stepIncrement);
  assert.equal(RACE_STEP_GOAL_MIN, vector.goalKeys.stepMin);
  assert.equal(RACE_STEP_GOAL_MAX, vector.goalKeys.stepMax);
  assert.equal(
    RACE_DURATION_GOAL_INCREMENT_SECONDS,
    vector.goalKeys.durationIncrementSeconds
  );
  assert.equal(
    RACE_DURATION_GOAL_MIN_SECONDS,
    vector.goalKeys.durationMinSeconds
  );
  assert.equal(
    RACE_DURATION_GOAL_MAX_SECONDS,
    vector.goalKeys.durationMaxSeconds
  );

  const steps = raceStepGoals();
  assert.equal(steps[0], 100);
  assert.equal(steps[steps.length - 1], 20000);
  assert.equal(steps.length, 200);

  const durations = raceDurationGoals();
  assert.equal(durations[0], 300);
  assert.equal(durations[durations.length - 1], 10800);
  assert.equal(durations.length, 36);
});

test("spells every goal key the way the app and the seeds spell it", () => {
  for (const testCase of vector.keyCases) {
    assert.equal(keyFor(testCase.goal), testCase.key, testCase.name);
  }
});

test("reads a split curve the way the replay buckets are anchored", () => {
  for (const testCase of vector.curveCases) {
    const curve = {workoutId: "curve", ...testCase.curve};

    for (const reading of testCase.stepsAtElapsed) {
      assert.equal(
        stepsAtElapsed(curve, reading.seconds),
        reading.steps,
        `${testCase.name}: steps at ${reading.seconds}s`
      );
    }
    for (const reading of testCase.secondsToReach) {
      const seconds = secondsToReach(curve, reading.steps);
      if (reading.seconds === null) {
        assert.equal(seconds, null, `${testCase.name}: ${reading.steps} steps`);
      } else {
        assert.ok(seconds !== null, `${testCase.name}: ${reading.steps} steps`);
        assert.ok(
          Math.abs(seconds - reading.seconds) < 0.001,
          `${testCase.name}: ${reading.steps} steps took ${seconds}s, ` +
            `expected ${reading.seconds}s`
        );
      }
    }
  }
});

// The captain's ruling of 2026-09-22, case by case: with no goal the marker's
// source is the most-steps climb (149, 390, 1,776 yields 1,776); with a step
// goal it is the fastest to that count, a longer climb counting through its
// split; with a duration goal it is the most steps within that duration, a
// climb that ended earlier counting at its final steps.
test("picks each climber's best for the goal the viewer set", () => {
  for (const testCase of vector.selectionCases) {
    assert.equal(
      winnerFor(attempts(testCase.attemptIds), testCase.goal),
      testCase.winner,
      testCase.name
    );
  }
});

test("with no goal the marker's source is the most-steps climb", () => {
  const history = attempts(["charminar-149", "just-climb-390", "cn-tower-1776"]);

  assert.equal(mostStepsAttemptId(history), "cn-tower-1776");
});

test("with a step goal a longer climb counts through its split", () => {
  const history = attempts(["three-thousand", "five-thousand"]);

  assert.equal(fastestToStepsAttemptId(history, 3000), "five-thousand");
});

test("with a duration goal a climb that ended earlier counts at its final steps", () => {
  const history = attempts(["slow-1500", "sprint-900"]);

  assert.equal(mostStepsWithinAttemptId(history, 600), "sprint-900");
});

test("awards every goal key to exactly one attempt, or to nobody", () => {
  const history = attempts(["three-thousand", "five-thousand"]);
  const keys = raceGoalKeysByWorkoutId(history);

  const fiveThousand = keys.get("five-thousand") ?? [];
  const threeThousand = keys.get("three-thousand") ?? [];

  // The 5,000-step climb is faster to every count it reached - a linear pace
  // of 125 steps a minute against 120 - so it holds every step goal up to its
  // own finish, and the 3,000-step climb holds none.
  assert.ok(fiveThousand.includes(stepGoalKey(3000)));
  assert.ok(fiveThousand.includes(stepGoalKey(5000)));
  assert.equal(threeThousand.some((key) => key.startsWith("steps:")), false);
  // A count neither reached belongs to nobody.
  assert.equal(fiveThousand.includes(stepGoalKey(5100)), false);
  assert.equal(threeThousand.includes(stepGoalKey(5100)), false);
  // Every duration goal is held by exactly one of them.
  for (const seconds of raceDurationGoals()) {
    const key = durationGoalKey(seconds);
    assert.equal(
      Number(fiveThousand.includes(key)) + Number(threeThousand.includes(key)),
      1,
      key
    );
  }
  // Sorted, so a stored array and a derived one compare without a sort at the
  // reconciliation site.
  assert.deepEqual(fiveThousand, [...fiveThousand].sort());
});

test("an attempt that wins nothing still appears in the map", () => {
  const keys = raceGoalKeysByWorkoutId(attempts(["tied-b", "tied-a"]));

  assert.deepEqual(keys.get("tied-b"), []);
  assert.ok((keys.get("tied-a") ?? []).length > 0);
});

test("a settled entry compares equal to what it should carry", () => {
  assert.equal(sameGoalKeys(["a", "b"], ["a", "b"]), true);
  assert.equal(sameGoalKeys(["a"], ["a", "b"]), false);
  assert.equal(sameGoalKeys(["b", "a"], ["a", "b"]), false);
  assert.equal(sameGoalKeys([], []), true);
});

// The 236 goals a climber's history is judged against read one polyline per
// attempt, built once; a prepared attempt has to answer exactly what the raw
// curve does, or the reconciliation would pick a different winner from the
// tests that pin the rule on raw curves.
test("a prepared attempt reads exactly like its raw curve", () => {
  for (const testCase of vector.curveCases) {
    const raw = {workoutId: "curve", ...testCase.curve};
    const prepared = prepareRaceAttemptCurve(raw);

    assert.equal(prepareRaceAttemptCurve(prepared), prepared);
    for (const reading of testCase.stepsAtElapsed) {
      assert.equal(
        stepsAtElapsed(prepared, reading.seconds),
        stepsAtElapsed(raw, reading.seconds),
        `${testCase.name}: steps at ${reading.seconds}s`
      );
    }
    for (const reading of testCase.secondsToReach) {
      assert.equal(
        secondsToReach(prepared, reading.steps),
        secondsToReach(raw, reading.steps),
        `${testCase.name}: ${reading.steps} steps`
      );
    }
  }

  const ids = Object.keys(vector.attempts);
  const raw = attempts(ids);
  assert.deepEqual(
    [...raceGoalKeysByWorkoutId(raw.map(prepareRaceAttemptCurve))],
    [...raceGoalKeysByWorkoutId(raw)]
  );
});
