import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteField, doc, getDoc, serverTimestamp, setDoc } from 'firebase/firestore';

// Test files run concurrently against one emulator, and `clearFirestore()` wipes a whole
// project. Own project id = this suite's seeded documents survive the other suite's reset.
const projectId = 'demo-ascendapp-rules-profile-stats';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const userId = 'user-123';
const statsPath = `users/${userId}/profile_stats/current`;

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

test('owner can write the renamed profile stats contract', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(doc(context.firestore(), statsPath), makeProfileStatsDocument()));
});

test('profile stats written under the legacy _weeks names are rejected', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(doc(context.firestore(), statsPath), makeLegacyProfileStatsDocument()));
});

test('profile stats carrying both the legacy and renamed counters are rejected', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(doc(context.firestore(), statsPath), {
    ...makeProfileStatsDocument(),
    top_1_weeks: 2,
    top_3_weeks: 5,
    top_10_weeks: 9,
    top_100_weeks: 14,
  }));
});

// The write path in ProfileRepository.upsertStats deletes the legacy keys in the same
// merge. This is what makes that necessary: rules validate the MERGED document, so a
// merge that only adds the renamed counters leaves the legacy keys in place and trips
// `hasOnly`. Publication failures are only debugLogged, so this would fail silently.
test('merging the renamed counters onto a legacy document is rejected while the legacy keys remain', async () => {
  await seedLegacyProfileStatsDocument();

  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(
    doc(context.firestore(), statsPath),
    makeProfileStatsDocument(),
    { merge: true }
  ));
});

test('the client payload rewrites a legacy document, preserving counts and dropping the legacy keys', async () => {
  await seedLegacyProfileStatsDocument();

  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(
    doc(context.firestore(), statsPath),
    makeUpsertStatsPayload(),
    { merge: true }
  ));

  const stored = await readProfileStatsDocument();

  assert.equal(stored.top_1_finishes, 2);
  assert.equal(stored.top_3_finishes, 5);
  assert.equal(stored.top_10_finishes, 9);
  assert.equal(stored.top_100_finishes, 14);
  assert.ok(!('top_1_weeks' in stored));
  assert.ok(!('top_3_weeks' in stored));
  assert.ok(!('top_10_weeks' in stored));
  assert.ok(!('top_100_weeks' in stored));
});

test('renamed counters must stay cumulative across bands', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(doc(context.firestore(), statsPath), makeProfileStatsDocument({
    top_1_finishes: 6,
    top_3_finishes: 5,
  })));

  await assertFails(setDoc(doc(context.firestore(), statsPath), makeProfileStatsDocument({
    top_10_finishes: 4,
    top_100_finishes: 3,
  })));
});

test('users cannot write profile stats into another users path', async () => {
  const context = testEnv.authenticatedContext(userId);
  const otherStatsRef = doc(context.firestore(), 'users/user-456/profile_stats/current');

  await assertFails(setDoc(otherStatsRef, makeProfileStatsDocument()));
});

async function seedLegacyProfileStatsDocument() {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), statsPath), makeLegacyProfileStatsDocument());
  });
}

async function readProfileStatsDocument() {
  let data;
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    const snapshot = await getDoc(doc(adminContext.firestore(), statsPath));
    data = snapshot.data();
  });
  return data;
}

/// Mirrors the merge payload ProfileRepository.upsertStats sends, including the
/// deletes that retire the legacy counter names.
function makeUpsertStatsPayload() {
  return {
    ...makeProfileStatsDocument({ lastUpdated: serverTimestamp() }),
    top_1_weeks: deleteField(),
    top_3_weeks: deleteField(),
    top_10_weeks: deleteField(),
    top_100_weeks: deleteField(),
  };
}

function makeProfileStatsDocument(overrides = {}) {
  return {
    total_climbs_completed: 12,
    total_first_ascents: 1,
    lifetime_total_steps: 240_000,
    lifetime_duration_seconds: 86_400,
    total_climbs: 15,
    average_steps_per_minute: 62.5,
    top_1_finishes: 2,
    top_3_finishes: 5,
    top_10_finishes: 9,
    top_100_finishes: 14,
    most_completed_climb_id: 'pyramid-giza',
    current_streak_weeks: 3,
    best_streak_weeks: 7,
    pr_most_steps: 12_000,
    pr_longest_climb_seconds: 3_600,
    pr_highest_spm: 88.25,
    lastUpdated: new Date('2026-05-18T12:00:00.000Z'),
    ...overrides,
  };
}

function makeLegacyProfileStatsDocument(overrides = {}) {
  const {
    top_1_finishes: top1,
    top_3_finishes: top3,
    top_10_finishes: top10,
    top_100_finishes: top100,
    ...rest
  } = makeProfileStatsDocument();

  return {
    ...rest,
    top_1_weeks: top1,
    top_3_weeks: top3,
    top_10_weeks: top10,
    top_100_weeks: top100,
    ...overrides,
  };
}
