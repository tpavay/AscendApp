import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join} from "node:path";
import {
  RACE_DURATION_GOAL_INCREMENT_SECONDS,
  RACE_DURATION_GOAL_MAX_SECONDS,
  RACE_DURATION_GOAL_MIN_SECONDS,
  RACE_STEP_GOAL_INCREMENT,
  RACE_STEP_GOAL_MAX,
  RACE_STEP_GOAL_MIN,
  contextRacesGoals,
  durationGoalKey,
  fastestToStepsAttemptId,
  mostStepsAttemptId,
  mostStepsWithinAttemptId,
  attemptCurveWrite,
  prepareRaceAttemptCurve,
  raceBestOnSteps,
  raceDurationGoals,
  raceGoalKeysByWorkoutId,
  raceStepGoals,
  secondsToReach,
  stepGoalKey,
  stepsAtElapsed,
} from "../lib/live-replay-race-best.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const vector = JSON.parse(
  readFileSync(
    join(here, "../../SharedTestVectors/live-replay-race-best-vector.json"),
    "utf8"
  )
);

function attempts(ids) {
  return ids.map((workoutId) => ({workoutId, ...vector.attempts[workoutId]}));
}

function keyFor(goal) {
  switch (goal.kind) {
    case "open":
      return null;
    case "steps":
      return stepGoalKey(goal.steps);
    case "duration":
      return durationGoalKey(goal.seconds);
    default:
      throw new Error(`unknown goal kind ${goal.kind}`);
  }
}

function winnerFor(candidates, goal) {
  switch (goal.kind) {
    case "open":
      return mostStepsAttemptId(candidates);
    case "steps":
      return fastestToStepsAttemptId(candidates, goal.steps);
    case "duration":
      return mostStepsWithinAttemptId(candidates, goal.seconds);
    default:
      throw new Error(`unknown goal kind ${goal.kind}`);
  }
}

// The seeds write the entries the app reads. A goal key spelled differently
// from the server, or a different winner, leaves a seeded rival out of the
// race - the board just looks empty.
test("the seed goal space matches the shared vector", () => {
  assert.equal(RACE_STEP_GOAL_INCREMENT, vector.goalKeys.stepIncrement);
  assert.equal(RACE_STEP_GOAL_MIN, vector.goalKeys.stepMin);
  assert.equal(RACE_STEP_GOAL_MAX, vector.goalKeys.stepMax);
  assert.equal(RACE_DURATION_GOAL_INCREMENT_SECONDS, vector.goalKeys.durationIncrementSeconds);
  assert.equal(RACE_DURATION_GOAL_MIN_SECONDS, vector.goalKeys.durationMinSeconds);
  assert.equal(RACE_DURATION_GOAL_MAX_SECONDS, vector.goalKeys.durationMaxSeconds);
  assert.equal(raceStepGoals().length, 200);
  assert.equal(raceDurationGoals().length, 36);
});

test("the seed spells every goal key the way the server does", () => {
  for (const testCase of vector.keyCases) {
    assert.equal(keyFor(testCase.goal), testCase.key, testCase.name);
  }
});

test("the seed reads a split curve the way the server does", () => {
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
        assert.ok(
          seconds !== null && Math.abs(seconds - reading.seconds) < 0.001,
          `${testCase.name}: ${reading.steps} steps took ${seconds}s, expected ${reading.seconds}s`
        );
      }
    }
  }
});

test("the seed picks the same winner as the server for every goal", () => {
  assert.ok(vector.selectionCases.length >= 12, "vector should carry every shape");

  for (const testCase of vector.selectionCases) {
    assert.equal(
      winnerFor(attempts(testCase.attemptIds), testCase.goal),
      testCase.winner,
      testCase.name
    );
  }
});

test("a seeded Just Climb races on steps and carries goal keys", () => {
  assert.equal(raceBestOnSteps("just_climb"), true);
  assert.equal(raceBestOnSteps("routine_template"), true);
  assert.equal(raceBestOnSteps("live_climb"), false);
  assert.equal(raceBestOnSteps("routine"), false);
  assert.equal(contextRacesGoals("just_climb"), true);
  assert.equal(contextRacesGoals("live_climb"), false);
});

test("a sole attempt wins every goal it reached and nothing beyond it", () => {
  const keys = raceGoalKeysByWorkoutId(attempts(["three-thousand"]));
  const held = keys.get("three-thousand");

  assert.ok(held.includes("steps:100"));
  assert.ok(held.includes("steps:3000"));
  assert.equal(held.includes("steps:3100"), false);
  assert.equal(held.filter((key) => key.startsWith("duration:")).length, 36);
  assert.deepEqual(held, [...held].sort());
});

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

  const raw = attempts(Object.keys(vector.attempts));
  assert.deepEqual(
    [...raceGoalKeysByWorkoutId(raw.map(prepareRaceAttemptCurve))],
    [...raceGoalKeysByWorkoutId(raw)]
  );
});

// The seeds store the curve their goal keys were judged on, in the document
// shape the server's `attemptCurveWrite` publishes; a field the server does
// not read back, or one it reads and the seed omits, makes the trigger and
// the backfill rebuild a differently anchored curve from the bucket entries.
test("a seeded curve document carries exactly the server's fields", () => {
  const updatedAt = {kind: "server-timestamp"};
  const curve = {
    workoutId: "workout-1",
    finalSteps: 1860,
    finalDurationSeconds: 480,
    splitIntervalSeconds: 120,
    splitSteps: [420, 900, 1400],
  };

  assert.deepEqual(attemptCurveWrite("user-1", curve, updatedAt), {
    finalDurationSeconds: 480,
    finalSteps: 1860,
    schemaVersion: 1,
    splitIntervalSeconds: 120,
    splitSteps: [420, 900, 1400],
    updatedAt,
    userId: "user-1",
    workoutId: "workout-1",
  });
});
