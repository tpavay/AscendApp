import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';
import { seedActiveAppAccess } from './paid-access-fixture.mjs';

// Own project id: `clearFirestore()` wipes a whole project, so this suite's
// seeded documents must not be another suite's.
const projectId = 'demo-ascendapp-rules-champion-recognition';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const paidUserId = 'paid-user-123';
const unpaidUserId = 'unpaid-user-456';
const otherPaidUserId = 'other-paid-user-789';
const resultId = 'weekly_2026-W38';
const resultPath = `leaderboard_results/${resultId}`;
const placingPath = `${resultPath}/placings/${paidUserId}`;
const recapId = 'weekly_2026-W38';
const recapPath = `users/${paidUserId}/recaps/${recapId}`;
const unpaidRecapPath = `users/${unpaidUserId}/recaps/${recapId}`;
const deliveryPath = `_champion_push_deliveries/${resultId}_${paidUserId}`;

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
    const firestore = adminContext.firestore();
    await seedActiveAppAccess(adminContext, [paidUserId, otherPaidUserId]);
    await setDoc(doc(firestore, resultPath), makeResult());
    await setDoc(doc(firestore, placingPath), makePlacing(paidUserId, 1));
    await setDoc(
      doc(firestore, `${resultPath}/placings/${otherPaidUserId}`),
      makePlacing(otherPaidUserId, 2)
    );
    await setDoc(doc(firestore, recapPath), makeRecap());
    await setDoc(doc(firestore, unpaidRecapPath), makeRecap());
    await setDoc(doc(firestore, deliveryPath), { sentAt: new Date() });
  });
});

after(async () => {
  await testEnv.cleanup();
});

// Past boards and champions are shared paid content, on the same terms as the
// live boards they were frozen from.
test('a paid climber reads a result and its placings in board order', async () => {
  const firestore = testEnv.authenticatedContext(otherPaidUserId).firestore();

  await assertSucceeds(getDoc(doc(firestore, resultPath)));
  await assertSucceeds(getDoc(doc(firestore, placingPath)));
  await assertSucceeds(getDocs(query(
    collection(firestore, `${resultPath}/placings`),
    orderBy('rank'),
    limit(100)
  )));
  await assertSucceeds(getDocs(query(
    collection(firestore, `${resultPath}/placings`),
    where('rank', '==', 1)
  )));
});

test('a climber without paid access reads no result or placing', async () => {
  const firestore = testEnv.authenticatedContext(unpaidUserId).firestore();

  await assertFails(getDoc(doc(firestore, resultPath)));
  await assertFails(getDoc(doc(firestore, placingPath)));
  await assertFails(getDocs(collection(firestore, `${resultPath}/placings`)));
});

test('a signed-out reader sees no result or placing', async () => {
  const firestore = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(firestore, resultPath)));
  await assertFails(getDoc(doc(firestore, placingPath)));
});

// A crown is minted from these documents, so nobody - not even the champion
// the placing names - may author, alter or remove one.
test('no client writes a result or a placing, even its own', async () => {
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();

  await assertFails(setDoc(doc(firestore, 'leaderboard_results/weekly_2026-W39'), makeResult()));
  await assertFails(updateDoc(doc(firestore, resultPath), {
    championUserIds: [paidUserId, otherPaidUserId],
  }));
  await assertFails(deleteDoc(doc(firestore, resultPath)));
  await assertFails(setDoc(
    doc(firestore, `leaderboard_results/weekly_2026-W39/placings/${paidUserId}`),
    makePlacing(paidUserId, 1)
  ));
  await assertFails(updateDoc(doc(firestore, placingPath), { rank: 1 }));
  await assertFails(updateDoc(
    doc(firestore, `${resultPath}/placings/${otherPaidUserId}`),
    { rank: 3 }
  ));
  await assertFails(deleteDoc(doc(firestore, placingPath)));
});

test('the owner reads their own recaps, paid or not', async () => {
  const paid = testEnv.authenticatedContext(paidUserId).firestore();
  const unpaid = testEnv.authenticatedContext(unpaidUserId).firestore();

  await assertSucceeds(getDoc(doc(paid, recapPath)));
  await assertSucceeds(getDoc(doc(unpaid, unpaidRecapPath)));
  // The app's own read: unseen recaps, newest first, at most six.
  await assertSucceeds(getDocs(query(
    collection(paid, `users/${paidUserId}/recaps`),
    where('seenAt', '==', null),
    orderBy('periodEndAt', 'desc'),
    limit(6)
  )));
  await assertSucceeds(getDocs(collection(unpaid, `users/${unpaidUserId}/recaps`)));
});

test('another climber cannot read a recap, paid or not', async () => {
  const other = testEnv.authenticatedContext(otherPaidUserId).firestore();
  const signedOut = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(other, recapPath)));
  await assertFails(getDocs(collection(other, `users/${paidUserId}/recaps`)));
  await assertFails(getDoc(doc(signedOut, recapPath)));
});

test('the owner marks a recap seen once, at the server clock', async () => {
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();

  await assertSucceeds(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
  }));

  const stored = await readRecap(recapPath);
  assert.ok(stored.seenAt, 'seenAt must be stamped');
  assert.equal(stored.variant, 'active', 'no other field may move');
});

test('an unpaid owner can still mark their own recap seen', async () => {
  const firestore = testEnv.authenticatedContext(unpaidUserId).firestore();

  await assertSucceeds(updateDoc(doc(firestore, unpaidRecapPath), {
    seenAt: serverTimestamp(),
  }));
});

test('a recap composed without seenAt counts as unseen', async () => {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await updateDoc(doc(adminContext.firestore(), recapPath), {
      seenAt: deleteField(),
    });
  });
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();

  await assertSucceeds(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
  }));
});

test('seenAt is only ever the server clock', async () => {
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();

  await assertFails(updateDoc(doc(firestore, recapPath), {
    seenAt: new Date('2026-09-28T13:00:00.000Z'),
  }));
  await assertFails(updateDoc(doc(firestore, recapPath), { seenAt: true }));
});

test('a seen recap can be neither re-seen nor un-seen', async () => {
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();
  await assertSucceeds(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
  }));

  await assertFails(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(firestore, recapPath), { seenAt: null }));
  await assertFails(updateDoc(doc(firestore, recapPath), {
    seenAt: deleteField(),
  }));
});

test('marking a recap seen cannot change anything else in it', async () => {
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();

  await assertFails(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
    variant: 'never_climbed',
  }));
  await assertFails(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
    'active.rank': 1,
  }));
  await assertFails(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
    forged: true,
  }));
  await assertFails(updateDoc(doc(firestore, recapPath), { variant: 'inactive' }));
});

test('another climber cannot mark a recap seen', async () => {
  const firestore = testEnv.authenticatedContext(otherPaidUserId).firestore();

  await assertFails(updateDoc(doc(firestore, recapPath), {
    seenAt: serverTimestamp(),
  }));
});

test('no client creates, replaces or deletes a recap', async () => {
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();

  await assertFails(setDoc(
    doc(firestore, `users/${paidUserId}/recaps/monthly_2026-M09`),
    makeRecap()
  ));
  await assertFails(deleteDoc(doc(firestore, recapPath)));
});

test('champion push deliveries are server-only', async () => {
  const firestore = testEnv.authenticatedContext(paidUserId).firestore();

  await assertFails(getDoc(doc(firestore, deliveryPath)));
  await assertFails(getDocs(collection(firestore, '_champion_push_deliveries')));
  await assertFails(setDoc(
    doc(firestore, `_champion_push_deliveries/${resultId}_${otherPaidUserId}`),
    { sentAt: new Date() }
  ));
  await assertFails(deleteDoc(doc(firestore, deliveryPath)));
});

async function readRecap(path) {
  let data;
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    const snapshot = await getDoc(doc(adminContext.firestore(), path));
    data = snapshot.data();
  });
  return data;
}

function makeResult() {
  return {
    schemaVersion: 1,
    timeFrame: 'weekly',
    periodKey: '2026-W38',
    periodStartAt: new Date('2026-09-14T00:00:00.000Z'),
    periodEndAt: new Date('2026-09-21T00:00:00.000Z'),
    metric: 'steps',
    climberCount: 2,
    championUserIds: [paidUserId],
    podiumUserIds: [paidUserId, otherPaidUserId],
    mostClimbs: { count: 4, userIds: [paidUserId] },
    community: { climbers: 2, climbs: 7, steps: 21_000, floors: 1_050 },
    finalizedAt: new Date('2026-09-21T00:15:00.000Z'),
    source: 'leaderboard_finalizer',
    reconstructed: false,
  };
}

function makePlacing(userId, rank) {
  return {
    schemaVersion: 1,
    userId,
    timeFrame: 'weekly',
    periodKey: '2026-W38',
    periodStartAt: new Date('2026-09-14T00:00:00.000Z'),
    rank,
    totalSteps: 12_000 - rank * 1_000,
    totalWorkouts: 4,
    displayName: `Climber ${userId}`,
    photoURL: '',
    identityPolicyVersion: 1,
    identityState: 'published',
    identityChangedAt: new Date('2026-04-09T12:00:00.000Z'),
    isSynthetic: false,
  };
}

function makeRecap() {
  return {
    schemaVersion: 1,
    cadence: 'weekly',
    periodKey: '2026-W38',
    periodStartAt: new Date('2026-09-14T00:00:00.000Z'),
    periodEndAt: new Date('2026-09-21T00:00:00.000Z'),
    variant: 'active',
    active: { rank: 3, climberCount: 40 },
    inactive: null,
    composedAt: new Date('2026-09-21T00:30:00.000Z'),
    seenAt: null,
  };
}
