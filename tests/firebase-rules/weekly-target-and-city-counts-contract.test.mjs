import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';

// Own project id so this suite's reset never wipes another suite's documents.
const projectId = 'demo-ascendapp-rules-weekly-target-city-counts';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const userId = 'user-123';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules: firestoreRules, host: '127.0.0.1', port: 8080 },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

function userDocument(extra = {}) {
  return {
    email: 'climber@example.com',
    firstName: 'Ada',
    lastName: 'Climber',
    displayName: 'Ada C.',
    createdAt: new Date('2026-11-04T12:00:00.000Z'),
    lastUpdated: new Date('2026-11-04T12:00:00.000Z'),
    ...extra,
  };
}

test('a weekly target is a whole number of days from one to seven', async () => {
  const db = testEnv.authenticatedContext(userId).firestore();

  for (const days of [1, 3, 7]) {
    await assertSucceeds(setDoc(doc(db, `users/${userId}`), userDocument({ weekly_target_days: days })));
  }
  for (const bad of [0, 8, -1, 3.5, '3', null, true]) {
    await assertFails(setDoc(doc(db, `users/${userId}`), userDocument({ weekly_target_days: bad })));
  }
});

test('no target at all is a valid user document, so skipping leaves the field absent', async () => {
  const db = testEnv.authenticatedContext(userId).firestore();

  await assertSucceeds(setDoc(doc(db, `users/${userId}`), userDocument()));
});

test('a target can be changed and only its owner can write it', async () => {
  const db = testEnv.authenticatedContext(userId).firestore();
  await assertSucceeds(setDoc(doc(db, `users/${userId}`), userDocument({ weekly_target_days: 3 })));
  await assertSucceeds(updateDoc(doc(db, `users/${userId}`), { weekly_target_days: 5, lastUpdated: new Date('2026-11-05T12:00:00.000Z') }));

  const stranger = testEnv.authenticatedContext('someone-else').firestore();
  await assertFails(updateDoc(doc(stranger, `users/${userId}`), { weekly_target_days: 1, lastUpdated: new Date('2026-11-05T12:00:00.000Z') }));
  await assertFails(getDoc(doc(stranger, `users/${userId}`)));
});

test('a city count is readable by a signed-out phone, one document at a time', async () => {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'public_city_climber_counts/US__il__chicago'), {
      schemaVersion: 1,
      city: 'Chicago',
      region: 'IL',
      countryCode: 'US',
      climbers: 12,
    });
  });
  const signedOut = testEnv.unauthenticatedContext().firestore();

  const snapshot = await assertSucceeds(getDoc(doc(signedOut, 'public_city_climber_counts/US__il__chicago')));
  if (snapshot.data().climbers !== 12) throw new Error('count not read');
  // A city with no document reads as absent, which the app treats as zero climbers.
  const absent = await assertSucceeds(getDoc(doc(signedOut, 'public_city_climber_counts/US__tx__austin')));
  if (absent.exists()) throw new Error('expected no document');
});

test('the set of cities cannot be listed', async () => {
  const signedOut = testEnv.unauthenticatedContext().firestore();
  const signedIn = testEnv.authenticatedContext(userId).firestore();

  await assertFails(getDocs(collection(signedOut, 'public_city_climber_counts')));
  await assertFails(getDocs(collection(signedIn, 'public_city_climber_counts')));
});

test('no client can author or change a city count', async () => {
  const signedOut = testEnv.unauthenticatedContext().firestore();
  const signedIn = testEnv.authenticatedContext(userId).firestore();
  const count = { schemaVersion: 1, city: 'Chicago', region: 'IL', countryCode: 'US', climbers: 9999 };

  await assertFails(setDoc(doc(signedOut, 'public_city_climber_counts/US__il__chicago'), count));
  await assertFails(setDoc(doc(signedIn, 'public_city_climber_counts/US__il__chicago'), count));
});

test('a signed-out phone can read the summary and no client can write it', async () => {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'public_city_climber_counts/_summary'), {
      schemaVersion: 1,
      updatedAt: new Date('2026-11-04T12:17:00.000Z'),
    });
  });
  const signedOut = testEnv.unauthenticatedContext().firestore();
  const signedIn = testEnv.authenticatedContext(userId).firestore();

  const snapshot = await assertSucceeds(getDoc(doc(signedOut, 'public_city_climber_counts/_summary')));
  if (!snapshot.exists()) throw new Error('summary not read');

  const forged = { schemaVersion: 1, updatedAt: new Date('2026-11-05T12:17:00.000Z') };
  await assertFails(setDoc(doc(signedOut, 'public_city_climber_counts/_summary'), forged));
  await assertFails(setDoc(doc(signedIn, 'public_city_climber_counts/_summary'), forged));
  await assertFails(deleteDoc(doc(signedIn, 'public_city_climber_counts/_summary')));
});
