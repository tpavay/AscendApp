import {randomBytes} from "node:crypto";
import * as admin from "firebase-admin";
import {STRAVA_OAUTH_STATES_COLLECTION} from "./access";
import {STRAVA_OAUTH_BASE, STRAVA_WRITE_SCOPE} from "./api";
import type {StravaServerConfig} from "./config";

/** How long a started connection may take before it must start over. */
export const STRAVA_OAUTH_STATE_TTL_MS = 10 * 60 * 1000;

/**
 * Builds the Strava consent URL for one pending connection.
 *
 * The mobile endpoint is the one Strava documents for iOS, and the one its
 * brand guidelines require a "Connect with Strava" button to open.
 * `approval_prompt=auto` skips the consent screen for an athlete who already
 * approved Ascend.
 * @param {StravaServerConfig} config Strava credentials.
 * @param {string} state The pending connection's state token.
 * @return {string} Authorize URL.
 */
export function buildStravaAuthorizeUrl(
  config: StravaServerConfig,
  state: string
): string {
  const url = new URL(`${STRAVA_OAUTH_BASE}/mobile/authorize`);
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("approval_prompt", "auto");
  url.searchParams.set("scope", STRAVA_WRITE_SCOPE);
  url.searchParams.set("state", state);
  return url.toString();
}

/**
 * An unguessable state token binding the Strava redirect to one climber.
 * @return {string} 43-character URL-safe token.
 */
export function newStravaOAuthState(): string {
  return randomBytes(32).toString("base64url");
}

/**
 * Records a pending connection for the caller.
 * @param {admin.firestore.Firestore} firestore Firestore handle.
 * @param {string} userId Caller uid.
 * @param {string} state State token.
 * @param {Date} now Current time.
 * @return {Promise<void>} Resolves once written.
 */
export async function saveStravaOAuthState(
  firestore: admin.firestore.Firestore,
  userId: string,
  state: string,
  now: Date
): Promise<void> {
  await firestore.collection(STRAVA_OAUTH_STATES_COLLECTION).doc(state).set({
    userId,
    createdAt: admin.firestore.Timestamp.fromDate(now),
    expiresAt: admin.firestore.Timestamp.fromMillis(
      now.getTime() + STRAVA_OAUTH_STATE_TTL_MS
    ),
  });
}

export type StravaOAuthStateCheck =
  "valid" | "missing" | "expired" | "wrong_user";

/**
 * Consumes a pending connection. The state is deleted whatever the outcome,
 * so a code can be exchanged at most once per state.
 * @param {admin.firestore.Firestore} firestore Firestore handle.
 * @param {string} userId Caller uid.
 * @param {string} state State token returned by Strava.
 * @param {Date} now Current time.
 * @return {Promise<StravaOAuthStateCheck>} Whether it may proceed.
 */
export async function consumeStravaOAuthState(
  firestore: admin.firestore.Firestore,
  userId: string,
  state: string,
  now: Date
): Promise<StravaOAuthStateCheck> {
  const reference = firestore
    .collection(STRAVA_OAUTH_STATES_COLLECTION)
    .doc(state);
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      return "missing";
    }
    transaction.delete(reference);
    return checkStravaOAuthState(snapshot.data(), userId, now);
  });
}

/**
 * Judges a stored pending connection.
 * @param {admin.firestore.DocumentData | undefined} data Stored state.
 * @param {string} userId Caller uid.
 * @param {Date} now Current time.
 * @return {StravaOAuthStateCheck} Whether it may proceed.
 */
export function checkStravaOAuthState(
  data: admin.firestore.DocumentData | undefined,
  userId: string,
  now: Date
): StravaOAuthStateCheck {
  if (!data) {
    return "missing";
  }
  if (data.userId !== userId) {
    return "wrong_user";
  }
  const expiresAt = data.expiresAt;
  if (!(expiresAt instanceof admin.firestore.Timestamp) ||
    expiresAt.toMillis() <= now.getTime()) {
    return "expired";
  }
  return "valid";
}

/**
 * Deletes pending connections nobody finished.
 * @param {admin.firestore.Firestore} firestore Firestore handle.
 * @param {Date} now Current time.
 * @return {Promise<number>} How many were deleted.
 */
export async function sweepExpiredStravaOAuthStates(
  firestore: admin.firestore.Firestore,
  now: Date
): Promise<number> {
  const snapshot = await firestore
    .collection(STRAVA_OAUTH_STATES_COLLECTION)
    .where("expiresAt", "<=", admin.firestore.Timestamp.fromDate(now))
    .limit(200)
    .get();
  if (snapshot.empty) {
    return 0;
  }
  const batch = firestore.batch();
  for (const document of snapshot.docs) {
    batch.delete(document.ref);
  }
  await batch.commit();
  return snapshot.size;
}
