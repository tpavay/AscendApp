// A workout document is client-authored end to end. There is no App Check attestation and no
// server-side sensor ingestion, so a signed-in paying account can POST straight to the REST API
// with the app closed - and `leaderboardStats` derives every global standing from the `steps` and
// `durationSeconds` it finds there, which `finalizeLeaderboardAchievements` then freezes into
// permanent top_1 / top_3 / top_10 awards. Until this envelope existed the rules validated only
// the SHAPE of those numbers, so a leaderboard-topping climb no human performed was one HTTPS
// request away.
//
// These tests pin both halves of that envelope, and the accept half matters at least as much as
// the reject half: a rejected write is a climb that can never back up, so every bound here has to
// clear a real effort by a wide margin. The 24-hour StairMaster world record - 111,285 steps,
// averaging 77 per minute - is exercised below as the hardest thing a human has actually done.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { seedActiveAppAccess } from './paid-access-fixture.mjs';

const projectId = 'demo-ascendapp-rules';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const userId = 'user-123';
const workoutId = '550E8400-E29B-41D4-A716-446655440000';

// The bounds `isPhysicallyPossibleClimb` declares, restated here so a test failure names which
// number moved rather than just which document stopped writing.
const MAX_STEPS_PER_SECOND = 4;
const MAX_STEPS = 120000;
const MAX_DURATION_SECONDS = 5 * 24 * 60 * 60;

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

// Rasmus Chan Holm, 24-hour StairMaster, the ceiling on what a human has actually climbed in one
// session. Every accept bound has to leave this comfortably inside.
const WORLD_RECORD_STEPS = 111285;
const WORLD_RECORD_DURATION_SECONDS = 24 * 60 * 60;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules: firestoreRules, host: '127.0.0.1', port: 8080 },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await seedActiveAppAccess(adminContext, [userId]);
  });
});

after(async () => {
  await testEnv.cleanup();
});

// ---------------------------------------------------------------------------
// What must keep writing
// ---------------------------------------------------------------------------

test('an ordinary stair session writes untouched', async () => {
  // 1,200 steps over 30 minutes - 40 per minute, the shape of a normal weekday climb.
  await assertSucceeds(write({durationSeconds: 1800, steps: 1200}));
});

test('a hard session at a cadence a strong climber actually holds writes untouched', async () => {
  // 4,000 steps over 20 minutes - 200 per minute, well past the 24-hour record holder's 77/min
  // average and the shape of a genuinely hard interval block.
  await assertSucceeds(write({durationSeconds: 1200, steps: 4000}));
});

test('a climb the leaderboard will refuse to score still backs up', async () => {
  // 4,600 steps over 20 minutes is 230/min: above `MAX_AVERAGE_STEPS_PER_MINUTE` (220), so
  // `leaderboardStats` will not count it toward any standing, and below the rules ceiling of 240,
  // so it still reaches the cloud. That gap is deliberate. Refusing a write is permanent and
  // unrecoverable; declining to score one is neither, so the judgement call belongs to the function
  // that can afford to be wrong and the rule refuses only what is impossible.
  await assertSucceeds(write({durationSeconds: 1200, steps: 4600}));
});

test('the 24-hour StairMaster world record writes untouched', async () => {
  await assertSucceeds(write({
    durationSeconds: WORLD_RECORD_DURATION_SECONDS,
    steps: WORLD_RECORD_STEPS,
  }));
});

test('a climb sitting exactly on every bound at once writes', async () => {
  // 120,000 steps in 30,000 seconds is simultaneously the step cap and exactly 4 steps per second.
  // Both bounds are inclusive, so the corner where they meet has to be accepted, not refused.
  await assertSucceeds(write({durationSeconds: MAX_STEPS / MAX_STEPS_PER_SECOND, steps: MAX_STEPS}));
  await assertSucceeds(write({durationSeconds: MAX_DURATION_SECONDS, steps: MAX_STEPS}));
});

test('a fractional duration writes, because that is what the sensor flow records', async () => {
  // Live Climb durations are never whole seconds. 3,042 steps over 2,347.756s is the real
  // ASCEND-IOS-1J climb, and the cadence bound has to hold against a float without rounding it
  // into a refusal.
  await assertSucceeds(write({durationSeconds: 2347.7563560009003, steps: 3042}));
});

test('an empty workout with no steps and no duration writes', async () => {
  // The cadence bound is what enforces "duration above zero whenever steps are above zero", so a
  // zero/zero document must stay writable - it tops no board and refusing it would be the rule
  // inventing a constraint the product does not have.
  await assertSucceeds(write({durationSeconds: 0, steps: 0}));
});

test('a start time an hour ahead of the server writes, because device clocks drift', async () => {
  await assertSucceeds(write({startedAt: new Date(Date.now() + HOUR_MS)}));
});

// ---------------------------------------------------------------------------
// What must stop writing
// ---------------------------------------------------------------------------

test('an impossible cadence is refused', async () => {
  // 5,000 steps in one minute. Nothing with legs does this.
  await assertFails(write({durationSeconds: 60, steps: 5000}));
});

test('the cadence bound is refused one step past its ceiling', async () => {
  const durationSeconds = 1800;
  const ceiling = durationSeconds * MAX_STEPS_PER_SECOND;

  await assertSucceeds(write({durationSeconds, steps: ceiling}));
  await assertFails(write({durationSeconds, steps: ceiling + 1}));
});

test('a single climb above the per-submission step cap is refused', async () => {
  // Slow enough to clear the cadence bound with room to spare, and long enough to clear the
  // duration ceiling - the cadence bound alone does not protect a board ranked by volume, which is
  // exactly what `finalizeLeaderboardAchievements` orders by.
  await assertSucceeds(write({durationSeconds: 100000, steps: MAX_STEPS}));
  await assertFails(write({durationSeconds: 100000, steps: MAX_STEPS + 1}));
});

test('steps against a zero duration are refused', async () => {
  await assertFails(write({durationSeconds: 0, steps: 1}));
});

test('steps against a negative duration are refused', async () => {
  await assertFails(write({durationSeconds: -3600, steps: 1200}));
});

test('a duration beyond five days is refused', async () => {
  await assertSucceeds(write({durationSeconds: MAX_DURATION_SECONDS, steps: 1200}));
  await assertFails(write({durationSeconds: MAX_DURATION_SECONDS + 1, steps: 1200}));
});

test('a start time days ahead of the server is refused', async () => {
  // A future start lands the climb in a leaderboard period that has not happened yet.
  await assertFails(write({startedAt: new Date(Date.now() + 3 * DAY_MS)}));
});

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

test('the source the product still produces writes', async () => {
  await assertSucceeds(write({source: 'headphone_motion', integrityLevel: 'verified'}));
});

test('sources a returning climber can still be carrying write', async () => {
  // #443 stopped the app CREATING these; it did not stop a pre-#443 row in a returning climber's
  // SwiftData store from syncing under its original source. `WorkoutSyncCoordinator` selects on
  // `ownerUserId` alone, and `WorkoutRemoteSyncMigrationService` adopts every ownerless local row
  // on authenticated bootstrap. Refusing them here would park a real climber's own history in
  // `remoteSyncStatus == .rejected` forever, and would stop no forger - nothing downstream treats
  // `manual` as less trustworthy than `headphone_motion`.
  await assertSucceeds(write({source: 'manual'}));
  await assertSucceeds(write({source: 'apple_health'}));
  await assertSucceeds(write({source: 'hevy'}));
});

test('sources no build has ever produced are refused', async () => {
  // `garmin` and `fitbit` named integrations that were never built, so no stored row can carry
  // them - they were two strings a direct REST caller could declare and nothing else.
  await assertFails(write({source: 'garmin'}));
  await assertFails(write({source: 'fitbit'}));
  await assertFails(write({source: 'strava'}));
});

// ---------------------------------------------------------------------------
// The envelope holds on update, not just on create
// ---------------------------------------------------------------------------

test('an existing climb cannot be edited outside the envelope', async () => {
  // Writes are whole-document `setData`, so the update path is the same forgery surface as create.
  const stored = makeWorkoutDocument({durationSeconds: 1800, steps: 1200});
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(
      doc(adminContext.firestore(), `users/${userId}/workouts/${workoutId}`),
      stored
    );
  });

  // Slow enough to clear the cadence bound, so the only thing refusing this is the step cap - the
  // update path evaluates the whole envelope, not just the rate half.
  await assertFails(write({durationSeconds: 100000, steps: MAX_STEPS + 1}));
  await assertFails(write({durationSeconds: 60, steps: 5000}));
  await assertSucceeds(write({durationSeconds: 1800, steps: 1500}));
});

function write(overrides) {
  const context = testEnv.authenticatedContext(userId);
  return setDoc(
    doc(context.firestore(), `users/${userId}/workouts/${workoutId}`),
    makeWorkoutDocument(overrides)
  );
}

function makeWorkoutDocument(overrides = {}) {
  return {
    userId,
    schemaVersion: 1,
    name: 'Morning Stair Session',
    startedAt: new Date('2026-04-10T06:30:00.000Z'),
    durationSeconds: 1800,
    steps: 1200,
    floors: 75,
    stepsPerFloor: 16,
    notes: 'Felt strong',
    source: 'headphone_motion',
    integrityLevel: 'verified',
    createdAt: new Date('2026-04-10T06:00:00.000Z'),
    updatedAt: new Date('2026-04-10T07:00:00.000Z'),
    ...overrides,
  };
}
