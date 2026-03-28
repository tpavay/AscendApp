import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {transactionalEmailConfig} from "./config";
import {renderEmailContentForJob} from "./catalog";
import {sendTransactionalEmail, EmailDeliveryError} from "./provider";
import {getNextRetryDelayMs} from "./retry";
import type {EmailJobDocument} from "./types";

const JOB_BATCH_SIZE = 25;
const STALE_PROCESSING_MS = 15 * 60 * 1000;

/**
 * Creates a Firestore timestamp from a Date instance.
 * @param {Date} value - Date value
 * @return {Timestamp} Firestore timestamp
 */
function toTimestamp(value: Date): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(value);
}

/**
 * Serializes an unknown error into a stable message.
 * @param {unknown} error - Unknown error value
 * @return {string} Safe error message
 */
function serializeErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  return "unknown_error";
}

/**
 * Requeues stale processing jobs so they are not stuck forever.
 * @param {Timestamp} nowTimestamp - Current timestamp
 * @return {Promise<number>} Number of jobs reclaimed
 */
async function reclaimStaleJobs(
  nowTimestamp: admin.firestore.Timestamp
): Promise<number> {
  const staleThreshold = admin.firestore.Timestamp.fromMillis(
    nowTimestamp.toMillis() - STALE_PROCESSING_MS
  );
  const staleSnapshot = await admin.firestore()
    .collection("email_jobs")
    .where("status", "==", "processing")
    .where("processingStartedAt", "<=", staleThreshold)
    .limit(JOB_BATCH_SIZE)
    .get();

  let reclaimedCount = 0;

  for (const document of staleSnapshot.docs) {
    const didReclaim = await admin.firestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(document.ref);
        if (!snapshot.exists) {
          return false;
        }

        const data = snapshot.data() as EmailJobDocument;
        const startedAt = data.processingStartedAt?.toMillis() ?? 0;
        if (
          data.status !== "processing" ||
          startedAt > staleThreshold.toMillis()
        ) {
          return false;
        }

        transaction.update(document.ref, {
          processingStartedAt: null,
          readyAt: nowTimestamp,
          status: "queued",
          updatedAt: nowTimestamp,
        });
        return true;
      }
    );

    if (didReclaim) {
      reclaimedCount += 1;
    }
  }

  return reclaimedCount;
}

/**
 * Claims a queued email job for processing.
 * @param {DocumentReference} jobRef - Email job document reference
 * @param {Timestamp} nowTimestamp - Current timestamp
 * @return {Promise<EmailJobDocument | null>} Claimed job or null
 */
async function claimEmailJob(
  jobRef: admin.firestore.DocumentReference,
  nowTimestamp: admin.firestore.Timestamp
): Promise<EmailJobDocument | null> {
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    if (!snapshot.exists) {
      return null;
    }

    const data = snapshot.data() as EmailJobDocument;
    if (data.status !== "queued" ||
      data.readyAt.toMillis() > nowTimestamp.toMillis()) {
      return null;
    }

    transaction.update(jobRef, {
      processingStartedAt: nowTimestamp,
      status: "processing",
      updatedAt: nowTimestamp,
    });

    return {
      ...data,
      processingStartedAt: nowTimestamp,
      status: "processing",
      updatedAt: nowTimestamp,
    };
  });
}

/**
 * Marks an email job as permanently failed.
 * @param {DocumentReference} jobRef - Email job document reference
 * @param {Timestamp} nowTimestamp - Current timestamp
 * @param {number} attemptCount - Attempt count after the failed attempt
 * @param {string} errorCode - Stable error code
 * @param {string} errorMessage - Human-readable error message
 * @param {string | null} provider - Delivery provider name
 * @return {Promise<void>}
 */
async function markJobFailed(
  jobRef: admin.firestore.DocumentReference,
  nowTimestamp: admin.firestore.Timestamp,
  attemptCount: number,
  errorCode: string,
  errorMessage: string,
  provider: string | null
): Promise<void> {
  await jobRef.update({
    attemptCount,
    lastErrorCode: errorCode,
    lastErrorMessage: errorMessage,
    processingStartedAt: null,
    provider,
    providerMessageId: null,
    status: "failed",
    updatedAt: nowTimestamp,
  });
}

/**
 * Requeues an email job after a retryable failure.
 * @param {DocumentReference} jobRef - Email job document reference
 * @param {Timestamp} nowTimestamp - Current timestamp
 * @param {number} attemptCount - Attempt count after the failed attempt
 * @param {number} delayMs - Delay until next retry
 * @param {string} errorCode - Stable error code
 * @param {string} errorMessage - Human-readable error message
 * @param {string | null} provider - Delivery provider name
 * @return {Promise<void>}
 */
async function requeueEmailJob(
  jobRef: admin.firestore.DocumentReference,
  nowTimestamp: admin.firestore.Timestamp,
  attemptCount: number,
  delayMs: number,
  errorCode: string,
  errorMessage: string,
  provider: string | null
): Promise<void> {
  await jobRef.update({
    attemptCount,
    lastErrorCode: errorCode,
    lastErrorMessage: errorMessage,
    processingStartedAt: null,
    provider,
    providerMessageId: null,
    readyAt: admin.firestore.Timestamp.fromMillis(
      nowTimestamp.toMillis() + delayMs
    ),
    status: "queued",
    updatedAt: nowTimestamp,
  });
}

/**
 * Processes a claimed email job.
 * @param {DocumentReference} jobRef - Email job document reference
 * @param {EmailJobDocument} job - Claimed email job
 * @param {Timestamp} nowTimestamp - Current timestamp
 * @return {Promise<"sent" | "retried" | "failed">} Processing outcome
 */
async function processClaimedJob(
  jobRef: admin.firestore.DocumentReference,
  job: EmailJobDocument,
  nowTimestamp: admin.firestore.Timestamp
): Promise<"sent" | "retried" | "failed"> {
  const nextAttemptCount = job.attemptCount + 1;
  let renderedEmail;

  try {
    renderedEmail = renderEmailContentForJob(job);
  } catch (error) {
    await markJobFailed(
      jobRef,
      nowTimestamp,
      nextAttemptCount,
      "invalid_payload",
      serializeErrorMessage(error),
      null
    );
    console.error("processEmailJobs invalid payload", {
      errorCode: "invalid_payload",
      jobId: jobRef.id,
    });
    return "failed";
  }

  try {
    const delivery = await sendTransactionalEmail({
      idempotencyKey: job.dedupeKey,
      html: renderedEmail.html,
      subject: renderedEmail.subject,
      text: renderedEmail.text,
      to: [job.recipientEmail],
    });

    await jobRef.update({
      attemptCount: nextAttemptCount,
      lastErrorCode: null,
      lastErrorMessage: null,
      processingStartedAt: null,
      provider: delivery.provider,
      providerMessageId: delivery.messageId,
      sentAt: nowTimestamp,
      status: "sent",
      updatedAt: nowTimestamp,
    });

    return "sent";
  } catch (error) {
    const errorCode = error instanceof EmailDeliveryError ?
      error.code :
      "unexpected_provider_error";
    const errorMessage = serializeErrorMessage(error);
    const provider = error instanceof EmailDeliveryError ?
      error.provider :
      null;

    if (error instanceof EmailDeliveryError && error.retryable) {
      const nextRetryDelay = getNextRetryDelayMs(job.type, nextAttemptCount);
      if (nextRetryDelay !== null) {
        await requeueEmailJob(
          jobRef,
          nowTimestamp,
          nextAttemptCount,
          nextRetryDelay,
          errorCode,
          errorMessage,
          provider
        );
        console.error("processEmailJobs retrying job", {
          errorCode,
          jobId: jobRef.id,
        });
        return "retried";
      }
    }

    await markJobFailed(
      jobRef,
      nowTimestamp,
      nextAttemptCount,
      errorCode,
      errorMessage,
      provider
    );
    console.error("processEmailJobs failed job", {
      errorCode,
      jobId: jobRef.id,
    });
    return "failed";
  }
}

/**
 * Processes queued transactional email jobs on a fixed schedule.
 */
export const processEmailJobs = onSchedule(
  {
    schedule: "* * * * *",
    secrets: [transactionalEmailConfig],
    timeZone: "Etc/UTC",
  },
  async () => {
    const startedAt = new Date();
    const startedAtTimestamp = toTimestamp(startedAt);
    const reclaimedCount = await reclaimStaleJobs(startedAtTimestamp);
    const dueJobsSnapshot = await admin.firestore()
      .collection("email_jobs")
      .where("status", "==", "queued")
      .where("readyAt", "<=", startedAtTimestamp)
      .limit(JOB_BATCH_SIZE)
      .get();

    let sentCount = 0;
    let retriedCount = 0;
    let failedCount = 0;

    for (const document of dueJobsSnapshot.docs) {
      const claimedJob = await claimEmailJob(document.ref, startedAtTimestamp);
      if (!claimedJob) {
        continue;
      }

      const outcome = await processClaimedJob(
        document.ref,
        claimedJob,
        startedAtTimestamp
      );
      if (outcome === "sent") {
        sentCount += 1;
      } else if (outcome === "retried") {
        retriedCount += 1;
      } else {
        failedCount += 1;
      }
    }

    console.log("processEmailJobs summary", {
      failedCount,
      queuedCount: dueJobsSnapshot.size,
      reclaimedCount,
      retriedCount,
      sentCount,
    });
  }
);
