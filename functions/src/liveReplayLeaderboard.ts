import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const MAX_SPLIT_CHECKPOINTS = 360;

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
    const beforePayload = parseLiveReplayPayload(beforeData, {
      requireEligibleParticipation: false,
    });
    const afterPayload = parseLiveReplayPayload(afterData, {
      requireEligibleParticipation: true,
    });

    if (!beforePayload && !afterPayload) {
      return;
    }

    const db = admin.firestore();
    const writer = db.bulkWriter();

    if (beforePayload) {
      deleteReplayEntries(writer, beforePayload, workoutId);
    }

    if (afterPayload) {
      const publicUser = await publicUserSnapshot(userId);
      writeReplayEntries(writer, afterPayload, userId, workoutId, publicUser);
    }

    await writer.close();
  }
);

/**
 * Converts a private workout backup into a replay indexing payload.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @param {{requireEligibleParticipation: boolean}} options Parse options.
 * @return {LiveReplayIndexPayload | null} Parsed replay payload, if valid.
 */
function parseLiveReplayPayload(
  data: Record<string, unknown> | undefined,
  options: {requireEligibleParticipation: boolean}
): LiveReplayIndexPayload | null {
  if (!data || data.source !== "headphone_motion") {
    return null;
  }

  if (
    options.requireEligibleParticipation &&
    !hasEligibleClimbAttemptParticipation(data.participations)
  ) {
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

  const climbId = stringValue(metadata.climbId);
  const splitIntervalSeconds = positiveIntegerValue(
    metadata.splitIntervalSeconds
  );
  const splitSteps = integerArrayValue(metadata.splitSteps)
    ?.slice(0, MAX_SPLIT_CHECKPOINTS);
  const finalDurationSeconds = nonNegativeNumberValue(data.durationSeconds);
  const finalSteps = nonNegativeIntegerValue(data.steps);
  const targetStepCount = positiveIntegerValue(metadata.targetStepCount);

  if (
    !climbId ||
    !splitIntervalSeconds ||
    !splitSteps ||
    splitSteps.length === 0 ||
    finalDurationSeconds === null ||
    finalSteps === null
  ) {
    return null;
  }

  return {
    contextKey: contextKey(LIVE_CLIMB_CONTEXT_TYPE, climbId),
    contextType: LIVE_CLIMB_CONTEXT_TYPE,
    contextId: climbId,
    splitIntervalSeconds,
    splitSteps,
    finalDurationSeconds,
    finalSteps,
    targetStepCount,
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
 * @param {string} workoutId Workout document ID.
 */
function deleteReplayEntries(
  writer: FirebaseFirestore.BulkWriter,
  payload: LiveReplayIndexPayload,
  workoutId: string
): void {
  for (let index = 0; index < payload.splitSteps.length; index += 1) {
    writer.delete(entryReference(payload, index, workoutId));
  }
}

/**
 * Writes summary and bucket entries for a saved live-attempt payload.
 * @param {FirebaseFirestore.BulkWriter} writer Bulk writer.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} userId Owner user ID.
 * @param {string} workoutId Workout document ID.
 * @param {PublicUserSnapshot} publicUser Public display snapshot.
 */
function writeReplayEntries(
  writer: FirebaseFirestore.BulkWriter,
  payload: LiveReplayIndexPayload,
  userId: string,
  workoutId: string,
  publicUser: PublicUserSnapshot
): void {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const leaderboardRef = admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey);

  writer.set(leaderboardRef, {
    bucketIntervalSeconds: payload.splitIntervalSeconds,
    contextId: payload.contextId,
    contextType: payload.contextType,
    schemaVersion: 1,
    targetStepCount: payload.targetStepCount,
    updatedAt: now,
  }, {merge: true});

  for (let index = 0; index < payload.splitSteps.length; index += 1) {
    writer.set(entryReference(payload, index, workoutId), {
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
      workoutId,
    });
  }
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
 * Bucket entry document reference for a replay payload.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {number} bucketIndex Split bucket index.
 * @param {string} workoutId Workout document ID.
 * @return {FirebaseFirestore.DocumentReference} Entry document reference.
 */
function entryReference(
  payload: LiveReplayIndexPayload,
  bucketIndex: number,
  workoutId: string
): FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey)
    .collection("splitBuckets")
    .doc(String(bucketIndex))
    .collection("entries")
    .doc(workoutId);
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
