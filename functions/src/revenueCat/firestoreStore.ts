import * as admin from "firebase-admin";
import type {
  AppAccessProjection,
  RevenueCatEntitlementStore,
  RevenueCatWebhookEvent,
  WebhookClaimOutcome,
} from "./types";

const EVENT_COLLECTION = "_revenuecat_webhook_events";
const PROCESSING_LEASE_MS = 2 * 60 * 1000;

export class FirestoreRevenueCatEntitlementStore
implements RevenueCatEntitlementStore {
  constructor(private readonly firestore: admin.firestore.Firestore) {}

  async claimEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    now: Date
  ): Promise<WebhookClaimOutcome> {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(event.id);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
      const leaseExpiresAt = admin.firestore.Timestamp.fromMillis(
        now.getTime() + PROCESSING_LEASE_MS
      );

      if (!snapshot.exists) {
        transaction.create(eventRef, {
          schemaVersion: 1,
          status: "processing",
          payloadSha256,
          eventType: event.type,
          eventTimestampMs: event.eventTimestampMs,
          attemptCount: 1,
          receivedAt: nowTimestamp,
          updatedAt: nowTimestamp,
          leaseExpiresAt,
          completedAt: null,
          lastErrorCode: null,
        });
        return "claimed";
      }

      const data = snapshot.data();
      if (data?.payloadSha256 !== payloadSha256) {
        return "conflict";
      }
      if (data.status === "completed") {
        return "duplicate";
      }
      const existingLease = data.leaseExpiresAt;
      if (data.status === "processing" &&
        existingLease instanceof admin.firestore.Timestamp &&
        existingLease.toMillis() > now.getTime()) {
        return "busy";
      }

      transaction.update(eventRef, {
        status: "processing",
        attemptCount: typeof data.attemptCount === "number" ?
          data.attemptCount + 1 : 1,
        updatedAt: nowTimestamp,
        leaseExpiresAt,
        lastErrorCode: null,
      });
      return "claimed";
    });
  }

  async completeEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    projections: AppAccessProjection[],
    now: Date
  ): Promise<void> {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(event.id);
    const projectionRefs = projections.map((projection) =>
      this.firestore.doc(
        `users/${projection.uid}/entitlements/${projection.entitlementId}`
      )
    );
    const statusRefs = projections.map((projection) =>
      this.firestore.doc(
        `users/${projection.uid}/entitlement_status/` +
        projection.entitlementId
      )
    );

    await this.firestore.runTransaction(async (transaction) => {
      const eventSnapshot = await transaction.get(eventRef);
      if (!eventSnapshot.exists ||
        eventSnapshot.get("payloadSha256") !== payloadSha256 ||
        eventSnapshot.get("status") !== "processing") {
        throw new Error("RevenueCat event claim was lost before completion");
      }

      const existingStatuses = statusRefs.length > 0 ?
        await transaction.getAll(...statusRefs) : [];
      projections.forEach((projection, index) => {
        const existingRequestDate = existingStatuses[index]?.get(
          "revenueCatRequestDateMs"
        );
        if (typeof existingRequestDate === "number" &&
          existingRequestDate > projection.revenueCatRequestDateMs) {
          return;
        }

        const serialized = serializeProjection(projection);
        transaction.set(statusRefs[index], serialized);
        if (projection.isActive) {
          transaction.set(projectionRefs[index], serialized);
        } else {
          transaction.delete(projectionRefs[index]);
        }
      });

      const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
      transaction.update(eventRef, {
        status: "completed",
        completedAt: nowTimestamp,
        updatedAt: nowTimestamp,
        leaseExpiresAt: null,
        lastErrorCode: null,
        affectedUserCount: projections.length,
      });
    });
  }

  async failEvent(
    eventId: string,
    payloadSha256: string,
    errorCode: string,
    now: Date
  ): Promise<void> {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(eventId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      if (!snapshot.exists ||
        snapshot.get("payloadSha256") !== payloadSha256 ||
        snapshot.get("status") !== "processing") {
        return;
      }
      transaction.update(eventRef, {
        status: "failed",
        updatedAt: admin.firestore.Timestamp.fromDate(now),
        leaseExpiresAt: null,
        lastErrorCode: errorCode,
      });
    });
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
