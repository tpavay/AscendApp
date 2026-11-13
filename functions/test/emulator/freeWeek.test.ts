/**
 * The free week against real Firestore.
 *
 * The grant callable, the webhook's projection write, the recovery callable's
 * projection write and the expiry sweep all touch the one document the rules
 * check. This suite proves the invariant they share: RevenueCat active means
 * the paid grant, else a running week means the free week grant, else none.
 */

import assert from "node:assert/strict";
import test, {after, before, beforeEach} from "node:test";
import * as admin from "firebase-admin";
import {
  expireRevenueCatAccessGrants,
} from "../../src/revenueCat/expiration.js";
import {
  FirestoreRevenueCatEntitlementStore,
} from "../../src/revenueCat/firestoreStore.js";
import {
  FREE_WEEK_DURATION_MS,
  FREE_WEEK_GRANT_SOURCE,
  FREE_WEEK_PRODUCT_ID,
} from "../../src/revenueCat/freeWeek.js";
import {
  startFreeWeekForUser,
} from "../../src/revenueCat/freeWeekGrant.js";
import type {
  AppAccessProjection,
  RevenueCatWebhookEvent,
} from "../../src/revenueCat/types.js";

const NOW = new Date("2026-11-10T12:00:00.000Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const uid = "free-week-user-1";
const eventCollection = "_revenuecat_webhook_events";
const grantPath = `users/${uid}/entitlements/app_access`;
const recordPath = `users/${uid}/trial/free_week`;
const statusPath = `users/${uid}/entitlement_status/app_access`;
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

beforeEach(clearFreeWeekUser);

// The expiry sweep is a collection-group query, so a grant left behind here
// would be swept - and counted - by the next suite that runs it.
after(clearFreeWeekUser);

async function clearFreeWeekUser(): Promise<void> {
  await clearCollection(eventCollection);
  await clearCollection(`users/${uid}/entitlements`);
  await clearCollection(`users/${uid}/entitlement_status`);
  await clearCollection(`users/${uid}/trial`);
}

test("the first call writes the record and a seven-day grant together", async () => {
  const result = await start(NOW);

  assert.deepEqual(result, {
    status: "granted",
    grantedAtMs: NOW.getTime(),
    expiresAtMs: NOW.getTime() + FREE_WEEK_DURATION_MS,
  });
  assert.equal(FREE_WEEK_DURATION_MS, 7 * DAY_MS);

  const record = await db.doc(recordPath).get();
  assert.equal(record.get("grantedAt").toMillis(), NOW.getTime());
  assert.equal(record.get("expiresAt").toMillis(), result.expiresAtMs);

  const grant = await db.doc(grantPath).get();
  assert.equal(grant.get("productId"), FREE_WEEK_PRODUCT_ID);
  assert.equal(grant.get("source"), FREE_WEEK_GRANT_SOURCE);
  assert.equal(grant.get("isActive"), true);
  assert.equal(grant.get("uid"), uid);
  assert.equal(grant.get("entitlementId"), "app_access");
  assert.equal(grant.get("accessUntil").toMillis(), result.expiresAtMs);
});

test("a retried call returns the same week and writes nothing new", async () => {
  const first = await start(NOW);
  const before = await db.doc(grantPath).get();

  const retry = await start(new Date(NOW.getTime() + 2 * DAY_MS));

  assert.deepEqual(retry, first);
  const after = await db.doc(grantPath).get();
  assert.deepEqual(after.updateTime, before.updateTime);
  assert.equal(
    (await db.doc(recordPath).get()).get("expiresAt").toMillis(),
    first.expiresAtMs
  );
});

test("a retry puts the grant back when the first call's grant is gone", async () => {
  const first = await start(NOW);
  await db.doc(grantPath).delete();

  const retry = await start(new Date(NOW.getTime() + DAY_MS));

  assert.equal(retry.status, "granted");
  assert.equal(retry.expiresAtMs, first.expiresAtMs);
  const grant = await db.doc(grantPath).get();
  assert.equal(grant.get("source"), FREE_WEEK_GRANT_SOURCE);
  assert.equal(grant.get("accessUntil").toMillis(), first.expiresAtMs);
});

test("a second week is refused for a climber who ever had one", async () => {
  const first = await start(NOW);
  const afterTheWeek = new Date(NOW.getTime() + 8 * DAY_MS);
  assert.equal(await expireRevenueCatAccessGrants(db, afterTheWeek), 1);

  const second = await start(afterTheWeek);

  assert.equal(second.status, "already_used");
  assert.equal(second.expiresAtMs, first.expiresAtMs);
  assert.equal((await db.doc(grantPath).get()).exists, false);
});

test("a record that cannot be read is spent, not handed out again", async () => {
  await db.doc(recordPath).set({schemaVersion: 1});

  const result = await start(NOW);

  assert.equal(result.status, "already_used");
  assert.equal((await db.doc(grantPath).get()).exists, false);
});

test("a climber who holds paid access is refused and keeps their week", async () => {
  await store.writeProjection(paidProjection("paid", NOW.getTime()));

  const result = await start(NOW);

  assert.equal(result.status, "paid_active");
  assert.equal((await db.doc(recordPath).get()).exists, false);
  assert.equal(
    (await db.doc(grantPath).get()).get("productId"),
    "ascend_yearly"
  );
});

test("a switch that is off grants nothing and writes nothing", async () => {
  const result = await startFreeWeekForUser(uid, {
    firestore: db,
    isEnabled: async () => false,
    now: () => NOW,
  });

  assert.deepEqual(
    result,
    {status: "disabled", grantedAtMs: null, expiresAtMs: null}
  );
  assert.equal((await db.doc(recordPath).get()).exists, false);
  assert.equal((await db.doc(grantPath).get()).exists, false);
});

test("an inactive webhook projection leaves a running week alone", async () => {
  const week = await start(NOW);
  const event = webhookEvent("inactive-during-week");
  const inactive = inactiveProjection(event.id, NOW.getTime() + 1_000);

  await store.claimEvent(event, "digest", NOW);
  await store.completeEvent(event, "digest", [inactive], [], NOW);

  const grant = await db.doc(grantPath).get();
  assert.equal(grant.exists, true);
  assert.equal(grant.get("source"), FREE_WEEK_GRANT_SOURCE);
  assert.equal(grant.get("accessUntil").toMillis(), week.expiresAtMs);
  // The audit document still records what RevenueCat said.
  assert.equal((await db.doc(statusPath).get()).get("isActive"), false);
});

test("an inactive reconciliation leaves a running week alone, and then writes nothing", async () => {
  const week = await start(NOW);

  assert.equal(
    await store.writeProjection(inactiveProjection("poll-1", NOW.getTime() + 1_000)),
    true
  );
  const grant = await db.doc(grantPath).get();
  assert.equal(grant.get("source"), FREE_WEEK_GRANT_SOURCE);
  assert.equal(grant.get("accessUntil").toMillis(), week.expiresAtMs);

  // The recovery check is polled: an unchanged answer over a running week
  // must not rewrite the grant on every poll.
  assert.equal(
    await store.writeProjection(inactiveProjection("poll-2", NOW.getTime() + 60_000)),
    false
  );
  assert.deepEqual(
    (await db.doc(grantPath).get()).updateTime,
    grant.updateTime
  );
});

test("a purchase during the week replaces the free week grant with the paid one", async () => {
  await start(NOW);
  const event = webhookEvent("purchase-during-week");

  await store.claimEvent(event, "digest", NOW);
  await store.completeEvent(
    event,
    "digest",
    [paidProjection(event.id, NOW.getTime() + 1_000)],
    [],
    NOW
  );

  const grant = await db.doc(grantPath).get();
  assert.equal(grant.get("productId"), "ascend_yearly");
  assert.equal(grant.get("source"), undefined);
  assert.equal(grant.get("sourceEventId"), event.id);
  // The record stays: it is what refuses a second week later.
  assert.equal((await db.doc(recordPath).get()).exists, true);
});

test("a reconciled purchase replaces the free week grant too", async () => {
  await start(NOW);

  assert.equal(
    await store.writeProjection(paidProjection("reconciled", NOW.getTime() + 1_000)),
    true
  );

  assert.equal(
    (await db.doc(grantPath).get()).get("productId"),
    "ascend_yearly"
  );
});

test("a purchase refunded inside the week hands the rest of the week back", async () => {
  const week = await start(NOW);
  await store.writeProjection(paidProjection("bought", NOW.getTime() + 1_000));

  await store.writeProjection(inactiveProjection("refunded", NOW.getTime() + 2_000));

  const grant = await db.doc(grantPath).get();
  assert.equal(grant.get("source"), FREE_WEEK_GRANT_SOURCE);
  assert.equal(grant.get("accessUntil").toMillis(), week.expiresAtMs);
});

test("an inactive projection after the week removes the grant", async () => {
  await start(NOW);
  const afterTheWeek = new Date(NOW.getTime() + 8 * DAY_MS);
  const lapsed = inactiveProjection("after-week", afterTheWeek.getTime());
  lapsed.verifiedAt = afterTheWeek;

  assert.equal(await store.writeProjection(lapsed), true);

  assert.equal((await db.doc(grantPath).get()).exists, false);
});

test("the sweep leaves a running week and removes it once it is over", async () => {
  await start(NOW);

  assert.equal(
    await expireRevenueCatAccessGrants(db, afterDays(6)),
    0
  );
  assert.equal((await db.doc(grantPath).get()).exists, true);

  assert.equal(
    await expireRevenueCatAccessGrants(db, afterDays(7)),
    1
  );
  assert.equal((await db.doc(grantPath).get()).exists, false);
  // Spent, not forgotten.
  assert.equal((await db.doc(recordPath).get()).exists, true);
});

test("a paid grant that expires inside the week falls back to the week", async () => {
  const week = await start(NOW);
  const shortPaid = paidProjection("short-paid", NOW.getTime() + 1_000);
  shortPaid.expiresAt = new Date(NOW.getTime() + DAY_MS);
  shortPaid.accessUntil = new Date(NOW.getTime() + DAY_MS);
  await store.writeProjection(shortPaid);

  assert.equal(
    await expireRevenueCatAccessGrants(db, afterDays(2)),
    1
  );

  const grant = await db.doc(grantPath).get();
  assert.equal(grant.get("source"), FREE_WEEK_GRANT_SOURCE);
  assert.equal(grant.get("accessUntil").toMillis(), week.expiresAtMs);
});

function afterDays(days: number): Date {
  return new Date(NOW.getTime() + days * DAY_MS);
}

function start(now: Date) {
  return startFreeWeekForUser(uid, {
    firestore: db,
    isEnabled: async () => true,
    now: () => now,
  });
}

function webhookEvent(id: string): RevenueCatWebhookEvent {
  return {
    id,
    type: "INITIAL_PURCHASE",
    appId: "app123",
    eventTimestampMs: NOW.getTime(),
    appUserIds: [uid],
    identityOverflowCount: 0,
    productId: "ascend_yearly",
    newProductId: null,
    store: "app_store",
    periodType: "normal",
    expirationAtMs: Date.parse("2027-11-10T12:00:00.000Z"),
    gracePeriodExpirationAtMs: null,
    isTrialConversion: false,
    lifecycleReason: null,
  };
}

function paidProjection(
  sourceEventId: string,
  requestDateMs: number
): AppAccessProjection {
  const expiry = new Date("2027-11-10T12:00:00.000Z");
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
    sourceEventId,
    sourceEventType: "INITIAL_PURCHASE",
    verifiedAt: NOW,
  };
}

function inactiveProjection(
  sourceEventId: string,
  requestDateMs: number
): AppAccessProjection {
  return {
    ...paidProjection(sourceEventId, requestDateMs),
    isActive: false,
    productId: null,
    expiresAt: null,
    accessUntil: new Date(0),
    sourceEventType: "EXPIRATION",
  };
}

async function clearCollection(path: string): Promise<void> {
  const snapshot = await db.collection(path).get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
}
