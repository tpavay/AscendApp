// Firestore aborts a rules evaluation at 1000 expressions and reports the abort as a bare
// PERMISSION_DENIED, indistinguishable from a rule that deliberately said no. That is how the
// workout write rule grew past what it could evaluate without anyone noticing: it kept accepting
// small documents, and the first climber whose Live Climb carried both a participation and a
// restored heart-rate sidecar got a permanent denial with no diagnosis (ASCEND-IOS-1J).
//
// These tests pin the budget itself. Every case is a document the app can legitimately build, so
// a failure here means the rule can no longer evaluate something the client will send - not that
// the rule correctly refused it. Before adding any check to the workout rule, re-run this. Do not
// assume there is room.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import { assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { seedActiveAppAccess } from './paid-access-fixture.mjs';

const projectId = 'demo-ascendapp-rules';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const userId = 'user-123';
const workoutId = '550E8400-E29B-41D4-A716-446655440000';

// What the workout rule declares it will accept. Each is exercised at its limit below, because a
// cap the rule cannot evaluate is not a cap - it is a document the client builds and the server
// refuses forever.
const DECLARED_MAX_PARTICIPATIONS = 4;
const DECLARED_MAX_MEDIA = 3;
const DECLARED_MAX_WEIGHT_ENTRIES = 5;

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

/// The document staging still holds for the workout in ASCEND-IOS-1J, plus the two fields the
/// current client adds to it: the promoted `climbId` (#258) and the restored heart-rate sidecar
/// reference (#267). That combination is what first exceeded the budget, on 2026-07-30.
test('the Live Climb from ASCEND-IOS-1J validates as the current client builds it', async () => {
  const document = {
    ...requiredFields(),
    source: 'headphone_motion',
    integrityLevel: 'verified',
    name: 'CN Tower Live Climb',
    durationSeconds: 2347.7563560009003,
    steps: 3042,
    floors: 190,
    climbId: 'cn-tower',
    deviceModel: 'iPhone',
    sourceMetadata: liveClimbSourceMetadata(),
    participations: [climbAttemptParticipation()],
    heartRateSeries: heartRateSeriesReference(),
  };

  await assertSucceeds(write(document));
  await assertSucceeds(rewrite(document));
});

test('a workout carrying every optional field validates', async () => {
  const document = { ...requiredFields(), ...everyOptionalScalar() };

  await assertSucceeds(write(document));
  await assertSucceeds(rewrite(document));
});

test('a workout at every declared repeated-structure limit validates', async () => {
  const document = {
    ...requiredFields(),
    ...everyOptionalScalar(),
    source: 'headphone_motion',
    integrityLevel: 'verified',
    climbId: 'cn-tower',
    participations: participations(DECLARED_MAX_PARTICIPATIONS),
    media: media(DECLARED_MAX_MEDIA),
    highlightedMediaId: mediaItem(0).id,
    weightConfiguration: { entries: weightEntries(DECLARED_MAX_WEIGHT_ENTRIES) },
    heartRateSeries: heartRateSeriesReference(),
  };

  await assertSucceeds(write(document));
  await assertSucceeds(rewrite(document));
});

function write(document) {
  const context = testEnv.authenticatedContext(userId);
  return setDoc(doc(context.firestore(), `users/${userId}/workouts/${workoutId}`), document);
}

/// The update path costs more than the create path - it evaluates the same validator plus the
/// three immutability clauses - so a document that only fits on create is still a workout that can
/// never be edited again.
async function rewrite(document) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), `users/${userId}/workouts/${workoutId}`), document);
  });
  return write(document);
}

function requiredFields() {
  return {
    userId,
    schemaVersion: 1,
    name: 'Morning Stair Session',
    startedAt: new Date('2026-06-11T22:49:25.690Z'),
    durationSeconds: 1800,
    steps: 1200,
    floors: 75,
    stepsPerFloor: 16,
    notes: 'Felt strong',
    source: 'apple_health',
    integrityLevel: 'verified',
    createdAt: new Date('2026-06-11T23:28:33.467Z'),
    updatedAt: new Date('2026-06-11T23:28:33.483Z'),
  };
}

function everyOptionalScalar() {
  return {
    avgHeartRateBpm: 130,
    maxHeartRateBpm: 165,
    caloriesBurned: 400,
    effortRating: 4,
    averageMETs: 8.5,
    deviceModel: 'iPhone17,1',
    sourceMetadata: liveClimbSourceMetadata(),
    healthKitUUID: '00000000-0000-0000-0000-000000000000',
    hevyWorkoutId: 'hevy-workout-1',
  };
}

function heartRateSeriesReference() {
  return {
    storagePath: `users/${userId}/workout_heart_rate/${workoutId}.json.gz`,
    encoding: 'json+gzip',
    sampleCount: 346,
    seriesStartAt: new Date('2026-06-11T22:49:25.690Z'),
    seriesEndAt: new Date('2026-06-11T23:28:33.000Z'),
    objectSchemaVersion: 1,
    compressedByteCount: 1510,
    sha256: 'a'.repeat(64),
  };
}

function climbAttemptParticipation() {
  return {
    id: '701388C3-4922-483D-B600-170B9B2D5E2B',
    workoutId,
    userId,
    contextType: 'climb_attempt',
    contextId: 'CD3630DB-53C0-42A8-960A-6079799EF7F3',
    contextVersion: 1,
    rulesVersion: 1,
    role: 'primary',
    leaderboardEligible: true,
    verificationTier: 'sensor_verified',
    metricsSnapshot: {
      startedAt: new Date('2026-06-11T22:49:25.690Z'),
      durationSeconds: 2347.7563560009003,
      steps: 3042,
      floors: 190,
      stepsPerMinute: 77.74230896382248,
    },
    createdAt: new Date('2026-06-11T23:28:33.472Z'),
  };
}

function participations(count) {
  return Array.from({ length: count }, (_, index) => {
    if (index === 0) return climbAttemptParticipation();
    return {
      ...climbAttemptParticipation(),
      id: `7013880${index}-4922-483D-B600-170B9B2D5E2B`,
      contextType: 'routine_template',
      contextId: `template-${index}`,
      verificationTier: 'provider_verified',
    };
  });
}

function mediaItem(index) {
  return {
    id: `1111111${index}-1111-1111-1111-111111111111`,
    url: 'https://example.com/workout-media.jpg',
    uploadedAt: new Date('2026-06-11T23:28:33.000Z'),
    type: 'photo',
  };
}

function media(count) {
  return Array.from({ length: count }, (_, index) => mediaItem(index));
}

const EQUIPMENT = ['weighted_vest', 'dumbbells', 'barbell', 'ankle_weights', 'wrist_weights'];

function weightEntries(count) {
  return Array.from({ length: count }, (_, index) => ({
    id: `3333333${index}-3333-3333-3333-333333333333`,
    equipmentType: EQUIPMENT[index],
    weightValue: 20,
    isEnabled: true,
  }));
}

/// A real Live Climb's metadata, at the length the splits actually reach.
function liveClimbSourceMetadata() {
  return JSON.stringify({
    algorithmVersion: 1,
    climbId: 'cn-tower',
    climbTargetStepCount: 3042,
    sampleCount: 117026,
    sampleRateAssumptionHz: 50,
    source: 'headphone_motion',
    splitIntervalSeconds: 10,
    splitSteps: Array.from({ length: 235 }, (_, index) => index * 13),
    stopReason: 'target_reached',
    targetStepCount: 3042,
    trackingInterruptionCount: 1,
    trackingMode: 'live_climb',
  });
}
