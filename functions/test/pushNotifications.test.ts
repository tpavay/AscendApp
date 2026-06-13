import test from "node:test";
import assert from "node:assert/strict";
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
