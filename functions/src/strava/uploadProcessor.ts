import * as logger from "firebase-functions/logger";
import {
  StravaApiError,
  isDuplicateUploadError,
  type StravaClient,
  type StravaUploadStatus,
} from "./api";
import {
  buildStravaDescription,
  buildStravaTitle,
  buildTcx,
  stravaExternalId,
  type HeartRateSample,
  type StravaActivityWorkout,
} from "./activityFile";

/**
 * The one workout source Ascend can still record. Every other stored source
 * is a legacy import or manual entry, and neither may reach Strava as if the
 * climber had just done it.
 */
export const STRAVA_UPLOADABLE_SOURCE = "headphone_motion";

/**
 * A climb is queued only while it is fresh. Workout documents are rewritten
 * long after the climb - Apple Health enrichment, notes, media - and a
 * connection made today must never send last month's history.
 */
export const STRAVA_UPLOAD_FRESHNESS_MS = 48 * 60 * 60 * 1000;

/**
 * How long a queued climb waits before it is sent. Heart rate from a live
 * source lands with the workout, but Apple Health enrichment arrives on its
 * own schedule afterwards, and Strava will not take a second upload of the
 * same climb once the first has landed.
 */
export const STRAVA_UPLOAD_SETTLE_MS = 10 * 60 * 1000;

export const STRAVA_UPLOAD_MAX_ATTEMPTS = 8;
const STRAVA_PROCESSING_RECHECK_MS = 2 * 60 * 1000;
const STRAVA_POLLS_PER_ATTEMPT = 3;
const STRAVA_POLL_INTERVAL_MS = 1500;
const DEFAULT_BATCH_SIZE = 20;
const DEFAULT_RUN_BUDGET_MS = 90 * 1000;
const RETRY_DELAYS_MS = [
  60 * 1000,
  5 * 60 * 1000,
  15 * 60 * 1000,
  60 * 60 * 1000,
  3 * 60 * 60 * 1000,
  6 * 60 * 60 * 1000,
];

export interface StravaUploadEligibilityInput {
  source: unknown;
  steps: unknown;
  durationSeconds: unknown;
  startedAtMillis: number | null;
  connectedAtMillis: number;
  nowMillis: number;
}

/**
 * Whether a written workout should be queued for Strava.
 * @param {StravaUploadEligibilityInput} input The workout and connection.
 * @return {boolean} True when the climb belongs on Strava.
 */
export function isStravaUploadEligible(
  input: StravaUploadEligibilityInput
): boolean {
  if (input.source !== STRAVA_UPLOADABLE_SOURCE ||
    typeof input.steps !== "number" || !(input.steps > 0) ||
    typeof input.durationSeconds !== "number" ||
    !(input.durationSeconds > 0) ||
    input.startedAtMillis === null) {
    return false;
  }
  return input.startedAtMillis >= input.connectedAtMillis &&
    input.startedAtMillis >= input.nowMillis - STRAVA_UPLOAD_FRESHNESS_MS &&
    input.startedAtMillis <= input.nowMillis + STRAVA_UPLOAD_FRESHNESS_MS;
}

/**
 * The queue document id for one climb.
 * @param {string} userId Owner uid.
 * @param {string} workoutId Canonical workout id.
 * @return {string} Job id.
 */
export function stravaUploadJobId(userId: string, workoutId: string): string {
  return `${userId}__${workoutId}`;
}

export interface StravaUploadClaim {
  jobId: string;
  claimId: string;
  userId: string;
  workoutId: string;
  attemptCount: number;
  /** Set once Strava accepted the file, so a retry polls instead of posting. */
  uploadId: string | null;
}

export interface StravaUploadRetry {
  readyAt: Date;
  errorCode: string;
  /** Set once Strava accepted the file, so the retry polls it. */
  uploadId: string | null;
  /** True when the failure was not the climb's, e.g. a 429. */
  refundAttempt: boolean;
}

export interface StravaUploadJobStore {
  reclaimStale(now: Date, limit: number): Promise<number>;
  claimDue(now: Date, limit: number): Promise<StravaUploadClaim[]>;
  /** Puts a claim back without consuming the attempt it took. */
  release(claim: StravaUploadClaim, now: Date): Promise<void>;
  requeue(
    claim: StravaUploadClaim,
    retry: StravaUploadRetry,
    now: Date
  ): Promise<void>;
  markUploaded(
    claim: StravaUploadClaim,
    activityId: string | null,
    duplicate: boolean,
    now: Date
  ): Promise<void>;
  markFailed(
    claim: StravaUploadClaim,
    errorCode: string,
    now: Date
  ): Promise<void>;
}

export interface StravaUploadWorkoutSource {
  /** Null when the climb has since been deleted. */
  read(
    userId: string,
    workoutId: string
  ): Promise<{workout: StravaActivityWorkout; heartRate: HeartRateSample[]} |
    null>;
}

export interface StravaUploadConnections {
  /** A usable token, or null when the climber is no longer connected. */
  accessToken(userId: string, nowMillis: number): Promise<string | null>;
  /** Called once Strava says the athlete revoked Ascend. */
  disconnectRevoked(userId: string): Promise<void>;
}

export interface StravaUploadDependencies {
  store: StravaUploadJobStore;
  workouts: StravaUploadWorkoutSource;
  connections: StravaUploadConnections;
  client: StravaClient;
  now: () => Date;
  sleep: (ms: number) => Promise<void>;
  batchSize?: number;
  runBudgetMs?: number;
}

export interface StravaUploadRunSummary {
  reclaimed: number;
  claimed: number;
  uploaded: number;
  requeued: number;
  failed: number;
  deferred: number;
  rateLimited: boolean;
}

/**
 * Sends due climbs to Strava.
 *
 * The caller has already checked the kill switch; this never runs while the
 * integration is off, so a disabled switch leaves every queued climb exactly
 * where it was.
 * @param {StravaUploadDependencies} dependencies Ports.
 * @return {Promise<StravaUploadRunSummary>} What the run did.
 */
export async function processStravaUploadQueue(
  dependencies: StravaUploadDependencies
): Promise<StravaUploadRunSummary> {
  const startedAt = dependencies.now();
  const batchSize = dependencies.batchSize ?? DEFAULT_BATCH_SIZE;
  const deadlineMillis = startedAt.getTime() +
    (dependencies.runBudgetMs ?? DEFAULT_RUN_BUDGET_MS);
  const summary: StravaUploadRunSummary = {
    reclaimed: await dependencies.store.reclaimStale(startedAt, batchSize),
    claimed: 0,
    uploaded: 0,
    requeued: 0,
    failed: 0,
    deferred: 0,
    rateLimited: false,
  };
  const claims = await dependencies.store.claimDue(startedAt, batchSize);
  summary.claimed = claims.length;

  for (const claim of claims) {
    const now = dependencies.now();
    // After a 429 every further request this window is refused too, so the
    // rest of the batch waits rather than spending attempts on it.
    if (summary.rateLimited || now.getTime() >= deadlineMillis) {
      await dependencies.store.release(claim, now);
      summary.deferred += 1;
      continue;
    }
    const outcome = await processClaim(claim, dependencies);
    summary[outcome.counter] += 1;
    summary.rateLimited = summary.rateLimited || outcome.rateLimited;
  }
  return summary;
}

interface ClaimOutcome {
  counter: "uploaded" | "requeued" | "failed";
  rateLimited: boolean;
}

const UPLOADED: ClaimOutcome = {counter: "uploaded", rateLimited: false};
const REQUEUED: ClaimOutcome = {counter: "requeued", rateLimited: false};
const FAILED: ClaimOutcome = {counter: "failed", rateLimited: false};

/**
 * Handles one claimed climb end to end.
 * @param {StravaUploadClaim} claim The claim.
 * @param {StravaUploadDependencies} dependencies Ports.
 * @return {Promise<ClaimOutcome>} Where it lands.
 */
async function processClaim(
  claim: StravaUploadClaim,
  dependencies: StravaUploadDependencies
): Promise<ClaimOutcome> {
  const {store, client} = dependencies;
  let uploadId = claim.uploadId;
  try {
    const accessToken = await dependencies.connections.accessToken(
      claim.userId,
      dependencies.now().getTime()
    );
    if (!accessToken) {
      await store.markFailed(claim, "not_connected", dependencies.now());
      return FAILED;
    }

    let status: StravaUploadStatus;
    if (uploadId === null) {
      const source = await dependencies.workouts.read(
        claim.userId,
        claim.workoutId
      );
      if (!source) {
        await store.markFailed(claim, "workout_deleted", dependencies.now());
        return FAILED;
      }
      status = await client.createUpload(accessToken, {
        name: buildStravaTitle(source.workout),
        description: buildStravaDescription(source.workout),
        externalId: stravaExternalId(claim.workoutId),
        tcx: buildTcx(source.workout, source.heartRate),
      });
      uploadId = status.uploadId;
    } else {
      status = await client.getUpload(accessToken, uploadId);
    }

    for (let poll = 0;
      status.activityId === null && status.error === null &&
        poll < STRAVA_POLLS_PER_ATTEMPT;
      poll += 1) {
      await dependencies.sleep(STRAVA_POLL_INTERVAL_MS);
      status = await client.getUpload(accessToken, status.uploadId);
    }

    if (status.activityId !== null) {
      await store.markUploaded(
        claim,
        status.activityId,
        false,
        dependencies.now()
      );
      return UPLOADED;
    }
    if (status.error !== null) {
      if (isDuplicateUploadError(status.error)) {
        await store.markUploaded(claim, null, true, dependencies.now());
        return UPLOADED;
      }
      logger.error("Strava refused a climb upload", {
        jobId: claim.jobId,
        stravaError: status.error.slice(0, 300),
      });
      await store.markFailed(claim, "strava_processing_error",
        dependencies.now());
      return FAILED;
    }
    return retryOrFail(
      claim,
      dependencies,
      "strava_still_processing",
      uploadId,
      new Date(dependencies.now().getTime() + STRAVA_PROCESSING_RECHECK_MS)
    );
  } catch (error) {
    return handleFailure(claim, dependencies, error, uploadId);
  }
}

/**
 * Routes a thrown failure to the right terminal or retry state.
 * @param {StravaUploadClaim} claim The claim.
 * @param {StravaUploadDependencies} dependencies Ports.
 * @param {unknown} error What was thrown.
 * @param {string | null} uploadId Upload id, if Strava accepted the file.
 * @return {Promise<ClaimOutcome>} Where it lands.
 */
async function handleFailure(
  claim: StravaUploadClaim,
  dependencies: StravaUploadDependencies,
  error: unknown,
  uploadId: string | null
): Promise<ClaimOutcome> {
  const now = dependencies.now();
  if (!(error instanceof StravaApiError)) {
    logger.warn("Strava upload hit a non-Strava failure", {
      jobId: claim.jobId,
      error: error instanceof Error ? error.message : String(error),
    });
    return retryOrFail(claim, dependencies, "internal", uploadId,
      new Date(now.getTime() + retryDelayMs(claim.attemptCount)));
  }
  switch (error.kind) {
  case "unauthorized":
    await dependencies.connections.disconnectRevoked(claim.userId);
    await dependencies.store.markFailed(claim, "not_authorized", now);
    return FAILED;
  case "rate_limited":
    // A 429 is not the climb's fault, so it does not spend an attempt.
    await dependencies.store.requeue(claim, {
      readyAt: nextRateLimitWindow(now),
      errorCode: "rate_limited",
      uploadId,
      refundAttempt: true,
    }, now);
    return {counter: "requeued", rateLimited: true};
  case "transient":
  case "misconfigured":
    return retryOrFail(claim, dependencies, error.kind, uploadId,
      new Date(now.getTime() + retryDelayMs(claim.attemptCount)));
  case "rejected":
    logger.error("Strava rejected a climb upload request", {
      jobId: claim.jobId,
      status: error.status,
      error: error.message,
    });
    await dependencies.store.markFailed(claim, "rejected", now);
    return FAILED;
  }
}

/**
 * Requeues a claim unless it has used its last attempt.
 * @param {StravaUploadClaim} claim The claim.
 * @param {StravaUploadDependencies} dependencies Ports.
 * @param {string} errorCode Why it is retrying.
 * @param {string | null} uploadId Upload id, if Strava accepted the file.
 * @param {Date} readyAt When to retry.
 * @return {Promise<ClaimOutcome>} Where it lands.
 */
async function retryOrFail(
  claim: StravaUploadClaim,
  dependencies: StravaUploadDependencies,
  errorCode: string,
  uploadId: string | null,
  readyAt: Date
): Promise<ClaimOutcome> {
  const now = dependencies.now();
  if (claim.attemptCount >= STRAVA_UPLOAD_MAX_ATTEMPTS) {
    logger.error("Strava upload gave up after its last attempt", {
      jobId: claim.jobId,
      attemptCount: claim.attemptCount,
      lastErrorCode: errorCode,
    });
    await dependencies.store.markFailed(claim, errorCode, now);
    return FAILED;
  }
  await dependencies.store.requeue(claim, {
    readyAt,
    errorCode,
    uploadId,
    refundAttempt: false,
  }, now);
  return REQUEUED;
}

/**
 * Backoff for the next attempt.
 * @param {number} attemptCount Attempts already made, including this one.
 * @return {number} Delay in milliseconds.
 */
export function retryDelayMs(attemptCount: number): number {
  const index = Math.max(0, Math.min(attemptCount - 1,
    RETRY_DELAYS_MS.length - 1));
  return RETRY_DELAYS_MS[index];
}

/**
 * Strava resets its short-term limit on the quarter hour.
 * @param {Date} now Current time.
 * @return {Date} The start of the next 15-minute window.
 */
export function nextRateLimitWindow(now: Date): Date {
  const quarter = 15 * 60 * 1000;
  return new Date((Math.floor(now.getTime() / quarter) + 1) * quarter);
}
