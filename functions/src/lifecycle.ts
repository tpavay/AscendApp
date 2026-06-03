import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

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

interface NormalizedEvent {
  eventDocId: string;
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

  await firestore.runTransaction(async (transaction) => {
    const [stateSnapshot, eventSnapshot] = await Promise.all([
      transaction.get(stateRef),
      transaction.get(eventRef),
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
      lastReceivedAt: now,
      payload: event.payload,
      receivedCount,
      schemaVersion: 1,
      source: "ios_app",
      type: event.type,
      uid,
      updatedAt: now,
    });

    if (event.type == "communication_preferences_updated") {
      const currentPreferences = currentState.communicationPreferences;
      const preferences = mergePlainObjects(
        isPlainObject(currentPreferences) ? currentPreferences : {},
        {
          ...event.payload,
          schemaVersion: 1,
          updatedAt: now,
        }
      );
      if (!preferences.createdAt) {
        preferences.createdAt = now;
      }
      transaction.set(preferencesRef, preferences);
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

  case "apple_health_integration_changed":
    return {
      integrations: {
        appleHealth: {
          autoImportEnabled: event.payload.autoImportEnabled,
          lastCheckedAt: now,
          status: event.payload.status,
        },
      },
    };

  case "communication_preferences_updated":
    return {
      communicationPreferences: event.payload,
    };
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
  return {
    eventDocId: "app_store_review_requested_v1",
    payload: {
      reason: optionalLifecycleKey(payload.reason, "reason") ?? "unknown",
    },
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
  const stage = requiredLifecycleKey(payload.stage, "stage");
  const completedStages = optionalLifecycleKeyArray(
    payload.completedStages,
    "completedStages"
  ) ?? [];

  return {
    eventDocId: "onboarding_stage_reached_v1",
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
  const currentStage = optionalLifecycleKey(
    payload.currentStage,
    "currentStage"
  ) ?? "unknown";
  const completedStages = optionalLifecycleKeyArray(
    payload.completedStages,
    "completedStages"
  ) ?? [];

  return {
    eventDocId: "onboarding_completed_v1",
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

  const reason = optionalLifecycleKey(payload.reason, "reason");

  return {
    eventDocId: `${type}_${placement}_v1`,
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
  if (typeof autoImportEnabled !== "boolean") {
    throw invalidArgument("Apple Health auto import state must be boolean.");
  }

  return {
    eventDocId: "apple_health_integration_changed_v1",
    payload: {autoImportEnabled, status},
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

  return {
    eventDocId: "communication_preferences_updated_v1",
    payload: normalized,
    type: "communication_preferences_updated",
  };
}

/**
 * Requires a small lifecycle key string.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name for error reporting.
 * @return {string} Validated key.
 */
function requiredLifecycleKey(value: unknown, field: string): string {
  const key = optionalLifecycleKey(value, field);
  if (!key) {
    throw invalidArgument(`${field} must be a lifecycle key.`);
  }
  return key;
}

/**
 * Validates an optional small lifecycle key string.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name for error reporting.
 * @return {string | undefined} Validated key.
 */
function optionalLifecycleKey(
  value: unknown,
  field: string
): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string" || !keyPattern.test(value)) {
    throw invalidArgument(`${field} must be a lifecycle key.`);
  }
  return value;
}

/**
 * Validates an optional lifecycle key array.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name for error reporting.
 * @return {string[] | undefined} Validated array.
 */
function optionalLifecycleKeyArray(
  value: unknown,
  field: string
): string[] | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (!Array.isArray(value) || value.length > 20) {
    throw invalidArgument(`${field} must be a small lifecycle key array.`);
  }

  return Array.from(new Set(value.map((item) => {
    if (typeof item !== "string" || !keyPattern.test(item)) {
      throw invalidArgument(`${field} contains an invalid lifecycle key.`);
    }
    return item;
  })));
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
