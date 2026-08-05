import * as admin from "firebase-admin";
import {shouldReplaceProjection} from "./projectionOrdering";
import type {
  AppAccessProjection,
  RevenueCatEntitlementStore,
  RevenueCatWebhookEvent,
  WebhookClaim,
} from "./types";

const EVENT_COLLECTION = "_revenuecat_webhook_events";
const PROCESSING_LEASE_MS = 2 * 60 * 1000;

// RevenueCat currently retries a failed delivery five times over roughly 155
// minutes, and dedupe only has to outlive that window. Thirty days keeps a
// human-inspectable trail of what the server acted on while still bounding the
// ledger, and the Firestore TTL policy on `retainUntil` does the deleting.
// `receivedAt` cannot carry the policy: it is already in the past when it is
// written, so every document would be eligible for deletion immediately.
export const EVENT_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

export class FirestoreRevenueCatEntitlementStore
implements RevenueCatEntitlementStore {
  constructor(private readonly firestore: admin.firestore.Firestore) {}

  async claimEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    now: Date
  ): Promise<WebhookClaim> {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(event.id);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
      const leaseExpiresAt = admin.firestore.Timestamp.fromMillis(
        now.getTime() + PROCESSING_LEASE_MS
      );
      const retainUntil = admin.firestore.Timestamp.fromMillis(
        now.getTime() + EVENT_RETENTION_MS
      );

      if (!snapshot.exists) {
        transaction.create(eventRef, {
          schemaVersion: 1,
          status: "processing",
          payloadSha256,
          eventType: event.type,
          eventTimestampMs: event.eventTimestampMs,
          attemptCount: 1,
          conflictingPayloadCount: 0,
          receivedAt: nowTimestamp,
          updatedAt: nowTimestamp,
          retainUntil,
          leaseExpiresAt,
          completedAt: null,
          lastErrorCode: null,
        });
        return {outcome: "claimed", claimDigest: payloadSha256};
      }

      // First seen wins. The event's ledger entry keeps the digest and the
      // metadata of the delivery that created it, so a redelivery with
      // different bytes can neither rewrite history nor be refused forever:
      // it completes against the canonical claim, and the projection it
      // writes comes from a fresh subscriber fetch either way.
      const data = snapshot.data() ?? {};
      const claimDigest = typeof data.payloadSha256 === "string" ?
        data.payloadSha256 : payloadSha256;
      const conflictingPayloadCount =
        (typeof data.conflictingPayloadCount === "number" ?
          data.conflictingPayloadCount : 0) +
        (claimDigest === payloadSha256 ? 0 : 1);
      const recordConflict = () => {
        if (claimDigest !== payloadSha256) {
          transaction.update(eventRef, {conflictingPayloadCount});
        }
      };

      if (data.status === "completed") {
        recordConflict();
        return {outcome: "duplicate", claimDigest};
      }
      const existingLease = data.leaseExpiresAt;
      if (data.status === "processing" &&
        existingLease instanceof admin.firestore.Timestamp &&
        existingLease.toMillis() > now.getTime()) {
        recordConflict();
        return {outcome: "busy", claimDigest};
      }

      transaction.update(eventRef, {
        status: "processing",
        attemptCount: typeof data.attemptCount === "number" ?
          data.attemptCount + 1 : 1,
        conflictingPayloadCount,
        updatedAt: nowTimestamp,
        retainUntil,
        leaseExpiresAt,
        lastErrorCode: null,
      });
      return {outcome: "claimed", claimDigest};
    });
  }

  async completeEvent(
    event: RevenueCatWebhookEvent,
    claimDigest: string,
    projections: AppAccessProjection[],
    now: Date
  ): Promise<void> {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(event.id);
    const projectionRefs = projections.map(
      (projection) => this.activeGrantRef(projection)
    );
    const statusRefs = projections.map(
      (projection) => this.statusRef(projection)
    );

    await this.firestore.runTransaction(async (transaction) => {
      const eventSnapshot = await transaction.get(eventRef);
      if (!eventSnapshot.exists ||
        eventSnapshot.get("payloadSha256") !== claimDigest ||
        eventSnapshot.get("status") !== "processing") {
        throw new Error("RevenueCat event claim was lost before completion");
      }

      const existingStatuses = statusRefs.length > 0 ?
        await transaction.getAll(...statusRefs) : [];
      projections.forEach((projection, index) => {
        if (!shouldReplaceProjection(
          existingStatuses[index]?.get("revenueCatRequestDateMs"),
          projection
        )) {
          return;
        }
        applyProjection(
          transaction,
          projection,
          statusRefs[index],
          projectionRefs[index]
        );
      });

      const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
      transaction.update(eventRef, {
        status: "completed",
        completedAt: nowTimestamp,
        updatedAt: nowTimestamp,
        retainUntil: admin.firestore.Timestamp.fromMillis(
          now.getTime() + EVENT_RETENTION_MS
        ),
        leaseExpiresAt: null,
        lastErrorCode: null,
        affectedUserCount: projections.length,
      });
    });
  }

  async failEvent(
    eventId: string,
    claimDigest: string,
    errorCode: string,
    now: Date
  ): Promise<void> {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(eventId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      if (!snapshot.exists ||
        snapshot.get("payloadSha256") !== claimDigest ||
        snapshot.get("status") !== "processing") {
        return;
      }
      transaction.update(eventRef, {
        status: "failed",
        updatedAt: admin.firestore.Timestamp.fromDate(now),
        retainUntil: admin.firestore.Timestamp.fromMillis(
          now.getTime() + EVENT_RETENTION_MS
        ),
        leaseExpiresAt: null,
        lastErrorCode: errorCode,
      });
    });
  }

  /**
   * Applies one server-derived projection outside the webhook ledger.
   *
   * The recovery path needs exactly the webhook's write, minus the event
   * bookkeeping, and under exactly the webhook's ordering rule.
   * @param {AppAccessProjection} projection - Freshly derived projection
   * @return {Promise<boolean>} Whether it replaced what was stored
   */
  async writeProjection(projection: AppAccessProjection): Promise<boolean> {
    const statusRef = this.statusRef(projection);
    const grantRef = this.activeGrantRef(projection);

    return this.firestore.runTransaction(async (transaction) => {
      const [existingStatus, existingGrant] = await transaction.getAll(
        statusRef,
        grantRef
      );
      if (!shouldReplaceProjection(
        existingStatus.get("revenueCatRequestDateMs"),
        projection
      )) {
        return false;
      }
      // A recovery check is polled rather than event-driven, and it carries a
      // fresh RevenueCat request stamp every time, so the ordering rule alone
      // would rewrite both documents on every call. Nothing an authorization
      // decision reads has changed in that case.
      if (isProjectedAccessUnchanged(
        existingStatus,
        existingGrant,
        projection
      )) {
        return false;
      }
      applyProjection(transaction, projection, statusRef, grantRef);
      return true;
    });
  }

  /**
   * Reserves the next self-service reconciliation for one Firebase user.
   *
   * The cooldown is server-owned so a modified client cannot turn the recovery
   * path into an unbounded RevenueCat subscriber-API amplifier.
   * @param {string} uid - Verified Firebase user id
   * @param {Date} now - Reservation clock
   * @param {number} cooldownMs - Minimum spacing between reconciliations
   * @return {Promise<boolean>} Whether this caller may reconcile now
   */
  async claimReconciliation(
    uid: string,
    now: Date,
    cooldownMs: number
  ): Promise<boolean> {
    const limitRef = this.firestore.doc(
      `users/${uid}/entitlement_reconciliations/current`
    );

    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(limitRef);
      const lastReconciledAt = snapshot.get("lastReconciledAt");
      if (lastReconciledAt instanceof admin.firestore.Timestamp &&
        now.getTime() - lastReconciledAt.toMillis() < cooldownMs) {
        return false;
      }

      const requestCount = snapshot.get("requestCount");
      transaction.set(limitRef, {
        schemaVersion: 1,
        lastReconciledAt: admin.firestore.Timestamp.fromDate(now),
        requestCount: typeof requestCount === "number" ? requestCount + 1 : 1,
      });
      return true;
    });
  }

  /**
   * Shortens this attempt's reservation to a brief retry window.
   *
   * An attempt that never reached subscriber truth must not hold the full
   * success cooldown, or a subscriber who then taps Restore is refused the
   * recovery they asked for. Clearing the reservation outright is the opposite
   * failure: during a RevenueCat outage every foreground would issue another
   * subscriber fetch, which is the amplification the cooldown exists to stop.
   * Only the reservation this attempt made is shortened, so a newer claim that
   * already replaced it is left alone.
   * @param {string} uid - Verified Firebase user id
   * @param {Date} claimedAt - The instant this attempt reserved
   * @param {number} retryAfterMs - Spacing to leave before the next attempt
   * @param {number} cooldownMs - The success cooldown being shortened
   * @return {Promise<void>}
   */
  async backOffReconciliation(
    uid: string,
    claimedAt: Date,
    retryAfterMs: number,
    cooldownMs: number
  ): Promise<void> {
    const limitRef = this.firestore.doc(
      `users/${uid}/entitlement_reconciliations/current`
    );

    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(limitRef);
      const lastReconciledAt = snapshot.get("lastReconciledAt");
      if (!(lastReconciledAt instanceof admin.firestore.Timestamp) ||
        lastReconciledAt.toMillis() !== claimedAt.getTime()) {
        return;
      }
      transaction.update(limitRef, {
        lastReconciledAt: admin.firestore.Timestamp.fromMillis(
          claimedAt.getTime() - Math.max(cooldownMs - retryAfterMs, 0)
        ),
      });
    });
  }

  private statusRef(
    projection: AppAccessProjection
  ): admin.firestore.DocumentReference {
    return this.firestore.doc(
      `users/${projection.uid}/entitlement_status/${projection.entitlementId}`
    );
  }

  private activeGrantRef(
    projection: AppAccessProjection
  ): admin.firestore.DocumentReference {
    return this.firestore.doc(
      `users/${projection.uid}/entitlements/${projection.entitlementId}`
    );
  }
}

function isProjectedAccessUnchanged(
  status: admin.firestore.DocumentSnapshot,
  grant: admin.firestore.DocumentSnapshot,
  projection: AppAccessProjection
): boolean {
  if (!status.exists || grant.exists !== projection.isActive) {
    return false;
  }
  const accessUntil = status.get("accessUntil");
  return status.get("isActive") === projection.isActive &&
    (status.get("productId") ?? null) === projection.productId &&
    accessUntil instanceof admin.firestore.Timestamp &&
    accessUntil.toMillis() === projection.accessUntil.getTime();
}

function applyProjection(
  transaction: admin.firestore.Transaction,
  projection: AppAccessProjection,
  statusRef: admin.firestore.DocumentReference,
  grantRef: admin.firestore.DocumentReference
): void {
  const serialized = serializeProjection(projection);
  transaction.set(statusRef, serialized);
  if (projection.isActive) {
    transaction.set(grantRef, serialized);
  } else {
    transaction.delete(grantRef);
  }
}

function serializeProjection(
  projection: AppAccessProjection
): Record<string, unknown> {
  return {
    ...projection,
    accessUntil: admin.firestore.Timestamp.fromDate(projection.accessUntil),
    expiresAt: projection.expiresAt ?
      admin.firestore.Timestamp.fromDate(projection.expiresAt) : null,
    verifiedAt: admin.firestore.Timestamp.fromDate(projection.verifiedAt),
  };
}
