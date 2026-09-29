import {randomUUID} from "node:crypto";
import {gunzipSync} from "node:zlib";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {STRAVA_UPLOAD_JOBS_COLLECTION} from "./access";
import {
  parseHeartRateSidecar,
  type HeartRateSample,
  type StravaActivityWorkout,
} from "./activityFile";
import type {
  StravaUploadClaim,
  StravaUploadJobStore,
  StravaUploadRetry,
  StravaUploadWorkoutSource,
} from "./uploadProcessor";

/**
 * Every transition restamps `retainUntil`, and a Firestore TTL policy on it
 * deletes the row. A completed row holds a Strava activity id, which Strava's
 * API Policy lets Ascend keep for at most seven days; five days of retention
 * plus the TTL sweep's own lag stays inside that.
 */
export const STRAVA_UPLOAD_JOB_RETENTION_MS = 5 * 24 * 60 * 60 * 1000;
const STALE_PROCESSING_MS = 10 * 60 * 1000;
const MAX_HEART_RATE_SIDECAR_BYTES = 2 * 1024 * 1024;

/**
 * Creates the queue row for one climb, once. A workout document is rewritten
 * many times, so a row that already exists - queued, sent, or failed - is
 * left exactly as it is.
 * @param {admin.firestore.Firestore} firestore Firestore handle.
 * @param {object} job What to queue.
 * @return {Promise<boolean>} True when this call created the row.
 */
export async function enqueueStravaUpload(
  firestore: admin.firestore.Firestore,
  job: {jobId: string; userId: string; workoutId: string; readyAt: Date}
): Promise<boolean> {
  const now = admin.firestore.Timestamp.now();
  try {
    await firestore.collection(STRAVA_UPLOAD_JOBS_COLLECTION).doc(job.jobId)
      .create({
        userId: job.userId,
        workoutId: job.workoutId,
        status: "queued",
        attemptCount: 0,
        readyAt: admin.firestore.Timestamp.fromDate(job.readyAt),
        processingStartedAt: null,
        claimId: null,
        uploadId: null,
        activityId: null,
        duplicate: false,
        lastErrorCode: null,
        createdAt: now,
        updatedAt: now,
        retainUntil: retention(now.toDate()),
      });
    return true;
  } catch (error) {
    if ((error as {code?: unknown})?.code === 6) {
      return false;
    }
    throw error;
  }
}

/**
 * The upload queue at `_strava_upload_jobs`, claimed by transaction so two
 * overlapping scheduler runs can never send the same climb twice.
 */
export class FirestoreStravaUploadJobStore implements StravaUploadJobStore {
  constructor(private readonly firestore: admin.firestore.Firestore) {}

  async reclaimStale(now: Date, limit: number): Promise<number> {
    const threshold = admin.firestore.Timestamp.fromMillis(
      now.getTime() - STALE_PROCESSING_MS
    );
    const snapshot = await this.collection()
      .where("status", "==", "processing")
      .where("processingStartedAt", "<=", threshold)
      .limit(limit)
      .get();
    let reclaimed = 0;
    for (const document of snapshot.docs) {
      const didReclaim = await this.firestore.runTransaction(
        async (transaction) => {
          const current = await transaction.get(document.ref);
          const startedAt = current.get("processingStartedAt");
          if (current.get("status") !== "processing" ||
            !(startedAt instanceof admin.firestore.Timestamp) ||
            startedAt.toMillis() > threshold.toMillis()) {
            return false;
          }
          transaction.update(document.ref, {
            status: "queued",
            readyAt: admin.firestore.Timestamp.fromDate(now),
            processingStartedAt: null,
            claimId: null,
            updatedAt: admin.firestore.Timestamp.fromDate(now),
            retainUntil: retention(now),
          });
          return true;
        }
      );
      if (didReclaim) {
        reclaimed += 1;
      }
    }
    return reclaimed;
  }

  async claimDue(now: Date, limit: number): Promise<StravaUploadClaim[]> {
    const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
    const snapshot = await this.collection()
      .where("status", "==", "queued")
      .where("readyAt", "<=", nowTimestamp)
      .orderBy("readyAt")
      .limit(limit)
      .get();
    const claims: StravaUploadClaim[] = [];
    for (const document of snapshot.docs) {
      const claim = await this.claimOne(document.ref, nowTimestamp);
      if (claim) {
        claims.push(claim);
      }
    }
    return claims;
  }

  async release(claim: StravaUploadClaim, now: Date): Promise<void> {
    await this.updateClaimed(claim, {
      status: "queued",
      readyAt: admin.firestore.Timestamp.fromDate(now),
      processingStartedAt: null,
      claimId: null,
      attemptCount: Math.max(claim.attemptCount - 1, 0),
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retention(now),
    });
  }

  async requeue(
    claim: StravaUploadClaim,
    retry: StravaUploadRetry,
    now: Date
  ): Promise<void> {
    await this.updateClaimed(claim, {
      status: "queued",
      readyAt: admin.firestore.Timestamp.fromDate(retry.readyAt),
      processingStartedAt: null,
      claimId: null,
      uploadId: retry.uploadId,
      lastErrorCode: retry.errorCode,
      attemptCount: retry.refundAttempt ?
        Math.max(claim.attemptCount - 1, 0) :
        claim.attemptCount,
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retention(now),
    });
  }

  async markUploaded(
    claim: StravaUploadClaim,
    activityId: string | null,
    duplicate: boolean,
    now: Date
  ): Promise<void> {
    await this.updateClaimed(claim, {
      status: "uploaded",
      activityId,
      duplicate,
      processingStartedAt: null,
      claimId: null,
      lastErrorCode: null,
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retention(now),
    });
  }

  async markFailed(
    claim: StravaUploadClaim,
    errorCode: string,
    now: Date
  ): Promise<void> {
    await this.updateClaimed(claim, {
      status: "failed",
      processingStartedAt: null,
      claimId: null,
      lastErrorCode: errorCode,
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retention(now),
    });
  }

  private collection(): admin.firestore.CollectionReference {
    return this.firestore.collection(STRAVA_UPLOAD_JOBS_COLLECTION);
  }

  private async claimOne(
    reference: admin.firestore.DocumentReference,
    now: admin.firestore.Timestamp
  ): Promise<StravaUploadClaim | null> {
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const readyAt = snapshot.get("readyAt");
      const userId = snapshot.get("userId");
      const workoutId = snapshot.get("workoutId");
      if (!snapshot.exists ||
        snapshot.get("status") !== "queued" ||
        !(readyAt instanceof admin.firestore.Timestamp) ||
        readyAt.toMillis() > now.toMillis()) {
        return null;
      }
      if (typeof userId !== "string" || typeof workoutId !== "string") {
        transaction.update(reference, {
          status: "failed",
          lastErrorCode: "invalid_job",
          updatedAt: now,
          retainUntil: retention(now.toDate()),
        });
        return null;
      }
      const previousAttempts = snapshot.get("attemptCount");
      const attemptCount = (Number.isInteger(previousAttempts) &&
        previousAttempts >= 0 ? previousAttempts : 0) + 1;
      const uploadId = snapshot.get("uploadId");
      const claimId = randomUUID();
      transaction.update(reference, {
        status: "processing",
        attemptCount,
        processingStartedAt: now,
        claimId,
        updatedAt: now,
      });
      return {
        jobId: reference.id,
        claimId,
        userId,
        workoutId,
        attemptCount,
        uploadId: typeof uploadId === "string" ? uploadId : null,
      };
    });
  }

  private async updateClaimed(
    claim: StravaUploadClaim,
    updates: Record<string, unknown>
  ): Promise<void> {
    const reference = this.collection().doc(claim.jobId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (snapshot.get("status") !== "processing" ||
        snapshot.get("claimId") !== claim.claimId) {
        return;
      }
      transaction.update(reference, updates);
    });
  }
}

/**
 * Reads the canonical workout and its heart-rate sidecar.
 */
export class FirestoreStravaWorkoutSource implements StravaUploadWorkoutSource {
  constructor(
    private readonly firestore: admin.firestore.Firestore,
    private readonly bucket: () => ReturnType<
      ReturnType<typeof admin.storage>["bucket"]
    > = () => admin.storage().bucket()
  ) {}

  async read(
    userId: string,
    workoutId: string
  ): Promise<{workout: StravaActivityWorkout; heartRate: HeartRateSample[]} |
    null> {
    const snapshot = await this.firestore
      .collection("users").doc(userId)
      .collection("workouts").doc(workoutId)
      .get();
    const workout = parseStravaActivityWorkout(workoutId, snapshot.data());
    if (!workout) {
      return null;
    }
    return {
      workout,
      heartRate: await this.readHeartRate(
        userId,
        workout,
        snapshot.get("heartRateSeries")
      ),
    };
  }

  private async readHeartRate(
    userId: string,
    workout: StravaActivityWorkout,
    reference: unknown
  ): Promise<HeartRateSample[]> {
    const storagePath = (reference as {storagePath?: unknown})?.storagePath;
    // The workout rule binds the sidecar path to its owner; checking the
    // prefix again here keeps a malformed reference from reading anyone
    // else's object with admin credentials.
    if (typeof storagePath !== "string" ||
      !storagePath.startsWith(`users/${userId}/workout_heart_rate/`)) {
      return [];
    }
    try {
      const [compressed] = await this.bucket().file(storagePath).download();
      if (compressed.length > MAX_HEART_RATE_SIDECAR_BYTES) {
        return [];
      }
      return parseHeartRateSidecar(
        gunzipSync(compressed, {maxOutputLength: 16 * 1024 * 1024})
          .toString("utf8"),
        workout
      );
    } catch (error) {
      logger.warn("Strava upload is going without heart rate", {
        userId,
        workoutId: workout.workoutId,
        error: error instanceof Error ? error.message : String(error),
      });
      return [];
    }
  }
}

/**
 * Reduces a stored workout document to what Strava needs.
 * @param {string} workoutId Canonical workout id.
 * @param {admin.firestore.DocumentData | undefined} data Stored document.
 * @return {StravaActivityWorkout | null} The climb, or null when absent.
 */
export function parseStravaActivityWorkout(
  workoutId: string,
  data: admin.firestore.DocumentData | undefined
): StravaActivityWorkout | null {
  if (!data) {
    return null;
  }
  const startedAt = data.startedAt;
  if (!(startedAt instanceof admin.firestore.Timestamp) ||
    typeof data.durationSeconds !== "number" ||
    typeof data.steps !== "number") {
    return null;
  }
  return {
    workoutId,
    name: typeof data.name === "string" ? data.name : "",
    startedAtMillis: startedAt.toMillis(),
    durationSeconds: data.durationSeconds,
    steps: data.steps,
    floors: typeof data.floors === "number" ? data.floors : 0,
    notes: typeof data.notes === "string" ? data.notes : "",
    caloriesBurned: finiteOrNull(data.caloriesBurned),
    avgHeartRateBpm: finiteOrNull(data.avgHeartRateBpm),
    maxHeartRateBpm: finiteOrNull(data.maxHeartRateBpm),
  };
}

/**
 * Narrows an unknown to a finite number.
 * @param {unknown} value Candidate.
 * @return {number | null} The number, or null.
 */
function finiteOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * The retention stamp for a row that just moved.
 * @param {Date} now Transition time.
 * @return {admin.firestore.Timestamp} When the TTL policy may delete it.
 */
function retention(now: Date): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromMillis(
    now.getTime() + STRAVA_UPLOAD_JOB_RETENTION_MS
  );
}
