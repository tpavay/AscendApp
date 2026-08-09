import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {lifecycleTestHooks} from "../src/lifecycle.js";

const now = admin.firestore.Timestamp.fromMillis(1_754_611_200_000);

/**
 * Builds the Apple Health integration mirror patch for a raw callable payload.
 * @param {Record<string, unknown>} payload Raw client payload.
 * @return {Record<string, unknown>} The appleHealth mirror object.
 */
function mirrorFor(payload: Record<string, unknown>) {
  const event = lifecycleTestHooks.normalizeRequestData({
    payload,
    type: "apple_health_integration_changed",
  });
  const patch = lifecycleTestHooks.statePatchForEvent(event, {}, now);
  const integrations = patch.integrations as Record<string, unknown>;
  return integrations.appleHealth as Record<string, unknown>;
}

test("Apple Health event from an older client keeps mirroring auto import", () => {
  const mirror = mirrorFor({autoImportEnabled: true, status: "connected"});

  assert.equal(mirror.status, "connected");
  assert.equal(mirror.autoImportEnabled, true);
  assert.equal(mirror.lastCheckedAt, now);
});

test("Apple Health event without auto import is accepted and omits the key", () => {
  const mirror = mirrorFor({status: "connected"});

  assert.equal(mirror.status, "connected");
  assert.equal(mirror.lastCheckedAt, now);
  // Omitted rather than undefined: Firestore rejects an undefined value, and a
  // value an older binary mirrored must survive a client that dropped it.
  assert.equal(
    Object.keys(mirror).includes("autoImportEnabled"),
    false
  );
  assert.equal(
    Object.values(mirror).some((value) => value === undefined),
    false
  );
});

test("Apple Health event with a non-boolean auto import is rejected", () => {
  assert.throws(
    () => mirrorFor({autoImportEnabled: "yes", status: "connected"}),
    /Apple Health auto import state must be boolean/
  );
});

test("Apple Health event with an unsupported status is rejected", () => {
  assert.throws(
    () => mirrorFor({status: "importing"}),
    /Unsupported Apple Health integration status/
  );
});
