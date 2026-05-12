import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  extendReplaySplitStepsToMaxBuckets,
  MAX_REPLAY_SPLIT_CHECKPOINTS,
  normalizeReplaySplitSteps,
} from "./liveReplaySplitNormalization.js";

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const JUST_CLIMB_CONTEXT_TYPE = "just_climb";
const JUST_CLIMB_GLOBAL_CONTEXT_ID = "global";
const JUST_CLIMB_TRACKING_MODE = "just_climb";

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

interface PublishedReplayBest {
  workoutId: string;
  completionDurationSeconds: number;
  bucketCount: number;
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
    const beforeGlobalPayload = parseGlobalReplayPayload(beforeData);
    const afterGlobalPayload = parseGlobalReplayPayload(afterData);

    if (
      !beforeClimbPayload &&
      !afterClimbPayload &&
      !beforeGlobalPayload &&
      !afterGlobalPayload
    ) {
      return;
    }

    const publicUser = afterClimbPayload || afterGlobalPayload ?
      await publicUserSnapshot(userId) :
      null;

    if (
      beforeClimbPayload &&
      (
        !afterClimbPayload ||
        beforeClimbPayload.contextKey !== afterClimbPayload.contextKey
      )
    ) {
      await removeBestReplayEntries(beforeClimbPayload, userId, workoutId);
    }

    if (afterClimbPayload && publicUser) {
      await publishBestReplayEntries(
        afterClimbPayload,
        userId,
        workoutId,
        publicUser
      );
    }

    if (beforeClimbPayload) {
      await deleteLegacyWorkoutReplayEntries(beforeClimbPayload, workoutId);
    }

    if (afterClimbPayload) {
      await deleteLegacyWorkoutReplayEntries(afterClimbPayload, workoutId);
    }

    if (beforeGlobalPayload) {
      await deleteReplayEntriesForId(beforeGlobalPayload, workoutId);
    }

    if (afterGlobalPayload && publicUser) {
      await publishReplayEntries(
        afterGlobalPayload,
        workoutId,
        userId,
        publicUser
      );
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
    !parsed.hasEligibleClimbAttempt
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

/**
 * Converts any completed live-tracked climb into the global Just Climb payload.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @return {LiveReplayIndexPayload | null} Parsed replay payload, if valid.
 */
function parseGlobalReplayPayload(
  data: Record<string, unknown> | undefined
): LiveReplayIndexPayload | null {
  const parsed = parseReplayPayloadParts(data);
  if (!parsed) {
    return null;
  }

  const trackingMode = stringValue(parsed.metadata.trackingMode);
  const isJustClimb = trackingMode === JUST_CLIMB_TRACKING_MODE;
  if (!parsed.hasEligibleClimbAttempt && !isJustClimb) {
    return null;
  }

  return replayPayload(
    parsed,
    JUST_CLIMB_CONTEXT_TYPE,
    JUST_CLIMB_GLOBAL_CONTEXT_ID,
    {extendThroughMaxBucket: true}
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
  const targetStepCount = positiveIntegerValue(metadata.targetStepCount);

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
  contextId: string,
  options: {extendThroughMaxBucket?: boolean} = {}
): LiveReplayIndexPayload {
  const normalizedSplitSteps = normalizeReplaySplitSteps({
    splitIntervalSeconds: parsed.splitIntervalSeconds,
    splitSteps: parsed.splitSteps,
    finalDurationSeconds: parsed.finalDurationSeconds,
    finalSteps: parsed.finalSteps,
  });
  const splitSteps = options.extendThroughMaxBucket === true ?
    extendReplaySplitStepsToMaxBuckets(
      normalizedSplitSteps,
      parsed.finalSteps
    ) :
    normalizedSplitSteps;

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
 * Deletes legacy workout-id keyed replay entries left by older publishers.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} workoutId Workout document ID.
 */
async function deleteLegacyWorkoutReplayEntries(
  payload: LiveReplayIndexPayload,
  workoutId: string
): Promise<void> {
  await deleteReplayEntriesForId(payload, workoutId);
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
 * Publishes a saved attempt only if it is the user's best public replay row.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} userId Owner user ID.
 * @param {string} workoutId Workout document ID.
 * @param {PublicUserSnapshot} publicUser Public display snapshot.
 */
async function publishBestReplayEntries(
  payload: LiveReplayIndexPayload,
  userId: string,
  workoutId: string,
  publicUser: PublicUserSnapshot
): Promise<void> {
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const leaderboardRef = db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey);
  const bestRef = userBestAttemptReference(payload, userId);

  await db.runTransaction(async (transaction) => {
    const currentBest = publishedReplayBest(
      (await transaction.get(bestRef)).data()
    );
    if (
      currentBest &&
      currentBest.workoutId !== workoutId &&
      currentBest.completionDurationSeconds <= payload.finalDurationSeconds
    ) {
      return;
    }

    transaction.set(leaderboardRef, {
      bucketIntervalSeconds: payload.splitIntervalSeconds,
      contextId: payload.contextId,
      contextType: payload.contextType,
      schemaVersion: 1,
      targetStepCount: payload.targetStepCount,
      updatedAt: now,
    }, {merge: true});

    transaction.set(bestRef, {
      bucketCount: payload.splitSteps.length,
      completionDurationSeconds: payload.finalDurationSeconds,
      contextId: payload.contextId,
      contextType: payload.contextType,
      finalSteps: payload.finalSteps,
      schemaVersion: 1,
      userId,
      workoutId,
      updatedAt: now,
    }, {merge: true});

    for (let index = 0; index < payload.splitSteps.length; index += 1) {
      transaction.set(entryReference(payload, index, userId), {
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

    const previousBucketCount = currentBest?.bucketCount ?? 0;
    for (
      let index = payload.splitSteps.length;
      index < previousBucketCount;
      index += 1
    ) {
      transaction.delete(entryReference(payload, index, userId));
    }
  });
}

/**
 * Removes replay entries when the user's published best attempt is removed.
 * @param {LiveReplayIndexPayload} payload Previous replay payload.
 * @param {string} userId Owner user ID.
 * @param {string} workoutId Workout document ID.
 */
async function removeBestReplayEntries(
  payload: LiveReplayIndexPayload,
  userId: string,
  workoutId: string
): Promise<void> {
  const db = admin.firestore();
  const bestRef = userBestAttemptReference(payload, userId);

  await db.runTransaction(async (transaction) => {
    const currentBest = publishedReplayBest(
      (await transaction.get(bestRef)).data()
    );
    if (!currentBest || currentBest.workoutId !== workoutId) {
      return;
    }

    for (let index = 0; index < currentBest.bucketCount; index += 1) {
      transaction.delete(entryReference(payload, index, userId));
    }

    transaction.delete(bestRef);
  });
}

/**
 * Parses the per-user published-best guard document.
 * @param {FirebaseFirestore.DocumentData | undefined} data Firestore data.
 * @return {PublishedReplayBest | null} Published best snapshot, if valid.
 */
function publishedReplayBest(
  data: FirebaseFirestore.DocumentData | undefined
): PublishedReplayBest | null {
  const workoutId = stringValue(data?.workoutId);
  const completionDurationSeconds = nonNegativeNumberValue(
    data?.completionDurationSeconds
  );
  const bucketCount = positiveIntegerValue(data?.bucketCount);

  if (!workoutId || completionDurationSeconds === null || !bucketCount) {
    return null;
  }

  return {
    workoutId,
    completionDurationSeconds,
    bucketCount,
  };
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
