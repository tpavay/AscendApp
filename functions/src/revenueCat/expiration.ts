import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";

const EXPIRATION_BATCH_SIZE = 200;
const EXPIRATION_PAGE_SIZE = 200;
const MAX_EXPIRATION_PAGES = 25;

export interface ExpirationSweepOptions {
  grantBudget?: number;
  pageSize?: number;
  maxPages?: number;
}

/**
 * Removes active grants once the last RevenueCat-verified access window ends.
 *
 * This makes the rules fail closed at a known expiry even if an expiration
 * webhook is delayed. A concurrent renewal wins through the transaction retry.
 *
 * The collection group is shared with any other `entitlements` subcollection,
 * and the query is ordered by `accessUntil`, so a foreign document with an
 * ancient timestamp would otherwise sit at the head of a fixed window forever
 * and starve every real expiry behind it. Paging past what the filter rejects
 * spends the budget on actual `users/{uid}/entitlements/app_access` grants.
 * @param {Firestore} firestore - Admin Firestore instance
 * @param {Date} now - Expiration clock
 * @param {ExpirationSweepOptions} options - Bounds for one sweep
 * @return {Promise<number>} Number of active grants removed
 */
export async function expireRevenueCatAccessGrants(
  firestore: admin.firestore.Firestore,
  now: Date,
  options: ExpirationSweepOptions = {}
): Promise<number> {
  const grantBudget = options.grantBudget ?? EXPIRATION_BATCH_SIZE;
  const pageSize = options.pageSize ?? EXPIRATION_PAGE_SIZE;
  const maxPages = options.maxPages ?? MAX_EXPIRATION_PAGES;
  const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
  const baseQuery = firestore.collectionGroup("entitlements")
    .where("accessUntil", "<=", nowTimestamp)
    .orderBy("accessUntil");

  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
  let consideredGrants = 0;
  let expiredCount = 0;

  for (let page = 0; page < maxPages; page++) {
    if (consideredGrants >= grantBudget) {
      break;
    }
    const query = cursor ?
      baseQuery.startAfter(cursor).limit(pageSize) :
      baseQuery.limit(pageSize);
    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];

    for (const document of snapshot.docs) {
      if (!isAppAccessGrant(document.ref)) {
        continue;
      }
      consideredGrants += 1;
      if (await expireGrant(firestore, document.ref, now, nowTimestamp)) {
        expiredCount += 1;
      }
      if (consideredGrants >= grantBudget) {
        break;
      }
    }

    if (snapshot.size < pageSize) {
      break;
    }
  }

  return expiredCount;
}

async function expireGrant(
  firestore: admin.firestore.Firestore,
  grantRef: admin.firestore.DocumentReference,
  now: Date,
  nowTimestamp: admin.firestore.Timestamp
): Promise<boolean> {
  return firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(grantRef);
    const accessUntil = current.get("accessUntil");
    if (!current.exists ||
      !(accessUntil instanceof admin.firestore.Timestamp) ||
      accessUntil.toMillis() > now.getTime()) {
      return false;
    }

    const statusRef = grantRef.parent.parent?.collection(
      "entitlement_status"
    ).doc(grantRef.id);
    if (!statusRef) {
      return false;
    }
    transaction.delete(grantRef);
    transaction.set(statusRef, {
      isActive: false,
      accessUntil: admin.firestore.Timestamp.fromDate(new Date(0)),
      expiredByServerAt: nowTimestamp,
    }, {merge: true});
    return true;
  });
}

function isAppAccessGrant(
  reference: admin.firestore.DocumentReference
): boolean {
  const segments = reference.path.split("/");
  return segments.length === 4 &&
    segments[0] === "users" &&
    segments[2] === "entitlements" &&
    segments[3] === "app_access";
}

export const expireRevenueCatEntitlements = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "UTC",
  },
  async () => {
    const expiredCount = await expireRevenueCatAccessGrants(
      admin.firestore(),
      new Date()
    );
    console.log("RevenueCat entitlement expiry sweep completed", {
      expiredCount,
    });
  }
);
