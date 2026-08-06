import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDocs, setDoc } from 'firebase/firestore';
import { seedActiveAppAccess } from './paid-access-fixture.mjs';

// `clearFirestore()` wipes a whole project and this suite deletes the accounts it
// seeds, so it owns a Firestore project id no other suite reads. That is data
// isolation only - it buys no concurrency. The whole rules suite still has to run
// one file at a time under `--test-concurrency=1`, because the Storage emulator
// holds a single global ruleset; see `ascend-firebase-data` for why a parallel run
// turns `assertFails` green for the wrong reason.
const projectId = 'demo-ascendapp-rules-account-deletion';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const entitledOwnerId = 'entitled-owner-123';
const unentitledOwnerId = 'unentitled-owner-456';
const emptyUnentitledOwnerId = 'empty-unentitled-owner-789';
const entitledIntruderId = 'entitled-intruder-012';
const unentitledIntruderId = 'unentitled-intruder-345';
const blockedClimberId = 'blocked-climber-678';

const workoutId = '550E8400-E29B-41D4-A716-446655440000';
const secondWorkoutId = '660E8400-E29B-41D4-A716-446655440000';
const routineId = '770E8400-E29B-41D4-A716-446655440000';
const secondRoutineId = '880E8400-E29B-41D4-A716-446655440000';
const folderId = '990E8400-E29B-41D4-A716-446655440000';
const secondFolderId = 'AA0E8400-E29B-41D4-A716-446655440000';
const intervalId = '11111111-1111-1111-1111-111111111111';

/**
 * Every collection `FirebaseAccountDeletionGateway` enumerates with
 * `getDocuments()` before batch-deleting what comes back.
 *
 * Firestore evaluates a list rule against the *query*, not against the stored
 * documents, so a paid read gate on any of these refuses an unentitled owner's
 * sweep even when the collection is empty - and guideline 5.1.1(v) deletion
 * becomes impossible the moment a subscription lapses.
 */
const sweptCollections = [
  {
    name: 'workouts',
    documentId: workoutId,
    secondDocumentId: secondWorkoutId,
    makeDocument: makeWorkoutDocument,
    paidWrites: true,
    crossAccountReadable: false,
  },
  {
    name: 'routines',
    documentId: routineId,
    secondDocumentId: secondRoutineId,
    makeDocument: makeRoutineDocument,
    paidWrites: true,
    crossAccountReadable: false,
  },
  {
    name: 'routine_folders',
    documentId: folderId,
    secondDocumentId: secondFolderId,
    makeDocument: makeFolderDocument,
    paidWrites: true,
    crossAccountReadable: false,
  },
  {
    name: 'blocked',
    documentId: blockedClimberId,
    makeDocument: makeBlockedClimberDocument,
    paidWrites: false,
    crossAccountReadable: false,
  },
  {
    // The one public projection the sweep enumerates: any entitled climber may
    // read another's, so the owner is added to that gate rather than replacing it.
    name: 'profile_workouts',
    documentId: workoutId,
    secondDocumentId: secondWorkoutId,
    makeDocument: makeProfileWorkoutSummary,
    paidWrites: true,
    crossAccountReadable: true,
  },
];

/** Single documents the sweep deletes by path, without listing first. */
const sweptDocuments = [
  { path: (ownerId) => `users/${ownerId}/public_profile/current`, makeDocument: makePublicProfileDocument },
  { path: (ownerId) => `users/${ownerId}/profile_stats/current`, makeDocument: makeProfileStatsDocument },
  { path: (ownerId) => `users/${ownerId}`, makeDocument: makeUserDocument },
];

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
    await seedActiveAppAccess(adminContext, [entitledOwnerId, entitledIntruderId]);

    for (const ownerId of [entitledOwnerId, unentitledOwnerId]) {
      await seedDeletableAccount(adminContext, ownerId);
    }
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('an entitled owner can enumerate and delete everything the sweep touches', async () => {
  await assertAccountSweepSucceeds(entitledOwnerId);
});

// The launch blocker: a lapsed subscriber tapping Delete Account. The sweep is
// ordered Storage, then these collections, then Auth, so a refusal here strands
// the climber with their media already gone and an account they cannot delete.
test('an unentitled owner can enumerate and delete everything the sweep touches', async () => {
  await assertAccountSweepSucceeds(unentitledOwnerId);
});

test('an unentitled owner can enumerate the swept collections with nothing stored', async () => {
  const context = testEnv.authenticatedContext(emptyUnentitledOwnerId);

  for (const swept of sweptCollections) {
    await assertSucceeds(getDocs(collection(
      context.firestore(),
      `users/${emptyUnentitledOwnerId}/${swept.name}`
    )));
  }
});

test('enumerating for deletion does not unlock paid creates or updates', async () => {
  const entitled = testEnv.authenticatedContext(entitledOwnerId);
  const unentitled = testEnv.authenticatedContext(unentitledOwnerId);

  for (const swept of sweptCollections.filter(({ paidWrites }) => paidWrites)) {
    // A fresh id is a create; the seeded id is an update. The entitled write
    // proves the payload is valid, so the unentitled refusal can only be the gate.
    const createPath = (ownerId) => `users/${ownerId}/${swept.name}/${swept.secondDocumentId}`;
    const updatePath = (ownerId) => `users/${ownerId}/${swept.name}/${swept.documentId}`;

    for (const path of [createPath, updatePath]) {
      await assertSucceeds(setDoc(
        doc(entitled.firestore(), path(entitledOwnerId)),
        swept.makeDocument(entitledOwnerId)
      ));
      await assertFails(setDoc(
        doc(unentitled.firestore(), path(unentitledOwnerId)),
        swept.makeDocument(unentitledOwnerId)
      ));
    }
  }
});

test('another climber cannot enumerate or delete an account they do not own', async () => {
  const context = testEnv.authenticatedContext(entitledIntruderId);

  for (const swept of sweptCollections) {
    const collectionRef = collection(
      context.firestore(),
      `users/${unentitledOwnerId}/${swept.name}`
    );
    const documentRef = doc(collectionRef, swept.documentId);

    if (swept.crossAccountReadable) {
      await assertSucceeds(getDocs(collectionRef));
    } else {
      await assertFails(getDocs(collectionRef));
    }

    await assertFails(deleteDoc(documentRef));
  }

  for (const swept of sweptDocuments) {
    await assertFails(deleteDoc(doc(context.firestore(), swept.path(unentitledOwnerId))));
  }
});

// The owner clause added to profile_workouts must not become a second way in for
// everyone else: an unentitled non-owner stays on the paid side of that gate.
test('an unentitled climber cannot read another climber public workout mirror', async () => {
  const context = testEnv.authenticatedContext(unentitledIntruderId);

  await assertFails(getDocs(collection(
    context.firestore(),
    `users/${entitledOwnerId}/profile_workouts`
  )));
});

test('a signed-out client cannot enumerate or delete anything the sweep touches', async () => {
  const context = testEnv.unauthenticatedContext();

  for (const swept of sweptCollections) {
    const collectionRef = collection(
      context.firestore(),
      `users/${unentitledOwnerId}/${swept.name}`
    );

    await assertFails(getDocs(collectionRef));
    await assertFails(deleteDoc(doc(collectionRef, swept.documentId)));
  }

  for (const swept of sweptDocuments) {
    await assertFails(deleteDoc(doc(context.firestore(), swept.path(unentitledOwnerId))));
  }
});

/** Walks the gateway's sweep in order: list each collection, delete what came back. */
async function assertAccountSweepSucceeds(ownerId) {
  const context = testEnv.authenticatedContext(ownerId);

  for (const swept of sweptCollections) {
    const collectionRef = collection(context.firestore(), `users/${ownerId}/${swept.name}`);
    const snapshot = await assertSucceeds(getDocs(collectionRef));

    for (const document of snapshot.docs) {
      await assertSucceeds(deleteDoc(document.ref));
    }
  }

  for (const swept of sweptDocuments) {
    await assertSucceeds(deleteDoc(doc(context.firestore(), swept.path(ownerId))));
  }
}

async function seedDeletableAccount(adminContext, ownerId) {
  for (const swept of sweptCollections) {
    await setDoc(
      doc(adminContext.firestore(), `users/${ownerId}/${swept.name}/${swept.documentId}`),
      swept.makeDocument(ownerId)
    );
  }

  for (const swept of sweptDocuments) {
    await setDoc(
      doc(adminContext.firestore(), swept.path(ownerId)),
      swept.makeDocument(ownerId)
    );
  }
}

function makeWorkoutDocument(ownerId) {
  return {
    userId: ownerId,
    schemaVersion: 1,
    name: 'Morning Stair Session',
    startedAt: new Date('2026-04-10T06:30:00.000Z'),
    durationSeconds: 1800,
    steps: 1200,
    floors: 75,
    stepsPerFloor: 16,
    notes: 'Felt strong',
    source: 'apple_health',
    integrityLevel: 'verified',
    createdAt: new Date('2026-04-10T06:00:00.000Z'),
    updatedAt: new Date('2026-04-10T07:00:00.000Z'),
  };
}

function makeRoutineDocument(ownerId) {
  return {
    userId: ownerId,
    schemaVersion: 1,
    name: 'Tuesday Pyramid',
    description: 'Build to level 14, then unwind.',
    source: 'userCreated',
    intervals: [{
      id: intervalId,
      durationSeconds: 120,
      intensityType: 'level',
      intensityValue: 12,
      order: 0,
      skipStep: false,
      backwardStep: false,
      holdingBars: false,
    }],
    isArchived: false,
    order: 0,
    completionCount: 3,
    lastCompletedAt: new Date('2026-04-10T06:30:00.000Z'),
    createdAt: new Date('2026-04-01T06:00:00.000Z'),
    updatedAt: new Date('2026-04-10T06:45:00.000Z'),
  };
}

function makeFolderDocument(ownerId) {
  return {
    userId: ownerId,
    schemaVersion: 1,
    name: 'Race prep',
    order: 0,
    createdAt: new Date('2026-04-01T06:00:00.000Z'),
    updatedAt: new Date('2026-04-10T06:45:00.000Z'),
  };
}

function makeBlockedClimberDocument() {
  return {
    blockedUid: blockedClimberId,
    createdAt: new Date('2026-04-10T07:00:00.000Z'),
  };
}

function makeProfileWorkoutSummary() {
  return {
    name: 'Morning Stair Session',
    startedAt: new Date('2026-04-10T06:30:00.000Z'),
    durationSeconds: 1800,
    steps: 1200,
    source: 'apple_health',
    lastUpdated: new Date('2026-04-10T07:00:00.000Z'),
  };
}

function makePublicProfileDocument(ownerId) {
  return {
    userId: ownerId,
    displayName: 'Climber',
    photoURL: '',
    identityPolicyVersion: 1,
    identityChangedAt: new Date('2026-04-09T12:00:00.000Z'),
    lastUpdated: new Date('2026-05-18T12:00:00.000Z'),
  };
}

function makeProfileStatsDocument(ownerId) {
  return {
    userId: ownerId,
    schemaVersion: 1,
    totalClimbs: 4,
    lastUpdated: new Date('2026-05-18T12:00:00.000Z'),
  };
}

function makeUserDocument() {
  return {
    email: 'climber@example.com',
    firstName: '',
    lastName: '',
    displayName: 'Climber',
    createdAt: new Date('2026-05-18T12:00:00.000Z'),
    lastUpdated: new Date('2026-05-18T12:00:00.000Z'),
  };
}
