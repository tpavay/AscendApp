import * as admin from "firebase-admin";

/**
 * Server-only collections for the Strava integration. Every one is
 * `allow read, write: if false` in firestore.rules: tokens, pending
 * authorizations and the upload queue are reachable only through the Admin
 * SDK, so no client can read a token or forge a connection.
 */
export const STRAVA_ACCESS_COLLECTION = "_strava_access";
export const STRAVA_ACCESS_DOCUMENT = "settings";
export const STRAVA_CONNECTIONS_COLLECTION = "_strava_connections";
export const STRAVA_OAUTH_STATES_COLLECTION = "_strava_oauth_states";
export const STRAVA_UPLOAD_JOBS_COLLECTION = "_strava_upload_jobs";

/**
 * Who may use Strava, read from `_strava_access/settings`.
 *
 * `enabled` is the kill switch and ships off: a missing document, a missing
 * field, or anything but a literal `true` keeps the whole integration dark.
 * It is server-side rather than a Remote Config flag because every Strava
 * call already runs in a Cloud Function, and because the capacity it guards
 * is Strava's - the app-side switches all ship on, and the automatic Remote
 * Config publisher refuses to run while any of them is off.
 *
 * `allowedUserIds` is who may *start* a connection. Strava caps the app at a
 * fixed number of connected athletes until it passes review, so a connect
 * that Strava would refuse must never be offered.
 */
export interface StravaAccessSettings {
  enabled: boolean;
  allowedUserIds: ReadonlySet<string>;
}

export const STRAVA_ACCESS_DISABLED: StravaAccessSettings = Object.freeze({
  enabled: false,
  allowedUserIds: new Set<string>(),
});

/**
 * Parses the settings document, failing closed on any unexpected shape.
 * @param {unknown} data The document's data, or undefined when absent.
 * @return {StravaAccessSettings} Parsed settings.
 */
export function parseStravaAccessSettings(
  data: unknown
): StravaAccessSettings {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return STRAVA_ACCESS_DISABLED;
  }
  const record = data as Record<string, unknown>;
  const allowed = Array.isArray(record.allowedUserIds) ?
    record.allowedUserIds.filter(
      (value): value is string => typeof value === "string" && value !== ""
    ) :
    [];
  return {
    enabled: record.enabled === true,
    allowedUserIds: new Set(allowed),
  };
}

/**
 * Whether this climber may start a Strava connection.
 * @param {StravaAccessSettings} settings Current settings.
 * @param {string} userId Firebase uid.
 * @return {boolean} True when the switch is on and the uid is allowlisted.
 */
export function mayConnectStrava(
  settings: StravaAccessSettings,
  userId: string
): boolean {
  return settings.enabled && settings.allowedUserIds.has(userId);
}

/**
 * Reads the live settings document.
 * @param {admin.firestore.Firestore} firestore Firestore handle.
 * @return {Promise<StravaAccessSettings>} Parsed settings.
 */
export async function readStravaAccessSettings(
  firestore: admin.firestore.Firestore
): Promise<StravaAccessSettings> {
  const snapshot = await firestore
    .collection(STRAVA_ACCESS_COLLECTION)
    .doc(STRAVA_ACCESS_DOCUMENT)
    .get();
  return parseStravaAccessSettings(snapshot.data());
}
