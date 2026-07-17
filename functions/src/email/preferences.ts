import * as admin from "firebase-admin";
import type {EmailJobDocument} from "./types";

export type CommunicationPreferences = Record<string, unknown>;
export type StoredCommunicationPreferences = CommunicationPreferences | null;
export type CommunicationPreferencesReader = (
  uid: string
) => Promise<StoredCommunicationPreferences>;

/**
 * Builds the next communication preferences document from the stored one.
 *
 * The document is shared by every writer of communication_preferences, so only
 * the keys in the payload change and unrelated stored keys are carried forward.
 * @param {CommunicationPreferences} existing Stored preferences document.
 * @param {CommunicationPreferences} payload Validated preference payload.
 * @param {admin.firestore.Timestamp} now Server timestamp for this write.
 * @return {CommunicationPreferences} Preferences document to write.
 */
export function buildNextCommunicationPreferences(
  existing: CommunicationPreferences,
  payload: CommunicationPreferences,
  now: admin.firestore.Timestamp
): CommunicationPreferences {
  return {
    ...existing,
    ...payload,
    createdAt: existing.createdAt ?? now,
    schemaVersion: 1,
    updatedAt: now,
  };
}

/**
 * Determines whether lifecycle emails are currently allowed.
 * @param {StoredCommunicationPreferences} preferences Stored preferences.
 * @return {boolean} True unless lifecycle emails were explicitly disabled.
 */
export function isLifecycleEmailAllowed(
  preferences: StoredCommunicationPreferences
): boolean {
  return preferences?.lifecycleEmailsEnabled !== false;
}

/**
 * Reads a user's stored communication preferences.
 * @param {string} uid Firebase Auth user ID.
 * @return {Promise<StoredCommunicationPreferences>} Stored preferences.
 */
export async function readCommunicationPreferences(
  uid: string
): Promise<StoredCommunicationPreferences> {
  const snapshot = await admin.firestore()
    .collection("users")
    .doc(uid)
    .collection("communication_preferences")
    .doc("current")
    .get();

  return snapshot.exists ?
    snapshot.data() as Record<string, unknown> :
    null;
}

/**
 * Decides whether a claimed job must be suppressed instead of delivered.
 *
 * The queue-time gate is not enough on its own: a retrying job can sit in the
 * queue for hours, so the preference is re-read at send time. Mail with no
 * recipient uid (waitlist, admin notifications) has no preference to consult
 * and always sends. A failed read throws rather than falling through, so a
 * transient Firestore error can never deliver mail to an unsubscribed user.
 * @param {Pick<EmailJobDocument, "recipientUid">} job Claimed email job.
 * @param {CommunicationPreferencesReader} readPreferences Preference reader.
 * @return {Promise<boolean>} True when the job must not be delivered.
 */
export async function isEmailJobSuppressed(
  job: Pick<EmailJobDocument, "recipientUid">,
  readPreferences: CommunicationPreferencesReader = readCommunicationPreferences
): Promise<boolean> {
  if (!job.recipientUid) {
    return false;
  }

  return !isLifecycleEmailAllowed(await readPreferences(job.recipientUid));
}
