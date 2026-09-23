import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  MAX_REPLAY_SPLIT_CHECKPOINTS,
  normalizeReplaySplitSteps,
} from "./liveReplaySplitNormalization.js";
import {
  RaceAttemptCurve,
  raceGoalKeysByWorkoutId,
  sameGoalKeys,
} from "./liveReplayRaceBest.js";
import {
  HEADPHONE_MOTION_SOURCE,
  isRecoverableLegacyCompletion,
} from "./legacyClimbCompletion.js";
import {
  ANONYMOUS_CLIMBER_NAME,
  PUBLIC_IDENTITY_STATE_DELETED,
  PUBLIC_IDENTITY_STATE_PENDING,
  PUBLIC_IDENTITY_STATE_PUBLISHED,
  PublicIdentityState,
  isAnonymousClimberName,
  publicIdentityFromData,
} from "./publicIdentity.js";

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
const ROUTINE_TEMPLATE_CONTEXT_TYPE = "routine_template";
const ROUTINE_TRACKING_MODE = "routine";
const CLIMB_ATTEMPT_PARTICIPATION_TYPE = "climb_attempt";
const TARGET_REACHED_STOP_REASON = "target_reached";
const USER_STOPPED_REASON = "user_stopped";
const FIRESTORE_NOT_FOUND_CODE = 5;
const BULK_WRITER_MAX_ATTEMPTS = 3;
const ATTEMPT_CURVES_COLLECTION = "attemptCurves";
const FINISHERS_COLLECTION = "finishers";
/**
 * The split interval every producer has ever published at, assumed for an
 * entry written before the interval was stored on it.
 */
const DEFAULT_SPLIT_INTERVAL_SECONDS = 10;

/**
 * What produced the completions a replay summary counts.
 *
 * The seed scripts stamp `seeded` on a board they populate with synthetic
 * competitors, and operators read it to mean "no real climber is on this
 * board". Nothing else maintained it, so a board that later took genuine
 * finishes still reported itself as seeded, and the field could not be trusted
 * for the one question it exists to answer.
 *
 * A publish therefore restamps it: once a real completion lands, the board is
 * live, whatever synthetic rows still stand beside it. `seedPackId` and
 * `seededAttemptCount` keep saying how many of those rows the seed wrote, so
 * nothing is lost by moving this one field off `seeded`.
 * `scripts/seed/lib/live-replay-summary-source.mjs` is the same two values on
 * the seed side; the two must agree.
 */
const REPLAY_SUMMARY_SOURCE_LIVE = "live";

/**
 * The field a context ranks its completions on.
 *
 * A climb fixes the step target and lets the clock vary, so the fastest run
 * wins. A routine inverts that: its intervals fix the clock, so every finisher
 * spends the same time and only the steps taken inside that window separate
 * them. Ranking a routine on duration would rank tracking jitter and reward the
 * shortest session, so routines rank on steps instead.
 */
const DURATION_RANKING_METRIC = "completionDurationSeconds";
const STEPS_RANKING_METRIC = "finalSteps";

/**
 * The finisher field holding one climber's standing best on each metric. The
 * finishers subcollection is one document per climber, so counting these
 * counts climbers - the population a collapsing board's denominator counts.
 */
const DURATION_BEST_METRIC = "bestCompletionDurationSeconds";
const STEPS_BEST_METRIC = "bestFinalSteps";

/**
 * Tie policies, one per ranking metric, stored on every rank snapshot so a
 * reader never has to infer how equal values were resolved.
 */
const DURATION_TIE_POLICY = "competition_rank_equal_durations_share_rank";
const STEPS_TIE_POLICY = "competition_rank_equal_steps_share_rank";

interface LiveReplayIndexPayload {
  contextKey: string;
  contextType: string;
  contextId: string;
  splitIntervalSeconds: number;
  splitSteps: number[];
  finalDurationSeconds: number;
  finalSteps: number;
  targetStepCount: number | null;
  /**
   * The clock the session was guided against, when the mode has one. A routine
   * fixes this, and steps only rank honestly between runs of the same length,
   * so every routine row records the window it was run in. See
   * `routineWindowFields`.
   */
  targetDurationSeconds: number | null;
  /**
   * Whether this row may claim an unheld First Ascent. Modern completions that
   * clear the strict gate are eligible; rows recovered through the legacy-shape
   * fallback never are, because a First Ascent is permanent and
   * hand-derived/backfilled data must never claim one.
   */
  firstAscentEligible: boolean;
}

export interface PublicUserSnapshot {
  displayName: string;
  avatarToken: string;
  photoURL: string | null;
  identityState: PublicIdentityState;
  age?: number | null;
  gender?: string | null;
  locationCity?: string | null;
}

export interface IdentityProtectedTransactionPort<Transaction> {
  runTransaction(
    operation: (transaction: Transaction) => Promise<void>
  ): Promise<void>;
  readCurrentPublicUser(
    transaction: Transaction,
    userId: string
  ): Promise<PublicUserSnapshot>;
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
  /** Null in contexts that publish no flag, so the field stays absent. */
  isBestForUser: boolean | null;
  /**
   * The goal keys this attempt is its climber's best under, or null on a
   * board that races no goals, so the field stays absent there.
   */
  bestForGoals: string[] | null;
  updatedAt: unknown;
}

/**
 * One published attempt, as seen from its bucket-zero entry document.
 */
interface UserAttemptEntry {
  workoutId: string;
  /**
   * The value the live race collapses this climber's attempts on
   * (`raceMetric`): steps on a Just Climb or a routine template, seconds on a
   * tower or a plain routine.
   */
  raceValue: number;
  /**
   * The value this attempt ranks on in the board's own metric
   * (`rankingMetric`) - what the finisher's standing best and every frozen
   * standing use. The two coincide everywhere but on a Just Climb.
   */
  rankingValue: number;
  finalSteps: number;
  completionDurationSeconds: number;
  splitIntervalSeconds: number;
  splitBucketCount: number;
  isBestForUser: boolean;
  /** The goal keys this entry carries, sorted; empty where it carries none. */
  bestForGoals: string[];
}

interface BestForUserFlagUpdate {
  workoutId: string;
  splitBucketCount: number;
  isBestForUser?: boolean;
  bestForGoals?: string[];
}

/**
 * A board a climber's flags are reconciled on: the two facts every replay
 * payload carries that reconciliation actually reads.
 */
interface ReplayContextRef {
  contextKey: string;
  contextType: string;
}

/**
 * What the field looked like when an attempt froze its standing, counted in
 * whichever population the board beside that standing counts.
 */
interface CompletionFieldReading {
  /**
   * Rows standing strictly ahead of this attempt. A collapsing context counts
   * finisher documents, which are one per climber by construction, measured
   * against the climber's best *after* this attempt; every other context counts
   * every published attempt as its own rival.
   */
  betterRowCount: number;
  /**
   * Published attempts in the context, this one included - the frozen stamp's
   * denominator on `just_climb` and `routine` (Option A). Null where the board
   * collapses repeat finishers instead, whose denominator is the
   * distinct-finisher count the publish transaction resolves.
   */
  attemptCount: number | null;
}

/**
 * The permanent pair stamped on a finished attempt: a position and the
 * population it was measured against.
 */
interface FrozenCompletionStanding {
  rank: number;
  population: number;
}

interface CompletionRankSnapshotWriteInput {
  payload: LiveReplayIndexPayload;
  userId: string;
  entryId: string;
  rank: number;
  /**
   * The population `rank` was measured against - distinct climbers where the
   * board collapses repeat finishers, published attempts where it does not.
   * Never a count of something the rank did not count.
   */
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
  /** The population `rankAtCompletion` was measured against. */
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
      for (const payload of beforePayloads) {
        await deleteReplayEntriesForId(payload, workoutId);
        if (shouldDeleteCompletionRankSnapshot(payload, afterPayloads)) {
          await deleteCompletionRankSnapshot(payload, workoutId);
        }
      }

      for (const payload of afterPayloads) {
        await publishReplayEntries(
          payload,
          workoutId,
          userId
        );
      }

      for (const payload of beforePayloads) {
        await deleteReplayEntriesForId(payload, userId);
        await deleteUserBestAttempt(payload, userId);
      }

      for (const payload of afterPayloads) {
        await deleteReplayEntriesForId(payload, userId);
        await deleteUserBestAttempt(payload, userId);
      }

      for (const payload of touchedReplayPayloads(
        beforePayloads,
        afterPayloads
      )) {
        await reconcileUserBestEntries(payload, userId);
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
 * Routine sessions publish only into their own template's context.
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
    parseRoutineReplayPayload(data, options),
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

  const climbId = stringValue(parsed.metadata.climbId);
  if (!climbId) {
    return null;
  }

  // Two publication paths: the strict modern gate (participation + trackingMode
  // + target_reached), which is First Ascent eligible, and a narrow legacy
  // fallback gated on the shared isRecoverableLegacyCompletion contract, which
  // publishes rows/finishers but is NOT First Ascent eligible. Legacy backups
  // lack the participation/trackingMode the modern gate needs, so without this
  // fallback their earned completions have zero public presence.
  const modernCompleted = hasCompletedLiveClimbAttempt(parsed);
  const legacyCompleted = !modernCompleted &&
    !parsed.hasClimbAttemptParticipation &&
    isLegacyRecoverableLiveClimb(parsed, climbId);

  if (
    options.requireEligibleParticipation &&
    !modernCompleted &&
    !legacyCompleted
  ) {
    return null;
  }

  return replayPayload(
    parsed,
    LIVE_CLIMB_CONTEXT_TYPE,
    climbId,
    {firstAscentEligible: modernCompleted}
  );
}

/**
 * Returns whether a headphone-motion backup is a trusted legacy landmark
 * completion, using the shared contract mirrored from the Swift guard. This
 * never implies First Ascent eligibility - the caller withholds First Ascent
 * for every legacy-recovered row.
 * @param {ParsedReplayPayloadParts} parsed Parsed replay payload parts.
 * @param {string} climbId Non-empty landmark id from the metadata.
 * @return {boolean} True when the backup may publish a replay row.
 */
function isLegacyRecoverableLiveClimb(
  parsed: ParsedReplayPayloadParts,
  climbId: string
): boolean {
  return isRecoverableLegacyCompletion({
    source: HEADPHONE_MOTION_SOURCE,
    climbId,
    stopReason: stringValue(parsed.metadata.stopReason) ?? "",
    steps: parsed.finalSteps,
    targetStepCount: parsed.targetStepCount,
  });
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

/**
 * Converts a completed routine session into its template's replay payload.
 *
 * Only catalog templates publish. A user-created routine is identified by a
 * private UUID nobody else can run, so its board could only ever hold its
 * author - and the client already marks those participations ineligible, so
 * requiring eligibility below excludes them without a second rule here.
 *
 * The template ID is the whole comparability guarantee: steps only rank
 * honestly between climbers who ran the same intervals for the same clock, and
 * one board holds exactly one template. Editing a published template's
 * intervals changes that clock, which would silently compare runs of different
 * lengths on one board - see the routine section of `ascend-routines`.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @param {{requireEligibleParticipation: boolean}} options Parse options.
 * @return {LiveReplayIndexPayload | null} Parsed replay payload, if valid.
 */
function parseRoutineReplayPayload(
  data: Record<string, unknown> | undefined,
  options: {requireEligibleParticipation: boolean}
): LiveReplayIndexPayload | null {
  const parsed = parseReplayPayloadParts(data);
  if (!parsed) {
    return null;
  }

  if (stringValue(parsed.metadata.trackingMode) !== ROUTINE_TRACKING_MODE) {
    return null;
  }

  const templateId = stringValue(parsed.metadata.routineTemplateId);
  if (!templateId) {
    return null;
  }

  if (
    options.requireEligibleParticipation &&
    !hasCompletedRoutineTemplateSession(parsed)
  ) {
    return null;
  }

  // A First Ascent is landmark prestige and belongs to climbs. A routine board
  // ranks steps and mints no first-ever claim, so it never seeds one.
  return replayPayload(
    parsed,
    ROUTINE_TEMPLATE_CONTEXT_TYPE,
    templateId,
    {firstAscentEligible: false}
  );
}

/**
 * Returns whether a routine backup may publish a replay row.
 *
 * Unlike a climb, a routine's stop reason *is* the verdict: the client resolves
 * it once in `HeadphoneMotionSessionStopReason.earnsCompetitiveCredit`, and a
 * session containing any skipped interval finishes as `skipped` because a skip
 * burns the routine clock without taking steps. Reading `target_reached` here
 * mirrors that single decision rather than re-deriving a competing one.
 * @param {ParsedReplayPayloadParts} parsed Parsed replay payload parts.
 * @return {boolean} True when the row may be published publicly.
 */
function hasCompletedRoutineTemplateSession(
  parsed: ParsedReplayPayloadParts
): boolean {
  return parsed.hasEligibleRoutineTemplateParticipation &&
    stringValue(parsed.metadata.stopReason) === TARGET_REACHED_STOP_REASON &&
    parsed.finalSteps > 0 &&
    parsed.finalDurationSeconds > 0;
}

interface ParsedReplayPayloadParts {
  metadata: Record<string, unknown>;
  hasClimbAttemptParticipation: boolean;
  hasEligibleRoutineTemplateParticipation: boolean;
  splitIntervalSeconds: number;
  splitSteps: number[];
  finalDurationSeconds: number;
  finalSteps: number;
  targetStepCount: number | null;
  targetDurationSeconds: number | null;
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
  const targetDurationSeconds = nonNegativeNumberValue(
    metadata.targetDurationSeconds
  );

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
    hasClimbAttemptParticipation: hasParticipation(
      data.participations,
      CLIMB_ATTEMPT_PARTICIPATION_TYPE
    ),
    hasEligibleRoutineTemplateParticipation: hasEligibleParticipation(
      data.participations,
      ROUTINE_TEMPLATE_CONTEXT_TYPE,
      stringValue(metadata.routineTemplateId) ?? undefined
    ),
    splitIntervalSeconds,
    splitSteps,
    finalDurationSeconds,
    finalSteps,
    targetStepCount,
    targetDurationSeconds,
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
 *
 * Every condition below is re-derived here from the backed-up workout. The gate
 * never reads the participation's `leaderboardEligible` boolean, which is the
 * client asserting its own eligibility with nothing behind it. This matches
 * parseCompletedLandmarkWorkout, which already derives "finished a landmark"
 * from the same evidence fields and likewise ignores the flag.
 *
 * Known residual: `parsed.targetStepCount` is the client's own
 * `climbTargetStepCount`/`targetStepCount` metadata, so `finalSteps >= target`
 * compares a claimed step count against a claimed target. The server cannot
 * derive the canonical target today - the landmark catalog ships as a static
 * Hosting asset (web/public/climbs/catalog-v1.json), and Firestore holds no
 * climb collection this trigger could read. Stating that out loud is the point:
 * it is an acknowledged gap in this gate, not a silent fallback. Closing it
 * needs a server-readable catalog, which is its own change.
 *
 * Deliberate consequence: the gate grandfathers a completion recorded against
 * the step target that existed when it was climbed. A catalog correction must
 * never retroactively void an earned completion or its First Ascent, so the
 * client's `leaderboardEligible: false` stays ignored even when a later,
 * higher catalog target would fail the device's local completion check. That
 * grandfathering is load-bearing rather than hypothetical: one change corrected
 * `referenceStepCount` on 32 already-shipped climbs when verified
 * `realStairCount` values landed (docs/climb-real-stair-counts.md), and any
 * future correction moves a target again. A row published under the old
 * distance stays published.
 * @param {ParsedReplayPayloadParts} parsed Parsed replay payload parts.
 * @return {boolean} True when the row may be published publicly.
 */
function hasCompletedLiveClimbAttempt(
  parsed: ParsedReplayPayloadParts
): boolean {
  if (!parsed.hasClimbAttemptParticipation) {
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
  options: {targetStepCount?: number | null; firstAscentEligible?: boolean} = {}
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
    targetDurationSeconds: parsed.targetDurationSeconds,
    firstAscentEligible: options.firstAscentEligible !== false,
  };
}

/**
 * Records the guided clock a steps-ranked row was run against.
 *
 * A routine board ranks steps, which is only comparable between runs of the
 * same length. One board holds exactly one template ID, so it can never mix
 * templates - but a published template's intervals can be edited in place under
 * that stable ID, and neither the template's `version` nor the workout's
 * participation `contextVersion` tracks the change. Stamping the window on
 * every row keeps a shortened or lengthened routine visible in the data instead
 * of silently ranking a 10-minute run against a 20-minute one. The supported
 * way to change a published routine's intervals is to publish a new template
 * ID, which starts a new board.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @return {Record<string, unknown>} Window field, or an empty object.
 */
function routineWindowFields(
  payload: LiveReplayIndexPayload
): Record<string, unknown> {
  if (!ranksOnSteps(payload.contextType) ||
    payload.targetDurationSeconds === null) {
    return {};
  }

  return {targetDurationSeconds: payload.targetDurationSeconds};
}

/**
 * Returns whether a workout carries a leaderboard-eligible participation of one
 * context type. The routine board gates on this flag; the climb modes
 * deliberately ignore the client's `leaderboardEligible` assertion and
 * re-derive eligibility from re-checked evidence instead - see
 * hasCompletedLiveClimbAttempt. When `contextId` is given, the eligible
 * participation must also be scoped to it, so a workout can never publish
 * onto a board whose eligibility verdict was issued for a different context.
 * @param {unknown} value Raw participations value.
 * @param {string} contextType Participation context type to match.
 * @param {string} [contextId] Participation context ID to match, if scoped.
 * @return {boolean} True when the workout can be indexed for replay.
 */
function hasEligibleParticipation(
  value: unknown,
  contextType: string,
  contextId?: string
): boolean {
  if (!Array.isArray(value)) {
    return false;
  }

  return value.some((item) => {
    if (!item || typeof item !== "object") {
      return false;
    }

    const participation = item as Record<string, unknown>;
    return participation.contextType === contextType &&
      participation.leaderboardEligible === true &&
      (contextId === undefined || participation.contextId === contextId);
  });
}

/**
 * Returns whether a workout carries any participation of one context type,
 * eligible or not. This is a shape check, not an eligibility check: the
 * `leaderboardEligible` flag is deliberately NOT read, so a modified client
 * cannot grant itself a row by flipping it. The legacy-shape fallback only
 * fires when none exists: a workout with a climb-attempt participation is
 * governed by the modern gate, so an explicitly ineligible one stays
 * deliberately unpublished, not resurrected.
 * @param {unknown} value Raw participations value.
 * @param {string} contextType Participation context type to match.
 * @return {boolean} True when a matching participation is present.
 */
function hasParticipation(value: unknown, contextType: string): boolean {
  if (!Array.isArray(value)) {
    return false;
  }

  return value.some((item) => {
    if (!item || typeof item !== "object") {
      return false;
    }

    return (item as Record<string, unknown>).contextType === contextType;
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
  // Only a Just Climb writes one, and deleting an absent document is a no-op,
  // so every context deletes unconditionally rather than re-deriving here
  // which boards race goals.
  writer.delete(attemptCurveReference(payload, entryId));
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
 * Every replay context one workout write touched, once each.
 * A workout can leave one context and enter another in a single write, so both
 * sides need their best-per-user flag re-derived.
 * @param {LiveReplayIndexPayload[]} beforePayloads Pre-write payloads.
 * @param {LiveReplayIndexPayload[]} afterPayloads Post-write payloads.
 * @return {LiveReplayIndexPayload[]} One payload per touched context key.
 */
function touchedReplayPayloads(
  beforePayloads: LiveReplayIndexPayload[],
  afterPayloads: LiveReplayIndexPayload[]
): LiveReplayIndexPayload[] {
  const payloadsByContextKey = new Map<string, LiveReplayIndexPayload>();

  for (const payload of [...afterPayloads, ...beforePayloads]) {
    if (!payloadsByContextKey.has(payload.contextKey)) {
      payloadsByContextKey.set(payload.contextKey, payload);
    }
  }

  return [...payloadsByContextKey.values()];
}

/**
 * Whether a context's frozen standing counts climbers rather than attempts.
 *
 * That is all it decides now. Every context type carries `isBestForUser` and
 * every live-race read filters on it (settled by the captain on 2026-09-02),
 * so this predicate gates neither `seedBestForUser` nor
 * `reconcileUserBestEntries`; it shapes `readCompletionField` and
 * `ownLeadingFinisherCount` only. Widening it changes write-once
 * `completionSnapshots` arithmetic, which is a separate decision.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @return {boolean} True when the context collapses repeat finishers.
 */
function collapsesRepeatFinishers(payload: LiveReplayIndexPayload): boolean {
  return payload.contextType === LIVE_CLIMB_CONTEXT_TYPE ||
    payload.contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE;
}

/**
 * Seeds the best-per-user flag for an attempt about to publish.
 *
 * reconcileUserBestEntries is the authority; this seed only lets a new best
 * race immediately. Judged against the climber's other published attempts on
 * the board, read just before the transaction: a republish of the standing
 * best (a workout edit fires this trigger too) is its own workout id among
 * them and so keeps its flag, and a first attempt has nobody to lose to.
 *
 * Read from the entries rather than the finisher document because the two
 * bests are not the same number on a Just Climb: the finisher's stored best
 * is the board's ranking metric, and the race collapses on `raceMetric`.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} entryId Public row document ID.
 * @param {UserAttemptEntry[]} attempts The climber's published attempts here.
 * @return {boolean} Seed flag.
 */
function seedBestForUser(
  payload: LiveReplayIndexPayload,
  entryId: string,
  attempts: UserAttemptEntry[]
): boolean {
  const candidate: UserAttemptEntry = {
    workoutId: entryId,
    raceValue: attemptRaceValue(payload),
    rankingValue: attemptRankingValue(payload),
    finalSteps: payload.finalSteps,
    completionDurationSeconds: payload.finalDurationSeconds,
    splitIntervalSeconds: payload.splitIntervalSeconds,
    splitBucketCount: payload.splitSteps.length,
    isBestForUser: false,
    bestForGoals: [],
  };
  const field = [
    ...attempts.filter((attempt) => attempt.workoutId !== entryId),
    candidate,
  ];

  return bestAttemptWorkoutId(field, payload.contextType) === entryId;
}

/**
 * Selects a user's best completion in a context on the race metric: the
 * highest steps where the race collapses on steps, the fastest time
 * otherwise. Equal values resolve on workout ID so every caller picks the
 * same winner.
 * @param {UserAttemptEntry[]} attempts Published attempts for one user.
 * @param {string} contextType Replay context type.
 * @return {UserAttemptEntry | null} Winner, or null when there are none.
 */
function bestAttempt(
  attempts: UserAttemptEntry[],
  contextType: string
): UserAttemptEntry | null {
  return bestOf(
    attempts,
    (attempt) => attempt.raceValue,
    raceBestOnSteps(contextType)
  );
}

/**
 * Selects the workout owning a user's best completion in a context.
 * @param {UserAttemptEntry[]} attempts Published attempts for one user.
 * @param {string} contextType Replay context type.
 * @return {string | null} Winning workout ID, or null when there are none.
 */
function bestAttemptWorkoutId(
  attempts: UserAttemptEntry[],
  contextType: string
): string | null {
  return bestAttempt(attempts, contextType)?.workoutId ?? null;
}

/**
 * Selects the attempt the finisher document's standing best belongs to: the
 * best on the board's own ranking metric, which is what the frozen and the
 * recomputed standings count. On a Just Climb this is the fastest completion
 * while the race best is the most steps, so the two are chosen separately.
 * @param {UserAttemptEntry[]} attempts Published attempts for one user.
 * @param {string} contextType Replay context type.
 * @return {UserAttemptEntry | null} Winner, or null when there are none.
 */
function rankingBestAttempt(
  attempts: UserAttemptEntry[],
  contextType: string
): UserAttemptEntry | null {
  return bestOf(
    attempts,
    (attempt) => attempt.rankingValue,
    ranksOnSteps(contextType)
  );
}

/**
 * The attempt with the best value, ties resolved on workout ID.
 * @param {UserAttemptEntry[]} attempts Candidates.
 * @param {(attempt: UserAttemptEntry) => number} value Measure.
 * @param {boolean} higherWins Whether a higher value is better.
 * @return {UserAttemptEntry | null} Winner, or null when there are none.
 */
function bestOf(
  attempts: UserAttemptEntry[],
  value: (attempt: UserAttemptEntry) => number,
  higherWins: boolean
): UserAttemptEntry | null {
  let best: UserAttemptEntry | null = null;

  for (const attempt of attempts) {
    const isBetter = best === null ||
      (higherWins ?
        value(attempt) > value(best) :
        value(attempt) < value(best));
    const breaksTie = best !== null &&
      value(attempt) === value(best) &&
      attempt.workoutId < best.workoutId;

    if (isBetter || breaksTie) {
      best = attempt;
    }
  }

  return best;
}

/**
 * Diffs a user's published attempts against the best-per-user rule.
 * Attempts already carrying the right flag are omitted so reconciliation
 * settles to zero writes once a context is correct.
 *
 * `goalKeysByWorkoutId` is the goal-aware half on a board that races goals:
 * an attempt whose stored `bestForGoals` disagrees with the derived list is
 * updated too, in the same write as its flag where both moved.
 * @param {UserAttemptEntry[]} attempts Published attempts for one user.
 * @param {string} contextType Replay context type.
 * @param {Map<string, string[]> | null} goalKeysByWorkoutId Derived goal keys,
 *   or null where the board races no goals.
 * @return {BestForUserFlagUpdate[]} Attempts whose flags must change.
 */
function bestForUserFlagUpdates(
  attempts: UserAttemptEntry[],
  contextType: string,
  goalKeysByWorkoutId: Map<string, string[]> | null = null
): BestForUserFlagUpdate[] {
  const winningWorkoutId = bestAttemptWorkoutId(attempts, contextType);
  const updates: BestForUserFlagUpdate[] = [];

  for (const attempt of attempts) {
    const update: BestForUserFlagUpdate = {
      workoutId: attempt.workoutId,
      splitBucketCount: attempt.splitBucketCount,
    };
    const isBestForUser = attempt.workoutId === winningWorkoutId;

    if (isBestForUser !== attempt.isBestForUser) {
      update.isBestForUser = isBestForUser;
    }

    const goalKeys = goalKeysByWorkoutId?.get(attempt.workoutId);
    if (
      goalKeys !== undefined &&
      !sameGoalKeys(attempt.bestForGoals, goalKeys)
    ) {
      update.bestForGoals = goalKeys;
    }

    if (
      update.isBestForUser !== undefined ||
      update.bestForGoals !== undefined
    ) {
      updates.push(update);
    }
  }

  return updates;
}

/**
 * The fields one flag update writes to each of an attempt's bucket entries.
 * @param {BestForUserFlagUpdate} update Flag update.
 * @return {Record<string, unknown>} Fields to `update()`.
 */
function flagUpdateFields(
  update: BestForUserFlagUpdate
): Record<string, unknown> {
  const fields: Record<string, unknown> = {};
  if (update.isBestForUser !== undefined) {
    fields.isBestForUser = update.isBestForUser;
  }
  if (update.bestForGoals !== undefined) {
    fields.bestForGoals = update.bestForGoals;
  }
  return fields;
}

/**
 * Bucket span to sweep when re-flagging a published attempt.
 * Entries written before best-per-user collapse carry no stored span, and
 * normalizeReplaySplitSteps sized the curve on the raw sample count as well as
 * the duration, so duration alone can undercount the real span. Legacy attempts
 * therefore sweep the whole checkpoint range: flags are written with update(),
 * so buckets an attempt never published into fail NOT_FOUND and are skipped,
 * whereas undercounting would strand the final bucket of a promoted climber.
 * @param {Record<string, unknown>} data Bucket-zero entry data.
 * @return {number} Number of buckets to sweep for the attempt.
 */
function attemptSplitBucketCount(data: Record<string, unknown>): number {
  const storedCount = positiveIntegerValue(data.splitBucketCount);

  if (storedCount === null) {
    return MAX_REPLAY_SPLIT_CHECKPOINTS;
  }

  return Math.min(storedCount, MAX_REPLAY_SPLIT_CHECKPOINTS);
}

/**
 * Reads one published attempt from its bucket-zero entry document, taking its
 * race value from the metric the live race collapses on and its ranking
 * value from the metric the board ranks on.
 * @param {Record<string, unknown>} data Bucket-zero entry data.
 * @param {string} documentId Entry document ID.
 * @param {string} contextType Replay context type.
 * @return {UserAttemptEntry | null} Parsed attempt, or null when unusable.
 */
function userAttemptEntry(
  data: Record<string, unknown>,
  documentId: string,
  contextType: string
): UserAttemptEntry | null {
  const finalSteps = nonNegativeIntegerValue(data.finalSteps);
  const completionDurationSeconds = nonNegativeNumberValue(
    data.completionDurationSeconds
  );
  const raceValue = raceBestOnSteps(contextType) ?
    finalSteps :
    completionDurationSeconds;
  const rankingValue = ranksOnSteps(contextType) ?
    finalSteps :
    completionDurationSeconds;

  if (raceValue === null || rankingValue === null) {
    return null;
  }

  return {
    workoutId: stringValue(data.workoutId) ?? documentId,
    raceValue,
    rankingValue,
    finalSteps: finalSteps ?? 0,
    completionDurationSeconds: completionDurationSeconds ?? 0,
    splitIntervalSeconds: positiveIntegerValue(data.splitIntervalSeconds) ??
      DEFAULT_SPLIT_INTERVAL_SECONDS,
    splitBucketCount: attemptSplitBucketCount(data),
    isBestForUser: data.isBestForUser === true,
    bestForGoals: goalKeyListValue(data.bestForGoals),
  };
}

/**
 * The climber's published attempts on one board, from their bucket-zero
 * entries - every run of theirs, flagged or not.
 * @param {ReplayContextRef} context Board.
 * @param {string} userId Owner user ID.
 * @return {Promise<UserAttemptEntry[]>} Parsed attempts.
 */
async function readUserAttempts(
  context: ReplayContextRef,
  userId: string
): Promise<UserAttemptEntry[]> {
  const snapshot = await entriesCollectionReference(context, 0)
    .where("userId", "==", userId)
    .get();

  return snapshot.docs
    .map((doc) => userAttemptEntry(doc.data(), doc.id, context.contextType))
    .filter((attempt): attempt is UserAttemptEntry => attempt !== null);
}

/**
 * Re-derives which of a user's attempts is their best in one replay context.
 *
 * A live race ranks one row per opponent, so at most one of a user's attempts
 * may carry isBestForUser. Publishes, edits and deletes all funnel through here
 * so the flag heals itself from the entries rather than from flip bookkeeping.
 *
 * Every context type maintains it, including the ones that do not collapse
 * repeat finishers in their frozen standing. Settled by the captain on
 * 2026-09-02: all three board types race off one mechanism rather than one of
 * them behaving differently because it is missing a piece of data. Without the
 * flag an open Just Climb raced a rival's four runs as four opponents and
 * showed a climber their own earlier attempts as racers.
 *
 * On a board that races goals (`contextRacesGoals`) the same pass derives
 * every attempt's `bestForGoals` from the climber's split curves, so a goal
 * session's window and marker are answered by the same entries. The curves
 * come from `attemptCurves`, and an attempt published before that collection
 * existed has its curve rebuilt from its own bucket entries and stored, so
 * the rebuild is paid once.
 *
 * `collapsesRepeatFinishers` still decides what the SERVER's frozen standing
 * counts, and that is all it decides now - do not re-gate this on it.
 * @param {ReplayContextRef} context Board.
 * @param {string} userId Owner user ID.
 */
async function reconcileUserBestEntries(
  context: ReplayContextRef,
  userId: string
): Promise<void> {
  const attempts = await readUserAttempts(context, userId);
  const rankingWinner = rankingBestAttempt(attempts, context.contextType);

  if (rankingWinner !== null) {
    await repairFinisherBestAttempt(context, userId, rankingWinner);
  }

  const goalKeysByWorkoutId = contextRacesGoals(context.contextType) ?
    raceGoalKeysByWorkoutId(
      await readAttemptCurves(context, userId, attempts)
    ) :
    null;
  const updates = bestForUserFlagUpdates(
    attempts,
    context.contextType,
    goalKeysByWorkoutId
  );

  if (updates.length === 0) {
    return;
  }

  const writer = admin.firestore().bulkWriter();
  const failures: unknown[] = [];
  writer.onWriteError((error) => {
    if (error.code === FIRESTORE_NOT_FOUND_CODE) {
      return false;
    }

    return error.failedAttempts < BULK_WRITER_MAX_ATTEMPTS;
  });

  for (const update of updates) {
    const fields = flagUpdateFields(update);
    for (let index = 0; index < update.splitBucketCount; index += 1) {
      // update() rather than set(): a bucket the attempt never published into
      // must stay absent, not appear as a flag-only row the counts would see.
      writer
        .update(entryReference(context, index, update.workoutId), fields)
        .catch((error) => {
          if (!isNotFoundWriteError(error)) {
            failures.push(error);
          }
        });
    }
  }

  await writer.close();

  if (failures.length > 0) {
    // A dropped flag write leaves a climber duplicated in the live field, so
    // fail the trigger and let its retry re-derive rather than report success.
    throw new Error(
      `Failed to reconcile ${failures.length} best-per-user entry ` +
      `write(s) for user ${userId} in ${context.contextKey}: ${
        String(failures[0])
      }`
    );
  }
}

/**
 * The split curves behind a climber's attempts on a board that races goals.
 *
 * Read from `attemptCurves`, one document per attempt written in the publish
 * transaction. An attempt with none - published before the collection
 * existed - is rebuilt from the `stepsAtBucket` of its own bucket entries and
 * the rebuilt curve is stored, so the next reconciliation is a document read
 * again. An attempt whose curve cannot be rebuilt at all falls back to a
 * straight line from start to finish, which is what the client's projection
 * draws for it anyway.
 * @param {ReplayContextRef} context Board.
 * @param {string} userId Owner user ID.
 * @param {UserAttemptEntry[]} attempts The climber's published attempts.
 * @return {Promise<RaceAttemptCurve[]>} One curve per attempt.
 */
async function readAttemptCurves(
  context: ReplayContextRef,
  userId: string,
  attempts: UserAttemptEntry[]
): Promise<RaceAttemptCurve[]> {
  if (attempts.length === 0) {
    return [];
  }

  const db = admin.firestore();
  const snapshots = await db.getAll(
    ...attempts.map((attempt) =>
      attemptCurveReference(context, attempt.workoutId)
    )
  );
  const curves: RaceAttemptCurve[] = [];
  const writer = db.bulkWriter();

  for (let index = 0; index < attempts.length; index += 1) {
    const attempt = attempts[index];
    const stored = attemptCurveFromData(attempt, snapshots[index].data());

    if (stored !== null) {
      curves.push(stored);
      continue;
    }

    const rebuilt = await rebuildAttemptCurve(context, attempt);
    curves.push(rebuilt);
    writer.set(
      attemptCurveReference(context, attempt.workoutId),
      attemptCurveWrite(
        userId,
        rebuilt,
        admin.firestore.FieldValue.serverTimestamp()
      )
    ).catch(() => {
      // Storing the rebuild is a saving on the next pass, not a correctness
      // step: the curve in hand is already what this pass derives from.
    });
  }

  await writer.close();
  return curves;
}

/**
 * Rebuilds an attempt's split curve from its own bucket entries.
 * @param {ReplayContextRef} context Board.
 * @param {UserAttemptEntry} attempt The attempt.
 * @return {Promise<RaceAttemptCurve>} The curve, straight-lined when no bucket
 *   entry could be read.
 */
async function rebuildAttemptCurve(
  context: ReplayContextRef,
  attempt: UserAttemptEntry
): Promise<RaceAttemptCurve> {
  const references = [];
  for (let index = 0; index < attempt.splitBucketCount; index += 1) {
    references.push(entryReference(context, index, attempt.workoutId));
  }

  const splitSteps: number[] = [];
  for (let start = 0; start < references.length; start += 100) {
    const snapshots = await admin.firestore().getAll(
      ...references.slice(start, start + 100)
    );
    let ended = false;
    for (const snapshot of snapshots) {
      const steps = nonNegativeIntegerValue(snapshot.data()?.stepsAtBucket);
      if (steps === null) {
        ended = true;
        break;
      }
      splitSteps.push(steps);
    }
    if (ended) {
      break;
    }
  }

  return {
    workoutId: attempt.workoutId,
    finalSteps: attempt.finalSteps,
    finalDurationSeconds: attempt.completionDurationSeconds,
    splitIntervalSeconds: attempt.splitIntervalSeconds,
    splitSteps,
  };
}

/**
 * Parses a stored attempt curve, or null when the document is absent or
 * unusable so the caller rebuilds it.
 * @param {UserAttemptEntry} attempt The attempt the curve belongs to.
 * @param {Record<string, unknown> | undefined} data Curve document data.
 * @return {RaceAttemptCurve | null} The curve, or null.
 */
function attemptCurveFromData(
  attempt: UserAttemptEntry,
  data: Record<string, unknown> | undefined
): RaceAttemptCurve | null {
  const splitSteps = data ? integerArrayValue(data.splitSteps) : null;
  if (!data || splitSteps === null) {
    return null;
  }

  return {
    workoutId: attempt.workoutId,
    finalSteps: nonNegativeIntegerValue(data.finalSteps) ?? attempt.finalSteps,
    finalDurationSeconds: nonNegativeNumberValue(data.finalDurationSeconds) ??
      attempt.completionDurationSeconds,
    splitIntervalSeconds: positiveIntegerValue(data.splitIntervalSeconds) ??
      attempt.splitIntervalSeconds,
    splitSteps,
  };
}

/**
 * The fields an attempt's curve document carries. No identity: the curve is
 * the climber's own numbers, keyed by uid so reconciliation can find it, and
 * nothing a client can read.
 * @param {string} userId Owner user ID.
 * @param {RaceAttemptCurve} curve The curve.
 * @param {unknown} updatedAt Write timestamp.
 * @return {Record<string, unknown>} Fields to write.
 */
function attemptCurveWrite(
  userId: string,
  curve: RaceAttemptCurve,
  updatedAt: unknown
): Record<string, unknown> {
  return {
    finalDurationSeconds: curve.finalDurationSeconds,
    finalSteps: curve.finalSteps,
    schemaVersion: 1,
    splitIntervalSeconds: curve.splitIntervalSeconds,
    splitSteps: curve.splitSteps,
    updatedAt,
    userId,
    workoutId: curve.workoutId,
  };
}

/**
 * Skips writes to buckets an attempt never published into.
 * @param {unknown} error Rejected BulkWriter write error.
 * @return {boolean} Whether the write failed because the entry is absent.
 */
function isNotFoundWriteError(error: unknown): boolean {
  return typeof error === "object" &&
    error !== null &&
    (error as {code?: unknown}).code === FIRESTORE_NOT_FOUND_CODE;
}

/**
 * Realigns a finisher's stored best fields with the re-derived winner on the
 * board's ranking metric.
 *
 * Nothing else repairs them once the standing best is deleted, and the
 * client's recomputed standing counts finisher documents through these
 * fields. Writes only on disagreement so a settled context still costs no
 * writes.
 * @param {ReplayContextRef} context Board.
 * @param {string} userId Owner user ID.
 * @param {UserAttemptEntry} winner Re-derived best on the ranking metric.
 */
async function repairFinisherBestAttempt(
  context: ReplayContextRef,
  userId: string,
  winner: UserAttemptEntry
): Promise<void> {
  const finisherRef = finisherReference(context, userId);
  const snapshot = await finisherRef.get();

  if (!snapshot.exists) {
    return;
  }

  const data = snapshot.data();

  if (
    stringValue(data?.bestWorkoutId) === winner.workoutId &&
    finisherStoredBest(context.contextType, data) === winner.rankingValue
  ) {
    return;
  }

  await finisherRef.update(finisherBestWrite(
    context.contextType,
    winner.rankingValue,
    winner.workoutId
  ));
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
 */
async function publishReplayEntries(
  payload: LiveReplayIndexPayload,
  entryId: string,
  userId: string
): Promise<void> {
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const leaderboardRef = db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(payload.contextKey);
  const finisherRef = finisherReference(payload, userId);
  const completionSnapshotRef = completionSnapshotReference(payload, entryId);
  const publishStatusRef = liveClimbPublishStatusReference(userId, entryId);
  // The climber's other attempts here decide the seed flag. Read before the
  // transaction on purpose: it is a seed, `reconcileUserBestEntries` runs
  // right after and is the authority, and a query inside the transaction
  // would be re-run on every retry for a number the reconciliation corrects
  // anyway.
  const isBestForUser = seedBestForUser(
    payload,
    entryId,
    await readUserAttempts(payload, userId)
  );
  const racesGoals = contextRacesGoals(payload.contextType);

  await runIdentityProtectedTransaction(
    firestoreIdentityTransactionPort(db),
    userId,
    async (transaction, publicUser) => {
      const completionField = await readCompletionField(
        transaction,
        payload,
        entryId,
        userId
      );
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
      const canClaimFirstAscent = payload.firstAscentEligible &&
      !hasFirstAscent &&
      previousCompletedCount === 0;
      const globalCompletionOrder = nextGlobalCompletionOrder({
        existingOrder,
        previousCompletedCount,
      });
      const completedCount = isNewFinisher ?
        Math.max(previousCompletedCount + 1, globalCompletionOrder) :
        Math.max(previousCompletedCount, globalCompletionOrder);
      // Resolved only where a write consumes it. `completionSnapshots` is
      // write-once, so a republish of an already-frozen attempt discards the
      // standing entirely - and resolving one anyway let a discarded number
      // abort a trigger that had already committed another context's publish,
      // reporting "couldn't sync" for a climb that did sync.
      //
      // This narrows WHEN the guard runs and nothing else. Where a standing is
      // resolved, an impossible rank/population pairing still throws: the
      // deleted Math.min clamp is not back under another name, there is no
      // fallback number, and nothing swallows the error.
      const freezesCompletionSnapshot = !completionSnapshot.exists;
      const publishesLiveClimbStatus =
        payload.contextType === LIVE_CLIMB_CONTEXT_TYPE;
      const standing = freezesCompletionSnapshot || publishesLiveClimbStatus ?
        frozenCompletionStanding({
          reading: completionField,
          completedCount,
          contextKey: payload.contextKey,
        }) :
        null;
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

      if (standing !== null && freezesCompletionSnapshot) {
        transaction.set(
          completionSnapshotRef,
          completionRankSnapshotWrite({
            payload,
            userId,
            entryId,
            rank: standing.rank,
            completedCount: standing.population,
            rankedAt: now,
          })
        );
      }

      if (standing !== null && publishesLiveClimbStatus) {
        transaction.set(
          publishStatusRef,
          liveClimbPublishStatusPublishedWrite({
            payload,
            userId,
            entryId,
            updatedAt: now,
            rankAtCompletion: standing.rank,
            completedCountAtCompletion: standing.population,
            finisherOrder: globalCompletionOrder,
          }),
          {merge: true}
        );
      }

      // The goal keys are seeded empty and filled by the reconciliation that
      // follows in this same trigger: they depend on every other attempt's
      // curve, which is the reconciliation's read, and a climber who has just
      // finished is seconds away from racing nobody.
      for (let index = 0; index < payload.splitSteps.length; index += 1) {
        transaction.set(
          entryReference(payload, index, entryId),
          replayEntryWrite({
            payload,
            userId,
            entryId,
            publicUser,
            stepsAtBucket: payload.splitSteps[index],
            isBestForUser,
            bestForGoals: racesGoals ? [] : null,
            updatedAt: now,
          })
        );
      }

      if (racesGoals) {
        transaction.set(
          attemptCurveReference(payload, entryId),
          attemptCurveWrite(
            userId,
            {
              workoutId: entryId,
              finalSteps: payload.finalSteps,
              finalDurationSeconds: payload.finalDurationSeconds,
              splitIntervalSeconds: payload.splitIntervalSeconds,
              splitSteps: payload.splitSteps,
            },
            now
          )
        );
      }
    }
  );
}

/**
 * Runs projection creation with its canonical identity read in the same
 * transaction. A concurrent identity edit therefore retries the complete
 * projection write instead of leaving a late-created v1 target behind.
 * @param {IdentityProtectedTransactionPort<Transaction>} port Persistence port.
 * @param {string} userId Projection owner.
 * @param {(transaction: Transaction, publicUser: PublicUserSnapshot) =>
 *   Promise<void>} operation Transactional projection writes.
 */
export async function runIdentityProtectedTransaction<Transaction>(
  port: IdentityProtectedTransactionPort<Transaction>,
  userId: string,
  operation: (
    transaction: Transaction,
    publicUser: PublicUserSnapshot
  ) => Promise<void>
): Promise<void> {
  await port.runTransaction(async (transaction) => {
    const publicUser = await port.readCurrentPublicUser(transaction, userId);
    await operation(transaction, publicUser);
  });
}

/**
 * Adapts an Admin Firestore transaction to the identity-protected port.
 * @param {FirebaseFirestore.Firestore} db Firestore database.
 * @return {IdentityProtectedTransactionPort<FirebaseFirestore.Transaction>}
 *   Transaction port.
 */
function firestoreIdentityTransactionPort(
  db: FirebaseFirestore.Firestore
): IdentityProtectedTransactionPort<FirebaseFirestore.Transaction> {
  return {
    runTransaction: (operation) => db.runTransaction(operation),
    readCurrentPublicUser: async (transaction, userId) => {
      const userRef = db.collection("users").doc(userId);
      const publicProfileRef = userRef
        .collection("public_profile")
        .doc("current");
      const [publicProfile, user] = await transaction.getAll(
        publicProfileRef,
        userRef
      );
      return currentPublicUserSnapshotFromData(
        publicProfile.data(),
        user.exists ? user.data() : undefined,
        userId
      );
    },
  };
}

/**
 * Whether a context ranks on steps taken rather than time elapsed.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when higher steps rank better.
 */
function ranksOnSteps(contextType: string): boolean {
  return contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE;
}

/**
 * Whether a context's live race collapses a climber's attempts on steps
 * rather than time - the metric the `BEST` marker and the rival rows are
 * chosen on.
 *
 * Not the same list as `ranksOnSteps`. A Just Climb still ranks its frozen
 * and recomputed standings on the clock, but the captain settled on
 * 2026-09-22 that a climber's previous best there with no goal set is their
 * most steps, all time - and the row a rival races as is chosen the same way.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when the most steps is the race best.
 */
function raceBestOnSteps(contextType: string): boolean {
  return contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE ||
    contextType === JUST_CLIMB_CONTEXT_TYPE;
}

/**
 * Whether a context's live race can be run against a goal, so its entries
 * carry `bestForGoals` and its attempts a stored split curve. Only the global
 * Just Climb board: a tower fixes its own target and a routine its own clock.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when entries carry goal keys.
 */
function contextRacesGoals(contextType: string): boolean {
  return contextType === JUST_CLIMB_CONTEXT_TYPE;
}

/**
 * The value an attempt races on, in its context's race metric.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @return {number} Race value for this attempt.
 */
function attemptRaceValue(payload: LiveReplayIndexPayload): number {
  return raceBestOnSteps(payload.contextType) ?
    payload.finalSteps :
    payload.finalDurationSeconds;
}

/**
 * Whether one ranking value stands strictly ahead of another.
 *
 * Every comparison against a context's metric goes through here so the rank
 * snapshot, the best-per-user collapse and the aggregation queries can never
 * drift into disagreeing about which direction wins.
 * @param {string} contextType Replay context type.
 * @param {number} value Candidate ranking value.
 * @param {number} other Ranking value to beat.
 * @return {boolean} True when value is strictly better than other.
 */
function beatsOnMetric(
  contextType: string,
  value: number,
  other: number
): boolean {
  return ranksOnSteps(contextType) ? value > other : value < other;
}

/**
 * The value an attempt ranks on, in its context's own metric.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @return {number} Ranking value for this attempt.
 */
function attemptRankingValue(payload: LiveReplayIndexPayload): number {
  return ranksOnSteps(payload.contextType) ?
    payload.finalSteps :
    payload.finalDurationSeconds;
}

/**
 * The entry field a context ranks on.
 * @param {string} contextType Replay context type.
 * @return {string} Ranking metric field name.
 */
function rankingMetric(contextType: string): string {
  return ranksOnSteps(contextType) ?
    STEPS_RANKING_METRIC :
    DURATION_RANKING_METRIC;
}

/**
 * How a context resolves attempts that tie on its ranking metric.
 * @param {string} contextType Replay context type.
 * @return {string} Tie policy identifier.
 */
function tiePolicy(contextType: string): string {
  return ranksOnSteps(contextType) ? STEPS_TIE_POLICY : DURATION_TIE_POLICY;
}

/**
 * Reads the field a completed attempt is about to freeze its standing against.
 *
 * The stamp counts whatever the board it sits beside counts, so this read is
 * shaped by `collapsesRepeatFinishers` and nothing else. A collapsing context
 * races one row per climber, and "1st of 5" there names five people - so both
 * halves count distinct climbers, and the finishers subcollection already holds
 * exactly one document per climber.
 *
 * The numerator asks the question that population implies: how many climbers
 * stand ahead of this climber once this attempt is in. It compares against the
 * climber's resulting best - their stored best, or this attempt where it beats
 * it - so their own finisher row can never satisfy a strictly-better filter and
 * nothing has to be subtracted back out afterwards. That subtraction was the
 * defect: a repeat climber with a slower time had their own faster row counted
 * ahead of them and then removed, freezing "1st of 1" over a run that came
 * second. This read owns both the finisher document and the count, so the two
 * halves of a collapsing standing can never be measured from different moments.
 *
 * Every other context (`just_climb`, `routine`) freezes an attempt-counted
 * stamp (Option A, settled 2026-09-06), so this read counts attempts on both
 * sides - including the one publishing now, which the write that follows has
 * not committed yet. That scope is the stamp and the field-size line only: the
 * board those contexts draw is still one row per climber, and it does not race
 * attempts as opponents.
 *
 * Ranks stay competition-style either way: only strictly better rows count, so
 * everything tied on the metric shares a rank. Steps are coarse integers, so
 * routine ties are common and that strict comparison is what keeps a recompute
 * from reshuffling tied climbers.
 *
 * Reads through the caller's transaction, never a bare `.get()` - a retried
 * transaction re-runs this read against the retry's snapshot instead of
 * reusing a count taken before the transaction ever started.
 * @param {FirebaseFirestore.Transaction} transaction Enclosing transaction.
 * @param {LiveReplayIndexPayload} payload Replay payload.
 * @param {string} entryId Public row document ID.
 * @param {string} userId Owner user ID.
 * @return {Promise<CompletionFieldReading>} Counts for the frozen standing.
 */
async function readCompletionField(
  transaction: FirebaseFirestore.Transaction,
  payload: LiveReplayIndexPayload,
  entryId: string,
  userId: string
): Promise<CompletionFieldReading> {
  const rankingValue = attemptRankingValue(payload);

  if (collapsesRepeatFinishers(payload)) {
    const finisherSnapshot = await transaction.get(
      finisherReference(payload, userId)
    );
    const storedBest = finisherStoredBest(
      payload.contextType,
      finisherSnapshot.data()
    );
    const resultingBest = storedBest === null ||
      beatsOnMetric(payload.contextType, rankingValue, storedBest) ?
      rankingValue :
      storedBest;
    const leadingFinishers = leadingRows(
      finishersCollectionReference(payload),
      payload.contextType,
      finisherBestMetric(payload.contextType),
      resultingBest
    );

    return {
      betterRowCount: (await transaction.get(leadingFinishers.count()))
        .data().count,
      attemptCount: null,
    };
  }

  const entries = entriesCollectionReference(payload, 0);
  const better = await transaction.get(
    leadingRows(
      entries,
      payload.contextType,
      rankingMetric(payload.contextType),
      rankingValue
    ).count()
  );
  const published = await transaction.get(entries.count());
  const ownRow = await transaction.get(entryReference(payload, 0, entryId));

  return {
    betterRowCount: better.data().count,
    // A first publish is not in the count yet; a republish already is.
    attemptCount: published.data().count + (ownRow.exists ? 0 : 1),
  };
}

/**
 * Narrows a query to the rows standing strictly ahead of one ranking value.
 *
 * The query counterpart of `beatsOnMetric`: both express "ahead" once, so a
 * count and an in-memory comparison can never disagree about which direction
 * a context's metric wins in.
 * @param {FirebaseFirestore.Query} rows Rows to narrow.
 * @param {string} contextType Replay context type.
 * @param {string} metric Field holding the ranking value on those rows.
 * @param {number} value Ranking value to stand ahead of.
 * @return {FirebaseFirestore.Query} Rows strictly ahead of value.
 */
function leadingRows(
  rows: FirebaseFirestore.Query,
  contextType: string,
  metric: string,
  value: number
): FirebaseFirestore.Query {
  return ranksOnSteps(contextType) ?
    rows.where(metric, ">", value) :
    rows.where(metric, "<", value);
}

/**
 * Resolves the permanent standing a finished attempt freezes.
 *
 * Both halves count one population: distinct climbers where the board collapses
 * repeat finishers, attempts on `just_climb` and `routine` - the frozen stamp's
 * own population there, not a description of the board, which draws one row
 * per climber on every context. The reading
 * already measured its numerator against the same population its denominator
 * names, so nothing is subtracted here and nothing is clamped - a rank outside
 * its own denominator means the two halves counted different things, and
 * rewriting it downward would only hide that with a number that was never true
 * either. It throws instead, so the publish retries rather than freezing a lie
 * into a value that never moves again.
 * @param {object} input Standing inputs.
 * @param {CompletionFieldReading} input.reading Field counts.
 * @param {number} input.completedCount Distinct finishers, this one included -
 *   the denominator wherever the reading counted climbers.
 * @param {string} input.contextKey Board this standing belongs to.
 * @return {FrozenCompletionStanding} Rank and the population it was measured
 *   against.
 */
function frozenCompletionStanding(input: {
  reading: CompletionFieldReading;
  completedCount: number;
  contextKey: string;
}): FrozenCompletionStanding {
  const rank = input.reading.betterRowCount + 1;
  const population = input.reading.attemptCount ?? input.completedCount;

  if (rank < 1 || rank > population) {
    throw new Error(
      `Refusing to freeze rank ${rank} of ${population} for ` +
      `${input.contextKey}: the rank and its population disagree ` +
      "about what they are counting."
    );
  }

  return {rank, population};
}

/**
 * The finisher field carrying a climber's standing best in a context.
 * @param {string} contextType Replay context type.
 * @return {string} Finisher best field name.
 */
function finisherBestMetric(contextType: string): string {
  return ranksOnSteps(contextType) ? STEPS_BEST_METRIC : DURATION_BEST_METRIC;
}

/**
 * One climber's stored best in a context, in that context's own metric.
 * @param {string} contextType Replay context type.
 * @param {Record<string, unknown> | undefined} finisherData Finisher document.
 * @return {number | null} Stored best, or null when none is recorded.
 */
function finisherStoredBest(
  contextType: string,
  finisherData: Record<string, unknown> | undefined
): number | null {
  return ranksOnSteps(contextType) ?
    nonNegativeIntegerValue(finisherData?.[STEPS_BEST_METRIC]) :
    nonNegativeNumberValue(finisherData?.[DURATION_BEST_METRIC]);
}

/**
 * The finisher fields recording one attempt as a climber's standing best.
 * @param {string} contextType Replay context type.
 * @param {number} rankingValue Attempt ranking value.
 * @param {string} workoutId Attempt workout ID.
 * @return {Record<string, unknown>} Finisher best fields.
 */
function finisherBestWrite(
  contextType: string,
  rankingValue: number,
  workoutId: string
): Record<string, unknown> {
  return {
    [finisherBestMetric(contextType)]: rankingValue,
    bestWorkoutId: workoutId,
  };
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
    ...routineWindowFields(input.payload),
    completedCount: input.completedCount,
    completionDurationSeconds: input.payload.finalDurationSeconds,
    contextId: input.payload.contextId,
    contextType: input.payload.contextType,
    finalSteps: input.payload.finalSteps,
    rank: input.rank,
    rankedAt: input.rankedAt,
    rankingMetric: rankingMetric(input.payload.contextType),
    schemaVersion: 1,
    targetStepCount: input.payload.targetStepCount ?? 0,
    tiePolicy: tiePolicy(input.payload.contextType),
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
    ...routineWindowFields(input.payload),
    bucketIntervalSeconds: input.payload.splitIntervalSeconds,
    completedCount: input.completedCount,
    contextId: input.payload.contextId,
    contextType: input.payload.contextType,
    schemaVersion: 1,
    source: REPLAY_SUMMARY_SOURCE_LIVE,
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
    ...bestForUserFields(input.isBestForUser),
    ...bestForGoalsFields(input.bestForGoals),
    ...routineWindowFields(input.payload),
    avatarToken: input.publicUser.avatarToken,
    completionDurationSeconds: input.payload.finalDurationSeconds,
    contextId: input.payload.contextId,
    contextType: input.payload.contextType,
    displayName: input.publicUser.displayName,
    finalSteps: input.payload.finalSteps,
    identityState: input.publicUser.identityState,
    isSynthetic: false,
    photoURL: input.publicUser.photoURL ?? "",
    schemaVersion: 1,
    splitBucketCount: input.payload.splitSteps.length,
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
    firstAscentIdentityState: input.publicUser.identityState,
    firstAscentIsSynthetic: false,
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
  const write: Record<string, unknown> = {
    ...publicUserDemographicFields(input.publicUser),
    avatarToken: input.publicUser.avatarToken,
    displayName: input.publicUser.displayName,
    globalCompletionOrder: input.globalCompletionOrder,
    identityState: input.publicUser.identityState,
    isSynthetic: false,
    photoURL: input.publicUser.photoURL ?? "",
    schemaVersion: 1,
    updatedAt: input.completedAt,
    userId: input.userId,
  };

  if (!input.existingData) {
    write.firstCompletedAt = input.completedAt;
    write.firstWorkoutId = input.entryId;
  }

  return Object.assign(write, finisherBestFields(input));
}

/**
 * Returns the finisher's personal-best fields when this attempt beats the
 * stored one on the context's own metric, and nothing when it does not.
 *
 * Each context stores only the metric it ranks on, so a routine finisher never
 * carries a "best duration" that would read as a time to beat on a board where
 * every finisher spends the same time.
 * @param {FinisherStatusWriteInput} input Finisher write input.
 * @return {Record<string, unknown>} Best fields, or an empty object.
 */
function finisherBestFields(
  input: FinisherStatusWriteInput
): Record<string, unknown> {
  const contextType = input.payload.contextType;
  const rankingValue = attemptRankingValue(input.payload);
  const storedBest = finisherStoredBest(contextType, input.existingData);

  if (
    storedBest !== null &&
    !beatsOnMetric(contextType, rankingValue, storedBest)
  ) {
    return {};
  }

  return finisherBestWrite(contextType, rankingValue, input.entryId);
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
 * Bucket entry document reference on a board.
 * @param {ReplayContextRef} context Board.
 * @param {number} bucketIndex Split bucket index.
 * @param {string} entryId Public row document ID.
 * @return {FirebaseFirestore.DocumentReference} Entry document reference.
 */
function entryReference(
  context: ReplayContextRef,
  bucketIndex: number,
  entryId: string
): FirebaseFirestore.DocumentReference {
  return entriesCollectionReference(context, bucketIndex).doc(entryId);
}

/**
 * Bucket entries collection reference on a board.
 * @param {ReplayContextRef} context Board.
 * @param {number} bucketIndex Split bucket index.
 * @return {FirebaseFirestore.CollectionReference} Entries collection reference.
 */
function entriesCollectionReference(
  context: ReplayContextRef,
  bucketIndex: number
): FirebaseFirestore.CollectionReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(context.contextKey)
    .collection("splitBuckets")
    .doc(String(bucketIndex))
    .collection("entries");
}

/**
 * The stored split curve behind one attempt on a board that races goals.
 * Server-only: no rule admits a client to it, and none should.
 * @param {ReplayContextRef} context Board.
 * @param {string} entryId Public row document ID.
 * @return {FirebaseFirestore.DocumentReference} Curve document reference.
 */
function attemptCurveReference(
  context: ReplayContextRef,
  entryId: string
): FirebaseFirestore.DocumentReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(context.contextKey)
    .collection(ATTEMPT_CURVES_COLLECTION)
    .doc(entryId);
}

/**
 * Finisher status collection reference on a board. One document per climber
 * who has completed the context.
 * @param {ReplayContextRef} context Board.
 * @return {FirebaseFirestore.CollectionReference} Finishers collection.
 */
function finishersCollectionReference(
  context: ReplayContextRef
): FirebaseFirestore.CollectionReference {
  return admin.firestore()
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(context.contextKey)
    .collection(FINISHERS_COLLECTION);
}

/**
 * Per-user finisher status document reference on a board.
 * @param {ReplayContextRef} context Board.
 * @param {string} userId Owner user ID.
 * @return {FirebaseFirestore.DocumentReference} Finisher document reference.
 */
function finisherReference(
  context: ReplayContextRef,
  userId: string
): FirebaseFirestore.DocumentReference {
  return finishersCollectionReference(context).doc(userId);
}

/**
 * Builds replay identity from the public-safe profile mirror.
 * @param {Record<string, unknown> | undefined} data Public profile fields.
 * @return {PublicUserSnapshot} Validated public snapshot.
 */
function publicUserSnapshotFromData(
  data: Record<string, unknown>,
  userId: string
): PublicUserSnapshot {
  const identity = publicIdentityFromData(userId, data);
  return {
    age: ageValue(data?.age),
    avatarToken: identity.avatarToken,
    displayName: identity.displayName,
    gender: genderValue(data?.gender),
    identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
    locationCity: locationTextValue(data?.location_city),
    photoURL: identity.photoURL,
  };
}

/**
 * Resolves the canonical public identity inside a target-write transaction.
 *
 * The public mirror is the only publishable source. A temporarily missing
 * mirror fails closed with a recoverable pending state. A missing account root
 * or deletion sentinel is permanent and can never be republished.
 * @param {Record<string, unknown> | undefined} publicProfileData Mirror data.
 * @param {Record<string, unknown> | undefined} userData Owner-root data.
 * @param {string} userId Owner user ID.
 * @return {PublicUserSnapshot} Current safe public snapshot.
 */
export function currentPublicUserSnapshotFromData(
  publicProfileData: Record<string, unknown> | undefined,
  userData: Record<string, unknown> | undefined,
  userId: string
): PublicUserSnapshot {
  if (
    userData === undefined ||
    isAnonymousClimberName(publicProfileData?.displayName) ||
    isAnonymousClimberName(userData.displayName)
  ) {
    return {
      avatarToken: "",
      displayName: ANONYMOUS_CLIMBER_NAME,
      identityState: PUBLIC_IDENTITY_STATE_DELETED,
      photoURL: null,
    };
  }

  if (publicProfileData === undefined) {
    return {
      avatarToken: "",
      displayName: ANONYMOUS_CLIMBER_NAME,
      identityState: PUBLIC_IDENTITY_STATE_PENDING,
      photoURL: null,
    };
  }

  return publicUserSnapshotFromData(publicProfileData, userId);
}

/**
 * Returns the best-per-user flag field, or nothing when the publish has none.
 *
 * A publish that carries no flag must leave the field absent rather than
 * store false: Firestore equality never matches a missing field, so an absent
 * flag cannot be filtered on by mistake, while a stored false could be.
 * @param {boolean | null} isBestForUser Seed flag, or null for no flag.
 * @return {Record<string, unknown>} Flag field, or an empty object.
 */
function bestForUserFields(
  isBestForUser: boolean | null
): Record<string, unknown> {
  return isBestForUser === null ? {} : {isBestForUser};
}

/**
 * The goal-key field a Just Climb entry carries, or nothing on a board that
 * races no goals, so the field stays absent there.
 * @param {string[] | null} bestForGoals Goal keys, or null for no field.
 * @return {Record<string, unknown>} Field to spread into the entry write.
 */
function bestForGoalsFields(
  bestForGoals: string[] | null
): Record<string, unknown> {
  return bestForGoals === null ? {} : {bestForGoals};
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

/**
 * The goal keys an entry carries, or none when the field is absent or holds
 * anything but strings. Sorted, so it compares against a derived list.
 * @param {unknown} value Stored `bestForGoals`.
 * @return {string[]} Goal keys.
 */
function goalKeyListValue(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((key): key is string => typeof key === "string")
    .sort();
}

export const liveReplayLeaderboardTestHooks = {
  attemptCurveWrite,
  attemptSplitBucketCount,
  beatsOnMetric,
  bestAttemptWorkoutId,
  bestForUserFlagUpdates,
  collapsesRepeatFinishers,
  contextRacesGoals,
  flagUpdateFields,
  raceBestOnSteps,
  rankingBestAttempt,
  completionRankSnapshotWrite,
  finisherBestMetric,
  finisherStatusWrite,
  firstAscentWrite,
  frozenCompletionStanding,
  leaderboardHasFirstAscent,
  liveClimbPublishStatusFailedWrite,
  liveClimbPublishStatusPublishedWrite,
  liveClimbPublishStatusPublishingWrite,
  nextGlobalCompletionOrder,
  parseJustClimbReplayPayload,
  parseLiveClimbReplayPayload,
  parseRoutineReplayPayload,
  currentPublicUserSnapshotFromData,
  publicUserSnapshotFromData,
  rankingMetric,
  readCompletionField,
  replayEntryWrite,
  replayPayloadsForWorkout,
  replaySummaryWrite,
  seedBestForUser,
  shouldDeleteCompletionRankSnapshot,
  tiePolicy,
  userAttemptEntry,
};
