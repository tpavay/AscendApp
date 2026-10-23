import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

// The sixty-second liveness heartbeat of a running headphone session
// (docs/headphone-session-recovery.md). Owner-only in every direction, server
// clock on every write, and a client may never claim the server's `stalled`
// verdict. The flags the server derives from it are server-only.
const projectId = 'demo-ascendapp-rules-attempt-heartbeat';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const ownerId = 'climber-123';
const strangerId = 'stranger-456';
const sessionID = '5B1C9F1E-2D1B-4C6B-9D3E-7A0F2C1B8E90';

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

function heartbeat(overrides = {}) {
  return {
    schemaVersion: 1,
    sessionID,
    mode: 'live_climb',
    steps: 66,
    durationSeconds: 62,
    startedAt: Timestamp.fromMillis(1_792_754_454_000),
    lastSeenAt: serverTimestamp(),
    state: 'open',
    endedAt: null,
    outcome: null,
    climbId: 'empire-state-building',
    appVersion: '1.2.3',
    ...overrides,
  };
}

function heartbeatRef(context, userId = ownerId, id = sessionID) {
  return doc(context.firestore(), 'users', userId, 'attempt_heartbeats', id);
}

test('the owner writes, re-writes, reads and deletes their own heartbeat', async () => {
  const owner = testEnv.authenticatedContext(ownerId);

  await assertSucceeds(setDoc(heartbeatRef(owner), heartbeat()));
  await assertSucceeds(setDoc(heartbeatRef(owner), heartbeat({ steps: 1_593, durationSeconds: 1_328 }), { merge: true }));
  await assertSucceeds(getDoc(heartbeatRef(owner)));
  await assertSucceeds(deleteDoc(heartbeatRef(owner)));
});

test('every mode is a valid heartbeat, and a Just Climb carries no climb', async () => {
  const owner = testEnv.authenticatedContext(ownerId);

  await assertSucceeds(setDoc(heartbeatRef(owner, ownerId, 'just'), heartbeat({ sessionID: 'just', mode: 'just_climb', climbId: null })));
  await assertSucceeds(setDoc(heartbeatRef(owner, ownerId, 'routine'), heartbeat({ sessionID: 'routine', mode: 'routine', climbId: null })));
  await assertFails(setDoc(heartbeatRef(owner, ownerId, 'other'), heartbeat({ sessionID: 'other', mode: 'manual' })));
});

test('ending a session stamps the end with the server clock and names the outcome', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  await assertSucceeds(setDoc(heartbeatRef(owner), heartbeat()));

  await assertSucceeds(setDoc(heartbeatRef(owner), heartbeat({
    state: 'ended',
    endedAt: serverTimestamp(),
    outcome: 'saved',
  }), { merge: true }));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({
    state: 'ended',
    endedAt: Timestamp.fromMillis(1_792_755_681_000),
    outcome: 'saved',
  })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ state: 'ended', endedAt: serverTimestamp(), outcome: 'crashed' })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ state: 'open', endedAt: serverTimestamp() })));
});

test('a client may not claim the server verdict, forge the clock, or add fields', async () => {
  const owner = testEnv.authenticatedContext(ownerId);

  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ state: 'stalled' })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ lastSeenAt: Timestamp.fromMillis(1_792_755_681_000) })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ flaggedAt: serverTimestamp() })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ sessionID: 'another-session' })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ steps: -1 })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ steps: 66.5 })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ schemaVersion: 2 })));
  await assertFails(setDoc(heartbeatRef(owner), heartbeat({ durationSeconds: 500_000 })));
});

test('a stranger can neither read nor write another climber heartbeat', async () => {
  const owner = testEnv.authenticatedContext(ownerId);
  await assertSucceeds(setDoc(heartbeatRef(owner), heartbeat()));

  const stranger = testEnv.authenticatedContext(strangerId);
  await assertFails(getDoc(heartbeatRef(stranger)));
  await assertFails(setDoc(heartbeatRef(stranger), heartbeat({ steps: 0 })));
  await assertFails(updateDoc(heartbeatRef(stranger), { steps: 0 }));
  await assertFails(deleteDoc(heartbeatRef(stranger)));

  const signedOut = testEnv.unauthenticatedContext();
  await assertFails(getDoc(heartbeatRef(signedOut)));
  await assertFails(setDoc(heartbeatRef(signedOut), heartbeat()));
});

test('the stall flags are server-only, even to the climber they name', async () => {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), 'attempt_heartbeat_flags', `${ownerId}__${sessionID}`), {
      userId: ownerId,
      sessionID,
      mode: 'live_climb',
      steps: 66,
      durationSeconds: 62,
      lastSeenAt: Timestamp.now(),
      flaggedAt: Timestamp.now(),
    });
  });

  const owner = testEnv.authenticatedContext(ownerId);
  const flagRef = doc(owner.firestore(), 'attempt_heartbeat_flags', `${ownerId}__${sessionID}`);
  await assertFails(getDoc(flagRef));
  await assertFails(setDoc(flagRef, { resolvedAt: serverTimestamp() }, { merge: true }));
  await assertFails(deleteDoc(flagRef));
});
