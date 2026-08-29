/**
 * The field read a frozen completion standing is built from, against a real
 * Firestore.
 *
 * The unit suite proves the arithmetic once the counts are in hand, but the
 * defect this suite exists for lived in the counts themselves: the two halves
 * counted different populations, so a rank could land outside its own
 * denominator. Only a real query over real rows shows which population each
 * half actually counted.
 *
 * Settled by the captain on 2026-08-29: a board that collapses repeat finishers
 * counts distinct climbers on both halves, and an open Just Climb counts
 * attempts on both. These tests seed finishers and entries the way a publish
 * writes them and read the standing back the way the summary will show it.
 *
 * Lives under test/emulator/ so `npm test` (glob: lib/test/*.test.js) does not
 * pick it up without a Firestore behind it. `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  liveReplayLeaderboardTestHooks,
  onWorkoutReplaySplitsWritten,
} from "../../src/liveReplayLeaderboard.js";

type ReplayTriggerEvent =
  Parameters<typeof onWorkoutReplaySplitsWritten.run>[0];

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_COMMUNITY_STATS_COLLECTION = "live_climb_community_stats";
const PUBLISH_STATUSES_COLLECTION = "liveClimbPublishStatuses";
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

test("counts a repeat rival once on a board that races climbers", async () => {
  const payload = liveClimbPayload();
  await seedRivalAttempts(payload.contextKey, {collapses: true});

  const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
    payload,
    WORKOUT,
    CLIMBER
  );

  // One rival holding five faster attempts is one climber ahead, because the
  // board this standing sits beside carries one row per climber.
  assert.deepEqual(reading, {betterRowCount: 1, attemptCount: null});
  assert.deepEqual(
    liveReplayLeaderboardTestHooks.frozenCompletionStanding({
      reading,
      completedCount: 2,
      contextKey: payload.contextKey,
    }),
    {rank: 2, population: 2}
  );
});

test("counts finishers, never the best-flag window entries open", async () => {
  const payload = liveClimbPayload();

  // publishReplayEntries commits an improved row flagged best while the old
  // row is still flagged best, and reconcileUserBestEntries clears the old one
  // many awaits later. A rival caught in that window has two rows flagged true
  // and would count as two climbers; the finishers subcollection is one
  // document per climber by construction, so this read cannot see the window.
  await seedEntry(payload.contextKey, {
    workoutId: "rival-old-best",
    userId: RIVAL,
    completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 30,
    isBestForUser: true,
  });
  await seedEntry(payload.contextKey, {
    workoutId: "rival-new-best",
    userId: RIVAL,
    completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 60,
    isBestForUser: true,
  });
  await seedFinisher(payload.contextKey, {
    userId: RIVAL,
    bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 60,
  });

  assert.deepEqual(
    await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      WORKOUT,
      CLIMBER
    ),
    {betterRowCount: 1, attemptCount: null}
  );
});

test("a rival's five faster attempts are five opponents on a Just Climb",
  async () => {
    const payload = justClimbPayload();
    await seedRivalAttempts(payload.contextKey, {collapses: false});

    const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      WORKOUT,
      CLIMBER
    );

    // No target, so every attempt races as its own opponent - and the
    // denominator has to count attempts back, this unpublished one included.
    assert.deepEqual(reading, {betterRowCount: 5, attemptCount: 6});
    assert.deepEqual(
      liveReplayLeaderboardTestHooks.frozenCompletionStanding({
        reading,
        completedCount: 1,
        contextKey: payload.contextKey,
      }),
      {rank: 6, population: 6}
    );
  });

test("never counts a climber's own finisher row in their own numerator",
  async () => {
    const payload = liveClimbPayload();

    // The captain's St Peter's pair, as the database held it: one climber, an
    // earlier faster completion, and this slower one publishing now. The
    // numerator compares against the climber's *resulting* best - still 638 -
    // so their own document cannot satisfy a strictly-faster filter. Counting
    // it and subtracting it back out is the deleted defect; a numerator of 1
    // here would be that subtraction waiting to be reinvented.
    await seedFinisher(payload.contextKey, {
      userId: CLIMBER,
      bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 100,
    });

    const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      WORKOUT,
      CLIMBER
    );

    assert.deepEqual(reading, {betterRowCount: 0, attemptCount: null});
    assert.deepEqual(
      liveReplayLeaderboardTestHooks.frozenCompletionStanding({
        reading,
        completedCount: 1,
        contextKey: payload.contextKey,
      }),
      {rank: 1, population: 1}
    );
  });

test("leaves a slower repeat where the climber already stood", async () => {
  const payload = liveClimbPayload();

  // Their record leads a rival who is faster than this run but slower than
  // that record, so the slower repeat moves nothing: first of two climbers,
  // reached without a subtraction.
  await seedFinisher(payload.contextKey, {
    userId: CLIMBER,
    bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 100,
  });
  await seedFinisher(payload.contextKey, {
    userId: RIVAL,
    bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 38,
  });

  const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
    payload,
    WORKOUT,
    CLIMBER
  );

  assert.deepEqual(reading, {betterRowCount: 0, attemptCount: null});
  assert.deepEqual(
    liveReplayLeaderboardTestHooks.frozenCompletionStanding({
      reading,
      completedCount: 2,
      contextKey: payload.contextKey,
    }),
    {rank: 1, population: 2}
  );
});

test("moves a climber up on a faster repeat without growing the field",
  async () => {
    const payload = liveClimbPayload();

    // Their stored 838 stood behind the rival's 800; this 738 takes the lead.
    // Two climbers before, two after - improving adds nobody to the board.
    await seedFinisher(payload.contextKey, {
      userId: CLIMBER,
      bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS + 100,
    });
    await seedFinisher(payload.contextKey, {
      userId: RIVAL,
      bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS + 62,
    });

    const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      WORKOUT,
      CLIMBER
    );

    assert.deepEqual(reading, {betterRowCount: 0, attemptCount: null});
    assert.deepEqual(
      liveReplayLeaderboardTestHooks.frozenCompletionStanding({
        reading,
        completedCount: 2,
        contextKey: payload.contextKey,
      }),
      {rank: 1, population: 2}
    );
  });

test("shares one rank with a climber tied on the metric", async () => {
  const payload = liveClimbPayload();

  // Only strictly faster finishers count, so a dead heat leaves both climbers
  // first of two rather than reshuffling one of them behind the other.
  await seedFinisher(payload.contextKey, {
    userId: RIVAL,
    bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS,
  });

  const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
    payload,
    WORKOUT,
    CLIMBER
  );

  assert.deepEqual(reading, {betterRowCount: 0, attemptCount: null});
  assert.deepEqual(
    liveReplayLeaderboardTestHooks.frozenCompletionStanding({
      reading,
      completedCount: 2,
      contextKey: payload.contextKey,
    }),
    {rank: 1, population: 2}
  );
});

test("a rival's slower repeat leaves the field it counts alone", async () => {
  const payload = liveClimbPayload();
  await seedFinisher(payload.contextKey, {
    userId: RIVAL,
    bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 60,
  });
  const before = await liveReplayLeaderboardTestHooks.readCompletionField(
    payload,
    WORKOUT,
    CLIMBER
  );

  // The rival runs again and does not improve. Their entry joins the static
  // board, but the finisher document the numerator counts does not move, and
  // one climber is still one climber.
  await seedEntry(payload.contextKey, {
    workoutId: "rival-repeat",
    userId: RIVAL,
    completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 30,
    isBestForUser: false,
  });

  assert.deepEqual(before, {betterRowCount: 1, attemptCount: null});
  assert.deepEqual(
    await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      WORKOUT,
      CLIMBER
    ),
    before
  );
});

test("a routine board reads the steps its intervals rank on", async () => {
  const payload = routinePayload();
  await seedFinisher(payload.contextKey, {
    userId: RIVAL,
    bestFinalSteps: 1900,
  });

  const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
    payload,
    WORKOUT,
    CLIMBER
  );

  // The fixture routine attempt takes 1,840 steps, so the rival's stored 1,900
  // leads it - read from the steps field, not the clock.
  assert.deepEqual(reading, {betterRowCount: 1, attemptCount: null});
});

test("a republished attempt is already one of the attempts counted",
  async () => {
    const payload = justClimbPayload();
    await seedRivalAttempts(payload.contextKey, {collapses: false});

    // The retry-after-partial-failure case: the row committed and the trigger
    // died afterwards, so the attempt publishing now is already standing in the
    // collection the denominator counts. Counting it in again would freeze a
    // permanent population one larger than the field it was measured against.
    await seedEntry(payload.contextKey, {
      workoutId: WORKOUT,
      userId: CLIMBER,
      isBestForUser: null,
    });

    const reading = await liveReplayLeaderboardTestHooks.readCompletionField(
      payload,
      WORKOUT,
      CLIMBER
    );

    assert.deepEqual(reading, {betterRowCount: 5, attemptCount: 6});
    assert.deepEqual(
      liveReplayLeaderboardTestHooks.frozenCompletionStanding({
        reading,
        completedCount: 1,
        contextKey: payload.contextKey,
      }),
      {rank: 6, population: 6}
    );
  });

test("a standing nothing can write cannot fail a climb that did publish",
  async () => {
    const liveClimb = liveClimbPayload();
    const justClimb = justClimbPayload();

    // Two rivals already home, so the climb's own standing is a pairing its
    // board agrees with and that publish commits.
    await seedSummary(liveClimb.contextKey, 2);
    await seedFinisher(liveClimb.contextKey, {
      userId: RIVAL,
      bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 60,
    });
    await seedFinisher(liveClimb.contextKey, {
      userId: "rival-2",
      bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 30,
    });

    // The open race froze this attempt's standing already, and
    // completionSnapshots is write-once, so no second standing can land there.
    // Its rows carry the pairing the two unsynchronised aggregations behind
    // that read can produce between them: every attempt counted back, this
    // one's own committed row included, stands strictly ahead of the attempt
    // republishing now.
    await seedCompletionSnapshot(justClimb.contextKey);
    await seedEntry(justClimb.contextKey, {
      workoutId: WORKOUT,
      userId: CLIMBER,
      completionDurationSeconds: ATTEMPT_DURATION_SECONDS - 20,
      isBestForUser: null,
    });
    await seedRivalAttempts(justClimb.contextKey, {collapses: false});

    await runReplayTrigger();

    // The climb publishes before the open race, so a standing raised and then
    // discarded there used to abort the trigger after this document had
    // already committed - telling the climber a synced climb had not synced.
    const status = await db
      .collection("users")
      .doc(CLIMBER)
      .collection(PUBLISH_STATUSES_COLLECTION)
      .doc(WORKOUT)
      .get();
    assert.equal(status.data()?.state, "published");
  });

/**
 * Runs the replay trigger over the fixture workout as its first write.
 */
async function runReplayTrigger(): Promise<void> {
  const workoutRef = db
    .collection("users")
    .doc(CLIMBER)
    .collection("workouts")
    .doc(WORKOUT);
  const before = await workoutRef.get();
  await workoutRef.set(makeWorkoutDocument());
  const after = await workoutRef.get();

  await onWorkoutReplaySplitsWritten.run({
    data: {before, after},
    params: {userId: CLIMBER, workoutId: WORKOUT},
  } as unknown as ReplayTriggerEvent);
}

/**
 * Seeds a replay summary carrying a completion count.
 * @param {string} contextKey Replay context key.
 * @param {number} completedCount Distinct finishers standing on the board.
 */
async function seedSummary(
  contextKey: string,
  completedCount: number
): Promise<void> {
  await db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(contextKey)
    .set({completedCount}, {merge: true});
}

/**
 * Seeds the write-once completion snapshot the fixture attempt already froze.
 * @param {string} contextKey Replay context key.
 */
async function seedCompletionSnapshot(contextKey: string): Promise<void> {
  await db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(contextKey)
    .collection("completionSnapshots")
    .doc(WORKOUT)
    .set({completedCount: 6, rank: 6, userId: CLIMBER, workoutId: WORKOUT});
}

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

  if (!options.collapses) {
    return;
  }

  // A publish writes the finisher document in the same transaction as the row,
  // so a board that races climbers always has one per climber.
  await seedFinisher(contextKey, {
    userId: RIVAL,
    bestCompletionDurationSeconds: ATTEMPT_DURATION_SECONDS - 50,
  });
}

/**
 * Seeds one finisher document - one climber's standing best on a board.
 * @param {string} contextKey Replay context key.
 * @param {object} finisher Finisher fields.
 * @param {string} finisher.userId Owner user ID.
 * @param {number | undefined} finisher.bestCompletionDurationSeconds Best
 *   clock, where the board ranks on the clock.
 * @param {number | undefined} finisher.bestFinalSteps Best steps, where the
 *   board ranks on steps.
 */
async function seedFinisher(
  contextKey: string,
  finisher: {
    userId: string;
    bestCompletionDurationSeconds?: number;
    bestFinalSteps?: number;
  }
): Promise<void> {
  await db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(contextKey)
    .collection("finishers")
    .doc(finisher.userId)
    .set({
      globalCompletionOrder: 1,
      userId: finisher.userId,
      ...(finisher.bestCompletionDurationSeconds === undefined ?
        {} :
        {
          bestCompletionDurationSeconds:
            finisher.bestCompletionDurationSeconds,
        }),
      ...(finisher.bestFinalSteps === undefined ?
        {} :
        {bestFinalSteps: finisher.bestFinalSteps}),
    });
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
  await db.recursiveDelete(db.collection("users"));
  await db.recursiveDelete(
    db.collection(LIVE_CLIMB_COMMUNITY_STATS_COLLECTION)
  );
}
