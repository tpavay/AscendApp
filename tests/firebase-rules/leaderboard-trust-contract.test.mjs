import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

// Test files run concurrently against one emulator, and `clearFirestore()` wipes a whole
// project. Own project id = this suite's seeded documents survive the other suite's reset.
const projectId = 'demo-ascendapp-rules-leaderboard-trust';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const userId = 'user-123';
const identityChangedAt = new Date('2026-04-09T12:00:00.000Z');
const statsPath = `leaderboard_stats/weekly_2026-W15_${userId}`;

// The audit's number. A climber who has never opened the app cannot produce it, which is
// the point: the rules must reject the write on its own terms, not on its magnitude.
const FORGED_TOTAL_STEPS = 2_000_000_000;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: firestoreRules,
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(
      doc(adminContext.firestore(), `users/${userId}/public_profile/current`),
      makePublicProfileDocument()
    );
  });
});

after(async () => {
  await testEnv.cleanup();
});

// Issue #307. A signed-in user with no workouts at all held first place on every board
// with one ordinary HTTPS request, and the nightly finalizer froze permanent awards from
// it. The document is server-derived now, so the write has nowhere to land.
test('a signed-in climber cannot author their own global standing', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(
    doc(context.firestore(), statsPath),
    makeLeaderboardDocument({ totalSteps: FORGED_TOTAL_STEPS })
  ));

  const stored = await readLeaderboardDocument();
  assert.equal(stored, undefined, 'no forged standing may exist after the rejected write');
});

// The honest shape is refused for the same reason the forged one is: the client is not the
// author of this document. Accepting "plausible" client aggregates is what the whole class
// of forgery lives inside.
test('an honest-looking client-authored standing is refused too', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(
    doc(context.firestore(), statsPath),
    makeLeaderboardDocument()
  ));
});

test('a climber cannot inflate a server-written standing by updating it', async () => {
  await seedServerWrittenStanding();
  const context = testEnv.authenticatedContext(userId);

  await assertFails(updateDoc(
    doc(context.firestore(), statsPath),
    { totalSteps: FORGED_TOTAL_STEPS }
  ));

  const stored = await readLeaderboardDocument();
  assert.equal(stored.totalSteps, 1200, 'the server-derived total must survive the attempt');
});

test('a climber cannot delete a server-written standing to escape a bad period', async () => {
  await seedServerWrittenStanding();
  const context = testEnv.authenticatedContext(userId);

  await assertFails(deleteDoc(doc(context.firestore(), statsPath)));

  const stored = await readLeaderboardDocument();
  assert.ok(stored, 'the standing must still be there');
});

test('a climber cannot write into another climbers standing', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(
    doc(context.firestore(), 'leaderboard_stats/weekly_2026-W15_user-456'),
    makeLeaderboardDocument({ userId: 'user-456' })
  ));
});

// The board is the product's central promise, so every signed-in climber still reads it.
// Closing the write path must not close the read path.
test('every signed-in climber still reads the standings', async () => {
  await seedServerWrittenStanding();
  const context = testEnv.authenticatedContext('user-456');

  await assertSucceeds(getDoc(doc(context.firestore(), statsPath)));
});

test('signed-out readers still see nothing', async () => {
  await seedServerWrittenStanding();
  const context = testEnv.unauthenticatedContext();

  await assertFails(getDoc(doc(context.firestore(), statsPath)));
});

async function seedServerWrittenStanding() {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), statsPath), makeLeaderboardDocument());
  });
}

async function readLeaderboardDocument() {
  let data;
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    const snapshot = await getDoc(doc(adminContext.firestore(), statsPath));
    data = snapshot.data();
  });
  return data;
}

function makeLeaderboardDocument(overrides = {}) {
  return {
    userId,
    displayName: 'Climber',
    photoURL: '',
    identityPolicyVersion: 1,
    identityChangedAt,
    identityState: 'published',
    timeFrame: 'weekly',
    schemaVersion: 2,
    periodKey: '2026-W15',
    periodStartAt: new Date('2026-04-06T00:00:00.000Z'),
    totalSteps: 1200,
    totalFloors: 75,
    totalWorkouts: 1,
    totalDuration: 1800,
    stepsPerMinute: 40,
    lastUpdated: new Date('2026-04-10T07:00:00.000Z'),
    ...overrides,
  };
}

function makePublicProfileDocument(overrides = {}) {
  return {
    userId,
    displayName: 'Climber',
    photoURL: '',
    identityPolicyVersion: 1,
    identityChangedAt,
    lastUpdated: new Date('2026-05-18T12:00:00.000Z'),
    ...overrides,
  };
}
