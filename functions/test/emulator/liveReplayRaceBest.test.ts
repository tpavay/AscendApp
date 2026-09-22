/*
 * The race-best rule against a real Firestore: the trigger publishing the
 * captain's morning history onto the global Just Climb board.
 *
 * The unit suite proves the selection; this proves the plumbing - that the
 * flags land on every bucket entry and that the curves are stored and
 * deleted with their attempt.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {onWorkoutReplaySplitsWritten} from "../../src/liveReplayLeaderboard.js";

type ReplayTriggerEvent =
  Parameters<typeof onWorkoutReplaySplitsWritten.run>[0];

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const JUST_CLIMB_BOARD = "just_climb__global";
const CAPTAIN = "captain";
const SPLIT_INTERVAL_SECONDS = 10;

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

test("publishing a Just Climb flags the most steps and fills goal keys", async () => {
  // The captain's history, in the order he climbed it: the 149-step climb
  // wore the flag on production because it was the shortest session.
  await publishJustClimb("charminar-149", 149, 70);
  await publishJustClimb("cn-tower-1776", 1776, 1200);
  await publishJustClimb("just-climb-390", 390, 250);

  const charminar = await bucketEntry(0, "charminar-149");
  const cnTower = await bucketEntry(0, "cn-tower-1776");
  const open390 = await bucketEntry(0, "just-climb-390");

  // No goal: the most steps, all time.
  assert.equal(cnTower.isBestForUser, true);
  assert.equal(charminar.isBestForUser, false);
  assert.equal(open390.isBestForUser, false);

  // A duration goal of five minutes: the CN Tower climb had 444 steps at
  // 300s, the 390 climb had ended on 390. A step goal of 1,700: only the CN
  // Tower climb ever got there. A step goal of 100: the 149-step sprint was
  // there first.
  assert.ok(goalKeys(cnTower).includes("duration:300"));
  assert.ok(goalKeys(cnTower).includes("steps:1700"));
  assert.ok(goalKeys(charminar).includes("steps:100"));
  assert.equal(goalKeys(open390).includes("steps:100"), false);

  // The flags reach every bucket the attempt published into, not only bucket
  // zero - a live window reads whichever bucket the race has reached. The
  // normalizer pads a 1,200-second curve to 121 checkpoints, one past the
  // finish clock.
  const lastCnTowerBucket = await bucketEntry(120, "cn-tower-1776");
  assert.equal(lastCnTowerBucket.isBestForUser, true);
  assert.deepEqual(goalKeys(lastCnTowerBucket), goalKeys(cnTower));

  // Each attempt's curve is stored for the next reconciliation.
  const curve = await attemptCurve("cn-tower-1776");
  assert.equal(curve.finalSteps, 1776);
  assert.equal(curve.finalDurationSeconds, 1200);
  assert.equal(curve.userId, CAPTAIN);
  assert.equal((curve.splitSteps as number[]).length, 121);
});

test("deleting the flagged climb promotes the next most steps", async () => {
  await publishJustClimb("charminar-149", 149, 70);
  await publishJustClimb("cn-tower-1776", 1776, 1200);
  await publishJustClimb("just-climb-390", 390, 250);

  await deleteWorkout("cn-tower-1776");

  assert.equal(
    (await db.doc(entryPath(0, "cn-tower-1776")).get()).exists,
    false
  );
  assert.equal(
    (await db.doc(attemptCurvePath("cn-tower-1776")).get()).exists,
    false
  );
  assert.equal((await bucketEntry(0, "just-climb-390")).isBestForUser, true);
  assert.equal((await bucketEntry(0, "charminar-149")).isBestForUser, false);
  assert.ok(goalKeys(await bucketEntry(0, "just-climb-390")).includes("steps:300"));
});

/**
 * Publishes one open Just Climb session for the captain through the trigger.
 * @param {string} workoutId Workout ID.
 * @param {number} steps Final steps.
 * @param {number} durationSeconds Final duration.
 */
async function publishJustClimb(
  workoutId: string,
  steps: number,
  durationSeconds: number
): Promise<void> {
  const workoutRef = db
    .collection("users")
    .doc(CAPTAIN)
    .collection("workouts")
    .doc(workoutId);
  const before = await workoutRef.get();
  await workoutRef.set(justClimbWorkout(steps, durationSeconds));
  const after = await workoutRef.get();

  await onWorkoutReplaySplitsWritten.run({
    data: {before, after},
    params: {userId: CAPTAIN, workoutId},
  } as unknown as ReplayTriggerEvent);
}

/**
 * Deletes one of the captain's workouts through the trigger.
 * @param {string} workoutId Workout ID.
 */
async function deleteWorkout(workoutId: string): Promise<void> {
  const workoutRef = db
    .collection("users")
    .doc(CAPTAIN)
    .collection("workouts")
    .doc(workoutId);
  const before = await workoutRef.get();
  await workoutRef.delete();
  const after = await workoutRef.get();

  await onWorkoutReplaySplitsWritten.run({
    data: {before, after},
    params: {userId: CAPTAIN, workoutId},
  } as unknown as ReplayTriggerEvent);
}

/**
 * A private open Just Climb backup with a linear split curve.
 * @param {number} steps Final steps.
 * @param {number} durationSeconds Final duration.
 * @return {Record<string, unknown>} Workout document.
 */
function justClimbWorkout(
  steps: number,
  durationSeconds: number
): Record<string, unknown> {
  return {
    durationSeconds,
    participations: [],
    source: "headphone_motion",
    sourceMetadata: JSON.stringify({
      splitIntervalSeconds: SPLIT_INTERVAL_SECONDS,
      splitSteps: linearCurve(steps, durationSeconds),
      stopReason: "user_stopped",
      trackingMode: "just_climb",
    }),
    steps,
  };
}

/**
 * A linear split curve at the shared interval, end-anchored.
 * @param {number} steps Final steps.
 * @param {number} durationSeconds Final duration.
 * @return {number[]} Steps at the end of each interval.
 */
function linearCurve(steps: number, durationSeconds: number): number[] {
  const buckets = Math.ceil(durationSeconds / SPLIT_INTERVAL_SECONDS);
  const curve: number[] = [];
  for (let index = 0; index < buckets; index += 1) {
    const elapsed = (index + 1) * SPLIT_INTERVAL_SECONDS;
    curve.push(Math.min(steps, Math.round(steps * elapsed / durationSeconds)));
  }
  return curve;
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
 * One attempt's stored curve, which must exist.
 * @param {string} workoutId Workout ID.
 * @return {Promise<Record<string, unknown>>} Curve data.
 */
async function attemptCurve(
  workoutId: string
): Promise<Record<string, unknown>> {
  const snapshot = await db.doc(attemptCurvePath(workoutId)).get();
  const data = snapshot.data();
  assert.ok(data, `${attemptCurvePath(workoutId)} should exist`);
  return data;
}

/**
 * The goal keys an entry carries.
 * @param {Record<string, unknown>} entry Entry data.
 * @return {string[]} Goal keys.
 */
function goalKeys(entry: Record<string, unknown>): string[] {
  assert.ok(Array.isArray(entry.bestForGoals), "entry carries bestForGoals");
  return entry.bestForGoals as string[];
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
