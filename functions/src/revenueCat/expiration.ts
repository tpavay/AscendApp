import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";

const EXPIRATION_BATCH_SIZE = 200;

/**
 * Removes active grants once the last RevenueCat-verified access window ends.
 *
 * This makes the rules fail closed at a known expiry even if an expiration
 * webhook is delayed. A concurrent renewal wins through the transaction retry.
 * @param {Firestore} firestore - Admin Firestore instance
 * @param {Date} now - Expiration clock
 * @return {Promise<number>} Number of active grants removed
 */
export async function expireRevenueCatAccessGrants(
  firestore: admin.firestore.Firestore,
  now: Date
): Promise<number> {
  const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
  const snapshot = await firestore.collectionGroup("entitlements")
    .where("accessUntil", "<=", nowTimestamp)
    .limit(EXPIRATION_BATCH_SIZE)
    .get();
  let expiredCount = 0;

  for (const document of snapshot.docs) {
    if (!isAppAccessGrant(document.ref)) {
      continue;
    }
    const didExpire = await firestore.runTransaction(async (transaction) => {
      const current = await transaction.get(document.ref);
      const accessUntil = current.get("accessUntil");
      if (!current.exists ||
        !(accessUntil instanceof admin.firestore.Timestamp) ||
        accessUntil.toMillis() > now.getTime()) {
        return false;
      }

      const statusRef = document.ref.parent.parent?.collection(
        "entitlement_status"
      ).doc(document.id);
      if (!statusRef) {
        return false;
      }
      transaction.delete(document.ref);
      transaction.set(statusRef, {
        isActive: false,
        accessUntil: admin.firestore.Timestamp.fromDate(new Date(0)),
        expiredByServerAt: nowTimestamp,
      }, {merge: true});
      return true;
    });
    if (didExpire) {
      expiredCount += 1;
    }
  }

  return expiredCount;
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
