import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {
  buildNextCommunicationPreferences,
  isAppLifecycleEmailConsentSource,
} from "./email/preferences";

type LifecycleEventType =
  | "rating_prompt_answered"
  | "app_store_review_requested"
  | "onboarding_stage_reached"
  | "onboarding_completed"
  | "paywall_reached"
  | "paywall_shown"
  | "paywall_dismissed"
  | "notification_permission_observed"
  | "apple_health_integration_changed"
  | "communication_preferences_updated";

type PlainObject = Record<string, unknown>;

/**
 * What the server did with an optional field it could not store as sent.
 *
 * `normalized` kept the climber's meaning in the lifecycle key shape,
 * `fallback` could not and used the documented default instead, and the two
 * array outcomes name which part of a list was unusable.
 */
type LifecycleFieldResolution =
  | "normalized"
  | "fallback"
  | "items_dropped"
  | "truncated";

/**
 * A durable record that an optional field arrived unusable.
 *
 * Every value is a bounded string so the note is safe to write to Firestore
 * verbatim, whatever the client sent.
 */
interface LifecycleFieldNote {
  field: string;
  received: string;
  resolution: LifecycleFieldResolution;
  resolved: string;
}

interface NormalizedEvent {
  eventDocId: string;
  // Empty for a clean call. Always written, never merged, so a later clean
  // call clears the notes an earlier malformed one left on the same document.
  fieldNotes: LifecycleFieldNote[];
  payload: PlainObject;
  type: LifecycleEventType;
}

const lifecycleEventTypes = new Set<LifecycleEventType>([
  "rating_prompt_answered",
  "app_store_review_requested",
  "onboarding_stage_reached",
  "onboarding_completed",
  "paywall_reached",
  "paywall_shown",
  "paywall_dismissed",
  "notification_permission_observed",
  "apple_health_integration_changed",
  "communication_preferences_updated",
]);

const validPaywallPlacements = new Set([
  "onboarding_paywall",
  "app_launch_hard_gate",
  "app_access_gate",
]);

const validNotificationStatuses = new Set([
  "not_determined",
  "denied",
  "authorized",
  "provisional",
  "ephemeral",
  "unknown",
]);

const validAppleHealthStatuses = new Set([
  "unavailable",
  "never_connected",
  "connected",
  "revoked",
  "unknown",
]);

const keyPattern = /^[a-z][a-z0-9_]{0,63}$/;

const maxLifecycleKeyLength = 64;
const maxLifecycleKeyArrayLength = 20;
const maxCoercionInputLength = 512;

// Bounds what an untrusted client value can cost in a note. Long enough to
// identify the offending value in Cloud Logging, short enough that no payload
// can inflate the event document.
const maxNoteValueLength = 120;
const noteTruncationMarker = "...";

/**
 * Records low-volume, client-observed lifecycle state for email automation.
 *
 * Domain achievements such as workouts, First Ascents, and leaderboard wins
 * should remain server-derived from existing workout/leaderboard documents.
 */
export const recordLifecycleEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to record lifecycle events."
    );
  }

  const event = normalizeRequestData(request.data);
  if (event.fieldNotes.length > 0) {
    // A malformed optional field no longer rejects the call, so this warning
    // is the only live signal that a client is sending one. ASCEND-IOS-1 stayed
    // invisible for two months precisely because nothing said so out loud.
    logger.warn("Lifecycle event carried unusable optional fields.", {
      eventDocId: event.eventDocId,
      fieldNotes: event.fieldNotes,
      type: event.type,
      uid,
    });
  }

  const firestore = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const userRef = firestore.collection("users").doc(uid);
  const stateRef = userRef.collection("lifecycle").doc("state");
  const eventRef = userRef
    .collection("lifecycle_events")
    .doc(event.eventDocId);
  const preferencesRef = userRef
    .collection("communication_preferences")
    .doc("current");

  const updatesPreferences = event.type === "communication_preferences_updated";

  await firestore.runTransaction(async (transaction) => {
    // Firestore requires every read before the first write. The preferences
    // document is only read for the event that rewrites it.
    const [stateSnapshot, eventSnapshot, preferencesSnapshot] =
      await Promise.all([
        transaction.get(stateRef),
        transaction.get(eventRef),
        updatesPreferences ? transaction.get(preferencesRef) : null,
      ]);

    const currentState = stateSnapshot.exists ?
      stateSnapshot.data() as PlainObject :
      {};
    const currentEvent = eventSnapshot.exists ?
      eventSnapshot.data() as PlainObject :
      {};
    const receivedCount = typeof currentEvent.receivedCount === "number" ?
      currentEvent.receivedCount + 1 :
      1;

    const nextState = mergePlainObjects(currentState, {
      ...statePatchForEvent(event, currentState, now),
      schemaVersion: 1,
      updatedAt: now,
    });
    if (!nextState.createdAt) {
      nextState.createdAt = now;
    }

    transaction.set(stateRef, nextState);
    transaction.set(eventRef, {
      createdAt: currentEvent.createdAt ?? now,
      eventDocId: event.eventDocId,
      // The event document is the one home for these notes: the lifecycle
      // state mirror holds what the server decided to use, not what it had to
      // repair to get there.
      fieldNotes: event.fieldNotes,
      lastReceivedAt: now,
      payload: event.payload,
      receivedCount,
      schemaVersion: 1,
      source: "ios_app",
      type: event.type,
      uid,
      updatedAt: now,
    });

    if (updatesPreferences) {
      const existingPreferences = preferencesSnapshot?.exists ?
        preferencesSnapshot.data() as PlainObject :
        {};
      transaction.set(
        preferencesRef,
        buildNextCommunicationPreferences(
          existingPreferences ?? {},
          event.payload,
          now
        ),
        // Merge so preferences owned by other writers, notably the push
        // preference from updatePushNotificationPreferences, survive an
        // email preference change.
        {merge: true}
      );
    }
  });

  return {
    eventDocId: event.eventDocId,
    ok: true,
  };
});

/**
 * Normalizes untrusted callable input into a server-owned event document.
 * @param {unknown} data Callable request data.
 * @return {NormalizedEvent} Validated lifecycle event.
 */
function normalizeRequestData(data: unknown): NormalizedEvent {
  if (!isPlainObject(data)) {
    throw invalidArgument("Lifecycle event payload must be an object.");
  }

  const type = data.type;
  if (
    typeof type !== "string" ||
    !lifecycleEventTypes.has(type as LifecycleEventType)
  ) {
    throw invalidArgument("Unsupported lifecycle event type.");
  }

  const payload = data.payload;
  if (!isPlainObject(payload)) {
    throw invalidArgument("Lifecycle event payload must include payload.");
  }

  switch (type as LifecycleEventType) {
  case "rating_prompt_answered":
    return normalizeRatingPromptAnswered(payload);
  case "app_store_review_requested":
    return normalizeAppStoreReviewRequested(payload);
  case "onboarding_stage_reached":
    return normalizeOnboardingStageReached(payload);
  case "onboarding_completed":
    return normalizeOnboardingCompleted(payload);
  case "paywall_reached":
  case "paywall_shown":
  case "paywall_dismissed":
    return normalizePaywallEvent(type as LifecycleEventType, payload);
  case "notification_permission_observed":
    return normalizeNotificationPermissionObserved(payload);
  case "apple_health_integration_changed":
    return normalizeAppleHealthIntegrationChanged(payload);
  case "communication_preferences_updated":
    return normalizeCommunicationPreferencesUpdated(payload);
  }
}

/**
 * Builds the user lifecycle state patch for a normalized event.
 * @param {NormalizedEvent} event Validated lifecycle event.
 * @param {PlainObject} currentState Current lifecycle state document.
 * @param {admin.firestore.Timestamp} now Server timestamp for this write.
 * @return {PlainObject} State patch.
 */
function statePatchForEvent(
  event: NormalizedEvent,
  currentState: PlainObject,
  now: admin.firestore.Timestamp
): PlainObject {
  switch (event.type) {
  case "rating_prompt_answered":
    return {
      ratingPrompt: {
        enjoymentResponse: event.payload.response,
        respondedAt: now,
      },
    };

  case "app_store_review_requested":
    return {
      ratingPrompt: {
        reviewRequestedAt: now,
      },
    };

  case "onboarding_stage_reached": {
    const currentOnboarding = currentState.onboarding;
    const startedAt = isPlainObject(currentOnboarding) &&
      currentOnboarding.startedAt ?
      currentOnboarding.startedAt :
      now;
    return {
      onboarding: {
        completedStages: event.payload.completedStages,
        currentStage: event.payload.stage,
        lastUpdatedAt: now,
        startedAt,
        status: "in_progress",
      },
    };
  }

  case "onboarding_completed": {
    const currentOnboarding = currentState.onboarding;
    const startedAt = isPlainObject(currentOnboarding) &&
      currentOnboarding.startedAt ?
      currentOnboarding.startedAt :
      now;
    return {
      onboarding: {
        completedAt: now,
        completedStages: event.payload.completedStages,
        currentStage: event.payload.currentStage,
        lastUpdatedAt: now,
        startedAt,
        status: "completed",
      },
    };
  }

  case "paywall_reached":
  case "paywall_shown":
  case "paywall_dismissed":
    return {
      paywall: {
        [event.payload.placement as string]: {
          lastEventAt: now,
          lastEventType: event.type,
          placement: event.payload.placement,
          reason: event.payload.reason ?? null,
          status: paywallStatusForEvent(event.type),
        },
      },
    };

  case "notification_permission_observed":
    return {
      permissions: {
        notifications: {
          lastCheckedAt: now,
          status: event.payload.status,
        },
      },
    };

  case "apple_health_integration_changed": {
    const appleHealth: PlainObject = {
      lastCheckedAt: now,
      status: event.payload.status,
    };
    // Omitted, never written as undefined (Firestore rejects that) and never
    // nulled: a value an older binary already mirrored stays untouched, so a
    // client that no longer knows about auto-import cannot erase it.
    if (event.payload.autoImportEnabled !== undefined) {
      appleHealth.autoImportEnabled = event.payload.autoImportEnabled;
    }
    return {integrations: {appleHealth}};
  }

  case "communication_preferences_updated":
    // No mirror here: communication_preferences/current is the only source of
    // truth, and unsubscribeFromEmails writes it without touching this state
    // document, so a copy here would go stale.
    return {};
  }
}

/**
 * Converts an event type to the latest paywall state.
 * @param {LifecycleEventType} type Validated lifecycle event type.
 * @return {string} Paywall status value.
 */
function paywallStatusForEvent(type: LifecycleEventType): string {
  switch (type) {
  case "paywall_reached":
    return "reached";
  case "paywall_shown":
    return "shown";
  case "paywall_dismissed":
    return "dismissed";
  default:
    return "unknown";
  }
}

/**
 * Validates the rating sentiment answer.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizeRatingPromptAnswered(payload: PlainObject): NormalizedEvent {
  const response = payload.response;
  if (response !== "yes" && response !== "no") {
    throw invalidArgument("Rating prompt response must be yes or no.");
  }

  return {
    eventDocId: "rating_prompt_answered_v1",
    fieldNotes: [],
    payload: {response},
    type: "rating_prompt_answered",
  };
}

/**
 * Validates the native App Store review request event.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizeAppStoreReviewRequested(
  payload: PlainObject
): NormalizedEvent {
  const fieldNotes: LifecycleFieldNote[] = [];
  const reason = optionalLifecycleKey(
    payload.reason,
    "reason",
    fieldNotes,
    "unknown"
  ) ?? "unknown";

  return {
    eventDocId: "app_store_review_requested_v1",
    fieldNotes,
    payload: {reason},
    type: "app_store_review_requested",
  };
}

/**
 * Validates an onboarding stage observation.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizeOnboardingStageReached(
  payload: PlainObject
): NormalizedEvent {
  const fieldNotes: LifecycleFieldNote[] = [];
  const stage = requiredLifecycleKey(payload.stage, "stage");
  const completedStages = optionalLifecycleKeyArray(
    payload.completedStages,
    "completedStages",
    fieldNotes
  ) ?? [];

  return {
    eventDocId: "onboarding_stage_reached_v1",
    fieldNotes,
    payload: {completedStages, stage},
    type: "onboarding_stage_reached",
  };
}

/**
 * Validates onboarding completion.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizeOnboardingCompleted(payload: PlainObject): NormalizedEvent {
  const fieldNotes: LifecycleFieldNote[] = [];
  const currentStage = optionalLifecycleKey(
    payload.currentStage,
    "currentStage",
    fieldNotes,
    "unknown"
  ) ?? "unknown";
  const completedStages = optionalLifecycleKeyArray(
    payload.completedStages,
    "completedStages",
    fieldNotes
  ) ?? [];

  return {
    eventDocId: "onboarding_completed_v1",
    fieldNotes,
    payload: {completedStages, currentStage},
    type: "onboarding_completed",
  };
}

/**
 * Validates paywall lifecycle events.
 * @param {LifecycleEventType} type Event type.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizePaywallEvent(
  type: LifecycleEventType,
  payload: PlainObject
): NormalizedEvent {
  const placement = payload.placement;
  if (
    typeof placement !== "string" ||
    !validPaywallPlacements.has(placement)
  ) {
    throw invalidArgument("Unsupported paywall placement.");
  }

  const fieldNotes: LifecycleFieldNote[] = [];
  const reason = optionalLifecycleKey(
    payload.reason,
    "reason",
    fieldNotes,
    "omitted"
  );

  return {
    eventDocId: `${type}_${placement}_v1`,
    fieldNotes,
    payload: {
      placement,
      ...(reason ? {reason} : {}),
    },
    type,
  };
}

/**
 * Validates a notification permission observation.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizeNotificationPermissionObserved(
  payload: PlainObject
): NormalizedEvent {
  const status = payload.status;
  if (
    typeof status !== "string" ||
    !validNotificationStatuses.has(status)
  ) {
    throw invalidArgument("Unsupported notification permission status.");
  }

  return {
    eventDocId: "notification_permission_observed_v1",
    fieldNotes: [],
    payload: {status},
    type: "notification_permission_observed",
  };
}

/**
 * Validates Apple Health integration state.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizeAppleHealthIntegrationChanged(
  payload: PlainObject
): NormalizedEvent {
  const status = payload.status;
  const autoImportEnabled = payload.autoImportEnabled;
  if (
    typeof status !== "string" ||
    !validAppleHealthStatuses.has(status)
  ) {
    throw invalidArgument("Unsupported Apple Health integration status.");
  }
  // Optional, not defaulted: Apple Health auto-import was removed from the app
  // on 2026-08-08, so current builds omit this field while released binaries
  // still send it, and the backend has to satisfy both contracts at once
  // (docs/backend-contract-compatibility.md). Absent means "this client has no
  // such concept", which is not the same claim as auto-import being off.
  const fieldNotes: LifecycleFieldNote[] = [];
  const usable = typeof autoImportEnabled === "boolean";
  if (!usable && autoImportEnabled !== undefined) {
    // Treated as absent rather than fatal, for the same reason as `reason`:
    // the connection status is the point of this event and must not be lost to
    // a companion field the mirror is allowed to go without.
    fieldNotes.push({
      field: "autoImportEnabled",
      received: describeValue(autoImportEnabled),
      resolution: "fallback",
      resolved: "omitted",
    });
  }

  return {
    eventDocId: "apple_health_integration_changed_v1",
    fieldNotes,
    payload: usable ? {autoImportEnabled, status} : {status},
    type: "apple_health_integration_changed",
  };
}

/**
 * Validates email communication preferences.
 * @param {PlainObject} payload Raw payload.
 * @return {NormalizedEvent} Normalized event.
 */
function normalizeCommunicationPreferencesUpdated(
  payload: PlainObject
): NormalizedEvent {
  const normalized: PlainObject = {};
  for (const key of [
    "lifecycleEmailsEnabled",
    "productUpdatesEnabled",
    "climbDropEmailsEnabled",
  ]) {
    const value = payload[key];
    if (typeof value === "boolean") {
      normalized[key] = value;
    }
  }

  if (Object.keys(normalized).length === 0) {
    throw invalidArgument(
      "At least one communication preference must be provided."
    );
  }

  // Where the climber answered. A source with no decision behind it records
  // nothing, and a decision with no source inherits the last one written: a
  // consent record is only evidence while both halves arrive together.
  const fieldNotes: LifecycleFieldNote[] = [];
  const source = payload.lifecycleEmailsSource;
  const isConsentDecision =
    typeof normalized.lifecycleEmailsEnabled === "boolean";
  if (isConsentDecision) {
    // Required here, so it stays loud: a consent decision with an unrecognized
    // source is not a consent record, and storing one anyway would forge the
    // evidence rather than lose it.
    if (!isAppLifecycleEmailConsentSource(source)) {
      throw invalidArgument("Unsupported lifecycle email consent source.");
    }
    normalized.lifecycleEmailsSource = source;
  } else if (source !== undefined && source !== null) {
    // Optional here, so it is dropped rather than fatal. A source with no
    // decision behind it was already going to be discarded; discarding the
    // preferences the climber did change alongside it was the defect.
    fieldNotes.push({
      field: "lifecycleEmailsSource",
      received: describeValue(source),
      resolution: "fallback",
      resolved: "omitted",
    });
  }

  return {
    eventDocId: "communication_preferences_updated_v1",
    fieldNotes,
    payload: normalized,
    type: "communication_preferences_updated",
  };
}

/**
 * Requires a small lifecycle key string.
 *
 * Required keys are never repaired. They identify the event, so a malformed
 * one means the caller is describing something the server cannot place, and
 * accepting a guess would be worse than refusing the call.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name for error reporting.
 * @return {string} Validated key.
 */
function requiredLifecycleKey(value: unknown, field: string): string {
  if (typeof value !== "string" || !keyPattern.test(value)) {
    throw invalidArgument(`${field} must be a lifecycle key.`);
  }
  return value;
}

/**
 * Resolves an optional lifecycle key without ever rejecting the whole event.
 *
 * An optional field the server is happy to do without may not decide whether
 * the surrounding lifecycle event survives (ASCEND-IOS-1: every paywall
 * dismissal was discarded because `String(describing:)` prints a Swift enum as
 * `manualClose`). A value that still carries meaning is normalized into the key
 * shape, one that does not falls back the way an absent value already does, and
 * either repair is recorded so the bad input stays visible.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name for reporting.
 * @param {LifecycleFieldNote[]} notes Collector for repairs made.
 * @param {string} fallbackLabel What the caller uses when there is no key.
 * @return {string | undefined} Usable key, or undefined to fall back.
 */
function optionalLifecycleKey(
  value: unknown,
  field: string,
  notes: LifecycleFieldNote[],
  fallbackLabel: string
): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === "string" && keyPattern.test(value)) {
    return value;
  }

  const normalized = coerceLifecycleKey(value);
  if (normalized) {
    notes.push({
      field,
      received: describeValue(value),
      resolution: "normalized",
      resolved: normalized,
    });
    return normalized;
  }

  notes.push({
    field,
    received: describeValue(value),
    resolution: "fallback",
    resolved: fallbackLabel,
  });
  return undefined;
}

/**
 * Resolves an optional lifecycle key array without rejecting the whole event.
 *
 * Same contract as {@link optionalLifecycleKey}, applied per entry: usable
 * entries are kept, unusable ones are dropped, and the list is bounded rather
 * than refused for being long.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name for reporting.
 * @param {LifecycleFieldNote[]} notes Collector for repairs made.
 * @return {string[] | undefined} Usable keys, or undefined to fall back.
 */
function optionalLifecycleKeyArray(
  value: unknown,
  field: string,
  notes: LifecycleFieldNote[]
): string[] | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (!Array.isArray(value)) {
    notes.push({
      field,
      received: describeValue(value),
      resolution: "fallback",
      resolved: "[]",
    });
    return undefined;
  }

  // Bounded before anything iterates it. The old code refused an oversized
  // array outright, so repairing entry by entry over the raw list would hand a
  // caller an unbounded amount of server work for one request.
  const bounded = value.slice(0, maxLifecycleKeyArrayLength);
  if (value.length > maxLifecycleKeyArrayLength) {
    notes.push({
      field,
      received: `${value.length} entries`,
      resolution: "truncated",
      resolved: `${maxLifecycleKeyArrayLength} entries`,
    });
  }

  const keys: string[] = [];
  const normalized: string[] = [];
  const dropped: unknown[] = [];

  for (const item of bounded) {
    if (typeof item === "string" && keyPattern.test(item)) {
      keys.push(item);
      continue;
    }
    const coerced = coerceLifecycleKey(item);
    if (coerced) {
      normalized.push(coerced);
      keys.push(coerced);
      continue;
    }
    dropped.push(item);
  }

  if (normalized.length > 0) {
    notes.push({
      field,
      received: describeValue(bounded),
      resolution: "normalized",
      resolved: describeValue(normalized),
    });
  }
  if (dropped.length > 0) {
    notes.push({
      field,
      received: describeValue(dropped),
      resolution: "items_dropped",
      resolved: "[]",
    });
  }

  return Array.from(new Set(keys));
}

/**
 * Coerces an arbitrary client value into the lifecycle key shape.
 *
 * Word boundaries survive the trip, so a Swift enum printed as `manualClose`
 * lands as `manual_close` rather than being thrown away.
 * @param {unknown} value Candidate value.
 * @return {string | undefined} A valid lifecycle key, or undefined.
 */
function coerceLifecycleKey(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  // Cut before the regex chain runs. Nothing past this prefix can contribute
  // to a key that is itself capped at 64 characters, and a caller does not get
  // to pay the server for scanning a megabyte of it.
  const key = value
    .slice(0, maxCoercionInputLength)
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^[^a-z]+/, "")
    .slice(0, maxLifecycleKeyLength)
    .replace(/_+$/g, "");

  return keyPattern.test(key) ? key : undefined;
}

/**
 * Renders an untrusted value as a bounded string safe to store and log.
 * @param {unknown} value Candidate value.
 * @return {string} Bounded rendering of the value.
 */
function describeValue(value: unknown): string {
  if (typeof value === "string") {
    return truncateForNote(value);
  }
  if (value === undefined) {
    return "undefined";
  }
  try {
    return truncateForNote(JSON.stringify(value) ?? String(value));
  } catch {
    return truncateForNote(String(value));
  }
}

/**
 * Bounds a rendered value so no client can inflate an event document.
 *
 * The marker is inside the bound, so a note value is never longer than
 * `maxNoteValueLength` whatever arrived.
 * @param {string} value Rendered value.
 * @return {string} Value within the note length bound.
 */
function truncateForNote(value: string): string {
  if (value.length <= maxNoteValueLength) {
    return value;
  }
  const kept = maxNoteValueLength - noteTruncationMarker.length;
  return `${value.slice(0, kept)}${noteTruncationMarker}`;
}

/**
 * Deep merges plain objects while preserving Firestore sentinel-like objects.
 * @param {PlainObject} target Existing object.
 * @param {PlainObject} patch Patch object.
 * @return {PlainObject} Merged object.
 */
function mergePlainObjects(
  target: PlainObject,
  patch: PlainObject
): PlainObject {
  const result: PlainObject = {...target};

  for (const [key, value] of Object.entries(patch)) {
    const current = result[key];
    if (isPlainObject(current) && isPlainObject(value)) {
      result[key] = mergePlainObjects(current, value);
    } else {
      result[key] = value;
    }
  }

  return result;
}

/**
 * Determines whether a value is a plain JSON-ish object.
 * @param {unknown} value Candidate value.
 * @return {boolean} True when the value is a plain object.
 */
function isPlainObject(value: unknown): value is PlainObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  return !(value instanceof admin.firestore.Timestamp);
}

/**
 * Builds a callable invalid-argument error.
 * @param {string} message Error message.
 * @return {HttpsError} Callable error.
 */
function invalidArgument(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}

export const lifecycleTestHooks = {
  normalizeRequestData,
  statePatchForEvent,
};
