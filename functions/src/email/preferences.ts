import * as admin from "firebase-admin";
import type {EmailJobDocument} from "./types";

export type CommunicationPreferences = Record<string, unknown>;
export type StoredCommunicationPreferences = CommunicationPreferences | null;
export type CommunicationPreferencesReader = (
  uid: string
) => Promise<StoredCommunicationPreferences>;

/**
 * Where an email consent decision can have been made inside the app.
 *
 * The unsubscribe endpoint records "email_link" server-side; it is not in this
 * set because no client may claim to be it.
 */
const appLifecycleEmailConsentSources = new Set([
  "onboarding",
  "settings",
]);

/**
 * Whether an untrusted value names a consent source the app can produce.
 *
 * The source is evidence, so it is an allowlist rather than free text: a client
 * may not write an arbitrary string into a record Ascend intends to rely on.
 * @param {unknown} value Candidate source from a callable payload.
 * @return {boolean} True when the value is a supported app consent source.
 */
export function isAppLifecycleEmailConsentSource(
  value: unknown
): value is string {
  return typeof value === "string" &&
    appLifecycleEmailConsentSources.has(value);
}

/**
 * Builds the next communication preferences document from the stored one.
 *
 * The document is shared by every writer of communication_preferences, so only
 * the keys in the payload change and unrelated stored keys are carried forward.
 *
 * A write that carries the lifecycle email flag is a consent decision, so it is
 * stamped with the server's own time. beehiiv can ask for the timestamp and
 * method behind any address it is asked to mail, and `updatedAt` cannot answer
 * that: any other writer of this shared document moves it.
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
  const next: CommunicationPreferences = {
    ...existing,
    ...payload,
    createdAt: existing.createdAt ?? now,
    schemaVersion: 1,
    updatedAt: now,
  };

  if (typeof payload.lifecycleEmailsEnabled === "boolean") {
    next.lifecycleEmailsDecidedAt = now;
  }

  return next;
}

/**
 * Determines whether lifecycle emails are currently allowed.
 *
 * Only a recorded yes qualifies. A missing flag means the climber has never
 * answered, and an unanswered question is not consent: Ascend could not
 * evidence it if beehiiv asked, so nothing is sent on the strength of it.
 * @param {StoredCommunicationPreferences} preferences Stored preferences.
 * @return {boolean} True only when lifecycle emails were explicitly enabled.
 */
export function isLifecycleEmailAllowed(
  preferences: StoredCommunicationPreferences
): boolean {
  return preferences?.lifecycleEmailsEnabled === true;
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
 * recipient uid (admin notifications) has no preference to consult and always
 * sends. A failed read throws rather than falling through, so a
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
