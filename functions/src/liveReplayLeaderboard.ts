import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  MAX_REPLAY_SPLIT_CHECKPOINTS,
  normalizeReplaySplitSteps,
} from "./liveReplaySplitNormalization.js";

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_COMMUNITY_STATS_COLLECTION = "live_climb_community_stats";
const LIVE_CLIMB_COMMUNITY_GLOBAL_ID = "global";
const LIVE_CLIMB_COMPLETED_USERS_COLLECTION = "completedUsers";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const LIVE_CLIMB_TRACKING_MODE = "live_climb";
const TARGET_REACHED_STOP_REASON = "target_reached";

interface LiveReplayIndexPayload {
  contextKey: string;
  contextType: string;
  contextId: string;
  splitIntervalSeconds: number;
  splitSteps: number[];
  finalDurationSeconds: number;
  finalSteps: number;
  targetStepCount: number | null;
}

interface PublicUserSnapshot {
  displayName: string;
  avatarToken: string;
  photoURL: string | null;
}

/**
 * Publishes saved live-attempt split checkpoints into read-only replay windows.
 */
export const onWorkoutReplaySplitsWritten = onDocumentWritten(
  "users/{userId}/workouts/{workoutId}",
  async (event) => {
    const beforeData = event.data?.before.data() as
      Record<string, unknown> | undefined;
    const afterData = event.data?.after.data() as
      Record<string, unknown> | undefined;
    const userId = event.params.userId;
    const workoutId = event.params.workoutId;
    const beforeClimbPayload = parseLiveClimbReplayPayload(beforeData, {
      requireEligibleParticipation: false,
    });
    const afterClimbPayload = parseLiveClimbReplayPayload(afterData, {
      requireEligibleParticipation: true,
    });

    if (
      !beforeClimbPayload &&
      !afterClimbPayload
    ) {
      return;
    }

    const publicUser = afterClimbPayload ?
      await publicUserSnapshot(userId) :
      null;

    if (beforeClimbPayload) {
      await deleteReplayEntriesForId(beforeClimbPayload, workoutId);
    }

    if (afterClimbPayload && publicUser) {
      await publishReplayEntries(
        afterClimbPayload,
        workoutId,
        userId,
        publicUser
      );
    }

    if (beforeClimbPayload) {
      await deleteReplayEntriesForId(beforeClimbPayload, userId);
      await deleteUserBestAttempt(beforeClimbPayload, userId);
    }

    if (afterClimbPayload) {
      await deleteReplayEntriesForId(afterClimbPayload, userId);
      await deleteUserBestAttempt(afterClimbPayload, userId);
    }

    if (beforeClimbPayload || afterClimbPayload) {
      await updateLiveClimbCommunityStats(userId);
    }
  }
);

/**
 * Converts a completed Live Climb backup into a per-climb replay payload.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @param {{requireEligibleParticipation: boolean}} options Parse options.
 * @return {LiveReplayIndexPayload | null} Parsed replay payload, if valid.
 */
function parseLiveClimbReplayPayload(
  data: Record<string, unknown> | undefined,
  options: {requireEligibleParticipation: boolean}
): LiveReplayIndexPayload | null {
  const parsed = parseReplayPayloadParts(data);
  if (!parsed) {
    return null;
  }

  if (
    options.requireEligibleParticipation &&
    !hasCompletedLiveClimbAttempt(parsed)
  ) {
    return null;
  }

  const climbId = stringValue(parsed.metadata.climbId);
  if (!climbId) {
    return null;
  }

  return replayPayload(
    parsed,
    LIVE_CLIMB_CONTEXT_TYPE,
    climbId
  );
}

interface ParsedReplayPayloadParts {
  metadata: Record<string, unknown>;
  hasEligibleClimbAttempt: boolean;
  splitIntervalSeconds: number;
  splitSteps: number[];
  finalDurationSeconds: number;
  finalSteps: number;
  targetStepCount: number | null;
}

/**
 * Parses source metadata and common replay fields from a private workout.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @return {ParsedReplayPayloadParts | null} Parsed common parts, if valid.
 */
function parseReplayPayloadParts(
  data: Record<string, unknown> | undefined
): ParsedReplayPayloadParts | null {
  if (!data || data.source !== "headphone_motion") {
    return null;
  }

  const sourceMetadata = data.sourceMetadata;
  if (typeof sourceMetadata !== "string") {
    return null;
  }

  let metadata: Record<string, unknown>;
  try {
    metadata = JSON.parse(sourceMetadata) as Record<string, unknown>;
  } catch {
    return null;
  }

  const splitIntervalSeconds = positiveIntegerValue(
    metadata.splitIntervalSeconds
  );
  const splitSteps = integerArrayValue(metadata.splitSteps)
    ?.slice(0, MAX_REPLAY_SPLIT_CHECKPOINTS);
  const finalDurationSeconds = nonNegativeNumberValue(data.durationSeconds);
  const finalSteps = nonNegativeIntegerValue(data.steps);
  const targetStepCount = positiveIntegerValue(
    metadata.climbTargetStepCount
  ) ?? positiveIntegerValue(metadata.targetStepCount);

  if (
    !splitIntervalSeconds ||
    !splitSteps ||
    splitSteps.length === 0 ||
    finalDurationSeconds === null ||
    finalSteps === null
  ) {
    return null;
  }

  return {
    metadata,
    hasEligibleClimbAttempt: hasEligibleClimbAttemptParticipation(
      data.participations
    ),
    splitIntervalSeconds,
    splitSteps,
    finalDurationSeconds,
    finalSteps,
    targetStepCount,
  };
}

/**
 * Returns whether a live climb workout represents a full completed climb.
 * @param {ParsedReplayPayloadParts} parsed Parsed replay payload parts.
 * @return {boolean} True when the row may be published publicly.
 */
function hasCompletedLiveClimbAttempt(
  parsed: ParsedReplayPayloadParts
): boolean {
  if (!parsed.hasEligibleClimbAttempt) {
    return false;
  }

  const trackingMode = stringValue(parsed.metadata.trackingMode);
  const stopReason = stringValue(parsed.metadata.stopReason);
  const baselineSteps = nonNegativeIntegerValue(
    parsed.metadata.attemptBaselineSteps
  );

  return trackingMode === LIVE_CLIMB_TRACKING_MODE &&
    stopReason === TARGET_REACHED_STOP_REASON &&
    parsed.targetStepCount !== null &&
    parsed.finalSteps >= parsed.targetStepCount &&
    (baselineSteps === null || baselineSteps === 0);
}

/**
 * Creates a context-specific replay payload from parsed common fields.
 * @param {ParsedReplayPayloadParts} parsed Common replay fields.
 * @param {string} contextType Replay context type.
 * @param {string} contextId Replay context ID.
 * @param {Object} options Replay shaping options.
 * @return {LiveReplayIndexPayload} Replay payload.
 */
function replayPayload(
  parsed: ParsedReplayPayloadParts,
  contextType: string,
  contextId: string
): LiveReplayIndexPayload {
  const splitSteps = normalizeReplaySplitSteps({
    splitIntervalSeconds: parsed.splitIntervalSeconds,
    splitSteps: parsed.splitSteps,
    finalDurationSeconds: parsed.finalDurationSeconds,
    finalSteps: parsed.finalSteps,
  });

  return {
    contextKey: contextKey(contextType, contextId),
    contextType,
    contextId,
    splitIntervalSeconds: parsed.splitIntervalSeconds,
    splitSteps,
    finalDurationSeconds: parsed.finalDurationSeconds,
    finalSteps: parsed.finalSteps,
    targetStepCount: parsed.targetStepCount,
  };
}

/**
 * Returns whether a workout has a completed leaderboard-eligible climb attempt.
 * @param {unknown} value Raw participations value.
 * @return {boolean} True when the workout can be indexed for replay.
 */
function hasEligibleClimbAttemptParticipation(value: unknown): boolean {
  if (!Array.isArray(value)) {
    return false;
  }

  return value.some((item) => {
    if (!item || typeof item !== "object") {
      return false;
    }

    const participation = item as Record<string, unknown>;
    return participation.contextType === "climb_attempt" &&
      participation.leaderboardEligible === true;
  });
}

/**
 * Removes bucket entries for an old live-attempt payload.
 * @param {FirebaseFirestore.BulkWriter} writer Bulk writer.
 * @param {LiveReplayIndexPayload} payload Previous replay payload.
 * @param {string} entryId Public row document ID.
 */
function deleteReplayEntries(
  writer: FirebaseFirestore.BulkWriter,
  payload: LiveReplayIndexPayload,
  entryId: string
): void {
  for (let index = 0; index < payload.splitSteps.length; index += 1) {
    writer.delete(entryReference(payload, index, entryId));
  }
}

/**
 * Deletes replay entries with the given public row document ID.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} entryId Public row document ID.
 */
async function deleteReplayEntriesForId(
  payload: LiveReplayIndexPayload,
  entryId: string
): Promise<void> {
  const writer = admin.firestore().bulkWriter();
  deleteReplayEntries(writer, payload, entryId);
  await writer.close();
}

/**
 * Deletes the legacy per-user best guard document.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} userId Owner user ID.
 */
async function deleteUserBestAttempt(
  payload: LiveReplayIndexPayload,
  userId: string
): Promise<void> {
  await userBestAttemptReference(payload, userId).delete();
}

/**
 * Publishes one saved attempt as a public replay row in a context.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} entryId Public row document ID.
 * @param {string} userId Owner user ID.
 * @param {PublicUserSnapshot} publicUser Public display snapshot.
 */
async function publishReplayEntries(
  payload: LiveReplayIndexPayload,
  entryId: string,
  userId: string,
  publicUser: PublicUserSnapshot
): Promise<void> {
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const leaderboardRef = db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey);

  await db.runTransaction(async (transaction) => {
    transaction.set(leaderboardRef, {
      bucketIntervalSeconds: payload.splitIntervalSeconds,
      contextId: payload.contextId,
      contextType: payload.contextType,
      schemaVersion: 1,
      targetStepCount: payload.targetStepCount,
      updatedAt: now,
    }, {merge: true});

    for (let index = 0; index < payload.splitSteps.length; index += 1) {
      transaction.set(entryReference(payload, index, entryId), {
        avatarToken: publicUser.avatarToken,
        completionDurationSeconds: payload.finalDurationSeconds,
        displayName: publicUser.displayName,
        finalSteps: payload.finalSteps,
        photoURL: publicUser.photoURL ?? "",
        schemaVersion: 1,
        splitIntervalSeconds: payload.splitIntervalSeconds,
        stepsAtBucket: payload.splitSteps[index],
        updatedAt: now,
        userId,
        workoutId: entryId,
      });
    }
  });
}

/**
 * Maintains the global unique user count for catalog Live Climb completions.
 * @param {string} userId Owner user ID.
 */
async function updateLiveClimbCommunityStats(userId: string): Promise<void> {
  const hasCompletedClimb = await userHasCompletedAnyLiveClimb(userId);
  const db = admin.firestore();
  const statsRef = liveClimbCommunityStatsReference();
  const completedUserRef = statsRef
    .collection(LIVE_CLIMB_COMPLETED_USERS_COLLECTION)
    .doc(userId);

  await db.runTransaction(async (transaction) => {
    const completedUserSnapshot = await transaction.get(completedUserRef);
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (hasCompletedClimb && !completedUserSnapshot.exists) {
      transaction.set(completedUserRef, {
        firstCompletedAt: now,
        schemaVersion: 1,
        updatedAt: now,
        userId,
      });
      transaction.set(statsRef, {
        schemaVersion: 1,
        uniqueCompletedUserCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      }, {merge: true});
      return;
    }

    if (hasCompletedClimb) {
      transaction.set(completedUserRef, {
        schemaVersion: 1,
        updatedAt: now,
        userId,
      }, {merge: true});
      transaction.set(statsRef, {
        schemaVersion: 1,
        updatedAt: now,
      }, {merge: true});
      return;
    }

    if (completedUserSnapshot.exists) {
      transaction.delete(completedUserRef);
      transaction.set(statsRef, {
        schemaVersion: 1,
        uniqueCompletedUserCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: now,
      }, {merge: true});
    }
  });
}

/**
 * Returns whether a user has at least one completed catalog Live Climb.
 * @param {string} userId Owner user ID.
 * @return {Promise<boolean>} True when the user has any eligible completion.
 */
async function userHasCompletedAnyLiveClimb(userId: string): Promise<boolean> {
  const snapshot = await admin.firestore()
    .collection("users")
    .doc(userId)
    .collection("workouts")
    .where("source", "==", "headphone_motion")
    .get();

  return snapshot.docs.some((document) => {
    const payload = parseLiveClimbReplayPayload(
      document.data() as Record<string, unknown>,
      {requireEligibleParticipation: true}
    );
    return payload !== null;
  });
}

/**
 * Stores the one published replay row selected for a user in this context.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} userId Owner user ID.
 * @return {FirebaseFirestore.DocumentReference} User best document reference.
 */
function userBestAttemptReference(
  payload: LiveReplayIndexPayload,
  userId: string
): FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey)
    .collection("userBestAttempts")
    .doc(userId);
}

/**
 * Global community stats document for catalog Live Climb completion counts.
 * @return {FirebaseFirestore.DocumentReference} Stats document reference.
 */
function liveClimbCommunityStatsReference():
  FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection(LIVE_CLIMB_COMMUNITY_STATS_COLLECTION)
    .doc(LIVE_CLIMB_COMMUNITY_GLOBAL_ID);
}

/**
 * Bucket entry document reference for a replay payload.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {number} bucketIndex Split bucket index.
 * @param {string} entryId Public row document ID.
 * @return {FirebaseFirestore.DocumentReference} Entry document reference.
 */
function entryReference(
  payload: LiveReplayIndexPayload,
  bucketIndex: number,
  entryId: string
): FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey)
    .collection("splitBuckets")
    .doc(String(bucketIndex))
    .collection("entries")
    .doc(entryId);
}

/**
 * Reads the minimal public profile data copied into leaderboard entries.
 * @param {string} userId Owner user ID.
 * @return {Promise<PublicUserSnapshot>} Public display snapshot.
 */
async function publicUserSnapshot(userId: string): Promise<PublicUserSnapshot> {
  const snapshot = await admin.firestore()
    .collection("users")
    .doc(userId)
    .get();
  const data = snapshot.data();
  const displayName = stringValue(data?.displayName) ??
    stringValue(data?.firstName) ??
    "Climber";

  return {
    avatarToken: avatarToken(displayName),
    displayName,
    photoURL: urlStringValue(data?.profilePictureURL),
  };
}

/**
 * Builds the same context key shape used by the iOS client.
 * @param {string} contextType Context type.
 * @param {string} contextId Context ID.
 * @return {string} Firestore-safe context key.
 */
function contextKey(contextType: string, contextId: string): string {
  return `${contextType}__${sanitizeContextId(contextId)}`;
}

/**
 * Keeps Firestore document IDs stable and path-safe.
 * @param {string} value Raw context ID.
 * @return {string} Sanitized context ID.
 */
function sanitizeContextId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, "_");
}

/**
 * Creates a compact deterministic avatar token from a display name.
 * @param {string} displayName Public display name.
 * @return {string} Initials token.
 */
function avatarToken(displayName: string): string {
  const token = displayName
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();

  return token || "A";
}

/**
 * Returns a non-empty trimmed string.
 * @param {unknown} value Raw value.
 * @return {string | null} Trimmed string, if present.
 */
function stringValue(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Returns a public http(s) URL string if present.
 * @param {unknown} value Raw value.
 * @return {string | null} URL string.
 */
function urlStringValue(value: unknown): string | null {
  const valueString = stringValue(value);
  if (!valueString || valueString.length > 2048) {
    return null;
  }

  return /^https?:\/\//i.test(valueString) ? valueString : null;
}

/**
 * Returns a non-negative finite number.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed number, if valid.
 */
function nonNegativeNumberValue(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return null;
  }

  return value;
}

/**
 * Returns a non-negative integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer, if valid.
 */
function nonNegativeIntegerValue(value: unknown): number | null {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 0
  ) {
    return null;
  }

  return value;
}

/**
 * Returns a positive integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer, if valid.
 */
function positiveIntegerValue(value: unknown): number | null {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value <= 0
  ) {
    return null;
  }

  return value;
}

/**
 * Returns a list of non-negative integers.
 * @param {unknown} value Raw value.
 * @return {number[] | null} Parsed integer list, if valid.
 */
function integerArrayValue(value: unknown): number[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const values: number[] = [];
  for (const entry of value) {
    const parsedEntry = nonNegativeIntegerValue(entry);
    if (parsedEntry === null) {
      return null;
    }

    values.push(parsedEntry);
  }

  return values;
}

export const liveReplayLeaderboardTestHooks = {
  parseLiveClimbReplayPayload,
};
