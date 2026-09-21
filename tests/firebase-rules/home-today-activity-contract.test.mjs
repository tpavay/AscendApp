import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { seedActiveAppAccess } from './paid-access-fixture.mjs';

// Own project id: test files run concurrently against one emulator and
// `clearFirestore()` wipes a whole project.
const projectId = 'demo-ascendapp-rules-home-today-activity';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const paidUserId = 'paid-user-123';
const unpaidUserId = 'unpaid-user-456';
const feedPath = 'home_today_activity/global';
const strayPath = 'home_today_activity/not-global';

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
    await seedActiveAppAccess(adminContext, [paidUserId]);
    const feed = {
      schemaVersion: 1,
      rowCount: 1,
      rows: [
        {
          workoutId: 'w1',
          userId: paidUserId,
          kind: 'live_climb',
          climbId: 'empire-state-building',
          steps: 2096,
          durationSeconds: 900,
          completedAt: new Date('2026-09-21T09:00:00.000Z'),
          publishedAt: new Date('2026-09-21T09:00:05.000Z'),
          displayName: 'Ada',
          avatarToken: 'AE7',
          photoURL: '',
          identityState: 'published',
          isSynthetic: false,
        },
      ],
      updatedAt: new Date('2026-09-21T09:00:05.000Z'),
    };
    await setDoc(doc(adminContext.firestore(), feedPath), feed);
    await setDoc(doc(adminContext.firestore(), strayPath), feed);
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('a paid climber reads the global today feed', async () => {
  const context = testEnv.authenticatedContext(paidUserId);

  await assertSucceeds(getDoc(doc(context.firestore(), feedPath)));
});

test('an unpaid climber and a signed-out caller cannot read it', async () => {
  await assertFails(getDoc(doc(testEnv.authenticatedContext(unpaidUserId).firestore(), feedPath)));
  await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), feedPath)));
});

test('only the global document is readable', async () => {
  const context = testEnv.authenticatedContext(paidUserId);

  await assertFails(getDoc(doc(context.firestore(), strayPath)));
});

test('no client writes the feed, not even its own row', async () => {
  const context = testEnv.authenticatedContext(paidUserId);
  const feed = doc(context.firestore(), feedPath);

  await assertFails(updateDoc(feed, { rowCount: 2 }));
  await assertFails(setDoc(feed, { schemaVersion: 1, rowCount: 0, rows: [] }));
  await assertFails(deleteDoc(feed));
  await assertFails(setDoc(doc(context.firestore(), 'home_today_activity/forged'), { rows: [] }));
});
