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
  writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-ascendapp-rules-moderation';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
const firestoreIndexes = JSON.parse(readFileSync(
  new URL('../../firestore.indexes.json', import.meta.url),
  'utf8'
));

const userId = 'user-123';
const otherUserId = 'user-456';
const thirdUserId = 'user-789';
const identityChangedAt = new Date('2026-07-29T11:00:00.000Z');

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
    for (const id of [otherUserId, thirdUserId]) {
      await setDoc(doc(adminContext.firestore(), `users/${id}`), {id});
    }
    await setDoc(
      doc(
        adminContext.firestore(),
        `users/${userId}/public_profile/current`
      ),
      makePublicProfileDocument({identityChangedAt})
    );
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('a user can create, read, list, and delete only their own blocks', async () => {
  const context = testEnv.authenticatedContext(userId);
  const blockRef = doc(context.firestore(), `users/${userId}/blocked/${otherUserId}`);

  await assertSucceeds(setDoc(blockRef, makeBlockDocument(otherUserId)));
  await assertSucceeds(getDoc(blockRef));
  await assertSucceeds(getDocs(collection(context.firestore(), `users/${userId}/blocked`)));
  await assertSucceeds(deleteDoc(blockRef));
});

test('a user cannot read or list another users blocks', async () => {
  await seedBlock(userId, otherUserId);

  const context = testEnv.authenticatedContext(thirdUserId);

  await assertFails(getDoc(
    doc(context.firestore(), `users/${userId}/blocked/${otherUserId}`)
  ));
  await assertFails(getDocs(
    collection(context.firestore(), `users/${userId}/blocked`)
  ));
});

test('a user cannot create or delete a block in another users list', async () => {
  const context = testEnv.authenticatedContext(thirdUserId);
  const otherUsersBlock = doc(
    context.firestore(),
    `users/${userId}/blocked/${otherUserId}`
  );

  await assertFails(setDoc(otherUsersBlock, makeBlockDocument(otherUserId)));

  await seedBlock(userId, otherUserId);
  await assertFails(deleteDoc(otherUsersBlock));
});

test('block documents reject self-blocking, mismatched ids, updates, and schema pollution', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(
    doc(context.firestore(), `users/${userId}/blocked/${userId}`),
    makeBlockDocument(userId)
  ));

  await assertFails(setDoc(
    doc(context.firestore(), `users/${userId}/blocked/${otherUserId}`),
    makeBlockDocument(thirdUserId)
  ));

  const blockRef = doc(context.firestore(), `users/${userId}/blocked/${otherUserId}`);
  await assertSucceeds(setDoc(blockRef, makeBlockDocument(otherUserId)));
  await assertFails(updateDoc(blockRef, { createdAt: serverTimestamp() }));

  await assertFails(setDoc(
    doc(context.firestore(), `users/${userId}/blocked/${thirdUserId}`),
    {
      ...makeBlockDocument(thirdUserId),
      displayName: 'Schema pollution',
    }
  ));
});

test('a signed-in user can create a complete moderation report', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(submitReport(context, 'report-1'));
});

test('moderation reports are unreadable and immutable to every client', async () => {
  const reporterContext = testEnv.authenticatedContext(userId);
  const reportRef = doc(reporterContext.firestore(), 'moderation_reports/report-1');
  await assertSucceeds(submitReport(reporterContext, 'report-1'));

  await assertFails(getDoc(reportRef));
  await assertFails(getDocs(collection(reporterContext.firestore(), 'moderation_reports')));
  await assertFails(updateDoc(reportRef, { reason: 'spam' }));
  await assertFails(deleteDoc(reportRef));

  const otherContext = testEnv.authenticatedContext(otherUserId);
  await assertFails(getDoc(
    doc(otherContext.firestore(), 'moderation_reports/report-1')
  ));
});

test('identity propagation checkpoints are server-only', async () => {
  const context = testEnv.authenticatedContext(userId);
  const jobRef = doc(
    context.firestore(),
    `_public_identity_propagation_jobs/${userId}/kinds/leaderboard`
  );

  await assertFails(getDoc(jobRef));
  await assertFails(setDoc(jobRef, {
    complete: false,
    cursor: null,
    kind: 'leaderboard',
    sequence: 1,
    sourceGeneration: 'spoofed',
    userId,
  }));
});

test('moderation reports reject spoofing, self-reports, invalid enums, and extra fields', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(submitReport(
    context,
    'spoofed-reporter',
    {reporterUserId: thirdUserId}
  ));

  await assertFails(submitReport(
    context,
    'self-report',
    {reportedUserId: userId}
  ));

  await assertFails(submitReport(
    context,
    'invalid-reason',
    {reason: 'disliked_result'}
  ));

  await assertFails(submitReport(
    context,
    'invalid-source',
    {source: 'hidden_inline_button'}
  ));

  await assertFails(submitReport(
    context,
    'extra-field',
    {captainOnlyStatus: 'resolved'}
  ));
});

test('reports require an existing target and an atomic rate-limit update', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertFails(setDoc(
    doc(context.firestore(), 'moderation_reports/no-rate-update'),
    makeReportDocument()
  ));

  await assertFails(submitReport(
    context,
    'missing-target',
    {reportedUserId: 'missing-user'}
  ));
});

test('a reporter cannot submit a second report during the server cooldown', async () => {
  const context = testEnv.authenticatedContext(userId);

  await assertSucceeds(submitReport(context, 'first-report'));
  await assertFails(submitReport(context, 'second-report'));
});

test('one batch cannot bind a single cooldown advance to two reports', async () => {
  const context = testEnv.authenticatedContext(userId);
  const db = context.firestore();
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'moderation_reports/report-a'),
    makeReportDocument()
  );
  batch.set(
    doc(db, 'moderation_reports/report-b'),
    makeReportDocument({reportedUserId: thirdUserId})
  );
  batch.set(
    doc(db, `userRateLimits/${userId}`),
    {
      lastModerationReport: serverTimestamp(),
      lastModerationReportId: 'report-a',
    },
    {merge: true}
  );

  await assertFails(batch.commit());
});

test('a reporter cannot spoof or delete moderation rate-limit timestamps', async () => {
  const context = testEnv.authenticatedContext(userId);
  const rateRef = doc(context.firestore(), `userRateLimits/${userId}`);

  await assertFails(submitReport(
    context,
    'spoofed-rate-time',
    {},
    {
      lastModerationReport: new Date('2000-01-01T00:00:00.000Z'),
      lastModerationReportId: 'spoofed-rate-time',
    }
  ));
  await assertSucceeds(setDoc(
    rateRef,
    {
      lastModerationReport: serverTimestamp(),
      lastModerationReportId: 'self-imposed-cooldown',
    }
  ));
  await assertFails(deleteDoc(rateRef));
  await assertFails(setDoc(rateRef, {
    lastModerationReport: serverTimestamp(),
    lastModerationReportId: 'polluted',
    arbitraryCounter: 0,
  }));
  await assertFails(setDoc(rateRef, {
    lastModerationReport: serverTimestamp(),
  }));
});

test('anonymous clients cannot create blocks or reports', async () => {
  const context = testEnv.unauthenticatedContext();

  await assertFails(setDoc(
    doc(context.firestore(), `users/${userId}/blocked/${otherUserId}`),
    makeBlockDocument(otherUserId)
  ));
  await assertFails(submitReport(context, 'anonymous-report'));
});

test('display-name screening is enforced on every client-writable publication', async () => {
  const context = testEnv.authenticatedContext(userId);
  const db = context.firestore();

  await assertFails(setDoc(
    doc(db, `users/${userId}`),
    makeUserDocument({displayName: 'f.u.c.k'})
  ));
  await assertFails(setDoc(
    doc(db, `users/${userId}/public_profile/current`),
    makePublicProfileDocument({displayName: 'f4gg0t'})
  ));
  await assertFails(setDoc(
    doc(db, `leaderboard_stats/weekly_2026-W31_${userId}`),
    makeLeaderboardDocument({displayName: 'friendlyniggername'})
  ));
  for (const displayName of [
    'fuсk',
    'fυck',
    'fucκ',
    'fսck',
    'ｆｕｃｋ',
    'ｎｉｇｇｅｒ',
    'fųck',
    'f𝕦ck',
    'fuuuck',
    'Maaaya',
    'asshole',
    ' Anonymous Climber ',
    '   ',
    '\t\n',
  ]) {
    await assertFails(setDoc(
      doc(db, `users/${userId}`),
      makeUserDocument({displayName})
    ));
    await assertFails(setDoc(
      doc(db, `users/${userId}/public_profile/current`),
      makePublicProfileDocument({displayName})
    ));
    await assertFails(setDoc(
      doc(db, `leaderboard_stats/weekly_2026-W31_${userId}`),
      makeLeaderboardDocument({displayName})
    ));
  }

  await assertSucceeds(setDoc(
    doc(db, `users/${userId}`),
    makeUserDocument({displayName: 'Nazim'})
  ));
  await assertSucceeds(setDoc(
    doc(db, `users/${userId}/public_profile/current`),
    makePublicProfileDocument({
      displayName: 'Scunthorpe',
      identityChangedAt: serverTimestamp(),
      photoURL: 'https://example.com/account-photo.jpg',
    })
  ));
  const publishedIdentity = (
    await getDoc(doc(db, `users/${userId}/public_profile/current`))
  ).data();
  await assertSucceeds(setDoc(
    doc(db, `leaderboard_stats/weekly_2026-W31_${userId}`),
    makeLeaderboardDocument({
      displayName: publishedIdentity.displayName,
      identityChangedAt: publishedIdentity.identityChangedAt,
      photoURL: publishedIdentity.photoURL,
    })
  ));
  await assertSucceeds(setDoc(
    doc(db, `users/${userId}`),
    makeUserDocument({displayName: 'Марія'})
  ));
  await assertSucceeds(setDoc(
    doc(db, `users/${userId}/public_profile/current`),
    makePublicProfileDocument({
      displayName: 'José',
      identityChangedAt: serverTimestamp(),
    })
  ));
  await assertSucceeds(setDoc(
    doc(db, `users/${userId}`),
    makeUserDocument({displayName: ''})
  ));
});

test('account and public identity can commit atomically', async () => {
  const context = testEnv.authenticatedContext(userId);
  const db = context.firestore();
  const batch = writeBatch(db);

  batch.set(
    doc(db, `users/${userId}`),
    makeUserDocument({displayName: 'Atomic Climber'})
  );
  batch.set(
    doc(db, `users/${userId}/public_profile/current`),
    makePublicProfileDocument({
      displayName: 'Atomic Climber',
      identityChangedAt: serverTimestamp(),
    })
  );

  await assertSucceeds(batch.commit());
  assert.equal(
    (await getDoc(doc(db, `users/${userId}`))).data().displayName,
    'Atomic Climber'
  );
  assert.equal(
    (
      await getDoc(doc(db, `users/${userId}/public_profile/current`))
    ).data().displayName,
    'Atomic Climber'
  );
});

test('public identity requires bounded nonempty names and bounded photo urls', async () => {
  const context = testEnv.authenticatedContext(userId);
  const db = context.firestore();

  await assertFails(setDoc(
    doc(db, `users/${userId}/public_profile/current`),
    makePublicProfileDocument({displayName: ''})
  ));
  await assertFails(setDoc(
    doc(db, `leaderboard_stats/weekly_2026-W31_${userId}`),
    makeLeaderboardDocument({displayName: ''})
  ));
  await assertFails(setDoc(
    doc(db, `users/${userId}/public_profile/current`),
    makePublicProfileDocument({displayName: 'a'.repeat(81)})
  ));
  await assertFails(setDoc(
    doc(db, `leaderboard_stats/weekly_2026-W31_${userId}`),
    makeLeaderboardDocument({photoURL: `https://example.com/${'a'.repeat(2030)}`})
  ));
});

test('identity policy blocks stale clients and permits modern refreshes', async () => {
  const context = testEnv.authenticatedContext(userId);
  const db = context.firestore();
  const profileRef = doc(db, `users/${userId}/public_profile/current`);
  const leaderboardRef = doc(
    db,
    `leaderboard_stats/weekly_2026-W31_${userId}`
  );
  const staleProfile = makePublicProfileDocument();
  delete staleProfile.identityPolicyVersion;
  delete staleProfile.identityChangedAt;

  await assertFails(setDoc(profileRef, staleProfile));
  await assertFails(setDoc(leaderboardRef, makeLeaderboardDocument({
    identityPolicyVersion: 0,
  })));

  await assertSucceeds(setDoc(profileRef, makePublicProfileDocument()));
  const publishedIdentity = (await getDoc(profileRef)).data();
  await assertSucceeds(setDoc(leaderboardRef, makeLeaderboardDocument({
    displayName: publishedIdentity.displayName,
    identityChangedAt: publishedIdentity.identityChangedAt,
    photoURL: publishedIdentity.photoURL,
  })));

  await assertFails(updateDoc(profileRef, {
    displayName: 'Old Client Name',
    lastUpdated: serverTimestamp(),
  }));
  await assertFails(updateDoc(leaderboardRef, {
    photoURL: 'https://example.com/old-client.jpg',
    lastUpdated: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(profileRef, {
    identityChangedAt: serverTimestamp(),
    lastUpdated: serverTimestamp(),
  }));
  await assertFails(updateDoc(leaderboardRef, {
    identityPolicyVersion: 1,
    identityChangedAt: serverTimestamp(),
    lastUpdated: serverTimestamp(),
  }));

  await assertSucceeds(updateDoc(profileRef, {
    displayName: 'Protected Name',
    identityPolicyVersion: 1,
    identityChangedAt: serverTimestamp(),
    lastUpdated: serverTimestamp(),
  }));
  await assertFails(updateDoc(leaderboardRef, {
    photoURL: 'https://example.com/protected.jpg',
    identityPolicyVersion: 1,
    identityChangedAt: serverTimestamp(),
    lastUpdated: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(leaderboardRef, {
    totalSteps: 2400,
    lastUpdated: serverTimestamp(),
  }));
});

test('leaderboard creates cannot spoof identity or create a masked lifecycle', async () => {
  const context = testEnv.authenticatedContext(userId);
  const leaderboardRef = doc(
    context.firestore(),
    `leaderboard_stats/weekly_2026-W31_${userId}`
  );

  await assertFails(setDoc(leaderboardRef, makeLeaderboardDocument({
    displayName: 'Spoofed Name',
  })));
  await assertFails(setDoc(leaderboardRef, makeLeaderboardDocument({
    displayName: 'Anonymous Climber',
    identityChangedAt: null,
    identityState: 'pending_public_profile',
    photoURL: '',
  })));
  await assertFails(setDoc(leaderboardRef, makeLeaderboardDocument({
    displayName: 'Anonymous Climber',
    identityChangedAt: null,
    identityState: 'deleted',
    photoURL: '',
  })));
});

test('metrics refresh preserves server-masked pending and deleted identity', async () => {
  const context = testEnv.authenticatedContext(userId);
  const leaderboardRef = doc(
    context.firestore(),
    `leaderboard_stats/weekly_2026-W31_${userId}`
  );
  const maskedDocument = makeLeaderboardDocument({
    displayName: 'Anonymous Climber',
    identityChangedAt: null,
    identityState: 'pending_public_profile',
    photoURL: '',
  });

  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(
      doc(
        adminContext.firestore(),
        `leaderboard_stats/weekly_2026-W31_${userId}`
      ),
      maskedDocument
    );
  });

  await assertSucceeds(updateDoc(leaderboardRef, {
    totalSteps: 2400,
    lastUpdated: serverTimestamp(),
  }));
  let refreshed = (await getDoc(leaderboardRef)).data();
  assert.equal(refreshed.displayName, 'Anonymous Climber');
  assert.equal(refreshed.identityState, 'pending_public_profile');
  assert.equal(refreshed.photoURL, '');

  await assertFails(updateDoc(leaderboardRef, {
    displayName: 'Restored by client',
    identityChangedAt: serverTimestamp(),
    identityState: 'published',
    photoURL: 'https://example.com/restored.jpg',
  }));

  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await updateDoc(
      doc(
        adminContext.firestore(),
        `leaderboard_stats/weekly_2026-W31_${userId}`
      ),
      {identityState: 'deleted'}
    );
  });
  await assertSucceeds(updateDoc(leaderboardRef, {
    totalSteps: 3600,
    lastUpdated: serverTimestamp(),
  }));
  await assertFails(updateDoc(leaderboardRef, {
    displayName: 'Reopened by client',
    identityChangedAt: serverTimestamp(),
    identityState: 'published',
  }));

  refreshed = (await getDoc(leaderboardRef)).data();
  assert.equal(refreshed.displayName, 'Anonymous Climber');
  assert.equal(refreshed.identityState, 'deleted');
  assert.equal(refreshed.photoURL, '');
});

test('incoming block cleanup has a collection-group single-field index', () => {
  const override = firestoreIndexes.fieldOverrides.find(
    (candidate) =>
      candidate.collectionGroup === 'blocked' &&
      candidate.fieldPath === 'blockedUid'
  );

  assert.ok(override);
  assert.deepEqual(override.indexes, [{
    order: 'ASCENDING',
    queryScope: 'COLLECTION_GROUP',
  }]);
});

test('identity propagation has collection-group user indexes', () => {
  for (const collectionGroup of ['entries', 'finishers']) {
    const override = firestoreIndexes.fieldOverrides.find(
      (candidate) =>
        candidate.collectionGroup === collectionGroup &&
        candidate.fieldPath === 'userId'
    );

    assert.ok(override);
    assert.deepEqual(override.indexes, [{
      order: 'ASCENDING',
      queryScope: 'COLLECTION_GROUP',
    }]);
  }
});

async function seedBlock(blockerUserId, blockedUserId) {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(
      doc(
        adminContext.firestore(),
        `users/${blockerUserId}/blocked/${blockedUserId}`
      ),
      {
        blockedUid: blockedUserId,
        createdAt: new Date('2026-07-29T12:00:00.000Z'),
      }
    );
  });
}

function makeBlockDocument(blockedUserId) {
  return {
    blockedUid: blockedUserId,
    createdAt: serverTimestamp(),
  };
}

function makeReportDocument(overrides = {}) {
  return {
    reportedUserId: otherUserId,
    reporterUserId: userId,
    reason: 'harassment',
    source: 'global_leaderboard',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function submitReport(
  context,
  reportId,
  reportOverrides = {},
  rateOverrides = {
    lastModerationReport: serverTimestamp(),
    lastModerationReportId: reportId,
  }
) {
  const batch = writeBatch(context.firestore());
  batch.set(
    doc(context.firestore(), `moderation_reports/${reportId}`),
    makeReportDocument(reportOverrides)
  );
  batch.set(
    doc(context.firestore(), `userRateLimits/${userId}`),
    rateOverrides,
    {merge: true}
  );
  return batch.commit();
}

function makeUserDocument(overrides = {}) {
  return {
    email: 'climber@example.com',
    firstName: '',
    lastName: '',
    displayName: 'Climber',
    createdAt: new Date('2026-07-29T12:00:00.000Z'),
    lastUpdated: new Date('2026-07-29T12:00:00.000Z'),
    ...overrides,
  };
}

function makePublicProfileDocument(overrides = {}) {
  return {
    userId,
    displayName: 'Climber',
    photoURL: '',
    identityPolicyVersion: 1,
    identityChangedAt,
    lastUpdated: new Date('2026-07-29T12:00:00.000Z'),
    ...overrides,
  };
}

function makeLeaderboardDocument(overrides = {}) {
  return {
    userId,
    displayName: 'Climber',
    photoURL: '',
    identityPolicyVersion: 1,
    identityChangedAt,
    identityState: 'published',
    timeFrame: 'weekly',
    schemaVersion: 2,
    periodKey: '2026-W31',
    periodStartAt: new Date('2026-07-27T00:00:00.000Z'),
    totalSteps: 1200,
    totalFloors: 75,
    totalWorkouts: 1,
    totalDuration: 1800,
    stepsPerMinute: 40,
    lastUpdated: new Date('2026-07-29T12:00:00.000Z'),
    ...overrides,
  };
}
