/**
 * The field read a frozen completion standing is built from, against a real
 * Firestore.
 *
 * The unit suite proves the arithmetic once the counts are in hand, but the
 * defect this suite exists for lived in the counts themselves: the rank counted
 * every strictly better entry while the denominator counted distinct climbers,
 * so one rival with five faster attempts pushed a finisher to 6th on a board of
 * 3 - and a clamp rewrote that to "3rd of 3". Only a real query over real rows
 * shows which population each half actually counted.
 *
 * Lives under test/emulator/ so `npm test` (glob: lib/test/*.test.js) does not
 * pick it up without a Firestore behind it. `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  liveReplayLeaderboardTestHooks,
} from "../../src/liveReplayLeaderboard.js";

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const CLIMBER = "climber-1";
const RIVAL = "rival-1";
const WORKOUT = "B91A3AB1-FBD5-4AC1-A18D-58A95BCF0C96";
// The fixture attempt: 738 seconds over 2,096 steps.
const ATTEMPT_DURATION_SECONDS = 738;
const ATTEMPT_STEPS = 2096;

let db: admin.firestore.Firestore;

before(() => {
  // Never let this suite pass by quietly doing nothing. Without an emulator the
  // Admin SDK would reach for real credentials, and a skip here would read as a
  // green gate over a permanent, unfixable value that never ran.
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  db = admin.firestore();
});

beforeEach(async () => {
  await clearFirestore();
});

test("a rival's five faster attempts are one climber ahead on a climb",
  async () => {
    const payload = liveClimbPayload();
    await seedRivalAttempts(payload.contextKey, {collapses: true});

    const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      CLIMBER,
      WORKOUT
    );

    // One row per climber, so the five collapse to the rival's fastest.
    assert.deepEqual(reading, {
      betterRowCount: 1,
      ownRowsAhead: 0,
      attemptCount: null,
    });
    assert.deepEqual(
      liveReplayLeaderboardTestHooks.frozenCompletionStanding({
        payload,
        reading,
        completedCount: 2,
      }),
      {rank: 2, population: 2}
    );
  });

test("a rival's five faster attempts are five opponents on a Just Climb",
  async () => {
    const payload = justClimbPayload();
    await seedRivalAttempts(payload.contextKey, {collapses: false});

    const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      CLIMBER,
      WORKOUT
    );

    // No target, so every attempt races as its own opponent - and the
    // denominator has to count attempts back, this unpublished one included.
    assert.deepEqual(reading, {
      betterRowCount: 5,
      ownRowsAhead: 0,
      attemptCount: 6,
    });
    assert.deepEqual(
      liveReplayLeaderboardTestHooks.frozenCompletionStanding({
        payload,
        reading,
        // The summary counts one distinct finisher; the stamp must not.
        completedCount: 1,
      }),
      {rank: 6, population: 6}
    );
  });

test("a climber is never seated behind their own faster attempt",
  async () => {
    const payload = liveClimbPayload();
    await seedEntry(payload.contextKey, {
      workoutId: "own-faster",
      userId: CLIMBER,
      completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 100,
      isBestForUser: true,
    });

    const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      CLIMBER,
      WORKOUT
    );

    assert.deepEqual(reading, {
      betterRowCount: 1,
      ownRowsAhead: 1,
      attemptCount: null,
    });
    assert.deepEqual(
      liveReplayLeaderboardTestHooks.frozenCompletionStanding({
        payload,
        reading,
        completedCount: 1,
      }),
      {rank: 1, population: 1}
    );
  });

test("beating your own attempt adds no climber to the field", async () => {
  const payload = liveClimbPayload();
  await seedEntry(payload.contextKey, {
    workoutId: "own-slower",
    userId: CLIMBER,
    completionDurationSeconds: ATTEMPT_DURATION_SECONDS + 100,
    isBestForUser: true,
  });

  const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
    payload,
    CLIMBER,
    WORKOUT
  );

  assert.deepEqual(reading, {
    betterRowCount: 0,
    ownRowsAhead: 0,
    attemptCount: null,
  });
  assert.deepEqual(
    liveReplayLeaderboardTestHooks.frozenCompletionStanding({
      payload,
      reading,
      // One climber before, one after: improving on themselves adds nobody.
      completedCount: 1,
    }),
    {rank: 1, population: 1}
  );
});

test("a repeat run by a standing rival leaves the rank where it was",
  async () => {
    const payload = liveClimbPayload();
    await seedEntry(payload.contextKey, {
      workoutId: "rival-best",
      userId: RIVAL,
      completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 60,
      isBestForUser: true,
    });
    const before = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      CLIMBER,
      WORKOUT
    );

    // The rival runs again and does not improve, so the board still carries
    // their one row and the rank it holds is the rank it held.
    await seedEntry(payload.contextKey, {
      workoutId: "rival-repeat",
      userId: RIVAL,
      completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 30,
      isBestForUser: false,
    });

    assert.deepEqual(
      await liveReplayLeaderboardTestHooks.readCompletionField(
        payload,
        CLIMBER,
        WORKOUT
      ),
      before
    );
  });

test("a routine board reads the steps its intervals rank on", async () => {
  const payload = routinePayload();
  await seedEntry(payload.contextKey, {
    workoutId: "rival-best",
    userId: RIVAL,
    finalSteps: 1900,
    isBestForUser: true,
  });
  await seedEntry(payload.contextKey, {
    workoutId: "rival-repeat",
    userId: RIVAL,
    finalSteps: 1870,
    isBestForUser: false,
  });

  const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
    payload,
    CLIMBER,
    WORKOUT
  );

  assert.deepEqual(reading, {
    betterRowCount: 1,
    ownRowsAhead: 0,
    attemptCount: null,
  });
});

/**
 * Seeds one rival holding five attempts faster than the fixture attempt.
 * @param {string} contextKey Replay context key.
 * @param {object} options Seed options.
 * @param {boolean} options.collapses Whether the context flags a best row.
 */
async function seedRivalAttempts(
  contextKey: string,
  options: {collapses: boolean}
): Promise<void> {
  for (let index = 0; index < 5; index += 1) {
    await seedEntry(contextKey, {
      workoutId: `rival-attempt-${index}`,
      userId: RIVAL,
      completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 10 * (index + 1),
      // Only the fastest stands on a board that races climbers; a board that
      // races attempts carries no flag at all.
      isBestForUser: options.collapses ? index === 4 : null,
    });
  }
}

/**
 * Seeds one bucket-zero replay entry.
 * @param {string} contextKey Replay context key.
 * @param {object} entry Entry fields.
 * @param {string} entry.workoutId Attempt workout ID.
 * @param {string} entry.userId Owner user ID.
 * @param {number | undefined} entry.completionDurationSeconds Attempt clock.
 * @param {number | undefined} entry.finalSteps Attempt steps.
 * @param {boolean | null} entry.isBestForUser Best-per-user flag, or null.
 */
async function seedEntry(
  contextKey: string,
  entry: {
    workoutId: string;
    userId: string;
    completionDurationSeconds?: number;
    finalSteps?: number;
    isBestForUser: boolean | null;
  }
): Promise<void> {
  await db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(contextKey)
    .collection("splitBuckets")
    .doc("0")
    .collection("entries")
    .doc(entry.workoutId)
    .set({
      completionDurationSeconds:
        entry.completionDurationSeconds ?? ATTEMPT_DURATION_SECONDS,
      finalSteps: entry.finalSteps ?? ATTEMPT_STEPS,
      splitBucketCount: 6,
      userId: entry.userId,
      workoutId: entry.workoutId,
      ...(entry.isBestForUser === null ?
        {} :
        {isBestForUser: entry.isBestForUser}),
    });
}

/**
 * Builds a parsed per-climb replay payload.
 * @return {ReturnType<
 *   typeof liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload>
 * } Parsed payload.
 */
function liveClimbPayload() {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  return payload;
}

/**
 * Builds a parsed open Just Climb replay payload.
 * @return {ReturnType<
 *   typeof liveReplayLeaderboardTestHooks.parseJustClimbReplayPayload>
 * } Parsed payload.
 */
function justClimbPayload() {
  const payload = liveReplayLeaderboardTestHooks.parseJustClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  return payload;
}

/**
 * Builds a parsed routine-template replay payload.
 * @return {ReturnType<
 *   typeof liveReplayLeaderboardTestHooks.parseRoutineReplayPayload>
 * } Parsed payload.
 */
function routinePayload() {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeWorkoutDocument({
      durationSeconds: 1200,
      participations: [
        {
          contextType: "routine_template",
          contextId: "social-pyramid-20",
          leaderboardEligible: true,
        },
      ],
      sourceMetadata: JSON.stringify({
        routineId: "6E1B0C1E-0E1A-4E5B-9C2E-0C6F0B7A1D22",
        routineTemplateId: "social-pyramid-20",
        splitIntervalSeconds: 10,
        splitSteps: [0, 150, 320, 610, 940, 1310, 1840],
        stopReason: "target_reached",
        targetDurationSeconds: 1200,
        targetStepCount: 1900,
        trackingMode: "routine",
      }),
      steps: 1840,
    }),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  return payload;
}

/**
 * Builds a completed Live Climb workout backup document.
 * @param {Record<string, unknown>} overrides Document overrides.
 * @return {Record<string, unknown>} Workout backup document.
 */
function makeWorkoutDocument(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    durationSeconds: ATTEMPT_DURATION_SECONDS,
    participations: [
      {contextType: "climb_attempt", leaderboardEligible: true},
    ],
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({
      climbId: "empire-state-building",
      climbTargetStepCount: ATTEMPT_STEPS,
      splitIntervalSeconds: 10,
      splitSteps: [0, 28, 56, 84, 112, 140],
      stopReason: "target_reached",
      targetStepCount: ATTEMPT_STEPS,
      trackingMode: "live_climb",
    }),
    steps: ATTEMPT_STEPS,
    ...overrides,
  };
}

/**
 * Clears every seeded document between tests.
 */
async function clearFirestore(): Promise<void> {
  await db.recursiveDelete(db.collection(LIVE_REPLAY_COLLECTION));
}
