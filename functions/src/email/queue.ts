import * as admin from "firebase-admin";
import {sha256Hex} from "./crypto";
import type {
  EmailJobDocument,
  EmailJobPayload,
  EmailType,
} from "./types";

/**
 * Builds the deterministic Firestore job ID for an email dedupe key.
 * @param {string} dedupeKey - Stable dedupe key
 * @return {string} Stable Firestore document ID
 */
export function buildEmailJobId(dedupeKey: string): string {
  return sha256Hex(dedupeKey);
}

/**
 * Creates a queued email job document.
 * @param {EmailType} type - Email type
 * @param {string} recipientEmail - Recipient email address
 * @param {string} recipientHash - Stable recipient hash
 * @param {string} dedupeKey - Stable dedupe key
 * @param {EmailJobPayload} payload - Template payload
 * @param {Timestamp} scheduledFor - Scheduled send time
 * @param {string | null} sourceRef - Source Firestore reference string
 * @param {string | null} recipientUid - Recipient uid when user-addressed
 * @return {EmailJobDocument} Firestore-ready queued job
 */
export function createQueuedEmailJob(
  type: EmailType,
  recipientEmail: string,
  recipientHash: string,
  dedupeKey: string,
  payload: EmailJobPayload,
  scheduledFor: admin.firestore.Timestamp,
  sourceRef: string | null,
  recipientUid: string | null = null
): EmailJobDocument {
  return {
    attemptCount: 0,
    createdAt: scheduledFor,
    dedupeKey,
    lastErrorCode: null,
    lastErrorMessage: null,
    payload,
    processingStartedAt: null,
    provider: null,
    providerMessageId: null,
    readyAt: scheduledFor,
    recipientEmail,
    recipientHash,
    recipientUid,
    scheduledFor,
    sentAt: null,
    sourceRef,
    status: "queued",
    type,
    updatedAt: scheduledFor,
  };
}
