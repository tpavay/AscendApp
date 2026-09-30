import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

import { seedActiveAppAccess } from './paid-access-fixture.mjs';

// The climbers someone filters Ascend Mountain's race down to: private to them like the block
// list, created only with paid access, and always deletable by the owner.
const projectId = 'demo-ascendapp-rules-race-filter';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
const firestoreIndexes = JSON.parse(readFileSync(new URL('../../firestore.indexes.json', import.meta.url), 'utf8'));

const ownerId = 'racer-123';
const unentitledOwnerId = 'lapsed-racer-321';
const climberId = 'climber-456';
const otherClimberId = 'climber-789';

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
    await seedActiveAppAccess(adminContext, [ownerId]);
  });
});

after(async () => {
  await testEnv.cleanup();
});

function makeChoice(uid) {
  return { climberUid: uid, createdAt: serverTimestamp() };
}

async function seedChoice(owner, uid) {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(
      doc(adminContext.firestore(), `users/${owner}/race_filter/${uid}`),
      { climberUid: uid, createdAt: new Date('2026-09-29T07:00:00.000Z') }
    );
  });
}

test('an entitled climber can choose, read, list and unchoose their own climbers', async () => {
  const context = testEnv.authenticatedContext(ownerId);
  const choice = doc(context.firestore(), `users/${ownerId}/race_filter/${climberId}`);

  await assertSucceeds(setDoc(choice, makeChoice(climberId)));
  await assertSucceeds(getDoc(choice));
  await assertSucceeds(getDocs(collection(context.firestore(), `users/${ownerId}/race_filter`)));
  await assertSucceeds(deleteDoc(choice));
});

test('choosing is the paid product, but a lapsed climber still reads and clears their list', async () => {
  await seedChoice(unentitledOwnerId, climberId);
  const context = testEnv.authenticatedContext(unentitledOwnerId);

  await assertFails(setDoc(
    doc(context.firestore(), `users/${unentitledOwnerId}/race_filter/${otherClimberId}`),
    makeChoice(otherClimberId)
  ));
  await assertSucceeds(getDocs(collection(context.firestore(), `users/${unentitledOwnerId}/race_filter`)));
  await assertSucceeds(deleteDoc(doc(context.firestore(), `users/${unentitledOwnerId}/race_filter/${climberId}`)));
});

test('nobody else can read, list, write or clear a climbers choices', async () => {
  await seedChoice(ownerId, climberId);
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await seedActiveAppAccess(adminContext, [climberId]);
  });
  // The chosen climber above all: nobody is told they were chosen.
  const context = testEnv.authenticatedContext(climberId);

  await assertFails(getDoc(doc(context.firestore(), `users/${ownerId}/race_filter/${climberId}`)));
  await assertFails(getDocs(collection(context.firestore(), `users/${ownerId}/race_filter`)));
  await assertFails(setDoc(
    doc(context.firestore(), `users/${ownerId}/race_filter/${otherClimberId}`),
    makeChoice(otherClimberId)
  ));
  await assertFails(deleteDoc(doc(context.firestore(), `users/${ownerId}/race_filter/${climberId}`)));
});

test('a choice names exactly one other climber and nothing else, and never changes', async () => {
  const context = testEnv.authenticatedContext(ownerId);

  await assertFails(setDoc(doc(context.firestore(), `users/${ownerId}/race_filter/${ownerId}`), makeChoice(ownerId)));
  await assertFails(setDoc(
    doc(context.firestore(), `users/${ownerId}/race_filter/${climberId}`),
    makeChoice(otherClimberId)
  ));
  await assertFails(setDoc(
    doc(context.firestore(), `users/${ownerId}/race_filter/${climberId}`),
    { ...makeChoice(climberId), displayName: 'Schema pollution' }
  ));
  await assertFails(setDoc(
    doc(context.firestore(), `users/${ownerId}/race_filter/${climberId}`),
    { climberUid: climberId, createdAt: new Date('2020-01-01T00:00:00.000Z') }
  ));

  const choice = doc(context.firestore(), `users/${ownerId}/race_filter/${climberId}`);
  await assertSucceeds(setDoc(choice, makeChoice(climberId)));
  await assertFails(updateDoc(choice, { createdAt: serverTimestamp() }));
});

// Account deletion removes the deleted climber from everyone else's filter with a
// collection-group query, which needs this single-field index.
test('incoming race filter cleanup has a collection-group single-field index', () => {
  const override = firestoreIndexes.fieldOverrides.find(
    (candidate) => candidate.collectionGroup === 'race_filter' && candidate.fieldPath === 'climberUid'
  );

  assert.ok(override);
  assert.deepEqual(override.indexes, [{ order: 'ASCENDING', queryScope: 'COLLECTION_GROUP' }]);
});
