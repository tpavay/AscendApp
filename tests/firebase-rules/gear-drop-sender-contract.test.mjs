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
 * The gear drop push's own collection (`functions/src/gearDropPush.ts`).
 *
 * A dispatch's existence is the announcement of a gear event and a receipt is
 * the record that a device was already alerted. A client that could touch
 * either could re-announce an event, silence it for a device, or read the
 * fleet's send ledger. Nothing outside a Cloud Function may reach them, which
 * the rules keep by never matching the collection.
 */

const projectId = 'demo-ascendapp-rules-gear-drop';
const firestoreRules = readFileSync(
  new URL('../../firestore.rules', import.meta.url),
  'utf8'
);

const userId = 'climber-1';
const dispatchId = 'thanksgiving-2026';
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
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    const firestore = adminContext.firestore();
    await setDoc(doc(firestore, `gear_drop_dispatches/${dispatchId}`), {
      eventId: dispatchId,
      schemaVersion: 1,
      sentCount: 2,
      state: 'sent',
      title: 'November gear just dropped',
    });
    await setDoc(
      doc(firestore, `gear_drop_dispatches/${dispatchId}/receipts/${tokenHash}`),
      { state: 'delivered' }
    );
  });
});

after(async () => {
  await testEnv?.cleanup();
});

test('a gear dispatch cannot be read, forged, resurrected or cancelled', async () => {
  const context = testEnv.authenticatedContext(userId);
  const dispatchRef = doc(
    context.firestore(),
    `gear_drop_dispatches/${dispatchId}`
  );

  await assertFails(getDoc(dispatchRef));
  await assertFails(getDocs(
    collection(context.firestore(), 'gear_drop_dispatches')
  ));
  // A dispatch a client could author is a push a client could send.
  await assertFails(setDoc(
    doc(context.firestore(), 'gear_drop_dispatches/forged'),
    { body: 'Tap here.', state: 'sending', title: 'Free gear' }
  ));
  // Dragging a finished event back to sending is how it would be re-sent.
  await assertFails(updateDoc(dispatchRef, { state: 'sending' }));
  await assertFails(deleteDoc(dispatchRef));
});

test('the gear send ledger is server-only in both directions', async () => {
  const context = testEnv.authenticatedContext(userId);
  const receiptRef = doc(
    context.firestore(),
    `gear_drop_dispatches/${dispatchId}/receipts/${tokenHash}`
  );

  await assertFails(getDoc(receiptRef));
  await assertFails(getDocs(collection(
    context.firestore(),
    `gear_drop_dispatches/${dispatchId}/receipts`
  )));
  await assertFails(setDoc(
    doc(
      context.firestore(),
      `gear_drop_dispatches/${dispatchId}/receipts/hash-someone-else`
    ),
    { state: 'claimed' }
  ));
  await assertFails(deleteDoc(receiptRef));
});

test('signing out changes nothing - the sender is closed to clients', async () => {
  const context = testEnv.unauthenticatedContext();

  await assertFails(getDoc(
    doc(context.firestore(), `gear_drop_dispatches/${dispatchId}`)
  ));
  await assertFails(getDoc(doc(
    context.firestore(),
    `gear_drop_dispatches/${dispatchId}/receipts/${tokenHash}`
  )));
});
