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
  ANALYTICS_OUTBOX_COLLECTION,
  EVENT_RETENTION_MS,
  FirestoreRevenueCatEntitlementStore,
} from "../../src/revenueCat/firestoreStore.js";
import {
  expireRevenueCatAccessGrants,
} from "../../src/revenueCat/expiration.js";
import {
  FirestoreAnalyticsOutboxStore,
} from "../../src/revenueCat/analyticsFirestoreOutbox.js";
import {
  MixpanelDeliveryError,
} from "../../src/revenueCat/analyticsMixpanelClient.js";
import {
  processAnalyticsOutbox,
} from "../../src/revenueCat/analyticsOutboxProcessor.js";
import type {
  AppAccessProjection,
  RevenueCatWebhookEvent,
} from "../../src/revenueCat/types.js";
import type {
  LifecycleAnalyticsClient,
  LifecycleAnalyticsEvent,
  RevenueCatAnalyticsEnvironment,
} from "../../src/revenueCat/analyticsTypes.js";

const NOW = new Date("2026-08-05T12:00:00.000Z");
// RevenueCat's documented retry ladder finishes 155 minutes after the first
// delivery, so dedupe evidence must comfortably outlive that window.
const REVENUECAT_RETRY_WINDOW_MS = 155 * 60 * 1000;
const uid = "firebase-user-1";
const eventCollection = "_revenuecat_webhook_events";
const analyticsEnvironment: RevenueCatAnalyticsEnvironment = {
  firebaseProjectId: "ascend-prod-9c8f2",
  mixpanelProjectId: "4051100",
  appEnvironment: "production",
  buildConfig: "server",
  appVersion: "cloud_functions",
  buildNumber: "test-revision",
};
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
  await clearCollection(ANALYTICS_OUTBOX_COLLECTION);
  await clearCollection(`users/${uid}/entitlements`);
  await clearCollection(`users/${uid}/entitlement_status`);
  await clearCollection(`users/${uid}/entitlement_reconciliations`);
  await clearCollection("organizations/org-1/entitlements");
});

test("duplicate webhook delivery is durably idempotent", async () => {
  const event = webhookEvent("event-duplicate");

  assert.deepEqual(
    await store.claimEvent(event, "payload-digest", NOW),
    {outcome: "claimed", claimDigest: "payload-digest"}
  );
  await store.completeEvent(
    event,
    "payload-digest",
    [projection(event, NOW.getTime())],
    [analyticsEvent(event)],
    NOW
  );
  for (let replay = 0; replay < 5; replay += 1) {
    assert.deepEqual(
      await store.claimEvent(event, "payload-digest", NOW),
      {outcome: "duplicate", claimDigest: "payload-digest"}
    );
  }

  const eventSnapshot = await db.doc(`${eventCollection}/${event.id}`).get();
  const entitlementSnapshot = await db.doc(
    `users/${uid}/entitlements/app_access`
  ).get();
  assert.equal(eventSnapshot.get("status"), "completed");
  assert.equal(eventSnapshot.get("attemptCount"), 1);
  assert.equal(entitlementSnapshot.get("sourceEventId"), event.id);
  const outbox = await db.collection(ANALYTICS_OUTBOX_COLLECTION).get();
  assert.equal(outbox.size, 1);
  assert.equal(outbox.docs[0].get("status"), "queued");
  assert.equal(outbox.docs[0].get("eventName"), "subscription_renewed");
});

test("a transient Mixpanel failure requeues and later delivers", async () => {
  const event = webhookEvent("event-transient-analytics");
  await store.claimEvent(event, "payload-digest", NOW);
  await store.completeEvent(
    event,
    "payload-digest",
    [projection(event, NOW.getTime())],
    [analyticsEvent(event)],
    NOW
  );

  const analyticsStore = new FirestoreAnalyticsOutboxStore(db);
  const client = new FailOnceAnalyticsClient();
  const first = await processAnalyticsOutbox({
    store: analyticsStore,
    client,
    environment: analyticsEnvironment,
    now: () => NOW,
  });
  assert.equal(first.retriedCount, 1);

  const queued = await db.collection(ANALYTICS_OUTBOX_COLLECTION)
    .doc(analyticsEvent(event).insertId)
    .get();
  assert.equal(queued.get("status"), "queued");
  assert.equal(queued.get("attemptCount"), 1);

  const retryAt = new Date(NOW.getTime() + 60_000);
  const second = await processAnalyticsOutbox({
    store: analyticsStore,
    client,
    environment: analyticsEnvironment,
    now: () => retryAt,
  });
  assert.equal(second.deliveredCount, 1);
  const delivered = await queued.ref.get();
  assert.equal(delivered.get("status"), "delivered");
  assert.equal(delivered.get("attemptCount"), 2);
  assert.equal(client.attemptCount, 2);
});

test("the ledger carries a future retention stamp for the TTL policy", async () => {
  const event = webhookEvent("event-retention");

  await store.claimEvent(event, "retention-payload", NOW);
  const claimed = await db.doc(`${eventCollection}/${event.id}`).get();
  await store.completeEvent(
    event,
    "retention-payload",
    [projection(event, NOW.getTime())],
    [],
    NOW
  );
  const completed = await db.doc(`${eventCollection}/${event.id}`).get();

  for (const snapshot of [claimed, completed]) {
    const retainUntil = snapshot.get("retainUntil");
    assert.ok(retainUntil instanceof admin.firestore.Timestamp);
    assert.equal(retainUntil.toMillis(), NOW.getTime() + EVENT_RETENTION_MS);
    // `receivedAt` is already in the past, so it can never carry the policy.
    assert.ok(
      retainUntil.toMillis() - snapshot.get("receivedAt").toMillis() >
        REVENUECAT_RETRY_WINDOW_MS
    );
  }
});

test("a completed event refuses a redelivery whose bytes differ", async () => {
  const event = webhookEvent("event-conflicting-complete");

  await store.claimEvent(event, "first-seen-digest", NOW);
  await store.completeEvent(
    event,
    "first-seen-digest",
    [projection(event, NOW.getTime())],
    [],
    NOW
  );

  assert.deepEqual(
    await store.claimEvent(event, "different-bytes-digest", NOW),
    {outcome: "duplicate", claimDigest: "first-seen-digest"}
  );
  const snapshot = await db.doc(`${eventCollection}/${event.id}`).get();
  assert.equal(snapshot.get("payloadSha256"), "first-seen-digest");
  assert.equal(snapshot.get("eventType"), event.type);
  assert.equal(snapshot.get("conflictingPayloadCount"), 1);
});

test("a failed event is reclaimable when its retry bytes differ", async () => {
  const event = webhookEvent("event-conflicting-retry");

  await store.claimEvent(event, "first-seen-digest", NOW);
  await store.failEvent(
    event.id,
    "first-seen-digest",
    "subscriber_fetch_failed",
    NOW
  );

  const claim = await store.claimEvent(event, "different-bytes-digest", NOW);
  assert.deepEqual(claim, {
    outcome: "claimed",
    claimDigest: "first-seen-digest",
  });
  await store.completeEvent(
    event,
    claim.claimDigest,
    [projection(event, NOW.getTime())],
    [],
    NOW
  );

  const snapshot = await db.doc(`${eventCollection}/${event.id}`).get();
  assert.equal(snapshot.get("status"), "completed");
  assert.equal(snapshot.get("payloadSha256"), "first-seen-digest");
  assert.equal(snapshot.get("conflictingPayloadCount"), 1);
  assert.equal(
    (await db.doc(`users/${uid}/entitlements/app_access`).get()).exists,
    true
  );
});

test("reconciliation writes the same grant the webhook would have", async () => {
  const recovered = projection(webhookEvent("recovered"), NOW.getTime());

  assert.equal(await store.writeProjection(recovered), true);

  const grant = await db.doc(`users/${uid}/entitlements/app_access`).get();
  assert.equal(grant.get("isActive"), true);
  assert.equal(grant.get("uid"), uid);

  const stale = projection(webhookEvent("stale"), NOW.getTime() - 1_000);
  assert.equal(await store.writeProjection(stale), false);
  assert.equal(
    (await db.doc(`users/${uid}/entitlements/app_access`).get())
      .get("sourceEventId"),
    "recovered"
  );
});

test("an unchanged reconciliation writes nothing at all", async () => {
  const first = projection(webhookEvent("recovered"), NOW.getTime());
  assert.equal(await store.writeProjection(first), true);
  const before = await db.doc(`users/${uid}/entitlement_status/app_access`).get();

  // A recovery check always carries a fresh RevenueCat request stamp, so the
  // ordering rule alone would rewrite both documents on every single call.
  const unchanged = projection(webhookEvent("polled"), NOW.getTime() + 60_000);
  assert.equal(await store.writeProjection(unchanged), false);

  const after = await db.doc(`users/${uid}/entitlement_status/app_access`).get();
  assert.equal(after.get("sourceEventId"), "recovered");
  assert.equal(after.get("revenueCatRequestDateMs"), NOW.getTime());
  assert.deepEqual(after.updateTime, before.updateTime);
});

test("a changed reconciliation still writes both transitions", async () => {
  const active = projection(webhookEvent("active"), NOW.getTime());
  await store.writeProjection(active);

  const lapsed = projection(webhookEvent("lapsed"), NOW.getTime() + 1_000);
  lapsed.isActive = false;
  lapsed.productId = null;
  lapsed.expiresAt = null;
  lapsed.accessUntil = new Date(0);
  assert.equal(await store.writeProjection(lapsed), true);
  assert.equal(
    (await db.doc(`users/${uid}/entitlements/app_access`).get()).exists,
    false
  );

  const renewed = projection(webhookEvent("renewed"), NOW.getTime() + 2_000);
  assert.equal(await store.writeProjection(renewed), true);
  assert.equal(
    (await db.doc(`users/${uid}/entitlements/app_access`).get()).exists,
    true
  );
});

test("reconciliation restores a grant that went missing under a current status", async () => {
  const granted = projection(webhookEvent("granted"), NOW.getTime());
  await store.writeProjection(granted);
  await db.doc(`users/${uid}/entitlements/app_access`).delete();

  // This is the whole point of the recovery path: the status can look current
  // while the document the rules actually read is gone.
  const recovery = projection(webhookEvent("recovery"), NOW.getTime() + 1_000);
  assert.equal(await store.writeProjection(recovery), true);
  assert.equal(
    (await db.doc(`users/${uid}/entitlements/app_access`).get()).exists,
    true
  );
});

test("a failed attempt keeps a short backoff instead of the success cooldown", async () => {
  assert.equal(await store.claimReconciliation(uid, NOW, 60_000), true);

  await store.backOffReconciliation(uid, NOW, 15_000, 60_000);

  // Still bounded, so a RevenueCat outage cannot turn every foreground into
  // another subscriber fetch...
  assert.equal(
    await store.claimReconciliation(
      uid,
      new Date(NOW.getTime() + 14_000),
      60_000
    ),
    false
  );
  // ...but the subscriber who taps Restore recovers in seconds, not a minute.
  assert.equal(
    await store.claimReconciliation(
      uid,
      new Date(NOW.getTime() + 15_000),
      60_000
    ),
    true
  );
  assert.equal(
    (await db.doc(`users/${uid}/entitlement_reconciliations/current`).get())
      .get("requestCount"),
    2
  );
});

test("a backoff never shortens a reservation another attempt already made", async () => {
  const staleClaim = NOW;
  await store.claimReconciliation(uid, staleClaim, 60_000);
  const newerClaim = new Date(NOW.getTime() + 60_000);
  await store.claimReconciliation(uid, newerClaim, 60_000);

  await store.backOffReconciliation(uid, staleClaim, 15_000, 60_000);

  assert.equal(
    (await db.doc(`users/${uid}/entitlement_reconciliations/current`).get())
      .get("lastReconciledAt").toMillis(),
    newerClaim.getTime()
  );
});

test("reconciliation is rate limited per user by the server", async () => {
  assert.equal(await store.claimReconciliation(uid, NOW, 60_000), true);
  assert.equal(await store.claimReconciliation(uid, NOW, 60_000), false);
  const afterCooldown = new Date(NOW.getTime() + 60_000);
  assert.equal(
    await store.claimReconciliation(uid, afterCooldown, 60_000),
    true
  );

  const limit = await db.doc(
    `users/${uid}/entitlement_reconciliations/current`
  ).get();
  assert.equal(limit.get("requestCount"), 2);
});

test("out-of-order webhook completion keeps newer RevenueCat truth", async () => {
  const newer = webhookEvent("newer-event");
  const older = webhookEvent("older-event");

  await store.claimEvent(newer, "newer-payload", NOW);
  await store.completeEvent(
    newer,
    "newer-payload",
    [projection(newer, NOW.getTime() + 2_000)],
    [],
    NOW
  );
  await store.claimEvent(older, "older-payload", NOW);
  await store.completeEvent(
    older,
    "older-payload",
    [projection(older, NOW.getTime() - 2_000)],
    [],
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
    [],
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
    [],
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
    [],
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

test("an older unrelated document cannot starve a real expiry behind it", async () => {
  // The collection-group query is ordered by accessUntil, so this document sits
  // at the head of every page. A fixed window would spend its whole budget here
  // and never reach the grant behind it.
  const unrelated = db.doc("organizations/org-1/entitlements/app_access");
  await unrelated.set({
    accessUntil: admin.firestore.Timestamp.fromMillis(NOW.getTime() - 60_000),
  });

  const event = webhookEvent("starvation-event");
  const expired = projection(event, NOW.getTime());
  expired.expiresAt = new Date(NOW.getTime() - 1_000);
  expired.accessUntil = new Date(NOW.getTime() - 1_000);
  await store.claimEvent(event, "starvation-payload", NOW);
  await store.completeEvent(event, "starvation-payload", [expired], [], NOW);

  // A one-document page proves the sweep pages past what the filter rejects
  // rather than discarding the rest of a fixed window.
  assert.equal(
    await expireRevenueCatAccessGrants(db, NOW, {pageSize: 1}),
    1
  );
  assert.equal(
    (await db.doc(`users/${uid}/entitlements/app_access`).get()).exists,
    false
  );
  assert.equal((await unrelated.get()).exists, true);
});

function webhookEvent(id: string): RevenueCatWebhookEvent {
  return {
    id,
    type: "RENEWAL",
    appId: "app123",
    eventTimestampMs: NOW.getTime(),
    appUserIds: [uid],
    identityOverflowCount: 0,
    productId: "ascend_yearly",
    newProductId: null,
    store: "app_store",
    periodType: "normal",
    expirationAtMs: Date.parse("2027-08-05T12:00:00.000Z"),
    gracePeriodExpirationAtMs: null,
    isTrialConversion: false,
    lifecycleReason: null,
  };
}

function analyticsEvent(
  event: RevenueCatWebhookEvent
): LifecycleAnalyticsEvent {
  return {
    schemaVersion: 1,
    eventName: "subscription_renewed",
    eventVersion: 1,
    source: "revenuecat_webhook",
    distinctId: uid,
    insertId: "0123456789abcdef0123456789abcdef",
    eventTimestampMs: event.eventTimestampMs,
    entitlementId: "app_access",
    productId: "ascend_yearly",
    previousProductId: null,
    store: "app_store",
    periodType: "normal",
    lifecycleReason: null,
    entitlementActive: true,
    effectiveExpirationAtMs: Date.parse("2027-08-05T12:00:00.000Z"),
    firebaseProjectId: "ascend-prod-9c8f2",
    appEnvironment: "production",
    buildConfig: "server",
    appVersion: "cloud_functions",
    buildNumber: "test-revision",
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

class FailOnceAnalyticsClient implements LifecycleAnalyticsClient {
  attemptCount = 0;

  async send(): Promise<void> {
    this.attemptCount += 1;
    if (this.attemptCount === 1) {
      throw new MixpanelDeliveryError("service_unavailable", true);
    }
  }
}
