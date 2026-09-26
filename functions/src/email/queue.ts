import * as admin from "firebase-admin";
import {normalizeEmail, sha256Hex} from "./crypto";
import {isLifecycleEmailAllowed} from "./preferences";
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
 * Drops optional keys a producer left `undefined` rather than omitted.
 *
 * A payload interface can declare a field optional (a recap with no rank
 * moment this period, say), but Firestore's `set` refuses any value that
 * contains a literal `undefined` anywhere in it. The one choke point every
 * job document is built through is the one place this has to be enforced,
 * so no future payload shape can reintroduce the failure mode by omission.
 * @param {EmailJobPayload} payload - Template payload
 * @return {EmailJobPayload} The same payload with `undefined` keys dropped
 */
function stripUndefinedFields(payload: EmailJobPayload): EmailJobPayload {
  const entries = Object.entries(payload as Record<string, unknown>)
    .filter(([, value]) => value !== undefined);
  return Object.fromEntries(entries) as unknown as EmailJobPayload;
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
    payload: stripUndefinedFields(payload),
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

export type EnqueueLifecycleEmailOutcome =
  | "queued"
  | "already_queued"
  | "preferences_disabled";

export interface EnqueueLifecycleEmailInput {
  dedupeKey: string;
  emailType: EmailType;
  payload: EmailJobPayload;
  recipientEmail: string;
  sourceRef: string | null;
  uid: string;
}

/**
 * Queues a user-addressed lifecycle email idempotently, gated on consent.
 *
 * The one enqueue path for every lifecycle email producer: a job already
 * queued under this dedupe key is left alone, and a climber who has not
 * explicitly opted in gets nothing queued at all. Both checks and the write
 * happen inside one transaction so a concurrent producer can never queue a
 * duplicate or slip past a preference read that is already stale.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {EnqueueLifecycleEmailInput} input - Job identity, payload, consent
 * @return {Promise<EnqueueLifecycleEmailOutcome>} What happened
 */
export async function enqueueLifecycleEmailIfAllowed(
  firestore: admin.firestore.Firestore,
  input: EnqueueLifecycleEmailInput
): Promise<EnqueueLifecycleEmailOutcome> {
  const normalizedEmail = normalizeEmail(input.recipientEmail);
  const recipientHash = sha256Hex(normalizedEmail);
  const jobRef = firestore
    .collection("email_jobs")
    .doc(buildEmailJobId(input.dedupeKey));
  const preferencesRef = firestore
    .collection("users")
    .doc(input.uid)
    .collection("communication_preferences")
    .doc("current");

  return firestore.runTransaction(async (transaction) => {
    const [jobSnapshot, preferencesSnapshot] = await Promise.all([
      transaction.get(jobRef),
      transaction.get(preferencesRef),
    ]);

    if (jobSnapshot.exists) {
      return "already_queued";
    }

    const preferences = preferencesSnapshot.exists ?
      preferencesSnapshot.data() as Record<string, unknown> :
      null;
    if (!isLifecycleEmailAllowed(preferences)) {
      return "preferences_disabled";
    }

    const now = admin.firestore.Timestamp.now();
    const job = createQueuedEmailJob(
      input.emailType,
      normalizedEmail,
      recipientHash,
      input.dedupeKey,
      input.payload,
      now,
      input.sourceRef,
      input.uid
    );
    transaction.set(jobRef, job);
    return "queued";
  });
}
