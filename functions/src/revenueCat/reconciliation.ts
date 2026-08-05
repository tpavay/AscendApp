import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  getRevenueCatServerConfig,
  revenueCatServerConfig,
} from "./config";
import {FirestoreRevenueCatEntitlementStore} from "./firestoreStore";
import {
  buildAppAccessProjection,
  HttpRevenueCatSubscriberClient,
} from "./subscriber";
import {AdminFirebaseUserVerifier} from "./firebaseUserVerifier";
import type {
  RevenueCatReconciliationDependencies,
  RevenueCatWebhookEvent,
} from "./types";

const RECONCILIATION_SOURCE_EVENT_ID = "client_reconciliation";
const RECONCILIATION_SOURCE_EVENT_TYPE = "CLIENT_RECONCILIATION";
export const RECONCILIATION_COOLDOWN_MS = 60 * 1000;
export const RECONCILIATION_FAILURE_RETRY_AFTER_MS = 15 * 1000;

export type ReconciliationOutcome = "active" | "inactive";

export interface ReconciliationResult {
  outcome: ReconciliationOutcome;
  didReplaceProjection: boolean;
}

export class UnknownFirebaseUserError extends Error {
  constructor() {
    super("The reconciliation subject is not a Firebase user");
    this.name = "UnknownFirebaseUserError";
  }
}

/**
 * Re-derives one Firebase user's paid access straight from RevenueCat.
 *
 * The webhook is at-least-once, not exactly-once: a delivery that never
 * arrived or exhausted RevenueCat's retries would otherwise leave a paying
 * subscriber locked out of every paid boundary with no in-app remedy, and a
 * brand-new purchase races the very first delivery. This recovers both from
 * the same subscriber API the webhook derives from, so nothing about the
 * trust boundary moves: the caller supplies no entitlement, product, expiry,
 * or identity.
 * @param {string} uid - Verified Firebase user id, never client-supplied
 * @param {RevenueCatReconciliationDependencies} dependencies - Trusted ports
 * @return {Promise<ReconciliationResult>} Server-derived access disposition
 */
export async function reconcileAppAccessForUser(
  uid: string,
  dependencies: RevenueCatReconciliationDependencies
): Promise<ReconciliationResult> {
  if (!await dependencies.userVerifier.isFirebaseUser(uid)) {
    throw new UnknownFirebaseUserError();
  }

  const now = dependencies.now();
  const subscriber = await dependencies.subscriberClient.fetchSubscriber(uid);
  const projection = buildAppAccessProjection(
    uid,
    subscriber,
    dependencies.config,
    reconciliationSourceEvent(dependencies.config.appId, uid, now),
    now
  );
  const didReplaceProjection = await dependencies.store.writeProjection(
    projection
  );

  return {
    outcome: projection.isActive ? "active" : "inactive",
    didReplaceProjection,
  };
}

function reconciliationSourceEvent(
  appId: string,
  uid: string,
  now: Date
): RevenueCatWebhookEvent {
  return {
    id: RECONCILIATION_SOURCE_EVENT_ID,
    type: RECONCILIATION_SOURCE_EVENT_TYPE,
    appId,
    eventTimestampMs: now.getTime(),
    appUserIds: [uid],
    identityOverflowCount: 0,
    productId: null,
    newProductId: null,
    store: "unknown",
    periodType: "unknown",
    expirationAtMs: null,
    gracePeriodExpirationAtMs: null,
    isTrialConversion: false,
    lifecycleReason: null,
  };
}

export const reconcileAppAccess = onCall(
  {
    secrets: [revenueCatServerConfig],
    timeoutSeconds: 30,
  },
  async (request) => {
    // Deliberately never reads request.data. The only identity this function
    // will act on is the one Firebase Authentication verified.
    const uid = request.auth?.uid;
    if (typeof uid !== "string" || uid.length === 0) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in to check your access."
      );
    }

    let config;
    try {
      config = getRevenueCatServerConfig();
    } catch {
      console.error("RevenueCat reconciliation configuration is invalid");
      throw new HttpsError("internal", "Access check is unavailable.");
    }

    const store = new FirestoreRevenueCatEntitlementStore(admin.firestore());
    const now = new Date();
    const mayReconcile = await store.claimReconciliation(
      uid,
      now,
      RECONCILIATION_COOLDOWN_MS
    );
    if (!mayReconcile) {
      return {status: "throttled"};
    }

    try {
      const result = await reconcileAppAccessForUser(uid, {
        store,
        subscriberClient: new HttpRevenueCatSubscriberClient(config.apiKey),
        userVerifier: new AdminFirebaseUserVerifier(),
        config,
        now: () => new Date(),
      });
      return {status: result.outcome};
    } catch (error) {
      await store.backOffReconciliation(
        uid,
        now,
        RECONCILIATION_FAILURE_RETRY_AFTER_MS,
        RECONCILIATION_COOLDOWN_MS
      ).catch(() => undefined);
      if (error instanceof UnknownFirebaseUserError) {
        throw new HttpsError(
          "permission-denied",
          "This account cannot be reconciled."
        );
      }
      console.error("RevenueCat reconciliation failed");
      throw new HttpsError(
        "unavailable",
        "Ascend could not reach your subscription. Try again."
      );
    }
  }
);
