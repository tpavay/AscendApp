import * as admin from "firebase-admin";

/**
 * The free week on the house: seven days of app access the server grants a
 * climber who declined every paid offer, with no Apple purchase behind it.
 *
 * It is written into the same `users/{uid}/entitlements/app_access` document
 * a paid grant uses, because that document's existence is the one thing the
 * Firestore and Storage rules check. What tells it apart is `productId` and
 * `source`, and the durable `users/{uid}/trial/free_week` record beside it.
 *
 * One invariant holds everywhere a grant is written or removed - the webhook,
 * the recovery callable, the expiry sweep and the grant callable itself:
 *
 *   RevenueCat says active        -> the paid grant
 *   else the free week is running -> the free week grant
 *   else                          -> no grant
 *
 * So an inactive RevenueCat answer can never take a running week away, a
 * purchase during the week replaces it, and a purchase that is refunded
 * inside the week hands the rest of the week back.
 */
export const FREE_WEEK_PRODUCT_ID = "ascend_free_week";
export const FREE_WEEK_GRANT_SOURCE = "trial";
export const FREE_WEEK_SOURCE_EVENT_ID = "free_week";
export const FREE_WEEK_SOURCE_EVENT_TYPE = "FREE_WEEK_GRANT";
export const FREE_WEEK_DURATION_MS = 7 * 24 * 60 * 60 * 1000;

// The rules check `users/{uid}/entitlements/app_access` by name, so the free
// week names the same document rather than reading the id out of the
// RevenueCat secret: this path must not depend on a vendor credential.
export const FREE_WEEK_ENTITLEMENT_ID = "app_access";

/**
 * The durable record that a climber was given their week.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Verified Firebase user id
 * @return {admin.firestore.DocumentReference} `users/{uid}/trial/free_week`
 */
export function freeWeekRecordRef(
  firestore: admin.firestore.Firestore,
  uid: string
): admin.firestore.DocumentReference {
  return firestore.doc(`users/${uid}/trial/free_week`);
}

export interface FreeWeekWindow {
  grantedAt: Date;
  expiresAt: Date;
}

/**
 * Reads a record's window, or null when there is no well-formed record.
 * @param {admin.firestore.DocumentSnapshot} record - The trial record
 * @return {FreeWeekWindow | null} The week it describes
 */
export function freeWeekWindow(
  record: admin.firestore.DocumentSnapshot
): FreeWeekWindow | null {
  if (!record.exists) {
    return null;
  }
  const grantedAt = record.get("grantedAt");
  const expiresAt = record.get("expiresAt");
  if (!(grantedAt instanceof admin.firestore.Timestamp) ||
    !(expiresAt instanceof admin.firestore.Timestamp)) {
    return null;
  }
  return {grantedAt: grantedAt.toDate(), expiresAt: expiresAt.toDate()};
}

/**
 * The week a record describes, only while it is still running.
 * @param {admin.firestore.DocumentSnapshot} record - The trial record
 * @param {Date} now - The clock
 * @return {FreeWeekWindow | null} The running week, or null
 */
export function liveFreeWeekWindow(
  record: admin.firestore.DocumentSnapshot,
  now: Date
): FreeWeekWindow | null {
  const window = freeWeekWindow(record);
  return window && window.expiresAt.getTime() > now.getTime() ? window : null;
}

/**
 * Whether a grant document is the free week rather than a paid grant.
 * @param {admin.firestore.DocumentSnapshot} grant - The active grant
 * @return {boolean} True for a free week grant
 */
export function isFreeWeekGrant(
  grant: admin.firestore.DocumentSnapshot
): boolean {
  return grant.exists && grant.get("source") === FREE_WEEK_GRANT_SOURCE;
}

/**
 * The grant document for a running week.
 *
 * It carries the fields a paid projection carries wherever they mean the same
 * thing, so the expiry sweep, the deploy preflight and anyone reading the
 * document by hand find `accessUntil` and `productId` where they expect them.
 * @param {string} uid - Verified Firebase user id
 * @param {FreeWeekWindow} window - The week being granted
 * @param {Date} now - When this document is written
 * @return {Record<string, unknown>} Firestore fields
 */
export function freeWeekGrantFields(
  uid: string,
  window: FreeWeekWindow,
  now: Date
): Record<string, unknown> {
  const expiresAt = admin.firestore.Timestamp.fromDate(window.expiresAt);
  return {
    schemaVersion: 1,
    uid,
    entitlementId: FREE_WEEK_ENTITLEMENT_ID,
    isActive: true,
    productId: FREE_WEEK_PRODUCT_ID,
    source: FREE_WEEK_GRANT_SOURCE,
    expiresAt,
    accessUntil: expiresAt,
    sourceEventId: FREE_WEEK_SOURCE_EVENT_ID,
    sourceEventType: FREE_WEEK_SOURCE_EVENT_TYPE,
    verifiedAt: admin.firestore.Timestamp.fromDate(now),
  };
}
