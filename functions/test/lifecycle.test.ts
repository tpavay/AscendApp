import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {lifecycleTestHooks} from "../src/lifecycle.js";

const now = admin.firestore.Timestamp.fromMillis(1_754_611_200_000);

interface FieldNote {
  field: string;
  received: string;
  resolution: string;
  resolved: string;
}

interface NormalizedEvent {
  eventDocId: string;
  fieldNotes: FieldNote[];
  payload: Record<string, unknown>;
  type: string;
}

/**
 * Normalizes a raw callable payload the way the callable itself does.
 * @param {string} type Lifecycle event type.
 * @param {Record<string, unknown>} payload Raw client payload.
 * @return {NormalizedEvent} The server-owned event.
 */
function normalize(
  type: string,
  payload: Record<string, unknown>
): NormalizedEvent {
  return lifecycleTestHooks.normalizeRequestData({
    payload,
    type,
  }) as unknown as NormalizedEvent;
}

/**
 * Finds the note a normalized event recorded for one field.
 * @param {NormalizedEvent} event Normalized event.
 * @param {string} field Field name.
 * @return {FieldNote} The single note for that field.
 */
function noteFor(event: NormalizedEvent, field: string): FieldNote {
  const notes = event.fieldNotes.filter((note) => note.field === field);
  assert.equal(
    notes.length,
    1,
    `expected exactly one note for ${field}, got ${notes.length}`
  );
  return notes[0];
}

/**
 * Builds the Apple Health integration mirror patch for a raw callable payload.
 * @param {Record<string, unknown>} payload Raw client payload.
 * @return {Record<string, unknown>} The appleHealth mirror object.
 */
function mirrorFor(payload: Record<string, unknown>) {
  const event = normalize("apple_health_integration_changed", payload);
  const patch = lifecycleTestHooks.statePatchForEvent(
    event as never,
    {},
    now
  );
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

test("Apple Health event with an unsupported status is rejected", () => {
  assert.throws(
    () => mirrorFor({status: "importing"}),
    /Unsupported Apple Health integration status/
  );
});

// ---------------------------------------------------------------------------
// ASCEND-IOS-1: a badly formatted OPTIONAL field discarded the whole event.
//
// The paywall sends `String(describing: paywallInfo.closeReason)`, which prints
// a Swift enum as `manualClose`. That failed the lifecycle key pattern on the
// capital letter, so `recordLifecycleEvent` rejected every paywall dismissal
// with `reason must be a lifecycle key.` for two months of production.
// ---------------------------------------------------------------------------

test("a camelCase paywall reason keeps the event and its meaning", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: "manualClose",
  });

  assert.equal(event.type, "paywall_dismissed");
  assert.equal(event.payload.placement, "onboarding_paywall");
  assert.equal(event.payload.reason, "manual_close");
});

test("every close reason Superwall can print survives", () => {
  const printed: Record<string, string | undefined> = {
    forNextPaywall: "for_next_paywall",
    manualClose: "manual_close",
    none: "none",
    systemLogic: "system_logic",
    webViewFailed: "web_view_failed",
  };

  for (const [raw, expected] of Object.entries(printed)) {
    const event = normalize("paywall_dismissed", {
      placement: "app_access_gate",
      reason: raw,
    });
    assert.equal(event.payload.reason, expected, `close reason ${raw}`);
  }
});

test("a normalized reason records what arrived and what was stored", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: "manualClose",
  });
  const note = noteFor(event, "reason");

  assert.equal(note.received, "manualClose");
  assert.equal(note.resolution, "normalized");
  assert.equal(note.resolved, "manual_close");
});

test("a well formed reason is stored untouched and records nothing", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: "manual_close",
  });

  assert.equal(event.payload.reason, "manual_close");
  assert.deepEqual(event.fieldNotes, []);
});

test("an absent reason still omits the field and records nothing", () => {
  const event = normalize("paywall_dismissed", {
    placement: "app_launch_hard_gate",
  });

  assert.equal(Object.keys(event.payload).includes("reason"), false);
  assert.deepEqual(event.fieldNotes, []);
});

test("an unsalvageable reason falls back but is not swallowed", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: "🎉",
  });
  const note = noteFor(event, "reason");

  assert.equal(Object.keys(event.payload).includes("reason"), false);
  assert.equal(note.received, "🎉");
  assert.equal(note.resolution, "fallback");
  assert.equal(note.resolved, "omitted");
});

test("a non-string reason falls back rather than rejecting the event", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: 42,
  });
  const note = noteFor(event, "reason");

  assert.equal(event.payload.placement, "onboarding_paywall");
  assert.equal(note.received, "42");
  assert.equal(note.resolution, "fallback");
});

test("the paywall state mirror carries the normalized reason", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: "manualClose",
  });
  const patch = lifecycleTestHooks.statePatchForEvent(event as never, {}, now);
  const paywall = patch.paywall as Record<string, Record<string, unknown>>;

  assert.equal(paywall.onboarding_paywall.reason, "manual_close");
  assert.equal(paywall.onboarding_paywall.status, "dismissed");
});

test("a rejected reason is bounded before it reaches Firestore", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: "!".repeat(5_000),
  });
  const note = noteFor(event, "reason");

  assert.equal(note.received.length, 120);
  assert.equal(note.received.endsWith("..."), true);
});

test("a normalized reason is bounded to the lifecycle key length", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: "a".repeat(200),
  });

  assert.equal((event.payload.reason as string).length, 64);
});

test("every recorded note is a plain string Firestore can store", () => {
  const event = normalize("paywall_dismissed", {
    placement: "onboarding_paywall",
    reason: {closeReason: "manualClose"},
  });

  for (const note of event.fieldNotes) {
    for (const value of Object.values(note)) {
      assert.equal(typeof value, "string");
    }
  }
});

test("an unsupported paywall placement is still rejected", () => {
  // Placement selects the state document key, so a wrong one is not a
  // formatting problem the server can repair.
  assert.throws(
    () => normalize("paywall_dismissed", {placement: "settings_upsell"}),
    /Unsupported paywall placement/
  );
});

// ---------------------------------------------------------------------------
// The same defect class on every other optional lifecycle field.
// ---------------------------------------------------------------------------

test("a malformed review reason falls back to unknown and is recorded", () => {
  const event = normalize("app_store_review_requested", {
    reason: "ratingPromptYes",
  });

  assert.equal(event.payload.reason, "rating_prompt_yes");
  assert.equal(noteFor(event, "reason").resolution, "normalized");
});

test("an unsalvageable review reason still records the event", () => {
  const event = normalize("app_store_review_requested", {reason: "!!!"});
  const note = noteFor(event, "reason");

  assert.equal(event.payload.reason, "unknown");
  assert.equal(note.resolution, "fallback");
  assert.equal(note.resolved, "unknown");
});

test("a malformed onboarding currentStage falls back to unknown", () => {
  const event = normalize("onboarding_completed", {
    completedStages: ["goal"],
    currentStage: "First Climb!",
  });

  assert.equal(event.payload.currentStage, "first_climb");
  assert.equal(noteFor(event, "currentStage").resolution, "normalized");
});

test("a malformed completed stage is normalized rather than fatal", () => {
  const event = normalize("onboarding_stage_reached", {
    completedStages: ["goal", "firstClimb"],
    stage: "notifications",
  });

  assert.deepEqual(event.payload.completedStages, ["goal", "first_climb"]);
  assert.equal(noteFor(event, "completedStages").resolution, "normalized");
});

test("an unusable completed stage is dropped, not fatal", () => {
  const event = normalize("onboarding_stage_reached", {
    completedStages: ["goal", 7, "***"],
    stage: "notifications",
  });
  const notes = event.fieldNotes.filter(
    (note) => note.field === "completedStages"
  );

  assert.deepEqual(event.payload.completedStages, ["goal"]);
  assert.equal(notes.length, 1);
  assert.equal(notes[0].resolution, "items_dropped");
  assert.equal(notes[0].received, "[7,\"***\"]");
});

test("completedStages that is not an array falls back to empty", () => {
  const event = normalize("onboarding_stage_reached", {
    completedStages: "goal",
    stage: "notifications",
  });

  assert.deepEqual(event.payload.completedStages, []);
  assert.equal(noteFor(event, "completedStages").resolution, "fallback");
});

test("an oversized completedStages is bounded rather than rejected", () => {
  const stages = Array.from({length: 30}, (_, index) => `stage_${index}`);
  const event = normalize("onboarding_stage_reached", {
    completedStages: stages,
    stage: "notifications",
  });

  assert.equal((event.payload.completedStages as string[]).length, 20);
  assert.equal(noteFor(event, "completedStages").resolution, "truncated");
});

test("an oversized completedStages is bounded before it is inspected", () => {
  // The old code refused an oversized array outright. Repairing entry by entry
  // must not turn that into unbounded server work, or a bounded note into an
  // unbounded document.
  const event = normalize("onboarding_stage_reached", {
    completedStages: Array.from({length: 5_000}, () => "Not A Key !!!"),
    stage: "notifications",
  });
  const truncated = event.fieldNotes.find(
    (note) => note.resolution === "truncated"
  );

  assert.equal(truncated?.received, "5000 entries");
  for (const note of event.fieldNotes) {
    assert.ok(note.received.length <= 120, note.received.length.toString());
    assert.ok(note.resolved.length <= 120, note.resolved.length.toString());
  }
});

test("completedStages still dedupes after normalization", () => {
  const event = normalize("onboarding_stage_reached", {
    completedStages: ["first_climb", "firstClimb", "First Climb"],
    stage: "notifications",
  });

  assert.deepEqual(event.payload.completedStages, ["first_climb"]);
});

test("a malformed REQUIRED onboarding stage is still rejected loudly", () => {
  // The required key names the event. Repairing it would invent a claim the
  // client never made, so this one keeps failing the call.
  assert.throws(
    () => normalize("onboarding_stage_reached", {stage: "First Climb"}),
    /stage must be a lifecycle key/
  );
  assert.throws(
    () => normalize("onboarding_stage_reached", {stage: 7}),
    /stage must be a lifecycle key/
  );
  assert.throws(
    () => normalize("onboarding_stage_reached", {}),
    /stage must be a lifecycle key/
  );
});

test("an unsupported notification status is still rejected", () => {
  assert.throws(
    () => normalize("notification_permission_observed", {status: "maybe"}),
    /Unsupported notification permission status/
  );
});

test("a non-boolean auto import keeps the Apple Health status", () => {
  // Same defect class as the paywall reason: the connection status is the
  // point of the event, and a companion field the mirror can go without is
  // not allowed to discard it.
  const event = normalize("apple_health_integration_changed", {
    autoImportEnabled: "yes",
    status: "connected",
  });
  const note = noteFor(event, "autoImportEnabled");

  assert.equal(event.payload.status, "connected");
  assert.equal(Object.keys(event.payload).includes("autoImportEnabled"), false);
  assert.equal(note.received, "yes");
  assert.equal(note.resolution, "fallback");
  assert.equal(note.resolved, "omitted");
});

test("a stray consent source keeps the preferences the climber changed", () => {
  const event = normalize("communication_preferences_updated", {
    lifecycleEmailsSource: "onboarding",
    productUpdatesEnabled: false,
  });
  const note = noteFor(event, "lifecycleEmailsSource");

  assert.equal(event.payload.productUpdatesEnabled, false);
  // Still not stored: a source with no decision behind it is not evidence.
  assert.equal(
    Object.keys(event.payload).includes("lifecycleEmailsSource"),
    false
  );
  assert.equal(note.resolution, "fallback");
  assert.equal(note.resolved, "omitted");
});

test("a consent decision with an unsupported source is still rejected", () => {
  // Required in this branch: storing a consent record without a real source
  // would forge the evidence rather than lose it.
  assert.throws(
    () => normalize("communication_preferences_updated", {
      lifecycleEmailsEnabled: true,
      lifecycleEmailsSource: "guessed",
    }),
    /Unsupported lifecycle email consent source/
  );
});

test("an empty communication preferences call is still rejected", () => {
  assert.throws(
    () => normalize("communication_preferences_updated", {}),
    /At least one communication preference must be provided/
  );
});

test("a clean call always carries an empty note list", () => {
  const clean: Array<[string, Record<string, unknown>]> = [
    ["rating_prompt_answered", {response: "yes"}],
    ["app_store_review_requested", {reason: "rating_prompt_yes"}],
    ["onboarding_stage_reached", {completedStages: ["goal"], stage: "age"}],
    ["onboarding_completed", {completedStages: [], currentStage: "age"}],
    ["paywall_shown", {placement: "onboarding_paywall"}],
    ["notification_permission_observed", {status: "authorized"}],
    ["apple_health_integration_changed", {status: "connected"}],
    ["communication_preferences_updated", {productUpdatesEnabled: true}],
  ];

  for (const [type, payload] of clean) {
    // Always present, never merged: the event document is overwritten on every
    // call, so a later clean call clears an earlier call's notes.
    assert.deepEqual(normalize(type, payload).fieldNotes, [], type);
  }
});

/**
 * Builds the onboarding mirror patch for a raw callable payload.
 * @param {string} type Lifecycle event type.
 * @param {Record<string, unknown>} payload Raw client payload.
 * @return {Record<string, unknown>} The onboarding mirror object.
 */
function onboardingMirrorFor(
  type: string,
  payload: Record<string, unknown>
) {
  const event = normalize(type, payload);
  const patch = lifecycleTestHooks.statePatchForEvent(
    event as never,
    {},
    now
  );
  return patch.onboarding as Record<string, unknown>;
}

test("a repaired completedStages leaves the mirror alone, stage still lands", () => {
  // The mirror is replaced, not merged, so writing the salvageable subset
  // would truncate accumulated onboarding history that cannot be rebuilt.
  const mirror = onboardingMirrorFor("onboarding_stage_reached", {
    completedStages: ["goal", 7, "***"],
    stage: "notifications",
  });

  assert.equal("completedStages" in mirror, false);
  assert.equal(mirror.currentStage, "notifications");
  assert.equal(mirror.status, "in_progress");
  assert.equal(mirror.lastUpdatedAt, now);
  assert.equal(mirror.startedAt, now);
});

test("a non-array completedStages leaves the mirror alone", () => {
  const mirror = onboardingMirrorFor("onboarding_stage_reached", {
    completedStages: "goal",
    stage: "notifications",
  });

  assert.equal("completedStages" in mirror, false);
  assert.equal(mirror.currentStage, "notifications");
});

test("an oversized completedStages leaves the mirror alone", () => {
  const mirror = onboardingMirrorFor("onboarding_stage_reached", {
    completedStages: Array.from({length: 30}, (_, i) => `stage_${i}`),
    stage: "notifications",
  });

  assert.equal("completedStages" in mirror, false);
});

test("onboarding_completed also protects the mirror from a lossy repair", () => {
  const mirror = onboardingMirrorFor("onboarding_completed", {
    completedStages: ["goal", 7],
    currentStage: "done",
  });

  assert.equal("completedStages" in mirror, false);
  assert.equal(mirror.currentStage, "done");
  assert.equal(mirror.status, "completed");
  assert.equal(mirror.completedAt, now);
});

test("a normalized-only completedStages still writes the mirror", () => {
  // Nothing was lost, so suppressing the write would throw away real progress.
  const mirror = onboardingMirrorFor("onboarding_stage_reached", {
    completedStages: ["goal", "firstClimb"],
    stage: "notifications",
  });

  assert.deepEqual(mirror.completedStages, ["goal", "first_climb"]);
});

test("a clean completedStages still writes the mirror", () => {
  const mirror = onboardingMirrorFor("onboarding_completed", {
    completedStages: ["goal", "age"],
    currentStage: "done",
  });

  assert.deepEqual(mirror.completedStages, ["goal", "age"]);
});

test("a normalized note names the entry that needed repair", () => {
  // The note used to render the whole list, so the 120-character bound cut out
  // the one entry the note exists to identify.
  const stages = Array.from({length: 19}, (_, i) => `onboarding_stage_${i}`);
  const event = normalize("onboarding_stage_reached", {
    completedStages: [...stages, "firstClimb"],
    stage: "notifications",
  });
  const note = noteFor(event, "completedStages");

  assert.equal(note.resolution, "normalized");
  assert.equal(note.received, "[\"firstClimb\"]");
  assert.equal(note.resolved, "[\"first_climb\"]");
});

test("a dropped-items note reports what was actually stored", () => {
  const event = normalize("onboarding_stage_reached", {
    completedStages: ["goal", 7, "***"],
    stage: "notifications",
  });
  const note = noteFor(event, "completedStages");

  assert.equal(note.resolution, "items_dropped");
  assert.equal(note.resolved, "[\"goal\"]");
});

test("a truncation note reports the count that was actually stored", () => {
  // Every entry coerces to the same key, so dedupe shrinks the stored list far
  // below the bound. Reporting the bound here would be a lie.
  const event = normalize("onboarding_stage_reached", {
    completedStages: Array.from({length: 5_000}, () => "Not A Key !!!"),
    stage: "notifications",
  });
  const truncated = event.fieldNotes.find(
    (note) => note.resolution === "truncated"
  );

  assert.equal(truncated?.received, "5000 entries");
  assert.equal(truncated?.resolved, "1 entry");
});
