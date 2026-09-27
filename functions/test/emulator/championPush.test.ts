/**
 * The champion push and the push-preference callable against a real
 * Firestore.
 *
 * The unit suite (test/championPush.test.ts) proves the copy, the
 * eligibility guard, the preference read, and the device filter in
 * isolation. This suite proves what only exists once documents are
 * involved: that the delivery marker makes a retried event push at most
 * once, that an opted-out champion or one with no deliverable device gets no
 * marker at all, that a champion whose placing is not written yet is left
 * for the retry, that a dead token is unregistered, and that the preference
 * callable keeps an old caller's request exactly as it was while merging the
 * new champion preference. Only FCM is stubbed.
 *
 * Lives under test/emulator/ - see emailQueue.test.ts for why, and for the
 * shared-database-between-tests caveat this suite follows the same way.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import type {CallableRequest} from "firebase-functions/v2/https";
import {
  deliverChampionPush,
  type ChampionPushSendOutcome,
  type ChampionPushSendRequest,
  type ChampionPushSender,
  type ChampionPushSummary,
} from "../../src/championPush.js";
import {
  updatePushNotificationPreferences,
} from "../../src/pushNotifications.js";

const PROJECT_ID = "demo-ascend-leaderboard-derivation";
const RESULT_ID = "weekly_2026-W39";
const periodEndAt = new Date("2026-09-28T00:00:00Z");
const now = new Date("2026-09-28T00:16:00Z");

let db: admin.firestore.Firestore;

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  admin.initializeApp({projectId: PROJECT_ID});
  db = admin.firestore();
});

beforeEach(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}` +
      "/databases/(default)/documents",
    {method: "DELETE"}
  );
  assert.ok(response.ok, `emulator reset failed: ${response.status}`);
});

/**
 * A sender that records every request and answers from a script.
 * @param {Function} [answer] - Per-token outcome, or throws for the batch
 * @return {{sender: ChampionPushSender, requests: ChampionPushSendRequest[]}}
 *   The stub and what it was asked to send
 */
function recordingSender(
  answer: (tokenHash: string) => Omit<ChampionPushSendOutcome, "tokenHash"> =
  () => ({invalidToken: false, ok: true})
): {sender: ChampionPushSender; requests: ChampionPushSendRequest[]} {
  const requests: ChampionPushSendRequest[] = [];
  return {
    requests,
    sender: {
      async send(request) {
        requests.push(request);
        return request.tokens.map((device) => ({
          ...answer(device.tokenHash),
          tokenHash: device.tokenHash,
        }));
      },
    },
  };
}

/**
 * Runs one delivery of the seeded weekly result and returns its summary.
 * @param {ChampionPushSender} sender - The stubbed FCM
 * @param {string[]} championUserIds - The result's champions
 * @return {Promise<ChampionPushSummary>} What the delivery did
 */
async function deliver(
  sender: ChampionPushSender,
  championUserIds: string[] = ["champ-1"]
): Promise<ChampionPushSummary> {
  const delivery = await deliverChampionPush({
    data: {
      championUserIds,
      periodEndAt: admin.firestore.Timestamp.fromDate(periodEndAt),
      periodKey: "2026-W39",
      source: "leaderboard_finalizer",
      timeFrame: "weekly",
    },
    firestore: db,
    now,
    resultId: RESULT_ID,
    sender,
  });
  assert.equal(delivery.eligible, true);
  return (delivery as {summary: ChampionPushSummary}).summary;
}

test("a crowned champion gets one push, and a retried event never a second", async () => {
  await seedPlacing("champ-1", 12345);
  await seedDevice("champ-1", "hash-1", "token-1");
  const {requests, sender} = recordingSender();

  const first = await deliver(sender);
  const second = await deliver(sender);

  assert.equal(first.delivered, 1);
  assert.equal(first.sentCount, 1);
  assert.equal(second.alreadyClaimed, 1);
  assert.equal(requests.length, 1);
  assert.deepEqual(requests[0], {
    body: "Week 39 champion. 12,345 steps. Defend it this week.",
    data: {
      periodKey: "2026-W39",
      timeFrame: "weekly",
      type: "champion_crowned",
    },
    title: "You took the crown.",
    tokens: [{fcmToken: "token-1", tokenHash: "hash-1"}],
  });

  const marker = await readMarker("champ-1");
  assert.equal(marker?.resultId, RESULT_ID);
  assert.equal(marker?.userId, "champ-1");
  assert.equal(marker?.sentCount, 1);
  assert.equal(marker?.status, "sent");
  assert.ok(marker?.createdAt instanceof admin.firestore.Timestamp);
});

test("co-champions each get their own push with their own steps", async () => {
  await seedPlacing("champ-1", 5000);
  await seedPlacing("champ-2", 5000);
  await seedDevice("champ-1", "hash-1", "token-1");
  await seedDevice("champ-2", "hash-2", "token-2");
  const {requests, sender} = recordingSender();

  const summary = await deliver(sender, ["champ-1", "champ-2"]);

  assert.equal(summary.delivered, 2);
  assert.deepEqual(
    requests.map((request) => request.tokens[0].tokenHash).sort(),
    ["hash-1", "hash-2"]
  );
  assert.ok(await readMarker("champ-1"));
  assert.ok(await readMarker("champ-2"));
});

test("an opted-out champion gets no push and no marker", async () => {
  await seedPlacing("champ-1", 5000);
  await seedDevice("champ-1", "hash-1", "token-1");
  await db.doc("users/champ-1/communication_preferences/current").set({
    pushChampionCrownEnabled: false,
    pushClimbDropsEnabled: true,
  });
  const {requests, sender} = recordingSender();

  const summary = await deliver(sender);

  assert.equal(summary.optedOut, 1);
  assert.equal(requests.length, 0);
  assert.equal(await readMarker("champ-1"), undefined);
});

test("the climb-drop toggle does not silence the crown", async () => {
  await seedPlacing("champ-1", 5000);
  await seedDevice("champ-1", "hash-1", "token-1", {
    climbDropPushEnabled: false,
  });
  await db.doc("users/champ-1/communication_preferences/current").set({
    pushClimbDropsEnabled: false,
  });
  const {requests, sender} = recordingSender();

  const summary = await deliver(sender);

  assert.equal(summary.delivered, 1);
  assert.equal(requests.length, 1);
});

test("a champion with no deliverable device gets no push and no marker", async () => {
  await seedPlacing("champ-1", 5000);
  await seedDevice("champ-1", "hash-1", "token-1", {
    authorizationStatus: "denied",
  });
  await seedDevice("champ-1", "hash-2", "token-2", {active: false});
  const {requests, sender} = recordingSender();

  const summary = await deliver(sender);

  assert.equal(summary.noDevices, 1);
  assert.equal(requests.length, 0);
  assert.equal(await readMarker("champ-1"), undefined);
});

test("a champion whose placing is not written yet is left for the retry", async () => {
  await seedDevice("champ-1", "hash-1", "token-1");
  await seedRecap("champ-1");
  const {requests, sender} = recordingSender();

  const early = await deliver(sender);
  assert.equal(early.awaitingPlacing, 1);
  assert.equal(requests.length, 0);
  assert.equal(await readMarker("champ-1"), undefined);

  await seedPlacing("champ-1", 777);
  const retried = await deliver(sender);
  assert.equal(retried.delivered, 1);
  assert.equal(requests.length, 1);
  assert.equal(
    requests[0].body,
    "Week 39 champion. 777 steps. Defend it this week."
  );
});

test("the crown alert waits for the recap it opens, then goes without it", async () => {
  await db.doc(`leaderboard_results/${RESULT_ID}/placings/champ-1`).set({
    rank: 1,
    schemaVersion: 1,
    totalSteps: 5000,
    totalWorkouts: 3,
    userId: "champ-1",
  });
  await seedDevice("champ-1", "hash-1", "token-1");
  const {requests, sender} = recordingSender();

  // 00:16 UTC: the finalizer has written the result, compose has not run.
  const early = await deliver(sender);
  assert.equal(early.awaitingRecap, 1);
  assert.equal(requests.length, 0);
  assert.equal(await readMarker("champ-1"), undefined);

  // 90 minutes after the close, a recap that never came no longer holds it.
  const late = await deliverChampionPush({
    data: {
      championUserIds: ["champ-1"],
      periodEndAt: admin.firestore.Timestamp.fromDate(periodEndAt),
      periodKey: "2026-W39",
      source: "leaderboard_finalizer",
      timeFrame: "weekly",
    },
    firestore: db,
    now: new Date("2026-09-28T01:31:00Z"),
    resultId: RESULT_ID,
    sender,
  });
  assert.equal(late.eligible, true);
  assert.equal((late as {summary: ChampionPushSummary}).summary.delivered, 1);
  assert.equal(requests.length, 1);
});

test("a dead token is unregistered after the send", async () => {
  await seedPlacing("champ-1", 5000);
  await seedDevice("champ-1", "hash-live", "token-live");
  await seedDevice("champ-1", "hash-dead", "token-dead");
  const {sender} = recordingSender((tokenHash) => tokenHash === "hash-dead" ?
    {invalidToken: true, ok: false} :
    {invalidToken: false, ok: true});

  const summary = await deliver(sender);

  assert.equal(summary.sentCount, 1);
  assert.equal(summary.invalidTokenCount, 1);
  const root = await db.doc("notification_devices/hash-dead").get();
  const mirror = await db.doc("users/champ-1/notification_devices/hash-dead")
    .get();
  assert.equal(root.get("active"), false);
  assert.equal(mirror.get("active"), false);
  const live = await db.doc("notification_devices/hash-live").get();
  assert.equal(live.get("active"), true);
});

test("a send that throws keeps its claim and is never retried", async () => {
  await seedPlacing("champ-1", 5000);
  await seedDevice("champ-1", "hash-1", "token-1");
  let attempts = 0;
  const throwing: ChampionPushSender = {
    async send() {
      attempts += 1;
      throw new Error("fcm unavailable");
    },
  };

  const first = await deliver(throwing);
  const second = await deliver(throwing);

  assert.equal(first.failed, 1);
  assert.equal(second.alreadyClaimed, 1);
  assert.equal(attempts, 1);
  assert.equal((await readMarker("champ-1"))?.status, "unsent");
});

test("a backfilled or stale result writes nothing and sends nothing", async () => {
  await seedPlacing("champ-1", 5000);
  await seedDevice("champ-1", "hash-1", "token-1");
  const {requests, sender} = recordingSender();
  const base = {
    championUserIds: ["champ-1"],
    periodEndAt: admin.firestore.Timestamp.fromDate(periodEndAt),
    periodKey: "2026-W39",
    timeFrame: "weekly",
  };

  const backfill = await deliverChampionPush({
    data: {...base, source: "backfill"},
    firestore: db,
    now,
    resultId: RESULT_ID,
    sender,
  });
  const stale = await deliverChampionPush({
    data: {...base, source: "leaderboard_finalizer"},
    firestore: db,
    now: new Date(periodEndAt.getTime() + 49 * 60 * 60 * 1000),
    resultId: RESULT_ID,
    sender,
  });

  assert.deepEqual(backfill, {eligible: false, reason: "not_finalizer"});
  assert.deepEqual(stale, {eligible: false, reason: "stale"});
  assert.equal(requests.length, 0);
  assert.equal(await readMarker("champ-1"), undefined);
});

test(
  "the preference callable merges the champion preference and leaves climb drops alone",
  async () => {
    const decidedAt = admin.firestore.Timestamp.fromMillis(1_700_000_000_000);
    await db.doc("users/pref-1/communication_preferences/current").set({
      createdAt: decidedAt,
      lifecycleEmailsDecidedAt: decidedAt,
      lifecycleEmailsEnabled: true,
      lifecycleEmailsSource: "settings",
      pushClimbDropsEnabled: true,
      schemaVersion: 1,
      updatedAt: decidedAt,
    });
    await seedDevice("pref-1", "hash-1", "token-1");

    await callPreferences("pref-1", {championPushEnabled: false});

    const afterChampion = (await db
      .doc("users/pref-1/communication_preferences/current").get()).data();
    assert.equal(afterChampion?.pushChampionCrownEnabled, false);
    assert.equal(afterChampion?.pushClimbDropsEnabled, true);
    assert.equal(afterChampion?.lifecycleEmailsEnabled, true);
    assert.equal(afterChampion?.lifecycleEmailsSource, "settings");
    assert.ok(decidedAt.isEqual(afterChampion?.createdAt));
    assert.equal(
      (await db.doc("notification_devices/hash-1").get())
        .get("climbDropPushEnabled"),
      true
    );

    // An old build's request: only the climb-drop field, with the device
    // mirrors updated exactly as before.
    await callPreferences("pref-1", {climbDropPushEnabled: false});

    const afterClimbDrop = (await db
      .doc("users/pref-1/communication_preferences/current").get()).data();
    assert.equal(afterClimbDrop?.pushClimbDropsEnabled, false);
    assert.equal(afterClimbDrop?.pushChampionCrownEnabled, false);
    assert.equal(
      (await db.doc("notification_devices/hash-1").get())
        .get("climbDropPushEnabled"),
      false
    );
    assert.equal(
      (await db.doc("users/pref-1/notification_devices/hash-1").get())
        .get("climbDropPushEnabled"),
      false
    );
  }
);

test("an old caller's first preference write is the document it always was", async () => {
  await callPreferences("pref-2", {climbDropPushEnabled: true});

  const stored = (await db
    .doc("users/pref-2/communication_preferences/current").get()).data();
  assert.deepEqual(Object.keys(stored ?? {}).sort(), [
    "createdAt",
    "pushClimbDropsEnabled",
    "schemaVersion",
    "updatedAt",
  ]);
  assert.equal(stored?.pushClimbDropsEnabled, true);
});

test("a preference request that changes nothing is refused", async () => {
  await assert.rejects(
    callPreferences("pref-3", {}),
    /climbDropPushEnabled or championPushEnabled is required/
  );
  const stored = await db
    .doc("users/pref-3/communication_preferences/current").get();
  assert.equal(stored.exists, false);
});

/**
 * Invokes the preference callable as a signed-in climber.
 * @param {string} uid - The caller
 * @param {Record<string, unknown>} data - The request body
 * @return {Promise<unknown>} The callable's response
 */
async function callPreferences(
  uid: string,
  data: Record<string, unknown>
): Promise<unknown> {
  return updatePushNotificationPreferences.run({
    auth: {token: {}, uid},
    data,
  } as unknown as CallableRequest);
}

/**
 * Seeds a champion's frozen placing on the result.
 * @param {string} uid - The champion
 * @param {number} totalSteps - Their frozen period total
 * @return {Promise<void>}
 */
async function seedPlacing(uid: string, totalSteps: number): Promise<void> {
  await db.doc(`leaderboard_results/${RESULT_ID}/placings/${uid}`).set({
    rank: 1,
    schemaVersion: 1,
    totalSteps,
    totalWorkouts: 3,
    userId: uid,
  });
  await seedRecap(uid);
}

/**
 * Seeds the champion's composed recap - the page the crown alert opens to.
 * @param {string} uid - The champion
 * @return {Promise<void>}
 */
async function seedRecap(uid: string): Promise<void> {
  await db.doc(`users/${uid}/recaps/weekly_2026-W39`).set({
    cadence: "weekly",
    periodKey: "2026-W39",
    seenAt: null,
    variant: "active",
  });
}

/**
 * Seeds a registered device - the root registry entry and the climber's
 * mirror - the way `registerPushDevice` writes them.
 * @param {string} uid - The owner
 * @param {string} tokenHash - The registration's id
 * @param {string} fcmToken - The token
 * @param {Record<string, unknown>} overrides - Fields to change on both
 * @return {Promise<void>}
 */
async function seedDevice(
  uid: string,
  tokenHash: string,
  fcmToken: string,
  overrides: Record<string, unknown> = {}
): Promise<void> {
  const shared = {
    active: true,
    authorizationStatus: "authorized",
    climbDropPushEnabled: true,
    platform: "ios",
    tokenHash,
    ...overrides,
  };
  await db.doc(`notification_devices/${tokenHash}`)
    .set({...shared, fcmToken, uid});
  await db.doc(`users/${uid}/notification_devices/${tokenHash}`).set(shared);
}

/**
 * Reads a champion's delivery marker for the seeded result.
 * @param {string} uid - The champion
 * @return {Promise<Record<string, unknown> | undefined>} The marker, if any
 */
async function readMarker(
  uid: string
): Promise<Record<string, unknown> | undefined> {
  return (await db.doc(`_champion_push_deliveries/${RESULT_ID}_${uid}`).get())
    .data();
}
