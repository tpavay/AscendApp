import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteField, doc, getDoc, serverTimestamp, setDoc } from 'firebase/firestore';
import { seedActiveAppAccess } from './paid-access-fixture.mjs';

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
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await seedActiveAppAccess(adminContext, [userId]);
  });
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

// The heart-rate aggregates are additive: a document without them is exactly what every
// shipped client writes, and it must keep passing.
test('profile stats carrying heart-rate aggregates are accepted', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(doc(context.firestore(), statsPath), makeProfileStatsDocument({
    average_heart_rate_bpm: 142,
    max_heart_rate_bpm: 178,
  })));
});

test('either heart-rate aggregate may be published without the other', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(doc(context.firestore(), statsPath), makeProfileStatsDocument({
    max_heart_rate_bpm: 178,
  })));
  await assertSucceeds(setDoc(doc(context.firestore(), statsPath), makeProfileStatsDocument({
    average_heart_rate_bpm: 142,
  })));
});

test('an earlier client merge onto a document holding heart rate still succeeds', async () => {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), statsPath), makeProfileStatsDocument({
      average_heart_rate_bpm: 142,
      max_heart_rate_bpm: 178,
    }));
  });

  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(
    doc(context.firestore(), statsPath),
    makeUpsertStatsPayload(),
    { merge: true }
  ));
  const stored = await readProfileStatsDocument();
  assert.equal(stored.average_heart_rate_bpm, 142);
  assert.equal(stored.max_heart_rate_bpm, 178);
});

test('the current client payload clears heart rate a climber no longer has', async () => {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), statsPath), makeProfileStatsDocument({
      average_heart_rate_bpm: 142,
      max_heart_rate_bpm: 178,
    }));
  });

  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(
    doc(context.firestore(), statsPath),
    {
      ...makeUpsertStatsPayload(),
      average_heart_rate_bpm: deleteField(),
      max_heart_rate_bpm: deleteField(),
    },
    { merge: true }
  ));
  const stored = await readProfileStatsDocument();
  assert.ok(!('average_heart_rate_bpm' in stored));
  assert.ok(!('max_heart_rate_bpm' in stored));
});

test('heart-rate aggregates outside a plausible human range are rejected', async () => {
  const context = testEnv.authenticatedContext(userId);
  const statsRef = doc(context.firestore(), statsPath);

  for (const overrides of [
    { average_heart_rate_bpm: 24 },
    { average_heart_rate_bpm: 251 },
    { max_heart_rate_bpm: 0 },
    { max_heart_rate_bpm: 300 },
    { average_heart_rate_bpm: 142.5 },
    { max_heart_rate_bpm: '178' },
  ]) {
    await assertFails(setDoc(statsRef, makeProfileStatsDocument(overrides)));
  }
});

test('a climber who hides heart rate publishes no heart-rate aggregate', async () => {
  const context = testEnv.authenticatedContext(userId);
  const statsRef = doc(context.firestore(), statsPath);

  await assertSucceeds(setDoc(statsRef, makeProfileStatsDocument({ heart_rate_public: false })));
  await assertSucceeds(setDoc(statsRef, makeProfileStatsDocument({
    heart_rate_public: true,
    average_heart_rate_bpm: 142,
    max_heart_rate_bpm: 178,
  })));
  await assertFails(setDoc(statsRef, makeProfileStatsDocument({
    heart_rate_public: false,
    average_heart_rate_bpm: 142,
  })));
  await assertFails(setDoc(statsRef, makeProfileStatsDocument({
    heart_rate_public: false,
    max_heart_rate_bpm: 178,
  })));
  await assertFails(setDoc(statsRef, makeProfileStatsDocument({ heart_rate_public: 'no' })));
});

// Another device that has not heard about the switch merges its numbers onto a hidden
// document; the merged result is what the rules judge, so that write is refused.
test('a merge that would put heart rate back onto a hidden document is rejected', async () => {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), statsPath), makeProfileStatsDocument({
      heart_rate_public: false,
    }));
  });

  const context = testEnv.authenticatedContext(userId);
  const statsRef = doc(context.firestore(), statsPath);

  await assertFails(setDoc(statsRef, {
    ...makeUpsertStatsPayload(),
    average_heart_rate_bpm: 142,
    max_heart_rate_bpm: 178,
  }, { merge: true }));
  // An earlier client, which never writes heart rate, keeps publishing unaffected.
  await assertSucceeds(setDoc(statsRef, makeUpsertStatsPayload(), { merge: true }));
});

test('switching heart rate off clears the aggregates in the same write', async () => {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), statsPath), makeProfileStatsDocument({
      average_heart_rate_bpm: 142,
      max_heart_rate_bpm: 178,
    }));
  });

  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(setDoc(doc(context.firestore(), statsPath), {
    ...makeUpsertStatsPayload(),
    heart_rate_public: false,
    average_heart_rate_bpm: deleteField(),
    max_heart_rate_bpm: deleteField(),
  }, { merge: true }));
  const stored = await readProfileStatsDocument();
  assert.equal(stored.heart_rate_public, false);
  assert.ok(!('average_heart_rate_bpm' in stored));
  assert.ok(!('max_heart_rate_bpm' in stored));
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
