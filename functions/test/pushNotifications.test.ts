import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {pushNotificationTestHooks} from "../src/pushNotifications.js";

test("push token hashes are deterministic and Firestore-safe", () => {
  const tokenHash = pushNotificationTestHooks.hashToken("fcm-token-123");

  assert.match(tokenHash, /^[a-f0-9]{64}$/);
  assert.equal(
    tokenHash,
    pushNotificationTestHooks.hashToken("fcm-token-123")
  );
  assert.notEqual(
    tokenHash,
    pushNotificationTestHooks.hashToken("other-token")
  );
});

test("push register payload trims metadata", () => {
  const payload = pushNotificationTestHooks.normalizeRegisterPushDevicePayload({
    appVersion: " 1.0 ",
    authorizationStatus: "authorized",
    buildNumber: " 42 ",
    bundleId: " com.TylerPavay.AscendApp.staging ",
    climbDropPushEnabled: true,
    fcmToken: " token ",
    locale: " en_US ",
    platform: "ios",
    timeZone: " America/Chicago ",
  });

  assert.equal(payload.appVersion, "1.0");
  assert.equal(payload.authorizationStatus, "authorized");
  assert.equal(payload.buildNumber, "42");
  assert.equal(payload.bundleId, "com.TylerPavay.AscendApp.staging");
  assert.equal(payload.climbDropPushEnabled, true);
  assert.equal(payload.fcmToken, "token");
  assert.equal(payload.platform, "ios");
});

test("climb-drop send payload defaults to all opted-in devices", () => {
  const payload = pushNotificationTestHooks.normalizeSendClimbDropPayload({
    body: "A new climb just opened.",
    climbId: "cn-tower",
    title: "New climb drop",
  });

  assert.equal(payload.audience, "all_opted_in");
  assert.equal(payload.dryRun, false);
  assert.equal(payload.userId, undefined);
});

test("climb-drop send payload requires a user id for user audience", () => {
  assert.throws(
    () => pushNotificationTestHooks.normalizeSendClimbDropPayload({
      audience: "user",
      body: "A new climb just opened.",
      climbId: "cn-tower",
      title: "New climb drop",
    }),
    /A user audience requires userId/
  );
});

/**
 * Builds a Firestore stand-in over a flat path -> fields map that records the
 * documents a write created.
 * @param {object} documents Seed documents keyed by full path.
 * @return {object} The stand-in plus the recorded documents and creations.
 */
function makeDeviceFirestore(
  documents: Record<string, Record<string, unknown>>
): {
  firestore: admin.firestore.Firestore;
  documents: Record<string, Record<string, unknown>>;
  created: string[];
} {
  const created: string[] = [];

  const documentAt = (path: string) => ({
    collection(collectionId: string) {
      return collectionAt(`${path}/${collectionId}`);
    },
    get() {
      const fields = documents[path];
      return Promise.resolve({
        data: () => fields,
        exists: fields !== undefined,
      });
    },
    set(fields: Record<string, unknown>) {
      if (documents[path] === undefined) {
        created.push(path);
      }
      documents[path] = {...(documents[path] ?? {}), ...fields};
      return Promise.resolve({});
    },
  });

  const collectionAt = (path: string) => ({
    doc(documentId: string) {
      return documentAt(`${path}/${documentId}`);
    },
  });

  const firestore = {
    collection(collectionId: string) {
      return collectionAt(collectionId);
    },
  };

  return {
    created,
    documents,
    firestore: firestore as unknown as admin.firestore.Firestore,
  };
}

test("unregistering an unknown token creates no delivery record", async () => {
  // A merging write would mint notification_devices/{tokenHash} with no `uid`,
  // and the account-deletion sweep queries by `uid`, so that orphan would
  // outlive the account forever.
  const {created, documents, firestore} = makeDeviceFirestore({});

  await pushNotificationTestHooks.deactivateToken(
    firestore,
    "user-a",
    "hash-1",
    admin.firestore.Timestamp.now()
  );

  assert.deepEqual(created, []);
  assert.deepEqual(Object.keys(documents), []);
});

test("unregistering leaves another climber's token active", async () => {
  const {created, documents, firestore} = makeDeviceFirestore({
    "notification_devices/hash-1": {active: true, uid: "user-b"},
  });

  await pushNotificationTestHooks.deactivateToken(
    firestore,
    "user-a",
    "hash-1",
    admin.firestore.Timestamp.now()
  );

  // Knowing a token is not proof of owning it.
  assert.equal(documents["notification_devices/hash-1"].active, true);
  assert.deepEqual(created, []);
});

test("unregistering deactivates the caller's token and mirror", async () => {
  const {created, documents, firestore} = makeDeviceFirestore({
    "notification_devices/hash-1": {active: true, uid: "user-a"},
    "users/user-a/notification_devices/hash-1": {active: true},
  });

  await pushNotificationTestHooks.deactivateToken(
    firestore,
    "user-a",
    "hash-1",
    admin.firestore.Timestamp.now()
  );

  assert.equal(documents["notification_devices/hash-1"].active, false);
  assert.equal(
    documents["users/user-a/notification_devices/hash-1"].active,
    false
  );
  assert.deepEqual(created, []);
});

test("a denied device leaves the climb-drop audience without losing intent", () => {
  const registrations = [
    {
      data: {
        active: true,
        authorizationStatus: "authorized",
        climbDropPushEnabled: true,
        fcmToken: "token-allowed",
        platform: "ios",
      },
      tokenHash: "hash-allowed",
    },
    {
      data: {
        active: true,
        authorizationStatus: "denied",
        climbDropPushEnabled: true,
        fcmToken: "token-denied",
        platform: "ios",
      },
      tokenHash: "hash-denied",
    },
    {
      data: {
        active: true,
        authorizationStatus: "not_determined",
        climbDropPushEnabled: true,
        fcmToken: "token-unasked",
        platform: "ios",
      },
      tokenHash: "hash-unasked",
    },
  ];

  const devices =
    pushNotificationTestHooks.selectDeliverableClimbDropDevices(registrations);

  // The denial costs delivery, never the stored preference.
  assert.deepEqual(devices, [
    {fcmToken: "token-allowed", tokenHash: "hash-allowed"},
  ]);
  assert.equal(registrations[1].data.climbDropPushEnabled, true);
});

test("a device rejoins the audience when authorization returns", () => {
  const registration = {
    data: {
      active: true,
      authorizationStatus: "denied",
      climbDropPushEnabled: true,
      fcmToken: "token-1",
      platform: "ios",
    },
    tokenHash: "hash-1",
  };

  assert.deepEqual(
    pushNotificationTestHooks.selectDeliverableClimbDropDevices([registration]),
    []
  );

  registration.data.authorizationStatus = "authorized";

  assert.deepEqual(
    pushNotificationTestHooks.selectDeliverableClimbDropDevices([registration]),
    [{fcmToken: "token-1", tokenHash: "hash-1"}]
  );
});

test("quiet authorizations still count as deliverable", () => {
  const devices = pushNotificationTestHooks.selectDeliverableClimbDropDevices([
    {
      data: {
        active: true,
        authorizationStatus: "provisional",
        climbDropPushEnabled: true,
        fcmToken: "token-provisional",
        platform: "ios",
      },
      tokenHash: "hash-provisional",
    },
    {
      data: {
        active: true,
        authorizationStatus: "ephemeral",
        climbDropPushEnabled: true,
        fcmToken: "token-ephemeral",
        platform: "ios",
      },
      tokenHash: "hash-ephemeral",
    },
  ]);

  assert.equal(devices.length, 2);
});
