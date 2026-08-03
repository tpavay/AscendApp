import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc } from 'firebase/firestore';

const projectId = 'demo-ascendapp-routine-rules';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const userId = 'user-123';
const otherUserId = 'user-456';
const routineId = '550E8400-E29B-41D4-A716-446655440000';
const folderId = '660E8400-E29B-41D4-A716-446655440000';
const intervalId = '11111111-1111-1111-1111-111111111111';

/**
 * The interval ceiling `isValidRoutineIntervalList` enforces. A routine at
 * exactly this size is the most expensive document the rule can be asked to
 * evaluate, so it is what proves the rule fits inside Firestore's 1000
 * expression budget rather than failing closed with a bare PERMISSION_DENIED.
 */
const maxRoutineIntervals = 40;

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
});

after(async () => {
  await testEnv.cleanup();
});

test('owner can back up a routine they authored', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument()));
});

test('owner can read back the routine they backed up', async () => {
  const context = testEnv.authenticatedContext(userId);
  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument()));

  await assertSucceeds(getDoc(routineRef(context)));
});

test('a routine at the interval ceiling still fits inside the rule expression budget', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument({
    intervals: makeIntervals(maxRoutineIntervals),
  })));
});

test('a routine past the interval ceiling is rejected', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(routineRef(context), makeRoutineDocument({
    intervals: makeIntervals(maxRoutineIntervals + 1),
  })));
});

test('another climber cannot read or write a routine that is not theirs', async () => {
  const owner = testEnv.authenticatedContext(userId);
  await assertSucceeds(setDoc(routineRef(owner), makeRoutineDocument()));

  const intruder = testEnv.authenticatedContext(otherUserId);
  await assertFails(getDoc(routineRef(intruder, userId)));
  await assertFails(setDoc(routineRef(intruder, userId), makeRoutineDocument()));
});

test('a signed-out client cannot read a routine', async () => {
  const owner = testEnv.authenticatedContext(userId);
  await assertSucceeds(setDoc(routineRef(owner), makeRoutineDocument()));

  await assertFails(getDoc(routineRef(testEnv.unauthenticatedContext(), userId)));
});

test('a routine document claiming another climber as its owner is rejected', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(routineRef(context), makeRoutineDocument({
    userId: otherUserId,
  })));
});

test('a catalog template cannot be uploaded as a user routine', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(routineRef(context), makeRoutineDocument({
    source: 'remoteTemplate',
  })));
  await assertFails(setDoc(routineRef(context), makeRoutineDocument({
    source: 'builtin',
  })));
});

test('an unknown field is rejected rather than stored', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(routineRef(context), {
    ...makeRoutineDocument(),
    secretPayload: 'nope',
  }));
});

test('a routine missing a required field is rejected', async () => {
  const context = testEnv.authenticatedContext(userId);

  for (const field of ['userId', 'name', 'source', 'intervals', 'isArchived', 'createdAt']) {
    const document = makeRoutineDocument();
    delete document[field];
    await assertFails(setDoc(routineRef(context), document));
  }
});

test('a lowercase routine document id is rejected', async () => {
  const context = testEnv.authenticatedContext(userId);
  const lowercaseRef = doc(
    context.firestore(),
    `users/${userId}/routines/${routineId.toLowerCase()}`
  );

  await assertFails(setDoc(lowercaseRef, makeRoutineDocument()));
});

test('intervals must be a list', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(routineRef(context), makeRoutineDocument({
    intervals: 'not a list',
  })));
});

test('a routine with no intervals is accepted', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument({ intervals: [] })));
});

test('the stored schema version may move forward but never backward', async () => {
  const context = testEnv.authenticatedContext(userId);
  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument({ schemaVersion: 2 })));

  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument({ schemaVersion: 3 })));
  await assertFails(setDoc(routineRef(context), makeRoutineDocument({ schemaVersion: 1 })));
});

test('createdAt is immutable once the routine exists', async () => {
  const context = testEnv.authenticatedContext(userId);
  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument()));

  await assertFails(setDoc(routineRef(context), makeRoutineDocument({
    createdAt: new Date('2027-01-01T00:00:00.000Z'),
  })));
});

test('owner can delete their own routine', async () => {
  const context = testEnv.authenticatedContext(userId);
  await assertSucceeds(setDoc(routineRef(context), makeRoutineDocument()));

  await assertSucceeds(deleteDoc(routineRef(context)));
});

test('owner can back up a routine folder', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(folderRef(context), makeFolderDocument()));
});

test('a folder colour must be a hex string', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(folderRef(context), makeFolderDocument({ colorHex: '#86D30A' })));
  await assertFails(setDoc(folderRef(context), makeFolderDocument({ colorHex: 'lime' })));
});

test('another climber cannot read or write a folder that is not theirs', async () => {
  const owner = testEnv.authenticatedContext(userId);
  await assertSucceeds(setDoc(folderRef(owner), makeFolderDocument()));

  const intruder = testEnv.authenticatedContext(otherUserId);
  await assertFails(getDoc(folderRef(intruder, userId)));
  await assertFails(setDoc(folderRef(intruder, userId), makeFolderDocument()));
});

test('routine_templates stays server-owned and read-only to clients', async () => {
  const context = testEnv.authenticatedContext(userId);
  const templateRef = doc(context.firestore(), 'routine_templates/pyramid_climb');

  await assertFails(setDoc(templateRef, { status: 'published', name: 'Mine now' }));
});

function routineRef(context, ownerId = userId, id = routineId) {
  return doc(context.firestore(), `users/${ownerId}/routines/${id}`);
}

function folderRef(context, ownerId = userId, id = folderId) {
  return doc(context.firestore(), `users/${ownerId}/routine_folders/${id}`);
}

function makeRoutineDocument(overrides = {}) {
  return {
    userId,
    schemaVersion: 1,
    name: 'Tuesday Pyramid',
    description: 'Build to level 14, then unwind.',
    source: 'userCreated',
    intervals: [makeInterval()],
    isArchived: false,
    order: 0,
    completionCount: 3,
    lastCompletedAt: new Date('2026-04-10T06:30:00.000Z'),
    createdAt: new Date('2026-04-01T06:00:00.000Z'),
    updatedAt: new Date('2026-04-10T06:45:00.000Z'),
    ...overrides,
  };
}

function makeFolderDocument(overrides = {}) {
  return {
    userId,
    schemaVersion: 1,
    name: 'Race prep',
    order: 0,
    createdAt: new Date('2026-04-01T06:00:00.000Z'),
    updatedAt: new Date('2026-04-10T06:45:00.000Z'),
    ...overrides,
  };
}

function makeInterval(overrides = {}) {
  return {
    id: intervalId,
    durationSeconds: 120,
    intensityType: 'level',
    intensityValue: 12,
    order: 0,
    skipStep: false,
    backwardStep: false,
    holdingBars: false,
    ...overrides,
  };
}

function makeIntervals(count) {
  return Array.from({ length: count }, (_unused, index) => makeInterval({
    id: `${index}`.padStart(8, '0') + '-1111-1111-1111-111111111111',
    order: index,
    sidewaysDirection: index % 2 === 0 ? 'left' : 'right',
    weightOverrideEquipmentTypes: ['weighted_vest', 'dumbbells'],
  }));
}
