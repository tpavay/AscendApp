import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

// Own project id: test files run concurrently against one emulator and
// `clearFirestore()` wipes a whole project.
const projectId = 'demo-ascendapp-rules-public-weekly-steps-top';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const boardPath = 'public_weekly_steps_top/current';
const strayPath = 'public_weekly_steps_top/other';

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
    const board = {
      schemaVersion: 1,
      periodKey: '2026-W45',
      periodStartAt: new Date('2026-11-02T00:00:00.000Z'),
      periodEndAt: new Date('2026-11-09T00:00:00.000Z'),
      rows: [{ rank: 1, displayName: 'Ada L.', photoURL: '', totalSteps: 38891 }],
      updatedAt: new Date('2026-11-04T12:00:00.000Z'),
    };
    await setDoc(doc(adminContext.firestore(), boardPath), board);
    await setDoc(doc(adminContext.firestore(), strayPath), board);
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('a signed-out visitor reads the public weekly board', async () => {
  const visitor = testEnv.unauthenticatedContext();
  await assertSucceeds(getDoc(doc(visitor.firestore(), boardPath)));
});

test('a signed-in climber reads it too, paid or not', async () => {
  const climber = testEnv.authenticatedContext('unpaid-user-456');
  await assertSucceeds(getDoc(doc(climber.firestore(), boardPath)));
});

test('only the one document is public', async () => {
  const visitor = testEnv.unauthenticatedContext();
  await assertFails(getDoc(doc(visitor.firestore(), strayPath)));
});

test('nobody writes it from a client', async () => {
  const visitor = testEnv.unauthenticatedContext();
  const climber = testEnv.authenticatedContext('some-user');
  for (const context of [visitor, climber]) {
    const ref = doc(context.firestore(), boardPath);
    await assertFails(setDoc(ref, { schemaVersion: 1, rows: [] }));
    await assertFails(updateDoc(ref, { rows: [] }));
    await assertFails(deleteDoc(ref));
  }
});

test('the paid leaderboard stays closed to a signed-out visitor', async () => {
  const visitor = testEnv.unauthenticatedContext();
  await assertFails(getDoc(doc(visitor.firestore(), 'leaderboard_stats/any')));
});
