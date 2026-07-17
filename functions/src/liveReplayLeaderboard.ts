import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  MAX_REPLAY_SPLIT_CHECKPOINTS,
  normalizeReplaySplitSteps,
} from "./liveReplaySplitNormalization.js";

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const COMPLETION_SNAPSHOTS_COLLECTION = "completionSnapshots";
const LIVE_CLIMB_COMMUNITY_STATS_COLLECTION = "live_climb_community_stats";
const LIVE_CLIMB_COMMUNITY_GLOBAL_ID = "global";
const LIVE_CLIMB_COMPLETED_USERS_COLLECTION = "completedUsers";
const LIVE_CLIMB_PUBLISH_STATUSES_COLLECTION = "liveClimbPublishStatuses";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const LIVE_CLIMB_TRACKING_MODE = "live_climb";
const JUST_CLIMB_CONTEXT_TYPE = "just_climb";
const JUST_CLIMB_GLOBAL_CONTEXT_ID = "global";
const JUST_CLIMB_TRACKING_MODE = "just_climb";
const TARGET_REACHED_STOP_REASON = "target_reached";
const USER_STOPPED_REASON = "user_stopped";

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
  age?: number | null;
  gender?: string | null;
  locationCity?: string | null;
}

interface FirstAscentWriteInput {
  userId: string;
  entryId: string;
  publicUser: PublicUserSnapshot;
  claimedAt: unknown;
}

interface FinisherStatusWriteInput {
  payload: LiveReplayIndexPayload;
  userId: string;
  entryId: string;
  publicUser: PublicUserSnapshot;
  globalCompletionOrder: number;
  existingData: Record<string, unknown> | undefined;
  completedAt: unknown;
}

interface ReplaySummaryWriteInput {
  payload: LiveReplayIndexPayload;
  completedCount: number;
}

interface ReplayEntryWriteInput {
  payload: LiveReplayIndexPayload;
  userId: string;
  entryId: string;
  publicUser: PublicUserSnapshot;
  stepsAtBucket: number;
  updatedAt: unknown;
}

interface CompletionRankSnapshotWriteInput {
  payload: LiveReplayIndexPayload;
  userId: string;
  entryId: string;
  rank: number;
  completedCount: number;
  rankedAt: unknown;
}

interface LiveClimbPublishStatusWriteInput {
  payload: LiveReplayIndexPayload;
  userId: string;
  entryId: string;
  updatedAt: unknown;
}

interface LiveClimbPublishStatusPublishedInput
  extends LiveClimbPublishStatusWriteInput {
  rankAtCompletion: number;
  completedCountAtCompletion: number;
  finisherOrder: number;
}

/**
 * Publishes saved live-attempt split checkpoints into read-only replay windows.
 */
export const onWorkoutReplaySplitsWritten = onDocumentWritten(
  {
    document: "users/{userId}/workouts/{workoutId}",
    retry: true,
  },
  async (event) => {
    const beforeData = event.data?.before.data() as
      Record<string, unknown> | undefined;
    const afterData = event.data?.after.data() as
      Record<string, unknown> | undefined;
    const userId = event.params.userId;
    const workoutId = event.params.workoutId;
    const beforePayloads = replayPayloadsForWorkout(beforeData, {
      requireEligibleParticipation: false,
    });
    const afterPayloads = replayPayloadsForWorkout(afterData, {
      requireEligibleParticipation: true,
    });

    if (
      beforePayloads.length === 0 &&
      afterPayloads.length === 0
    ) {
      return;
    }

    await writeLiveClimbPublishStatusesPublishing(
      afterPayloads,
      userId,
      workoutId
    );

    try {
      const publicUser = afterPayloads.length > 0 ?
        await publicUserSnapshot(userId) :
        null;

      for (const payload of beforePayloads) {
        await deleteReplayEntriesForId(payload, workoutId);
        if (shouldDeleteCompletionRankSnapshot(payload, afterPayloads)) {
          await deleteCompletionRankSnapshot(payload, workoutId);
        }
      }

      if (publicUser) {
        for (const payload of afterPayloads) {
          await publishReplayEntries(
            payload,
            workoutId,
            userId,
            publicUser
          );
        }
      }

      for (const payload of beforePayloads) {
        await deleteReplayEntriesForId(payload, userId);
        await deleteUserBestAttempt(payload, userId);
      }

      for (const payload of afterPayloads) {
        await deleteReplayEntriesForId(payload, userId);
        await deleteUserBestAttempt(payload, userId);
      }

      if (
        beforePayloads.some(
          (payload) => payload.contextType === LIVE_CLIMB_CONTEXT_TYPE
        ) ||
        afterPayloads.some(
          (payload) => payload.contextType === LIVE_CLIMB_CONTEXT_TYPE
        )
      ) {
        await updateLiveClimbCommunityStats(userId);
      }
    } catch (error) {
      await writeLiveClimbPublishStatusesFailed(
        afterPayloads,
        userId,
        workoutId,
        error
      );
      throw error;
    }
  }
);

/**
 * Converts a workout backup into every replay context it should publish.
 * Landmark Live Climbs publish both their per-climb context and the global
 * Just Climb replay context. Open Just Climb sessions publish only globally.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @param {{requireEligibleParticipation: boolean}} options Parse options.
 * @return {LiveReplayIndexPayload[]} Parsed replay payloads.
 */
function replayPayloadsForWorkout(
  data: Record<string, unknown> | undefined,
  options: {requireEligibleParticipation: boolean}
): LiveReplayIndexPayload[] {
  return [
    parseLiveClimbReplayPayload(data, options),
    parseJustClimbReplayPayload(data, options),
  ].filter((payload): payload is LiveReplayIndexPayload => payload !== null);
}

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

/**
 * Converts either a completed landmark Live Climb or an open Just Climb session
 * into the global Just Climb replay context.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @param {{requireEligibleParticipation: boolean}} options Parse options.
 * @return {LiveReplayIndexPayload | null} Parsed replay payload, if valid.
 */
function parseJustClimbReplayPayload(
  data: Record<string, unknown> | undefined,
  options: {requireEligibleParticipation: boolean}
): LiveReplayIndexPayload | null {
  const parsed = parseReplayPayloadParts(data);
  if (!parsed) {
    return null;
  }

  if (options.requireEligibleParticipation) {
    const isCompletedLandmarkLiveClimb = hasCompletedLiveClimbAttempt(parsed);
    const isCompletedOpenJustClimb = hasCompletedJustClimbSession(parsed);
    if (!isCompletedLandmarkLiveClimb && !isCompletedOpenJustClimb) {
      return null;
    }
  }

  const trackingMode = stringValue(parsed.metadata.trackingMode);
  if (
    trackingMode !== LIVE_CLIMB_TRACKING_MODE &&
    trackingMode !== JUST_CLIMB_TRACKING_MODE
  ) {
    return null;
  }

  return replayPayload(
    parsed,
    JUST_CLIMB_CONTEXT_TYPE,
    JUST_CLIMB_GLOBAL_CONTEXT_ID,
    {targetStepCount: null}
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
 * Returns whether a live climb workout may publish a replay row. This is a
 * publication gate, not the definition of finishing a climb: the client owns
 * that in LiveClimbCompletionPolicy, which reads steps against the target and
 * never reads stopReason. Requiring target_reached here deliberately declines
 * some attempts the client counts as finished. A recovered draft is saved as
 * interrupted and carries a hand-typed step count, and a First Ascent is
 * permanent and never reclaimable, so a typed number must never claim one. The
 * client normalizes a manual stop past the target to target_reached at save
 * time, so that path agrees with this gate without a change here.
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
 * Returns whether a headphone-motion workout is a completed open Just Climb
 * session that can be published into the global replay context.
 * @param {ParsedReplayPayloadParts} parsed Parsed replay payload parts.
 * @return {boolean} True when the row may be published publicly.
 */
function hasCompletedJustClimbSession(
  parsed: ParsedReplayPayloadParts
): boolean {
  const trackingMode = stringValue(parsed.metadata.trackingMode);
  const stopReason = stringValue(parsed.metadata.stopReason);

  return trackingMode === JUST_CLIMB_TRACKING_MODE &&
    parsed.finalSteps > 0 &&
    parsed.finalDurationSeconds > 0 &&
    (
      stopReason === TARGET_REACHED_STOP_REASON ||
      stopReason === USER_STOPPED_REASON
    );
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
  options: {targetStepCount?: number | null} = {}
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
    targetStepCount: options.targetStepCount !== undefined ?
      options.targetStepCount :
      parsed.targetStepCount,
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
  const finisherRef = finisherReference(payload, userId);
  const completionSnapshotRef = completionSnapshotReference(payload, entryId);
  const publishStatusRef = liveClimbPublishStatusReference(userId, entryId);
  const completionRank = await completionRankForPayload(payload);

  await db.runTransaction(async (transaction) => {
    const leaderboardSnapshot = await transaction.get(leaderboardRef);
    const finisherSnapshot = await transaction.get(finisherRef);
    const completionSnapshot = await transaction.get(completionSnapshotRef);
    const leaderboardData = leaderboardSnapshot.data();
    const existingFinisherData = finisherSnapshot.data();
    const existingOrder = positiveIntegerValue(
      existingFinisherData?.globalCompletionOrder
    );
    const isNewFinisher = existingOrder === null;
    const previousCompletedCount = nonNegativeIntegerValue(
      leaderboardData?.completedCount
    ) ?? 0;
    const hasFirstAscent = leaderboardHasFirstAscent(leaderboardData);
    const canClaimFirstAscent = !hasFirstAscent && previousCompletedCount === 0;
    const globalCompletionOrder = nextGlobalCompletionOrder({
      existingOrder,
      previousCompletedCount,
    });
    const completedCount = isNewFinisher ?
      Math.max(previousCompletedCount + 1, globalCompletionOrder) :
      Math.max(previousCompletedCount, globalCompletionOrder);
    const summaryWrite = replaySummaryWrite({
      payload,
      completedCount,
    });
    summaryWrite.updatedAt = now;

    if (canClaimFirstAscent) {
      Object.assign(
        summaryWrite,
        firstAscentWrite({
          userId,
          entryId,
          publicUser,
          claimedAt: now,
        })
      );
    }

    transaction.set(leaderboardRef, summaryWrite, {merge: true});
    transaction.set(
      finisherRef,
      finisherStatusWrite({
        payload,
        userId,
        entryId,
        publicUser,
        globalCompletionOrder,
        existingData: existingFinisherData,
        completedAt: now,
      }),
      {merge: true}
    );

    if (!completionSnapshot.exists) {
      transaction.set(
        completionSnapshotRef,
        completionRankSnapshotWrite({
          payload,
          userId,
          entryId,
          rank: Math.min(completionRank, completedCount),
          completedCount,
          rankedAt: now,
        })
      );
    }

    if (payload.contextType === LIVE_CLIMB_CONTEXT_TYPE) {
      transaction.set(
        publishStatusRef,
        liveClimbPublishStatusPublishedWrite({
          payload,
          userId,
          entryId,
          updatedAt: now,
          rankAtCompletion: Math.min(completionRank, completedCount),
          completedCountAtCompletion: completedCount,
          finisherOrder: globalCompletionOrder,
        }),
        {merge: true}
      );
    }

    for (let index = 0; index < payload.splitSteps.length; index += 1) {
      transaction.set(
        entryReference(payload, index, entryId),
        replayEntryWrite({
          payload,
          userId,
          entryId,
          publicUser,
          stepsAtBucket: payload.splitSteps[index],
          updatedAt: now,
        })
      );
    }
  });
}

/**
 * Calculates the performance rank for this completed attempt at publish time.
 * Rank is competition-style: equal durations share the same rank.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @return {Promise<number>} Rank among faster completed attempts plus one.
 */
async function completionRankForPayload(
  payload: LiveReplayIndexPayload
): Promise<number> {
  const snapshot = await entriesCollectionReference(payload, 0)
    .where("completionDurationSeconds", "<", payload.finalDurationSeconds)
    .count()
    .get();
  return snapshot.data().count + 1;
}

/**
 * Deletes the immutable completion-rank snapshot for a removed attempt.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} entryId Public row document ID.
 */
async function deleteCompletionRankSnapshot(
  payload: LiveReplayIndexPayload,
  entryId: string
): Promise<void> {
  await completionSnapshotReference(payload, entryId).delete();
}

/**
 * Keeps immutable rank-at-completion snapshots stable across ordinary
 * workout republishes. A snapshot is removed only when the workout no longer
 * belongs to that same replay leaderboard context.
 * @param {LiveReplayIndexPayload} beforePayload Existing replay context.
 * @param {LiveReplayIndexPayload[]} afterPayloads New replay contexts.
 * @return {boolean} Whether to delete the old snapshot.
 */
function shouldDeleteCompletionRankSnapshot(
  beforePayload: LiveReplayIndexPayload,
  afterPayloads: LiveReplayIndexPayload[]
): boolean {
  return !afterPayloads.some(
    (afterPayload) => afterPayload.contextKey === beforePayload.contextKey
  );
}

/**
 * Marks eligible Live Climb results as currently publishing.
 * @param {LiveReplayIndexPayload[]} payloads Parsed replay payloads.
 * @param {string} userId Owner user ID.
 * @param {string} entryId Workout/public row ID.
 */
async function writeLiveClimbPublishStatusesPublishing(
  payloads: LiveReplayIndexPayload[],
  userId: string,
  entryId: string
): Promise<void> {
  const writes = payloads
    .filter((payload) => payload.contextType === LIVE_CLIMB_CONTEXT_TYPE)
    .map((payload) => liveClimbPublishStatusReference(userId, entryId).set(
      liveClimbPublishStatusPublishingWrite({
        payload,
        userId,
        entryId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
      {merge: true}
    ));

  await Promise.all(writes);
}

/**
 * Marks eligible Live Climb result publishes as retryable failures.
 * @param {LiveReplayIndexPayload[]} payloads Parsed replay payloads.
 * @param {string} userId Owner user ID.
 * @param {string} entryId Workout/public row ID.
 * @param {unknown} error Publish error.
 */
async function writeLiveClimbPublishStatusesFailed(
  payloads: LiveReplayIndexPayload[],
  userId: string,
  entryId: string,
  error: unknown
): Promise<void> {
  const writes = payloads
    .filter((payload) => payload.contextType === LIVE_CLIMB_CONTEXT_TYPE)
    .map((payload) => liveClimbPublishStatusReference(userId, entryId).set(
      liveClimbPublishStatusFailedWrite({
        payload,
        userId,
        entryId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, error),
      {merge: true}
    ));

  await Promise.all(writes);
}

/**
 * Builds the common live-climb publish status fields.
 * @param {LiveClimbPublishStatusWriteInput} input Status write input.
 * @return {Record<string, unknown>} Common Firestore fields.
 */
function liveClimbPublishStatusBaseWrite(
  input: LiveClimbPublishStatusWriteInput
): Record<string, unknown> {
  return {
    attemptDurationSeconds: input.payload.finalDurationSeconds,
    attemptSteps: input.payload.finalSteps,
    climbId: input.payload.contextId,
    contextId: input.payload.contextId,
    contextKey: input.payload.contextKey,
    contextType: input.payload.contextType,
    schemaVersion: 1,
    targetStepCount: input.payload.targetStepCount ?? 0,
    updatedAt: input.updatedAt,
    userId: input.userId,
    workoutId: input.entryId,
  };
}

/**
 * Builds a live-climb publish status for in-flight server publishing.
 * @param {LiveClimbPublishStatusWriteInput} input Status write input.
 * @return {Record<string, unknown>} Firestore fields.
 */
function liveClimbPublishStatusPublishingWrite(
  input: LiveClimbPublishStatusWriteInput
): Record<string, unknown> {
  return {
    ...liveClimbPublishStatusBaseWrite(input),
    lastErrorCode: admin.firestore.FieldValue.delete(),
    lastErrorMessageSafe: admin.firestore.FieldValue.delete(),
    state: "publishing",
  };
}

/**
 * Builds a live-climb publish status for a committed public result.
 * @param {LiveClimbPublishStatusPublishedInput} input Status write input.
 * @return {Record<string, unknown>} Firestore fields.
 */
function liveClimbPublishStatusPublishedWrite(
  input: LiveClimbPublishStatusPublishedInput
): Record<string, unknown> {
  return {
    ...liveClimbPublishStatusBaseWrite(input),
    completedCountAtCompletion: input.completedCountAtCompletion,
    finisherOrder: input.finisherOrder,
    lastErrorCode: admin.firestore.FieldValue.delete(),
    lastErrorMessageSafe: admin.firestore.FieldValue.delete(),
    publishedAt: input.updatedAt,
    rankAtCompletion: input.rankAtCompletion,
    rankSnapshotId: input.entryId,
    state: "published",
  };
}

/**
 * Builds a live-climb publish status for a retryable server failure.
 * @param {LiveClimbPublishStatusWriteInput} input Status write input.
 * @param {unknown} error Publish error.
 * @return {Record<string, unknown>} Firestore fields.
 */
function liveClimbPublishStatusFailedWrite(
  input: LiveClimbPublishStatusWriteInput,
  error: unknown
): Record<string, unknown> {
  return {
    ...liveClimbPublishStatusBaseWrite(input),
    lastErrorCode: safeErrorCode(error),
    lastErrorMessageSafe: "Leaderboard sync failed.",
    retryCount: admin.firestore.FieldValue.increment(1),
    state: "failed_retryable",
  };
}

/**
 * Builds an immutable rank-at-completion snapshot for a saved attempt.
 * @param {CompletionRankSnapshotWriteInput} input Snapshot write input.
 * @return {Record<string, unknown>} Firestore fields to write.
 */
function completionRankSnapshotWrite(
  input: CompletionRankSnapshotWriteInput
): Record<string, unknown> {
  return {
    completedCount: input.completedCount,
    completionDurationSeconds: input.payload.finalDurationSeconds,
    contextId: input.payload.contextId,
    contextType: input.payload.contextType,
    finalSteps: input.payload.finalSteps,
    rank: input.rank,
    rankedAt: input.rankedAt,
    rankingMetric: "completionDurationSeconds",
    schemaVersion: 1,
    targetStepCount: input.payload.targetStepCount ?? 0,
    tiePolicy: "competition_rank_equal_durations_share_rank",
    userId: input.userId,
    workoutId: input.entryId,
  };
}

/**
 * Builds the replay summary fields for a completed replay context.
 * @param {ReplaySummaryWriteInput} input Summary write input.
 * @return {Record<string, unknown>} Firestore fields to merge.
 */
function replaySummaryWrite(
  input: ReplaySummaryWriteInput
): Record<string, unknown> {
  return {
    bucketIntervalSeconds: input.payload.splitIntervalSeconds,
    completedCount: input.completedCount,
    contextId: input.payload.contextId,
    contextType: input.payload.contextType,
    schemaVersion: 1,
    targetStepCount: input.payload.targetStepCount,
    totalClimbers: input.completedCount,
  };
}

/**
 * Builds a public replay bucket entry for one split checkpoint.
 * @param {ReplayEntryWriteInput} input Entry write input.
 * @return {Record<string, unknown>} Firestore fields to write.
 */
function replayEntryWrite(
  input: ReplayEntryWriteInput
): Record<string, unknown> {
  return {
    ...publicUserDemographicFields(input.publicUser),
    avatarToken: input.publicUser.avatarToken,
    completionDurationSeconds: input.payload.finalDurationSeconds,
    contextId: input.payload.contextId,
    contextType: input.payload.contextType,
    displayName: input.publicUser.displayName,
    finalSteps: input.payload.finalSteps,
    photoURL: input.publicUser.photoURL ?? "",
    schemaVersion: 1,
    splitIntervalSeconds: input.payload.splitIntervalSeconds,
    stepsAtBucket: input.stepsAtBucket,
    updatedAt: input.updatedAt,
    userId: input.userId,
    workoutId: input.entryId,
  };
}

/**
 * Returns whether a replay summary already has a permanent First Ascent holder.
 * @param {Record<string, unknown> | undefined} data Replay summary data.
 * @return {boolean} True when the First Ascent slot is already claimed.
 */
function leaderboardHasFirstAscent(
  data: Record<string, unknown> | undefined
): boolean {
  if (!data) {
    return false;
  }

  return data.firstAscentCompletedAt !== undefined ||
    stringValue(data.firstAscentUserId) !== null;
}

/**
 * Resolves the permanent chronological finisher order for a user in a replay
 * @param {object} input Completion order inputs.
 * @param {number | null} input.existingOrder Existing permanent order.
 * @param {number} input.previousCompletedCount Current summary completed count.
 * @return {number} Permanent global completion order.
 */
function nextGlobalCompletionOrder(input: {
  existingOrder: number | null;
  previousCompletedCount: number;
}): number {
  if (input.existingOrder !== null) {
    return input.existingOrder;
  }

  return input.previousCompletedCount + 1;
}

/**
 * Builds the server-owned First Ascent payload for a replay summary.
 * @param {FirstAscentWriteInput} input First Ascent write input.
 * @return {Record<string, unknown>} Firestore fields to merge.
 */
function firstAscentWrite(
  input: FirstAscentWriteInput
): Record<string, unknown> {
  return {
    firstAscentAvatarToken: input.publicUser.avatarToken,
    firstAscentCompletedAt: input.claimedAt,
    firstAscentDisplayName: input.publicUser.displayName,
    firstAscentPhotoURL: input.publicUser.photoURL ?? "",
    firstAscentUserId: input.userId,
    firstAscentWorkoutId: input.entryId,
  };
}

/**
 * Builds the server-owned per-user finisher status for a replay context.
 * The completion order is permanent; later attempts only refresh display
 * snapshots and best-time metadata.
 * @param {FinisherStatusWriteInput} input Finisher write input.
 * @return {Record<string, unknown>} Firestore fields to merge.
 */
function finisherStatusWrite(
  input: FinisherStatusWriteInput
): Record<string, unknown> {
  const existingBestDuration = nonNegativeNumberValue(
    input.existingData?.bestCompletionDurationSeconds
  );
  const didImproveBest = existingBestDuration === null ||
    input.payload.finalDurationSeconds < existingBestDuration;
  const write: Record<string, unknown> = {
    ...publicUserDemographicFields(input.publicUser),
    avatarToken: input.publicUser.avatarToken,
    displayName: input.publicUser.displayName,
    globalCompletionOrder: input.globalCompletionOrder,
    photoURL: input.publicUser.photoURL ?? "",
    schemaVersion: 1,
    updatedAt: input.completedAt,
    userId: input.userId,
  };

  if (!input.existingData) {
    write.firstCompletedAt = input.completedAt;
    write.firstWorkoutId = input.entryId;
  }

  if (didImproveBest) {
    write.bestCompletionDurationSeconds = input.payload.finalDurationSeconds;
    write.bestWorkoutId = input.entryId;
  }

  return write;
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
 * Rank-at-completion snapshot document reference for a saved attempt.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} entryId Public row document ID.
 * @return {FirebaseFirestore.DocumentReference} Snapshot document reference.
 */
function completionSnapshotReference(
  payload: LiveReplayIndexPayload,
  entryId: string
): FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey)
    .collection(COMPLETION_SNAPSHOTS_COLLECTION)
    .doc(entryId);
}

/**
 * Per-user live climb publish status document reference.
 * @param {string} userId Owner user ID.
 * @param {string} entryId Workout/public row document ID.
 * @return {FirebaseFirestore.DocumentReference} Publish status reference.
 */
function liveClimbPublishStatusReference(
  userId: string,
  entryId: string
): FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection("users")
    .doc(userId)
    .collection(LIVE_CLIMB_PUBLISH_STATUSES_COLLECTION)
    .doc(entryId);
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
  return entriesCollectionReference(payload, bucketIndex).doc(entryId);
}

/**
 * Bucket entries collection reference for a replay payload.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {number} bucketIndex Split bucket index.
 * @return {FirebaseFirestore.CollectionReference} Entries collection reference.
 */
function entriesCollectionReference(
  payload: LiveReplayIndexPayload,
  bucketIndex: number
): FirebaseFirestore.CollectionReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey)
    .collection("splitBuckets")
    .doc(String(bucketIndex))
    .collection("entries");
}

/**
 * Per-user finisher status document reference for a replay payload.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} userId Owner user ID.
 * @return {FirebaseFirestore.DocumentReference} Finisher document reference.
 */
function finisherReference(
  payload: LiveReplayIndexPayload,
  userId: string
): FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey)
    .collection("finishers")
    .doc(userId);
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
    age: ageValue(data?.age),
    avatarToken: avatarToken(displayName),
    displayName,
    gender: genderValue(data?.gender),
    locationCity: locationTextValue(data?.location_city),
    photoURL: urlStringValue(data?.profilePictureURL),
  };
}

/**
 * Returns the public demographic fields allowed on replay rows.
 * @param {PublicUserSnapshot} publicUser Public display snapshot.
 * @return {Record<string, unknown>} Compact demographic fields.
 */
function publicUserDemographicFields(
  publicUser: PublicUserSnapshot
): Record<string, unknown> {
  const fields: Record<string, unknown> = {};

  if (publicUser.age !== null && publicUser.age !== undefined) {
    fields.age = publicUser.age;
  }

  if (publicUser.gender !== null && publicUser.gender !== undefined) {
    fields.gender = publicUser.gender;
  }

  if (
    publicUser.locationCity !== null &&
    publicUser.locationCity !== undefined
  ) {
    fields.locationCity = publicUser.locationCity;
  }

  return fields;
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
 * Returns an age value that is safe to publish.
 * @param {unknown} value Raw value.
 * @return {number | null} Age if valid.
 */
function ageValue(value: unknown): number | null {
  const age = nonNegativeIntegerValue(value);
  if (age === null || age < 13 || age > 120) {
    return null;
  }

  return age;
}

/**
 * Returns a profile gender raw value that is safe to publish.
 * @param {unknown} value Raw value.
 * @return {string | null} Gender raw value if valid.
 */
function genderValue(value: unknown): string | null {
  const gender = stringValue(value);
  if (
    gender !== "man" &&
    gender !== "woman" &&
    gender !== "non_binary" &&
    gender !== "prefer_not_to_say"
  ) {
    return null;
  }

  return gender;
}

/**
 * Returns a bounded location text value.
 * @param {unknown} value Raw value.
 * @return {string | null} Location text if valid.
 */
function locationTextValue(value: unknown): string | null {
  const text = stringValue(value);
  if (!text || text.length > 120) {
    return null;
  }

  return text;
}

/**
 * Returns a low-cardinality safe error code for status documents.
 * @param {unknown} error Raw error.
 * @return {string} Safe error code.
 */
function safeErrorCode(error: unknown): string {
  if (error instanceof Error && error.name.trim().length > 0) {
    return error.name.slice(0, 64);
  }

  return "unknown";
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
  completionRankSnapshotWrite,
  finisherStatusWrite,
  firstAscentWrite,
  leaderboardHasFirstAscent,
  liveClimbPublishStatusFailedWrite,
  liveClimbPublishStatusPublishedWrite,
  liveClimbPublishStatusPublishingWrite,
  nextGlobalCompletionOrder,
  parseLiveClimbReplayPayload,
  replayEntryWrite,
  replaySummaryWrite,
  shouldDeleteCompletionRankSnapshot,
};
