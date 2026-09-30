/*
 * Attempts longer than an hour against a real Firestore, through the trigger.
 *
 * The pre-fix sampler clamped every sample after 59:50 into bucket 359, and
 * the publish stopped at 360 buckets, so in a live race every rival whose
 * attempt ran past the hour jumped to their final steps at 60:00 and was
 * counted home from then on. These tests publish long attempts the way both
 * the pre-fix and the current sampler store them and read the board back the
 * way a live race does: `splitBuckets/{floor(elapsed / 10)}/entries` for the
 * rivals still climbing, and bucket zero's `splitBucketCount` for the ones
 * already home.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {onWorkoutReplaySplitsWritten} from "../../src/liveReplayLeaderboard.js";

type ReplayTriggerEvent =
  Parameters<typeof onWorkoutReplaySplitsWritten.run>[0];

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const JUST_CLIMB_BOARD = "just_climb__global";
const RIVAL = "rival";
const CLIMBER = "climber";

let db: admin.firestore.Firestore;

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  db = admin.firestore();
});

beforeEach(async () => {
  await db.recursiveDelete(db.collection(LIVE_REPLAY_COLLECTION));
  await db.recursiveDelete(db.collection("users"));
});

test("a rival clamped at the hour races where they really were", async () => {
  // The rival's shape from the captain's race: 16,645 steps over 2:30:02,
  // stored by the pre-fix sampler with the finish clamped into bucket 359.
  const durationSeconds = 9002.35;
  const finalSteps = 16645;
  const splitSteps = Array.from({length: 360}, (_, index) =>
    index < 359 ? Math.round((index + 1) * 10 * 6632 / 3590) : finalSteps
  );
  await publish(RIVAL, "rival-2h30", {
    durationSeconds,
    steps: finalSteps,
    splitIntervalSeconds: 10,
    splitSteps,
  });

  const home = await bucketEntry(0, "rival-2h30");
  assert.equal(home.splitBucketCount, 901);

  // At 60:00 the captain was near 5,000 steps. The rival is on the board at
  // the steps they had then, not at their finish.
  const atOneHour = await bucketEntry(360, "rival-2h30");
  assert.ok(
    (atOneHour.stepsAtBucket as number) < 6700,
    `60:00 = ${atOneHour.stepsAtBucket}`
  );
  assert.equal(await isHomeBy(360, "rival-2h30"), false);

  // Halfway through the unrecorded stretch (1:45:00) they are halfway from
  // the 6,632 steps recorded at 59:50 to the finish.
  const halfway = await bucketEntry(629, "rival-2h30");
  assert.ok(
    Math.abs((halfway.stepsAtBucket as number) - 11640) < 20,
    `1:45:00 = ${halfway.stepsAtBucket}`
  );

  // They finish on their own clock, and only then count as home.
  assert.equal((await bucketEntry(900, "rival-2h30")).stepsAtBucket, 16645);
  assert.equal(await entryExists(901, "rival-2h30"), false);
  assert.equal(await isHomeBy(900, "rival-2h30"), false);
  assert.equal(await isHomeBy(901, "rival-2h30"), true);
});

test("a ten-hour compacted attempt publishes every bucket", async () => {
  // The current sampler's curve for a steady 80 spm climb of ten hours: 226
  // checkpoints at 160 seconds. 3,601 board buckets span ten commits.
  const durationSeconds = 36000;
  const finalSteps = 48000;
  const splitSteps = Array.from({length: 226}, (_, index) =>
    Math.min(finalSteps, Math.floor(((index * 160) + 159) * 4 / 3))
  );
  await publish(CLIMBER, "ten-hours", {
    durationSeconds,
    steps: finalSteps,
    splitIntervalSeconds: 160,
    splitSteps,
  });

  const entries = await db
    .collectionGroup("entries")
    .where("workoutId", "==", "ten-hours")
    .get();
  assert.equal(entries.size, 3601);

  const home = await bucketEntry(0, "ten-hours");
  assert.equal(home.splitBucketCount, 3601);
  assert.equal(home.splitIntervalSeconds, 10);
  // The reconciliation flags reach the far end of the climb too.
  const last = await bucketEntry(3600, "ten-hours");
  assert.equal(last.stepsAtBucket, finalSteps);
  assert.equal(last.isBestForUser, true);
  assert.deepEqual(last.bestForGoals, home.bestForGoals);
  const fiveHours = await bucketEntry(1799, "ten-hours");
  assert.ok(Math.abs((fiveHours.stepsAtBucket as number) - 24000) <= 3);

  const curve = (await db.doc(attemptCurvePath("ten-hours")).get()).data();
  assert.ok(curve);
  assert.equal(curve.splitIntervalSeconds, 10);
  assert.equal((curve.splitSteps as number[]).length, 3601);

  // Deleting the workout takes every bucket with it.
  await deleteWorkout(CLIMBER, "ten-hours");
  const after = await db
    .collectionGroup("entries")
    .where("workoutId", "==", "ten-hours")
    .get();
  assert.equal(after.size, 0);
});

test("a clamped stored curve no longer wins goals it reached hours later", async () => {
  // An eight-hour, 20,000-step session published before this fix: its stored
  // curve reaches 20,000 steps at 60:00, so it held "most steps within an
  // hour" although it had climbed 2,500 by then.
  const bentCurve = Array.from({length: 360}, (_, index) =>
    index < 359 ? Math.round((index + 1) * 10 * 20000 / 28800) : 20000
  );
  await seedPreFixPublishedAttempt(CLIMBER, "eight-hours", {
    durationSeconds: 28800,
    finalSteps: 20000,
    splitSteps: bentCurve,
  });

  // A one-hour, 5,000-step climb published now reconciles the climber.
  await publish(CLIMBER, "one-hour", {
    durationSeconds: 3600,
    steps: 5000,
    splitIntervalSeconds: 20,
    splitSteps: Array.from({length: 181}, (_, index) =>
      Math.min(5000, Math.round(((index * 20) + 19) * 5000 / 3600))
    ),
  });

  const oneHour = await bucketEntry(0, "one-hour");
  const eightHours = await bucketEntry(0, "eight-hours");
  assert.ok(
    (oneHour.bestForGoals as string[]).includes("duration:3600"),
    "the hour's real best holds the hour"
  );
  assert.equal(
    (eightHours.bestForGoals as string[]).includes("duration:3600"),
    false
  );
  // Its fastest 20,000 steps are its real ones, at the end of eight hours.
  assert.ok((eightHours.bestForGoals as string[]).includes("steps:20000"));

  // The repaired curve is stored, so the next pass reads it directly.
  const stored = (await db.doc(attemptCurvePath("eight-hours")).get()).data();
  assert.ok(stored);
  assert.equal((stored.splitSteps as number[]).length, 2881);
  assert.ok((stored.splitSteps as number[])[359] < 2600);
});

test("a long publish that fails leaves no bucket behind", async () => {
  // Two rivals already home on a board whose summary counts none: the
  // standing this climb would freeze, third of one, is a pairing the publish
  // refuses, so its bucket-zero commit throws after the buckets past the hour
  // have already landed.
  const board = "live_climb__empire-state-building";
  for (const [rival, duration] of [["rival-a", 3000], ["rival-b", 3200]]) {
    await db.doc(`${LIVE_REPLAY_COLLECTION}/${board}/finishers/${rival}`).set({
      bestCompletionDurationSeconds: duration,
      globalCompletionOrder: 1,
      userId: rival,
    });
  }
  await db.doc(`${LIVE_REPLAY_COLLECTION}/${board}`).set({completedCount: 0});

  const durationSeconds = 4000;
  const targetSteps = 2096;
  const workoutRef = db.doc(`users/${CLIMBER}/workouts/long-refused`);
  const before = await workoutRef.get();
  await workoutRef.set({
    durationSeconds,
    participations: [
      {contextType: "climb_attempt", leaderboardEligible: true},
    ],
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({
      climbId: "empire-state-building",
      climbTargetStepCount: targetSteps,
      splitIntervalSeconds: 20,
      splitSteps: Array.from({length: 201}, (_, index) =>
        Math.min(targetSteps, Math.floor(((index * 20) + 19) * 2096 / 4000))
      ),
      stopReason: "target_reached",
      targetStepCount: targetSteps,
      trackingMode: "live_climb",
    }),
    steps: targetSteps,
  });
  const after = await workoutRef.get();

  await assert.rejects(
    onWorkoutReplaySplitsWritten.run({
      data: {before, after},
      params: {userId: CLIMBER, workoutId: "long-refused"},
    } as unknown as ReplayTriggerEvent),
    /Refusing to freeze rank 3 of 1/
  );

  const entries = await db
    .collectionGroup("entries")
    .where("workoutId", "==", "long-refused")
    .get();
  assert.deepEqual(entries.docs.map((doc) => doc.ref.path), []);
});

/**
 * Publishes one open Just Climb session through the trigger.
 * @param {string} userId Owner.
 * @param {string} workoutId Workout ID.
 * @param {object} session Final stats and the stored split curve.
 */
async function publish(
  userId: string,
  workoutId: string,
  session: {
    durationSeconds: number;
    steps: number;
    splitIntervalSeconds: number;
    splitSteps: number[];
  }
): Promise<void> {
  const workoutRef = db.doc(`users/${userId}/workouts/${workoutId}`);
  const before = await workoutRef.get();
  await workoutRef.set({
    durationSeconds: session.durationSeconds,
    participations: [],
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({
      splitIntervalSeconds: session.splitIntervalSeconds,
      splitSteps: session.splitSteps,
      stopReason: "user_stopped",
      trackingMode: "just_climb",
    }),
    steps: session.steps,
  });
  const after = await workoutRef.get();

  await onWorkoutReplaySplitsWritten.run({
    data: {before, after},
    params: {userId, workoutId},
  } as unknown as ReplayTriggerEvent);
}

/**
 * Deletes one workout through the trigger.
 * @param {string} userId Owner.
 * @param {string} workoutId Workout ID.
 */
async function deleteWorkout(
  userId: string,
  workoutId: string
): Promise<void> {
  const workoutRef = db.doc(`users/${userId}/workouts/${workoutId}`);
  const before = await workoutRef.get();
  await workoutRef.delete();
  const after = await workoutRef.get();

  await onWorkoutReplaySplitsWritten.run({
    data: {before, after},
    params: {userId, workoutId},
  } as unknown as ReplayTriggerEvent);
}

/**
 * Writes what the pre-fix publish left for a long attempt: 360 entries and a
 * 360-point attempt curve, both ending on the finish at 60:00.
 * @param {string} userId Owner.
 * @param {string} workoutId Workout ID.
 * @param {object} attempt Final stats and the clamped curve.
 */
async function seedPreFixPublishedAttempt(
  userId: string,
  workoutId: string,
  attempt: {durationSeconds: number; finalSteps: number; splitSteps: number[]}
): Promise<void> {
  const batch = db.batch();
  attempt.splitSteps.forEach((stepsAtBucket, index) => {
    batch.set(db.doc(entryPath(index, workoutId)), {
      avatarToken: "token",
      bestForGoals: [],
      completionDurationSeconds: attempt.durationSeconds,
      contextId: "global",
      contextType: "just_climb",
      displayName: "Climber",
      finalSteps: attempt.finalSteps,
      identityState: "published",
      isBestForUser: true,
      isSynthetic: false,
      photoURL: "",
      schemaVersion: 1,
      splitBucketCount: 360,
      splitIntervalSeconds: 10,
      stepsAtBucket,
      userId,
      workoutId,
    });
  });
  batch.set(db.doc(attemptCurvePath(workoutId)), {
    finalDurationSeconds: attempt.durationSeconds,
    finalSteps: attempt.finalSteps,
    schemaVersion: 1,
    splitIntervalSeconds: 10,
    splitSteps: attempt.splitSteps,
    userId,
    workoutId,
  });
  await batch.commit();
}

/**
 * Whether the live race counts an attempt home by this bucket - the
 * predicate the client's finished half reads off bucket zero.
 * @param {number} bucketIndex Bucket the race has reached.
 * @param {string} workoutId Workout ID.
 * @return {Promise<boolean>} True when the attempt reads as finished.
 */
async function isHomeBy(
  bucketIndex: number,
  workoutId: string
): Promise<boolean> {
  const home = await db
    .collection(`${LIVE_REPLAY_COLLECTION}/${JUST_CLIMB_BOARD}/splitBuckets/0/entries`)
    .where("splitBucketCount", "<=", bucketIndex)
    .get();
  return home.docs.some((doc) => doc.id === workoutId);
}

/**
 * One bucket entry's data, which must exist.
 * @param {number} bucketIndex Bucket.
 * @param {string} workoutId Workout ID.
 * @return {Promise<Record<string, unknown>>} Entry data.
 */
async function bucketEntry(
  bucketIndex: number,
  workoutId: string
): Promise<Record<string, unknown>> {
  const snapshot = await db.doc(entryPath(bucketIndex, workoutId)).get();
  const data = snapshot.data();
  assert.ok(data, `${entryPath(bucketIndex, workoutId)} should exist`);
  return data;
}

/**
 * Whether one bucket entry exists.
 * @param {number} bucketIndex Bucket.
 * @param {string} workoutId Workout ID.
 * @return {Promise<boolean>} True when it exists.
 */
async function entryExists(
  bucketIndex: number,
  workoutId: string
): Promise<boolean> {
  return (await db.doc(entryPath(bucketIndex, workoutId)).get()).exists;
}

/**
 * Path of one bucket entry on the global Just Climb board.
 * @param {number} bucketIndex Bucket.
 * @param {string} workoutId Workout ID.
 * @return {string} Document path.
 */
function entryPath(bucketIndex: number, workoutId: string): string {
  return `${LIVE_REPLAY_COLLECTION}/${JUST_CLIMB_BOARD}/splitBuckets/` +
    `${bucketIndex}/entries/${workoutId}`;
}

/**
 * Path of one attempt's curve on the global Just Climb board.
 * @param {string} workoutId Workout ID.
 * @return {string} Document path.
 */
function attemptCurvePath(workoutId: string): string {
  return `${LIVE_REPLAY_COLLECTION}/${JUST_CLIMB_BOARD}/attemptCurves/` +
    workoutId;
}
