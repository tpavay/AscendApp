import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc } from 'firebase/firestore';

// Strava tokens, pending authorizations, the upload queue and the access
// switch live only where the Admin SDK can reach them. A client that could read
// `_strava_connections` would hold a live Strava token; one that could write
// `_strava_access` could connect past the allowlist that keeps the Strava app
// inside its athlete capacity.
const projectId = 'demo-ascendapp-rules';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const climberId = 'strava-climber-123';
const serverOnlyPaths = [
  '_strava_access/settings',
  `_strava_connections/${climberId}`,
  '_strava_oauth_states/state-token-0123456789',
  `_strava_upload_jobs/${climberId}__workout-1`,
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
    const firestore = adminContext.firestore();
    await setDoc(doc(firestore, '_strava_access/settings'), {
      enabled: true,
      allowedUserIds: ['someone-else'],
    });
    await setDoc(doc(firestore, `_strava_connections/${climberId}`), {
      userId: climberId,
      accessToken: 'live-access-token',
      refreshToken: 'live-refresh-token',
    });
    await setDoc(doc(firestore, '_strava_oauth_states/state-token-0123456789'), {
      userId: climberId,
    });
    await setDoc(doc(firestore, `_strava_upload_jobs/${climberId}__workout-1`), {
      userId: climberId,
      status: 'queued',
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

test('a climber can read no Strava record, not even their own', async () => {
  const context = testEnv.authenticatedContext(climberId);

  for (const path of serverOnlyPaths) {
    await assertFails(getDoc(doc(context.firestore(), path)));
  }
});

test('a climber cannot allowlist themselves or forge a connection', async () => {
  const context = testEnv.authenticatedContext(climberId);
  const firestore = context.firestore();

  await assertFails(setDoc(doc(firestore, '_strava_access/settings'), {
    enabled: true,
    allowedUserIds: [climberId],
  }));
  await assertFails(setDoc(doc(firestore, `_strava_connections/${climberId}`), {
    userId: climberId,
    accessToken: 'forged',
  }));
  await assertFails(setDoc(doc(firestore, '_strava_oauth_states/forged-state-0123456789'), {
    userId: climberId,
  }));
  await assertFails(setDoc(doc(firestore, `_strava_upload_jobs/${climberId}__workout-2`), {
    userId: climberId,
    status: 'queued',
  }));
  for (const path of serverOnlyPaths) {
    await assertFails(deleteDoc(doc(firestore, path)));
  }
});

test('a signed-out caller is refused too', async () => {
  const context = testEnv.unauthenticatedContext();

  for (const path of serverOnlyPaths) {
    await assertFails(getDoc(doc(context.firestore(), path)));
  }
});
