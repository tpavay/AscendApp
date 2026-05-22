import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

const projectId = 'demo-ascendapp-rules';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
const storageRules = readFileSync(new URL('../../storage.rules', import.meta.url), 'utf8');

const userId = 'user-123';
const otherUserId = 'user-456';
const workoutId = '550e8400-e29b-41d4-a716-446655440000';
const mediaId = '11111111-1111-1111-1111-111111111111';
const secondMediaId = '22222222-2222-2222-2222-222222222222';
const weightEntryId = '33333333-3333-3333-3333-333333333333';
const participationId = '44444444-4444-4444-4444-444444444444';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: firestoreRules,
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: storageRules,
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

after(async () => {
  await testEnv.cleanup();
});

test('owner can write profile demographics on their private user document', async () => {
  const context = testEnv.authenticatedContext(userId);
  const userRef = doc(context.firestore(), `users/${userId}`);

  await assertSucceeds(setDoc(userRef, makeUserDocument({
    age: 34,
    gender: 'non_binary',
  })));
});

test('profile demographic values are bounded', async () => {
  const context = testEnv.authenticatedContext(userId);
  const userRef = doc(context.firestore(), `users/${userId}`);

  await assertFails(setDoc(userRef, makeUserDocument({
    age: 12,
    gender: 'non_binary',
  })));

  await assertFails(setDoc(userRef, makeUserDocument({
    age: 34,
    gender: 'unknown',
  })));
});

test('users cannot write demographics into another users profile', async () => {
  const context = testEnv.authenticatedContext(userId);
  const userRef = doc(context.firestore(), `users/${otherUserId}`);

  await assertFails(setDoc(userRef, makeUserDocument({
    age: 34,
    gender: 'woman',
  })));
});

test('owner can write a valid workout backup document', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${userId}/workouts/${workoutId}`);

  await assertSucceeds(setDoc(workoutRef, makeWorkoutDocument({
    media: [makeMediaItem()],
    highlightedMediaId: mediaId,
    weightConfiguration: {
      entries: [makeWeightEntry()],
    },
    heartRateSeries: makeHeartRateSeriesReference(userId, workoutId),
  })));
});

test('owner can write a workout with routine template participation', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${userId}/workouts/${workoutId}`);

  await assertSucceeds(setDoc(workoutRef, makeWorkoutDocument({
    participations: [makeRoutineTemplateParticipation()],
  })));
});

test('owner can write a headphone motion workout with climb attempt participation', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${userId}/workouts/${workoutId}`);

  await assertSucceeds(setDoc(workoutRef, makeWorkoutDocument({
    source: 'headphone_motion',
    integrityLevel: 'verified',
    participations: [makeClimbAttemptParticipation()],
  })));
});

test('climb attempt participation requires headphone motion source', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${userId}/workouts/${workoutId}`);

  await assertFails(setDoc(workoutRef, makeWorkoutDocument({
    source: 'manual',
    integrityLevel: 'unverified',
    participations: [makeClimbAttemptParticipation()],
  })));
});

test('highlighted media id must point to an uploaded media item', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${userId}/workouts/${workoutId}`);

  await assertFails(setDoc(workoutRef, makeWorkoutDocument({
    media: [makeMediaItem()],
    highlightedMediaId: secondMediaId,
  })));
});

test('invalid nested media items are rejected', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${userId}/workouts/${workoutId}`);

  await assertFails(setDoc(workoutRef, makeWorkoutDocument({
    media: [
      makeMediaItem(),
      {
        ...makeMediaItem(secondMediaId),
        type: 'gif',
      },
    ],
    highlightedMediaId: mediaId,
  })));
});

test('invalid weight entries are rejected', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${userId}/workouts/${workoutId}`);

  await assertFails(setDoc(workoutRef, makeWorkoutDocument({
    weightConfiguration: {
      entries: [
        makeWeightEntry(),
        {
          ...makeWeightEntry('44444444-4444-4444-4444-444444444444'),
          equipmentType: 'sled',
        },
      ],
    },
  })));
});

test('users cannot write workouts into another users path', async () => {
  const context = testEnv.authenticatedContext(userId);
  const workoutRef = doc(context.firestore(), `users/${otherUserId}/workouts/${workoutId}`);

  await assertFails(setDoc(workoutRef, makeWorkoutDocument({
    userId: otherUserId,
  })));
});

test('owner can upload a valid heart-rate sidecar blob', async () => {
  const context = testEnv.authenticatedContext(userId);
  const sidecarRef = ref(
    context.storage(),
    `users/${userId}/workout_heart_rate/${workoutId}.json.gz`
  );

  await assertSucceeds(uploadBytes(sidecarRef, new Uint8Array([1, 2, 3]), {
    contentType: 'application/gzip',
  }));
});

test('non-owners cannot upload heart-rate sidecars into another users scope', async () => {
  const context = testEnv.authenticatedContext(userId);
  const sidecarRef = ref(
    context.storage(),
    `users/${otherUserId}/workout_heart_rate/${workoutId}.json.gz`
  );

  await assertFails(uploadBytes(sidecarRef, new Uint8Array([1, 2, 3]), {
    contentType: 'application/gzip',
  }));
});

test('heart-rate sidecars must be compressed uploads', async () => {
  const context = testEnv.authenticatedContext(userId);
  const sidecarRef = ref(
    context.storage(),
    `users/${userId}/workout_heart_rate/${workoutId}.json.gz`
  );

  await assertFails(uploadBytes(sidecarRef, new Uint8Array([1, 2, 3]), {
    contentType: 'application/json',
  }));
});

test('signed-in users can read server-published live replay leaderboard windows', async () => {
  const contextKey = 'live_climb__pyramid-giza';

  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    const db = adminContext.firestore();
    await setDoc(doc(db, `live_replay_leaderboards/${contextKey}`), {
      schemaVersion: 1,
      contextType: 'live_climb',
      contextId: 'pyramid-giza',
      totalClimbers: 247,
      updatedAt: new Date('2026-05-04T12:00:00.000Z'),
    });
    await setDoc(doc(db, `live_replay_leaderboards/${contextKey}/splitBuckets/60/entries/attempt-1`), {
      userId: otherUserId,
      displayName: 'Sarah K.',
      avatarToken: 'SK',
      photoURL: 'https://example.com/sarah.jpg',
      stepsAtBucket: 1389,
      rank: 12,
      completionDurationSeconds: 872,
      updatedAt: new Date('2026-05-04T12:00:00.000Z'),
    });
  });

  const context = testEnv.authenticatedContext(userId);
  await assertSucceeds(getDoc(doc(context.firestore(), `live_replay_leaderboards/${contextKey}`)));
  await assertSucceeds(getDoc(doc(
    context.firestore(),
    `live_replay_leaderboards/${contextKey}/splitBuckets/60/entries/attempt-1`
  )));
});

test('signed-in users can read server-owned live replay avatars', async () => {
  const avatarPath = 'live-replay-avatars/live-replay-v1-dev/avatar-001.jpg';

  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await uploadBytes(ref(adminContext.storage(), avatarPath), new Uint8Array([1, 2, 3]), {
      contentType: 'image/jpeg',
    });
  });

  const context = testEnv.authenticatedContext(userId);
  const anonymousContext = testEnv.unauthenticatedContext();

  await assertSucceeds(getBytes(ref(context.storage(), avatarPath)));
  await assertFails(getBytes(ref(anonymousContext.storage(), avatarPath)));
  await assertFails(uploadBytes(ref(context.storage(), avatarPath), new Uint8Array([4, 5, 6]), {
    contentType: 'image/jpeg',
  }));
});

test('clients cannot write live replay leaderboard indexes', async () => {
  const context = testEnv.authenticatedContext(userId);
  const contextKey = 'live_climb__pyramid-giza';

  await assertFails(setDoc(doc(context.firestore(), `live_replay_leaderboards/${contextKey}`), {
    schemaVersion: 1,
    contextType: 'live_climb',
    contextId: 'pyramid-giza',
    totalClimbers: 1,
    updatedAt: new Date('2026-05-04T12:00:00.000Z'),
  }));

  await assertFails(setDoc(doc(
    context.firestore(),
    `live_replay_leaderboards/${contextKey}/splitBuckets/60/entries/${userId}`
  ), {
    userId,
    displayName: 'You',
    avatarToken: 'YOU',
    stepsAtBucket: 1200,
    rank: 1,
    updatedAt: new Date('2026-05-04T12:00:00.000Z'),
  }));
});

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
    source: 'apple_health',
    integrityLevel: 'verified',
    createdAt: new Date('2026-04-10T06:00:00.000Z'),
    updatedAt: new Date('2026-04-10T07:00:00.000Z'),
    ...overrides,
  };
}

function makeUserDocument(overrides = {}) {
  return {
    email: 'tyler@example.com',
    firstName: '',
    lastName: '',
    displayName: 'Tyler',
    createdAt: new Date('2026-05-18T12:00:00.000Z'),
    lastUpdated: new Date('2026-05-18T12:00:00.000Z'),
    ...overrides,
  };
}

function makeMediaItem(id = mediaId) {
  return {
    id,
    url: 'https://example.com/workout-media.jpg',
    uploadedAt: new Date('2026-04-10T07:00:00.000Z'),
    type: 'photo',
  };
}

function makeWeightEntry(id = weightEntryId) {
  return {
    id,
    equipmentType: 'weighted_vest',
    weightValue: 20,
    isEnabled: true,
  };
}

function makeHeartRateSeriesReference(ownerUserId, ownerWorkoutId) {
  return {
    storagePath: `users/${ownerUserId}/workout_heart_rate/${ownerWorkoutId}.json.gz`,
    encoding: 'json+gzip',
    sampleCount: 3,
    seriesStartAt: new Date('2026-04-10T06:30:00.000Z'),
    seriesEndAt: new Date('2026-04-10T06:45:00.000Z'),
  };
}

function makeRoutineTemplateParticipation() {
  return {
    id: participationId,
    workoutId,
    userId,
    contextType: 'routine_template',
    contextId: 'pyramid_climb',
    contextVersion: 1,
    rulesVersion: 1,
    role: 'primary',
    leaderboardEligible: true,
    verificationTier: 'provider_verified',
    metricsSnapshot: makeMetricsSnapshot(),
    createdAt: new Date('2026-04-10T07:00:00.000Z'),
  };
}

function makeClimbAttemptParticipation() {
  return {
    ...makeRoutineTemplateParticipation(),
    contextType: 'climb_attempt',
    contextId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    verificationTier: 'sensor_verified',
  };
}

function makeMetricsSnapshot() {
  return {
    startedAt: new Date('2026-04-10T06:30:00.000Z'),
    durationSeconds: 1800,
    steps: 1200,
    floors: 75,
    stepsPerMinute: 40,
  };
}
