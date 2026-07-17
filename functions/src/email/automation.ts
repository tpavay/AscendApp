import * as admin from "firebase-admin";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {normalizeEmail, sha256Hex} from "./crypto";
import {buildEmailJobId, createQueuedEmailJob} from "./queue";
import type {EmailType} from "./types";

type PlainObject = Record<string, unknown>;
type QueueOutcome =
  | "already_queued"
  | "missing_email"
  | "preferences_disabled"
  | "queued";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RATING_PROMPT_EVENT_ID = "rating_prompt_answered_v1";
const RATING_PROMPT_EVENT_TYPE = "rating_prompt_answered";

/**
 * Maps the in-app enjoyment prompt response to its lifecycle email.
 * @param {unknown} response Raw rating prompt answer.
 * @return {EmailType | null} Email type for valid responses.
 */
export function emailTypeForRatingPromptResponse(
  response: unknown
): EmailType | null {
  if (response === "yes") {
    return "rating_positive_followup";
  }
  if (response === "no") {
    return "rating_negative_feedback";
  }
  return null;
}

/**
 * Builds the one-send dedupe key for the rating prompt follow-up email.
 * @param {string} uid Firebase Auth user ID.
 * @return {string} Stable dedupe key.
 */
export function buildRatingPromptEmailDedupeKey(uid: string): string {
  return `rating-prompt-answer-email:${uid}`;
}

/**
 * Determines whether lifecycle emails are currently allowed.
 * @param {PlainObject | null} preferences Stored communication preferences.
 * @return {boolean} True unless lifecycle emails were explicitly disabled.
 */
export function isLifecycleEmailAllowed(
  preferences: PlainObject | null
): boolean {
  return preferences?.lifecycleEmailsEnabled !== false;
}

/**
 * Queues lifecycle emails when server-owned lifecycle events are recorded.
 */
export const onLifecycleEventEmailAutomation = onDocumentWritten(
  "users/{uid}/lifecycle_events/{eventId}",
  async (event) => {
    const snapshot = event.data?.after;
    if (!snapshot?.exists) {
      return;
    }

    const eventId = event.params.eventId;
    if (eventId !== RATING_PROMPT_EVENT_ID) {
      return;
    }

    const data = snapshot.data() as PlainObject;
    const emailType = emailTypeFromRatingPromptEvent(data);
    if (!emailType) {
      return;
    }

    const uid = event.params.uid;
    const firestore = admin.firestore();
    const userRef = firestore.collection("users").doc(uid);
    const userSnapshot = await userRef.get();
    const userData = userSnapshot.exists ?
      userSnapshot.data() as PlainObject :
      {};
    const recipientEmail = await resolveRecipientEmail(uid, userData);
    if (!recipientEmail) {
      console.error("onLifecycleEventEmailAutomation missing user email", {
        uid,
      });
      return;
    }

    const outcome = await queueRatingPromptEmail({
      emailType,
      recipientEmail,
      sourceRef: snapshot.ref.path,
      uid,
    });

    if (outcome === "queued") {
      console.log("onLifecycleEventEmailAutomation queued email", {
        emailType,
        uid,
      });
    } else if (outcome === "preferences_disabled") {
      console.log("onLifecycleEventEmailAutomation skipped by preferences", {
        emailType,
        uid,
      });
    }
  }
);

/**
 * Reads the rating prompt email type from a lifecycle event document.
 * @param {PlainObject} data Firestore lifecycle event data.
 * @return {EmailType | null} Email type when this event should send.
 */
function emailTypeFromRatingPromptEvent(data: PlainObject): EmailType | null {
  if (data.type !== RATING_PROMPT_EVENT_TYPE) {
    return null;
  }

  const payload = isPlainObject(data.payload) ? data.payload : null;
  if (!payload) {
    return null;
  }

  return emailTypeForRatingPromptResponse(payload.response);
}

/**
 * Queues a rating prompt follow-up email idempotently.
 * @param {{emailType: EmailType, recipientEmail: string, sourceRef: string,
 * uid: string}} input Queue input.
 * @return {Promise<QueueOutcome>} Queue result.
 */
async function queueRatingPromptEmail(input: {
  emailType: EmailType;
  recipientEmail: string;
  sourceRef: string;
  uid: string;
}): Promise<QueueOutcome> {
  const firestore = admin.firestore();
  const normalizedEmail = normalizeEmail(input.recipientEmail);
  const recipientHash = sha256Hex(normalizedEmail);
  const dedupeKey = buildRatingPromptEmailDedupeKey(input.uid);
  const jobRef = firestore
    .collection("email_jobs")
    .doc(buildEmailJobId(dedupeKey));
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
      preferencesSnapshot.data() as PlainObject :
      null;
    if (!isLifecycleEmailAllowed(preferences)) {
      return "preferences_disabled";
    }

    const now = admin.firestore.Timestamp.now();
    const job = createQueuedEmailJob(
      input.emailType,
      normalizedEmail,
      recipientHash,
      dedupeKey,
      {},
      now,
      input.sourceRef,
      input.uid
    );
    transaction.set(jobRef, job);
    return "queued";
  });
}

/**
 * Resolves the recipient email from the user document or Firebase Auth.
 * @param {string} uid Firebase Auth user ID.
 * @param {PlainObject} userData Firestore user document data.
 * @return {Promise<string | null>} Normalized valid email, if available.
 */
async function resolveRecipientEmail(
  uid: string,
  userData: PlainObject
): Promise<string | null> {
  const firestoreEmail = validEmailFromValue(userData.email);
  if (firestoreEmail) {
    return firestoreEmail;
  }

  try {
    const userRecord = await admin.auth().getUser(uid);
    return validEmailFromValue(userRecord.email);
  } catch (error) {
    console.error("resolveRecipientEmail auth fallback failed", {
      errorCode: error instanceof Error ? error.name : "unknown_error",
      uid,
    });
    return null;
  }
}

/**
 * Normalizes and validates an email-like value.
 * @param {unknown} value Candidate email.
 * @return {string | null} Normalized email, if valid.
 */
function validEmailFromValue(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const email = normalizeEmail(value);
  if (!email || email.length > 255 || !EMAIL_PATTERN.test(email)) {
    return null;
  }
  return email;
}

/**
 * Determines whether a value is a plain JSON-ish object.
 * @param {unknown} value Candidate value.
 * @return {boolean} True when the value is a plain object.
 */
function isPlainObject(value: unknown): value is PlainObject {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
