/**
 * ASCEND-IOS-1, against a real Firestore.
 *
 * The unit suite proves the normalizer in isolation. It cannot prove the thing
 * a climber actually experiences: that a paywall dismissal carrying a printed
 * Swift enum now LANDS - a document in `lifecycle_events`, a paywall state in
 * the lifecycle mirror, and a durable note saying what the server repaired -
 * where for two months of production the whole call came back
 * `invalid-argument: reason must be a lifecycle key.` and nothing was stored.
 *
 * Lives under test/emulator/ so `npm test` does not pick it up without a
 * Firestore behind it. `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {recordLifecycleEvent} from "../../src/lifecycle.js";

const uid = "climber-lifecycle-1";

let db: admin.firestore.Firestore;

/**
 * Invokes the shipped callable as a signed-in climber would.
 * @param {string} type Lifecycle event type.
 * @param {Record<string, unknown>} payload Raw client payload.
 * @return {Promise<unknown>} Whatever the callable returned.
 */
function record(type: string, payload: Record<string, unknown>) {
  return (recordLifecycleEvent as unknown as {
    run: (request: unknown) => Promise<unknown>;
  }).run({
    auth: {uid},
    data: {payload, type},
  });
}

/**
 * Invokes the owner-bound delivery contract used by current iOS clients.
 * @param {string} type Lifecycle event type.
 * @param {Record<string, unknown>} payload Raw client payload.
 * @return {Promise<unknown>} Whatever the callable returned.
 */
function recordV2(type: string, payload: Record<string, unknown>) {
  return (recordLifecycleEvent as unknown as {
    run: (request: unknown) => Promise<unknown>;
  }).run({
    auth: {uid},
    data: {
      deliverySchemaVersion: 2,
      expectedUserID: uid,
      payload,
      type,
    },
  });
}

/**
 * Reads a stored lifecycle event document.
 * @param {string} eventDocId Event document id.
 * @return {Promise<admin.firestore.DocumentSnapshot>} The snapshot.
 */
function readEvent(eventDocId: string) {
  return db
    .collection("users")
    .doc(uid)
    .collection("lifecycle_events")
    .doc(eventDocId)
    .get();
}

/**
 * Reads the climber's lifecycle state mirror.
 * @return {Promise<Record<string, unknown>>} Mirror contents.
 */
async function readState(): Promise<Record<string, unknown>> {
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("lifecycle")
    .doc("state")
    .get();
  return (snapshot.data() ?? {}) as Record<string, unknown>;
}

/**
 * Clears everything this suite writes for the climber.
 * @return {Promise<void>} Resolves once the climber's tree is gone.
 */
async function clearClimber(): Promise<void> {
  await db.recursiveDelete(db.collection("users").doc(uid));
}

before(() => {
  // Never let this suite pass by quietly doing nothing.
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );

  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  }
  db = admin.firestore();
});

beforeEach(async () => {
  await clearClimber();
});

test("a paywall dismissal printing a Swift enum is stored, not discarded",
  async () => {
    // Verbatim what SuperwallPaywallPresenter sends today:
    // String(describing: paywallInfo.closeReason) prints `manualClose`.
    await record("paywall_dismissed", {
      placement: "onboarding_paywall",
      reason: "manualClose",
    });

    const snapshot = await readEvent("paywall_dismissed_onboarding_paywall_v1");
    assert.equal(snapshot.exists, true);

    const stored = snapshot.data() as Record<string, never>;
    const payload = stored.payload as unknown as Record<string, unknown>;
    assert.equal(payload.placement, "onboarding_paywall");
    // Normalized, not defaulted: the dismissal reason is the question this
    // field exists to answer, so `unknown` would have been a lost answer.
    assert.equal(payload.reason, "manual_close");

    // Nothing swallowed: the repair is durable on the document itself.
    assert.deepEqual(stored.fieldNotes, [{
      field: "reason",
      received: "manualClose",
      resolution: "normalized",
      resolved: "manual_close",
    }]);

    // And the repaired value is what the lifecycle mirror - the document email
    // automation reads - actually carries for that placement.
    const state = await readState();
    const paywall = state.paywall as Record<string, unknown>;
    const placement = paywall.onboarding_paywall as Record<string, unknown>;
    assert.equal(placement.lastEventType, "paywall_dismissed");
    assert.equal(placement.status, "dismissed");
    assert.equal(placement.reason, "manual_close");
  });

test("owner-bound V2 lands without persisting delivery metadata", async () => {
  await recordV2("paywall_shown", {
    placement: "app_access_gate",
  });

  const stored = (await readEvent("paywall_shown_app_access_gate_v1"))
    .data() as Record<string, unknown>;
  const payload = stored.payload as Record<string, unknown>;
  assert.equal(stored.expectedUserID, undefined);
  assert.equal(stored.deliverySchemaVersion, undefined);
  assert.equal(payload.expectedUserID, undefined);
  assert.equal(payload.deliverySchemaVersion, undefined);
});

test("a clean repeat of the same event clears the earlier repair note",
  async () => {
    await record("paywall_dismissed", {
      placement: "onboarding_paywall",
      reason: "manualClose",
    });
    await record("paywall_dismissed", {
      placement: "onboarding_paywall",
      reason: "manual_close",
    });

    const stored = (await readEvent("paywall_dismissed_onboarding_paywall_v1"))
      .data() as Record<string, never>;
    assert.deepEqual(stored.fieldNotes, []);
    assert.equal(stored.receivedCount, 2);
  });

test("a malformed REQUIRED key still refuses the call and stores nothing",
  async () => {
    await assert.rejects(
      () => record("onboarding_stage_reached", {stage: "notificationPriming"}),
      /stage must be a lifecycle key\./
    );

    const snapshot = await readEvent("onboarding_stage_reached_v1");
    assert.equal(snapshot.exists, false);
    assert.deepEqual(await readState(), {});
  });

test("a consent decision with an unrecognized source is still refused",
  async () => {
    await assert.rejects(
      () => record("communication_preferences_updated", {
        lifecycleEmailsEnabled: true,
        lifecycleEmailsSource: "MysterySurface",
      }),
      /Unsupported lifecycle email consent source\./
    );

    assert.equal(
      (await readEvent("communication_preferences_updated_v1")).exists,
      false
    );
  });

test("a source with no consent decision keeps the preferences it accompanied",
  async () => {
    await record("communication_preferences_updated", {
      climbDropEmailsEnabled: true,
      lifecycleEmailsSource: "settings_screen",
      productUpdatesEnabled: false,
    });

    const preferences = (await db
      .collection("users")
      .doc(uid)
      .collection("communication_preferences")
      .doc("current")
      .get()).data() as Record<string, unknown>;

    assert.equal(preferences.climbDropEmailsEnabled, true);
    assert.equal(preferences.productUpdatesEnabled, false);
    // No consent decision arrived, so no consent record was forged.
    assert.equal(preferences.lifecycleEmailsSource, undefined);
  });

test("a lossy completedStages repair never truncates the accumulated mirror",
  async () => {
    await record("onboarding_stage_reached", {
      completedStages: ["welcome", "goal_setting", "notification_priming"],
      stage: "notification_priming",
    });

    // A later event whose list cannot be repaired entry for entry. The mirror
    // is replaced wholesale, so writing the shrunken list would silently lose
    // history that cannot be reconstructed.
    await record("onboarding_completed", {
      completedStages: ["!!!", "???"],
      currentStage: "paywall",
    });

    const onboarding =
      (await readState()).onboarding as Record<string, unknown>;
    assert.equal(onboarding.status, "completed");
    assert.equal(onboarding.currentStage, "paywall");
    assert.deepEqual(
      onboarding.completedStages,
      ["welcome", "goal_setting", "notification_priming"]
    );

    const stored = (await readEvent("onboarding_completed_v1"))
      .data() as Record<string, never>;
    const notes = stored.fieldNotes as unknown as {resolution: string}[];
    assert.equal(notes.some((n) => n.resolution === "items_dropped"), true);
  });

test("an Apple Health event survives a non-boolean auto import flag",
  async () => {
    await record("apple_health_integration_changed", {
      autoImportEnabled: "true",
      status: "connected",
    });

    const state = await readState();
    const integrations = state.integrations as Record<string, unknown>;
    const appleHealth = integrations.appleHealth as Record<string, unknown>;
    // The connection status is the point of this event, and it survived.
    assert.equal(appleHealth.status, "connected");
    assert.equal(
      Object.keys(appleHealth).includes("autoImportEnabled"),
      false
    );
  });
