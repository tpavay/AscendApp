import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

/**
 * The climb-drop sender's own collections.
 *
 * The baseline says which climbs Ascend has already announced and a receipt
 * says which device has already been alerted for a drop. Both are the sender's
 * evidence about work it has done, so a client that could touch either could
 * announce a climb twice, silence a drop for a device, or read the whole
 * fleet's send ledger. Nothing outside a Cloud Function may reach them.
 */

const projectId = 'demo-ascendapp-rules-climb-drop';
const firestoreRules = readFileSync(
  new URL('../../firestore.rules', import.meta.url),
  'utf8'
);

const userId = 'climber-1';
const dispatchId = 'the-shard-2e2a56024403';
const tokenHash = 'hash-authorized-ios';

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
  // Seeded the way the sweep writes them, so every refusal below is the rules
  // denying access to a document that is really there.
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    const firestore = adminContext.firestore();
    await setDoc(doc(firestore, 'climb_drop_notification_state/current'), {
      announcedClimbIds: ['empire-state-building'],
      lastCatalogVersion: 10,
      schemaVersion: 1,
      sendingEnabled: true,
    });
    await setDoc(doc(firestore, `climb_drop_dispatches/${dispatchId}`), {
      climbIds: ['the-shard'],
      primaryClimbId: 'the-shard',
      schemaVersion: 1,
      sentCount: 2,
      state: 'sent',
      title: 'New climb: The Shard',
      type: 'climb_drop',
    });
    await setDoc(
      doc(
        firestore,
        `climb_drop_dispatches/${dispatchId}/receipts/${tokenHash}`
      ),
      {
        dispatchId,
        errorCode: null,
        schemaVersion: 1,
        sendAttempts: 0,
        state: 'delivered',
      }
    );
  });
});

after(async () => {
  await testEnv?.cleanup();
});

test('the announcement baseline is server-only', async () => {
  const context = testEnv.authenticatedContext(userId);
  const stateRef = doc(
    context.firestore(),
    'climb_drop_notification_state/current'
  );

  await assertFails(getDoc(stateRef));
  await assertFails(getDocs(
    collection(context.firestore(), 'climb_drop_notification_state')
  ));
  // Rewriting the baseline is how a client would re-announce a climb, and
  // flipping `sendingEnabled` is how it would silence every drop.
  await assertFails(setDoc(stateRef, {announcedClimbIds: []}));
  await assertFails(updateDoc(stateRef, {sendingEnabled: false}));
  await assertFails(deleteDoc(stateRef));
});

test('a dispatch cannot be read, forged, resurrected or cancelled', async () => {
  const context = testEnv.authenticatedContext(userId);
  const dispatchRef = doc(
    context.firestore(),
    `climb_drop_dispatches/${dispatchId}`
  );

  await assertFails(getDoc(dispatchRef));
  await assertFails(getDocs(
    collection(context.firestore(), 'climb_drop_dispatches')
  ));
  // A dispatch a client could author is a push a client could send.
  await assertFails(setDoc(
    doc(context.firestore(), 'climb_drop_dispatches/forged'),
    {
      body: 'Tap here.',
      climbIds: ['the-shard'],
      primaryClimbId: 'the-shard',
      state: 'pending',
      title: 'Free climbs',
      type: 'climb_drop',
    }
  ));
  // Dragging a completed drop back to `pending` is how it would be re-sent.
  await assertFails(updateDoc(dispatchRef, {state: 'pending'}));
  await assertFails(deleteDoc(dispatchRef));
});

test('the send ledger is server-only in both directions', async () => {
  const context = testEnv.authenticatedContext(userId);
  const receiptRef = doc(
    context.firestore(),
    `climb_drop_dispatches/${dispatchId}/receipts/${tokenHash}`
  );

  await assertFails(getDoc(receiptRef));
  await assertFails(getDocs(collection(
    context.firestore(),
    `climb_drop_dispatches/${dispatchId}/receipts`
  )));
  // Pre-claiming another device's receipt would suppress its alert; deleting
  // one would hand it a second copy of the same drop.
  await assertFails(setDoc(
    doc(
      context.firestore(),
      `climb_drop_dispatches/${dispatchId}/receipts/hash-someone-else`
    ),
    {dispatchId, sendAttempts: 0, state: 'claimed'}
  ));
  await assertFails(deleteDoc(receiptRef));
});

test('signing out changes nothing - the sender is closed to clients', async () => {
  const context = testEnv.unauthenticatedContext();

  await assertFails(getDoc(
    doc(context.firestore(), 'climb_drop_notification_state/current')
  ));
  await assertFails(getDoc(
    doc(context.firestore(), `climb_drop_dispatches/${dispatchId}`)
  ));
  await assertFails(getDoc(doc(
    context.firestore(),
    `climb_drop_dispatches/${dispatchId}/receipts/${tokenHash}`
  )));
});
