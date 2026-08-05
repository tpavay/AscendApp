/**
 * RevenueCat's durable dedupe and projection adapter against real Firestore.
 *
 * Unit tests prove orchestration with an in-memory port. This suite proves the
 * shipped transaction stores one event, treats its redelivery as complete,
 * and prevents an older subscriber snapshot from replacing newer truth.
 */

import assert from "node:assert/strict";
import test, {before, beforeEach} from "node:test";
import * as admin from "firebase-admin";
import {
  FirestoreRevenueCatEntitlementStore,
} from "../../src/revenueCat/firestoreStore.js";
import {
  expireRevenueCatAccessGrants,
} from "../../src/revenueCat/expiration.js";
import type {
  AppAccessProjection,
  RevenueCatWebhookEvent,
} from "../../src/revenueCat/types.js";

const NOW = new Date("2026-08-05T12:00:00.000Z");
const uid = "firebase-user-1";
const eventCollection = "_revenuecat_webhook_events";
let db: admin.firestore.Firestore;
let store: FirestoreRevenueCatEntitlementStore;

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  }
  db = admin.firestore();
  store = new FirestoreRevenueCatEntitlementStore(db);
});

beforeEach(async () => {
  await clearCollection(eventCollection);
  await clearCollection(`users/${uid}/entitlements`);
  await clearCollection(`users/${uid}/entitlement_status`);
  await clearCollection("organizations/org-1/entitlements");
});

test("duplicate webhook delivery is durably idempotent", async () => {
  const event = webhookEvent("event-duplicate");

  assert.equal(
    await store.claimEvent(event, "payload-digest", NOW),
    "claimed"
  );
  await store.completeEvent(
    event,
    "payload-digest",
    [projection(event, NOW.getTime())],
    NOW
  );
  assert.equal(
    await store.claimEvent(event, "payload-digest", NOW),
    "duplicate"
  );

  const eventSnapshot = await db.doc(`${eventCollection}/${event.id}`).get();
  const entitlementSnapshot = await db.doc(
    `users/${uid}/entitlements/app_access`
  ).get();
  assert.equal(eventSnapshot.get("status"), "completed");
  assert.equal(eventSnapshot.get("attemptCount"), 1);
  assert.equal(entitlementSnapshot.get("sourceEventId"), event.id);
});

test("out-of-order webhook completion keeps newer RevenueCat truth", async () => {
  const newer = webhookEvent("newer-event");
  const older = webhookEvent("older-event");

  await store.claimEvent(newer, "newer-payload", NOW);
  await store.completeEvent(
    newer,
    "newer-payload",
    [projection(newer, NOW.getTime() + 2_000)],
    NOW
  );
  await store.claimEvent(older, "older-payload", NOW);
  await store.completeEvent(
    older,
    "older-payload",
    [projection(older, NOW.getTime() - 2_000)],
    NOW
  );

  const entitlementSnapshot = await db.doc(
    `users/${uid}/entitlements/app_access`
  ).get();
  assert.equal(entitlementSnapshot.get("sourceEventId"), newer.id);
  assert.equal(
    entitlementSnapshot.get("revenueCatRequestDateMs"),
    NOW.getTime() + 2_000
  );
  assert.equal(
    (await db.doc(`${eventCollection}/${older.id}`).get()).get("status"),
    "completed"
  );
});

test("a known RevenueCat expiry removes the active grant without the app", async () => {
  const event = webhookEvent("expiring-event");
  const expiredProjection = projection(event, NOW.getTime());
  expiredProjection.expiresAt = new Date(NOW.getTime() - 1_000);
  expiredProjection.accessUntil = new Date(NOW.getTime() - 1_000);
  await store.claimEvent(event, "expiring-payload", NOW);
  await store.completeEvent(
    event,
    "expiring-payload",
    [expiredProjection],
    NOW
  );

  assert.equal(await expireRevenueCatAccessGrants(db, NOW), 1);

  const grant = await db.doc(
    `users/${uid}/entitlements/app_access`
  ).get();
  const status = await db.doc(
    `users/${uid}/entitlement_status/app_access`
  ).get();
  assert.equal(grant.exists, false);
  assert.equal(status.get("isActive"), false);
});

test("inactive subscriber truth is recorded and removes the active grant", async () => {
  const activeEvent = webhookEvent("active-event");
  await store.claimEvent(activeEvent, "active-payload", NOW);
  await store.completeEvent(
    activeEvent,
    "active-payload",
    [projection(activeEvent, NOW.getTime())],
    NOW
  );

  const inactiveEvent = webhookEvent("inactive-event");
  const inactive = projection(inactiveEvent, NOW.getTime() + 1_000);
  inactive.isActive = false;
  inactive.productId = null;
  inactive.expiresAt = null;
  inactive.accessUntil = new Date(0);
  await store.claimEvent(inactiveEvent, "inactive-payload", NOW);
  await store.completeEvent(
    inactiveEvent,
    "inactive-payload",
    [inactive],
    NOW
  );

  const grant = await db.doc(
    `users/${uid}/entitlements/app_access`
  ).get();
  const status = await db.doc(
    `users/${uid}/entitlement_status/app_access`
  ).get();
  assert.equal(grant.exists, false);
  assert.equal(status.get("isActive"), false);
  assert.equal(status.get("sourceEventId"), inactiveEvent.id);
});

test("the expiry sweep ignores unrelated entitlement collection groups", async () => {
  const unrelated = db.doc("organizations/org-1/entitlements/app_access");
  await unrelated.set({
    accessUntil: admin.firestore.Timestamp.fromMillis(NOW.getTime() - 1_000),
  });

  assert.equal(await expireRevenueCatAccessGrants(db, NOW), 0);
  assert.equal((await unrelated.get()).exists, true);
});

function webhookEvent(id: string): RevenueCatWebhookEvent {
  return {
    id,
    type: "RENEWAL",
    appId: "app123",
    eventTimestampMs: NOW.getTime(),
    appUserIds: [uid],
  };
}

function projection(
  event: RevenueCatWebhookEvent,
  requestDateMs: number
): AppAccessProjection {
  const expiry = new Date("2027-08-05T12:00:00.000Z");
  return {
    schemaVersion: 1,
    uid,
    entitlementId: "app_access",
    isActive: true,
    productId: "ascend_yearly",
    expiresAt: expiry,
    accessUntil: expiry,
    revenueCatAppId: "app123",
    revenueCatRequestDateMs: requestDateMs,
    sourceEventId: event.id,
    sourceEventType: event.type,
    verifiedAt: NOW,
  };
}

async function clearCollection(path: string): Promise<void> {
  const snapshot = await db.collection(path).get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
}
