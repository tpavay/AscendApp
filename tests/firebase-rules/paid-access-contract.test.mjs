import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

// Cross-service Storage rules read the Firestore database of the emulator's
// configured project, so this contract intentionally uses the CLI project id.
const projectId = 'demo-ascendapp-rules';
const firestoreRules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
const storageRules = readFileSync(new URL('../../storage.rules', import.meta.url), 'utf8');

const paidUserId = 'paid-user-123';
const unpaidUserId = 'unpaid-user-456';
const leaderboardPath = 'leaderboard_stats/weekly_2026-W32_paid-user-123';
const climbImagePath = 'climb-images/gateway-arch/hero.jpg';
const shareCardTemplatePath = 'share-card-templates/podium/background.jpg';
const imageBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

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
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(
      doc(adminContext.firestore(), leaderboardPath),
      { userId: paidUserId, totalSteps: 12_000 }
    );
    await setDoc(
      doc(adminContext.firestore(), `users/${paidUserId}/entitlements/app_access`),
      {
        entitlementId: 'app_access',
        isActive: true,
        expiresAt: new Date('2099-01-01T00:00:00.000Z'),
        accessUntil: new Date('2099-01-01T00:00:00.000Z'),
      }
    );
    await uploadBytes(
      ref(adminContext.storage(), climbImagePath),
      imageBytes,
      { contentType: 'image/jpeg' }
    );
    await uploadBytes(
      ref(adminContext.storage(), shareCardTemplatePath),
      imageBytes,
      { contentType: 'image/jpeg' }
    );
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('an authenticated but unpaid caller cannot read the paid leaderboard', async () => {
  const context = testEnv.authenticatedContext(unpaidUserId);

  await assertFails(getDoc(doc(context.firestore(), leaderboardPath)));
});

test('a caller with active app_access can read the paid leaderboard', async () => {
  const context = testEnv.authenticatedContext(paidUserId);

  await assertSucceeds(getDoc(doc(context.firestore(), leaderboardPath)));
});

test('an authenticated but unpaid caller cannot download paid media', async () => {
  const context = testEnv.authenticatedContext(unpaidUserId);

  await assertFails(getBytes(ref(context.storage(), shareCardTemplatePath)));
});

test('a caller with active app_access can download paid media', async () => {
  const context = testEnv.authenticatedContext(paidUserId);

  await assertSucceeds(getBytes(ref(context.storage(), shareCardTemplatePath)));
});

// The `firstClimb` onboarding stage recommends a landmark and shows its artwork
// before the paywall, so a brand-new unpaid account has to be able to finish
// onboarding. Paid media above stays closed to the same caller.
test('a new unpaid account can still load the onboarding climb artwork', async () => {
  const context = testEnv.authenticatedContext(unpaidUserId);

  await assertSucceeds(getBytes(ref(context.storage(), climbImagePath)));
  await assertFails(getBytes(ref(context.storage(), shareCardTemplatePath)));
});

test('an unauthenticated caller cannot load the onboarding climb artwork', async () => {
  const context = testEnv.unauthenticatedContext();

  await assertFails(getBytes(ref(context.storage(), climbImagePath)));
});

test('a caller cannot forge or inspect the server-owned access projection', async () => {
  const context = testEnv.authenticatedContext(unpaidUserId);
  const grant = doc(
    context.firestore(),
    `users/${unpaidUserId}/entitlements/app_access`
  );

  await assertFails(setDoc(grant, {
    isActive: true,
    accessUntil: new Date('2099-01-01T00:00:00.000Z'),
  }));
  await assertFails(getDoc(grant));
  await assertFails(getDoc(doc(context.firestore(), leaderboardPath)));
});

test('webhook dedupe records and inactive status are server-only', async () => {
  const context = testEnv.authenticatedContext(paidUserId);

  await assertFails(getDoc(doc(
    context.firestore(),
    `users/${paidUserId}/entitlement_status/app_access`
  )));
  await assertFails(setDoc(
    doc(context.firestore(), '_revenuecat_webhook_events/forged-event'),
    { status: 'completed' }
  ));
  await assertFails(setDoc(
    doc(
      context.firestore(),
      `users/${paidUserId}/entitlement_reconciliations/current`
    ),
    { lastReconciledAt: new Date('1970-01-01T00:00:00.000Z') }
  ));
});
