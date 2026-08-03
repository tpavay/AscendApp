import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {createHash} from "crypto";

type PlainObject = Record<string, unknown>;

const validAuthorizationStatuses = new Set([
  "not_determined",
  "denied",
  "authorized",
  "provisional",
  "ephemeral",
  "unknown",
]);

const validPlatforms = new Set(["ios"]);
const validAudienceTypes = new Set(["all_opted_in", "user"]);
const fcmInvalidTokenCodes = new Set([
  "messaging/invalid-argument",
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

/**
 * Registers the current signed-in user's push token.
 */
export const registerPushDevice = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const payload = normalizeRegisterPushDevicePayload(request.data);
  const now = admin.firestore.Timestamp.now();
  const tokenHash = hashToken(payload.fcmToken);
  const firestore = admin.firestore();
  const deviceRef = firestore.collection("notification_devices").doc(tokenHash);
  const userDeviceRef = firestore
    .collection("users")
    .doc(uid)
    .collection("notification_devices")
    .doc(tokenHash);
  const preferencesRef = firestore
    .collection("users")
    .doc(uid)
    .collection("communication_preferences")
    .doc("current");

  await runContendedTransaction(firestore, async (transaction) => {
    const [deviceSnapshot, preferencesSnapshot] = await Promise.all([
      transaction.get(deviceRef),
      transaction.get(preferencesRef),
    ]);
    const existing = deviceSnapshot.exists ? deviceSnapshot.data() : {};
    const preferences = preferencesSnapshot.exists ?
      preferencesSnapshot.data() ?? {} :
      {};
    const existingUid = typeof existing?.uid === "string" ?
      existing.uid :
      null;
    const climbDropPushEnabled =
      typeof preferences.pushClimbDropsEnabled === "boolean" ?
        preferences.pushClimbDropsEnabled :
        payload.climbDropPushEnabled;
    const createdAt = existing?.createdAt ?? now;

    if (existingUid && existingUid !== uid) {
      transaction.set(
        firestore
          .collection("users")
          .doc(existingUid)
          .collection("notification_devices")
          .doc(tokenHash),
        {
          active: false,
          disabledAt: now,
          updatedAt: now,
        },
        {merge: true}
      );
    }

    transaction.set(deviceRef, {
      active: true,
      appVersion: payload.appVersion,
      authorizationStatus: payload.authorizationStatus,
      buildNumber: payload.buildNumber,
      bundleId: payload.bundleId,
      climbDropPushEnabled,
      createdAt,
      disabledAt: null,
      environment: process.env.GCLOUD_PROJECT ?? "unknown",
      fcmToken: payload.fcmToken,
      lastSeenAt: now,
      locale: payload.locale,
      platform: payload.platform,
      schemaVersion: 1,
      timeZone: payload.timeZone,
      tokenHash,
      uid,
      updatedAt: now,
    });

    transaction.set(userDeviceRef, {
      active: true,
      appVersion: payload.appVersion,
      authorizationStatus: payload.authorizationStatus,
      buildNumber: payload.buildNumber,
      bundleId: payload.bundleId,
      climbDropPushEnabled,
      createdAt,
      disabledAt: null,
      environment: process.env.GCLOUD_PROJECT ?? "unknown",
      lastSeenAt: now,
      locale: payload.locale,
      platform: payload.platform,
      schemaVersion: 1,
      timeZone: payload.timeZone,
      tokenHash,
      updatedAt: now,
    });
  });

  return {ok: true, tokenHash};
});

/**
 * Updates the signed-in user's push notification preferences.
 */
export const updatePushNotificationPreferences = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const climbDropPushEnabled = requiredBoolean(
    asPlainObject(request.data).climbDropPushEnabled,
    "climbDropPushEnabled"
  );
  const now = admin.firestore.Timestamp.now();
  const firestore = admin.firestore();
  const preferencesRef = firestore
    .collection("users")
    .doc(uid)
    .collection("communication_preferences")
    .doc("current");

  await runContendedTransaction(firestore, async (transaction) => {
    const snapshot = await transaction.get(preferencesRef);
    const existing = snapshot.exists ? snapshot.data() ?? {} : {};
    transaction.set(preferencesRef, {
      ...existing,
      createdAt: existing.createdAt ?? now,
      pushClimbDropsEnabled: climbDropPushEnabled,
      schemaVersion: 1,
      updatedAt: now,
    });
  });

  await updateActiveDevicePreference(uid, climbDropPushEnabled, now);

  return {ok: true};
});

/**
 * Deactivates the current push token, or every active token for the user when
 * the current token is unavailable.
 */
export const unregisterPushDevice = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const data = asPlainObject(request.data);
  const fcmToken = optionalString(data.fcmToken, "fcmToken", 4096);
  const now = admin.firestore.Timestamp.now();

  if (fcmToken) {
    await deactivateToken(
      admin.firestore(),
      uid,
      hashToken(fcmToken),
      now
    );
  } else {
    await deactivateActiveUserTokens(uid, now);
  }

  return {ok: true};
});

/**
 * Sends, or dry-runs, a climb-drop push campaign.
 */
export const sendClimbDropNotification = onCall(async (request) => {
  requireAdmin(request.auth?.token);
  const payload = normalizeSendClimbDropPayload(request.data);
  const firestore = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const campaignRef = firestore.collection("notification_campaigns").doc();
  const tokens = await loadClimbDropTokens(payload.audience, payload.userId);

  if (payload.dryRun) {
    return {
      dryRun: true,
      eligibleDeviceCount: tokens.length,
      ok: true,
    };
  }

  await campaignRef.set({
    audience: payload.audience,
    body: payload.body,
    climbId: payload.climbId,
    createdAt: now,
    failedCount: 0,
    schemaVersion: 1,
    sentCount: 0,
    status: "sending",
    title: payload.title,
    type: "climb_drop",
    updatedAt: now,
    userId: payload.userId ?? null,
  });

  const result = await sendClimbDropBatches({
    body: payload.body,
    campaignId: campaignRef.id,
    climbId: payload.climbId,
    title: payload.title,
    tokens,
  });

  await campaignRef.set({
    failedCount: result.failedCount,
    invalidTokenCount: result.invalidTokenHashes.length,
    sentAt: admin.firestore.Timestamp.now(),
    sentCount: result.sentCount,
    status: result.failedCount > 0 ? "sent_with_failures" : "sent",
    updatedAt: admin.firestore.Timestamp.now(),
  }, {merge: true});

  await deactivateInvalidTokens(result.invalidTokenHashes);

  return {
    campaignId: campaignRef.id,
    eligibleDeviceCount: tokens.length,
    failedCount: result.failedCount,
    invalidTokenCount: result.invalidTokenHashes.length,
    ok: true,
    sentCount: result.sentCount,
  };
});

/**
 * Normalizes the register-device callable payload.
 * @param {unknown} data Raw callable payload.
 * @return {object} Validated register-device payload.
 */
function normalizeRegisterPushDevicePayload(data: unknown) {
  const payload = asPlainObject(data);
  const platform = requiredString(payload.platform, "platform", 24);
  if (!validPlatforms.has(platform)) {
    throw invalidArgument("Unsupported push platform.");
  }

  const authorizationStatus = requiredString(
    payload.authorizationStatus,
    "authorizationStatus",
    32
  );
  if (!validAuthorizationStatuses.has(authorizationStatus)) {
    throw invalidArgument("Unsupported notification authorization status.");
  }

  return {
    appVersion: optionalString(payload.appVersion, "appVersion", 32) ?? "",
    authorizationStatus,
    buildNumber: optionalString(payload.buildNumber, "buildNumber", 32) ?? "",
    bundleId: optionalString(payload.bundleId, "bundleId", 160) ?? "",
    climbDropPushEnabled: requiredBoolean(
      payload.climbDropPushEnabled,
      "climbDropPushEnabled"
    ),
    fcmToken: requiredString(payload.fcmToken, "fcmToken", 4096),
    locale: optionalString(payload.locale, "locale", 64) ?? "",
    platform,
    timeZone: optionalString(payload.timeZone, "timeZone", 80) ?? "",
  };
}

/**
 * Normalizes the send-campaign callable payload.
 * @param {unknown} data Raw callable payload.
 * @return {object} Validated send-campaign payload.
 */
function normalizeSendClimbDropPayload(data: unknown) {
  const payload = asPlainObject(data);
  const audience = optionalString(payload.audience, "audience", 32) ??
    "all_opted_in";
  if (!validAudienceTypes.has(audience)) {
    throw invalidArgument("Unsupported climb-drop audience.");
  }

  const userId = optionalString(payload.userId, "userId", 128) ?? undefined;
  if (audience === "user" && !userId) {
    throw invalidArgument("A user audience requires userId.");
  }

  return {
    audience,
    body: requiredString(payload.body, "body", 180),
    climbId: requiredString(payload.climbId, "climbId", 160),
    dryRun: optionalBoolean(payload.dryRun, "dryRun") ?? false,
    title: requiredString(payload.title, "title", 80),
    userId,
  };
}

/**
 * Sends the FCM campaign in chunks of 500 tokens.
 * @param {object} params Send parameters.
 * @return {Promise<object>} Send counters and invalid token hashes.
 */
async function sendClimbDropBatches(params: {
  body: string;
  campaignId: string;
  climbId: string;
  title: string;
  tokens: Array<{fcmToken: string; tokenHash: string}>;
}) {
  let sentCount = 0;
  let failedCount = 0;
  const invalidTokenHashes: string[] = [];

  for (const chunk of chunkArray(params.tokens, 500)) {
    const response = await admin.messaging().sendEachForMulticast({
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
      data: {
        campaignId: params.campaignId,
        climbId: params.climbId,
        route: "climb_detail",
        type: "climb_drop",
      },
      notification: {
        body: params.body,
        title: params.title,
      },
      tokens: chunk.map((device) => device.fcmToken),
    });

    sentCount += response.successCount;
    failedCount += response.failureCount;

    response.responses.forEach((sendResponse, index) => {
      const errorCode = sendResponse.error?.code;
      if (errorCode && fcmInvalidTokenCodes.has(errorCode)) {
        invalidTokenHashes.push(chunk[index].tokenHash);
      }
    });
  }

  return {failedCount, invalidTokenHashes, sentCount};
}

/**
 * Loads eligible tokens for a climb-drop audience.
 * @param {string} audience Audience key.
 * @param {string=} userId Optional target user ID.
 * @return {Promise<Array<object>>} Eligible devices.
 */
async function loadClimbDropTokens(audience: string, userId?: string) {
  let query: FirebaseFirestore.Query = admin.firestore()
    .collection("notification_devices")
    .where("active", "==", true)
    .where("climbDropPushEnabled", "==", true)
    .where("platform", "==", "ios");

  if (audience === "user" && userId) {
    query = query.where("uid", "==", userId);
  }

  const snapshot = await query.get();
  const devices: Array<{fcmToken: string; tokenHash: string}> = [];
  snapshot.forEach((doc) => {
    const data = doc.data();
    if (typeof data.fcmToken === "string" && data.fcmToken.length > 0) {
      devices.push({
        fcmToken: data.fcmToken,
        tokenHash: doc.id,
      });
    }
  });
  return devices;
}

/**
 * Updates active device preference mirrors for a user.
 * @param {string} uid User ID.
 * @param {boolean} climbDropPushEnabled Whether climb-drop pushes are on.
 * @param {admin.firestore.Timestamp} now Server timestamp.
 * @return {Promise<void>} Resolves when mirrors are updated.
 */
async function updateActiveDevicePreference(
  uid: string,
  climbDropPushEnabled: boolean,
  now: admin.firestore.Timestamp
) {
  const firestore = admin.firestore();
  const snapshot = await firestore.collection("notification_devices")
    .where("uid", "==", uid)
    .where("active", "==", true)
    .get();
  const batch = firestore.batch();

  snapshot.forEach((doc) => {
    batch.set(doc.ref, {
      climbDropPushEnabled,
      updatedAt: now,
    }, {merge: true});
    batch.set(
      firestore
        .collection("users")
        .doc(uid)
        .collection("notification_devices")
        .doc(doc.id),
      {
        climbDropPushEnabled,
        updatedAt: now,
      },
      {merge: true}
    );
  });

  if (!snapshot.empty) {
    await batch.commit();
  }
}

/**
 * Deactivates one token for a user.
 *
 * Only existing records are touched. A merging write would otherwise create
 * notification_devices/{tokenHash} for a token that was never registered
 * (push denied, or registration failed), and that document carries no `uid`,
 * so the account-deletion sweep - which queries by `uid` - could never reach
 * it. A record owned by another uid is left alone: the caller only proves it
 * knows a token, not that the token is theirs.
 * @param {admin.firestore.Firestore} firestore Firestore instance.
 * @param {string} uid User ID.
 * @param {string} tokenHash Token hash document ID.
 * @param {admin.firestore.Timestamp} now Server timestamp.
 * @return {Promise<void>} Resolves when token is deactivated.
 */
async function deactivateToken(
  firestore: admin.firestore.Firestore,
  uid: string,
  tokenHash: string,
  now: admin.firestore.Timestamp
) {
  const deviceRef = firestore
    .collection("notification_devices")
    .doc(tokenHash);
  const mirrorRef = firestore
    .collection("users")
    .doc(uid)
    .collection("notification_devices")
    .doc(tokenHash);
  const [deviceSnapshot, mirrorSnapshot] = await Promise.all([
    deviceRef.get(),
    mirrorRef.get(),
  ]);

  if (deviceSnapshot.exists && deviceSnapshot.data()?.uid !== uid) {
    return;
  }

  const deactivation = {
    active: false,
    disabledAt: now,
    updatedAt: now,
  };
  const writes: Promise<unknown>[] = [];

  if (deviceSnapshot.exists) {
    writes.push(deviceRef.set(deactivation, {merge: true}));
  }
  if (mirrorSnapshot.exists) {
    writes.push(mirrorRef.set(deactivation, {merge: true}));
  }

  await Promise.all(writes);
}

/**
 * Deactivates every active token owned by the user.
 * @param {string} uid User ID.
 * @param {admin.firestore.Timestamp} now Server timestamp.
 * @return {Promise<void>} Resolves when tokens are deactivated.
 */
async function deactivateActiveUserTokens(
  uid: string,
  now: admin.firestore.Timestamp
) {
  const firestore = admin.firestore();
  const snapshot = await firestore.collection("notification_devices")
    .where("uid", "==", uid)
    .where("active", "==", true)
    .get();
  await Promise.all(
    snapshot.docs.map((doc) => deactivateToken(firestore, uid, doc.id, now))
  );
}

/**
 * Deactivates invalid tokens returned by FCM.
 * @param {string[]} tokenHashes Invalid token hashes.
 * @return {Promise<void>} Resolves when invalid tokens are deactivated.
 */
async function deactivateInvalidTokens(tokenHashes: string[]) {
  if (tokenHashes.length === 0) {
    return;
  }

  const now = admin.firestore.Timestamp.now();
  const firestore = admin.firestore();
  await Promise.all(tokenHashes.map(async (tokenHash) => {
    const snapshot = await firestore
      .collection("notification_devices")
      .doc(tokenHash)
      .get();
    const uid = snapshot.data()?.uid;
    if (typeof uid !== "string" || uid.length === 0) {
      return;
    }
    await deactivateToken(firestore, uid, tokenHash, now);
  }));
}

const grpcAbortedCode = 10;
const contentionRetryAttempts = 3;

/**
 * Runs a Firestore transaction, retrying cross-transaction contention.
 *
 * Concurrent callable invocations for the same user (the client can fire
 * launch, APNS, and token-refresh syncs close together) contend on the same
 * documents. The SDK does not always classify that ABORTED as transient, so
 * it escapes runTransaction as an unhandled error and reaches the client as
 * INTERNAL. Retry it here, and fail with a typed callable error when the
 * retries are exhausted.
 * @param {admin.firestore.Firestore} firestore Firestore instance.
 * @param {Function} updateFunction Transaction body.
 * @return {Promise<*>} Transaction result.
 */
async function runContendedTransaction<T>(
  firestore: admin.firestore.Firestore,
  updateFunction: (
    transaction: admin.firestore.Transaction
  ) => Promise<T>
): Promise<T> {
  for (let attempt = 1; attempt <= contentionRetryAttempts; attempt++) {
    try {
      return await firestore.runTransaction(updateFunction);
    } catch (error) {
      if (
        !isTransactionContentionError(error) ||
        attempt === contentionRetryAttempts
      ) {
        if (isTransactionContentionError(error)) {
          throw new HttpsError(
            "aborted",
            "Another update is in progress. Retry shortly."
          );
        }
        throw error;
      }
      await delay(50 * 2 ** (attempt - 1) + Math.floor(Math.random() * 50));
    }
  }
  throw new HttpsError("internal", "Transaction retry loop exited early.");
}

/**
 * Detects the gRPC ABORTED contention error surfaced by the Firestore SDK.
 * @param {unknown} error Candidate error.
 * @return {boolean} True when the error is transaction contention.
 */
function isTransactionContentionError(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }
  return (error as {code?: unknown}).code === grpcAbortedCode;
}

/**
 * Waits for a duration.
 * @param {number} milliseconds Delay duration.
 * @return {Promise<void>} Resolves after the delay.
 */
function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

/**
 * Hashes an FCM token for stable Firestore document IDs.
 * @param {string} token FCM registration token.
 * @return {string} SHA-256 token hash.
 */
function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/**
 * Splits an array into chunks.
 * @param {Array<*>} items Items to split.
 * @param {number} size Maximum chunk size.
 * @return {Array<Array<*>>} Chunked items.
 */
function chunkArray<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

/**
 * Requires a signed-in callable user.
 * @param {string|undefined} uid Firebase Auth user ID.
 * @return {string} Signed-in user ID.
 */
function requireUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to use push notifications."
    );
  }
  return uid;
}

/**
 * Requires an admin custom claim for operational sends.
 * @param {admin.auth.DecodedIdToken|undefined} token Firebase Auth token.
 */
function requireAdmin(token: admin.auth.DecodedIdToken | undefined) {
  if (token?.admin === true || token?.internalAdmin === true) {
    return;
  }

  throw new HttpsError(
    "permission-denied",
    "You must be an admin to send notifications."
  );
}

/**
 * Validates an object payload.
 * @param {unknown} data Candidate payload.
 * @return {PlainObject} Plain object payload.
 */
function asPlainObject(data: unknown): PlainObject {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw invalidArgument("Payload must be an object.");
  }
  return data as PlainObject;
}

/**
 * Requires a string field.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name.
 * @param {number} maxLength Maximum string length.
 * @return {string} Validated string.
 */
function requiredString(value: unknown, field: string, maxLength: number) {
  const normalized = optionalString(value, field, maxLength);
  if (!normalized) {
    throw invalidArgument(`${field} is required.`);
  }
  return normalized;
}

/**
 * Validates an optional string field.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name.
 * @param {number} maxLength Maximum string length.
 * @return {string|null} Trimmed string, or null when absent.
 */
function optionalString(value: unknown, field: string, maxLength: number) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw invalidArgument(`${field} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw invalidArgument(`${field} is too long.`);
  }
  return trimmed;
}

/**
 * Requires a boolean field.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name.
 * @return {boolean} Validated boolean.
 */
function requiredBoolean(value: unknown, field: string) {
  const normalized = optionalBoolean(value, field);
  if (normalized === null) {
    throw invalidArgument(`${field} is required.`);
  }
  return normalized;
}

/**
 * Validates an optional boolean field.
 * @param {unknown} value Candidate value.
 * @param {string} field Field name.
 * @return {boolean|null} Boolean, or null when absent.
 */
function optionalBoolean(value: unknown, field: string) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "boolean") {
    throw invalidArgument(`${field} must be a boolean.`);
  }
  return value;
}

/**
 * Builds an invalid argument error.
 * @param {string} message Error message.
 * @return {HttpsError} Callable invalid-argument error.
 */
function invalidArgument(message: string) {
  return new HttpsError("invalid-argument", message);
}

export const pushNotificationTestHooks = {
  chunkArray,
  deactivateToken,
  hashToken,
  normalizeRegisterPushDevicePayload,
  normalizeSendClimbDropPayload,
};
