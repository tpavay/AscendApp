import {randomUUID} from "node:crypto";
import * as admin from "firebase-admin";
import type {
  AnalyticsOutboxClaim,
  AnalyticsOutboxStore,
  LifecycleAnalyticsEvent,
  LifecycleAnalyticsEventName,
} from "./analyticsTypes";

export const ANALYTICS_OUTBOX_COLLECTION =
  "_revenuecat_analytics_outbox";

// A row carries the affected Firebase UID as its Mixpanel `distinct_id`, so it
// may not outlive the reason it exists. Delivery dedupe only has to outlive
// RevenueCat's roughly 155-minute retry ladder; thirty days matches the event
// ledger and leaves a human-inspectable trail. The Firestore TTL policy on
// `retainUntil` does the deleting.
//
// Every state transition restamps it, so the bound measures thirty days from
// the row's last movement rather than from its creation: a row still retrying
// cannot be deleted out from under the retry-until-delivery guarantee, while a
// delivered or terminally failed row gets exactly one bounded window after it
// settled.
export const ANALYTICS_OUTBOX_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

const STALE_PROCESSING_MS = 15 * 60 * 1000;
const EVENT_NAMES = new Set<LifecycleAnalyticsEventName>([
  "subscription_started",
  "subscription_trial_started",
  "subscription_trial_converted",
  "subscription_renewed",
  "subscription_cancelled",
  "subscription_uncancelled",
  "subscription_billing_issue",
  "subscription_expired",
  "subscription_refunded",
  "subscription_product_changed",
]);

export class FirestoreAnalyticsOutboxStore
implements AnalyticsOutboxStore {
  constructor(private readonly firestore: admin.firestore.Firestore) {}

  async reclaimStale(now: Date, limit = 25): Promise<number> {
    const threshold = admin.firestore.Timestamp.fromMillis(
      now.getTime() - STALE_PROCESSING_MS
    );
    const snapshot = await this.collection()
      .where("status", "==", "processing")
      .where("processingStartedAt", "<=", threshold)
      .limit(limit)
      .get();
    let reclaimedCount = 0;

    for (const document of snapshot.docs) {
      const didReclaim = await this.firestore.runTransaction(
        async (transaction) => {
          const current = await transaction.get(document.ref);
          const startedAt = current.get("processingStartedAt");
          if (current.get("status") !== "processing" ||
            !(startedAt instanceof admin.firestore.Timestamp) ||
            startedAt.toMillis() > threshold.toMillis()) {
            return false;
          }
          transaction.update(document.ref, {
            status: "queued",
            readyAt: admin.firestore.Timestamp.fromDate(now),
            processingStartedAt: null,
            claimId: null,
            updatedAt: admin.firestore.Timestamp.fromDate(now),
            retainUntil: retentionStamp(now),
          });
          return true;
        }
      );
      if (didReclaim) {
        reclaimedCount += 1;
      }
    }
    return reclaimedCount;
  }

  async claimDue(now: Date, limit = 25): Promise<AnalyticsOutboxClaim[]> {
    const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
    const snapshot = await this.collection()
      .where("status", "==", "queued")
      .where("readyAt", "<=", nowTimestamp)
      .limit(limit)
      .get();
    const claims: AnalyticsOutboxClaim[] = [];

    for (const document of snapshot.docs) {
      const claim = await this.claimOne(document.ref, nowTimestamp);
      if (claim === "invalid_outbox_payload") {
        console.error("RevenueCat analytics row is unreadable and discarded", {
          outboxId: document.id,
          lastErrorCode: "invalid_outbox_payload",
        });
        continue;
      }
      if (claim) {
        claims.push(claim);
      }
    }
    return claims;
  }

  async markDelivered(
    claim: AnalyticsOutboxClaim,
    now: Date
  ): Promise<void> {
    await this.updateClaimed(claim, {
      status: "delivered",
      deliveredAt: admin.firestore.Timestamp.fromDate(now),
      processingStartedAt: null,
      claimId: null,
      lastErrorCode: null,
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retentionStamp(now),
    });
  }

  async requeue(
    claim: AnalyticsOutboxClaim,
    readyAt: Date,
    errorCode: string,
    now: Date
  ): Promise<void> {
    await this.updateClaimed(claim, {
      status: "queued",
      readyAt: admin.firestore.Timestamp.fromDate(readyAt),
      processingStartedAt: null,
      claimId: null,
      lastErrorCode: errorCode,
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retentionStamp(now),
    });
  }

  async release(
    claim: AnalyticsOutboxClaim,
    now: Date
  ): Promise<void> {
    await this.updateClaimed(claim, {
      status: "queued",
      readyAt: admin.firestore.Timestamp.fromDate(now),
      processingStartedAt: null,
      claimId: null,
      attemptCount: Math.max(claim.attemptCount - 1, 0),
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retentionStamp(now),
    });
  }

  async markFailed(
    claim: AnalyticsOutboxClaim,
    errorCode: string,
    now: Date
  ): Promise<void> {
    await this.updateClaimed(claim, {
      status: "failed",
      processingStartedAt: null,
      claimId: null,
      lastErrorCode: errorCode,
      updatedAt: admin.firestore.Timestamp.fromDate(now),
      retainUntil: retentionStamp(now),
    });
  }

  private collection(): admin.firestore.CollectionReference {
    return this.firestore.collection(ANALYTICS_OUTBOX_COLLECTION);
  }

  private async claimOne(
    reference: admin.firestore.DocumentReference,
    now: admin.firestore.Timestamp
  ): Promise<AnalyticsOutboxClaim | "invalid_outbox_payload" | null> {
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const readyAt = snapshot.get("readyAt");
      if (!snapshot.exists ||
        snapshot.get("status") !== "queued" ||
        !(readyAt instanceof admin.firestore.Timestamp) ||
        readyAt.toMillis() > now.toMillis()) {
        return null;
      }
      const event = parseLifecycleAnalyticsEvent(snapshot.data());
      if (!event || event.insertId !== reference.id) {
        transaction.update(reference, {
          status: "failed",
          processingStartedAt: null,
          claimId: null,
          lastErrorCode: "invalid_outbox_payload",
          updatedAt: now,
        });
        return "invalid_outbox_payload";
      }
      const attemptCount = integerAtLeast(snapshot.get("attemptCount"), 0) + 1;
      const claimId = randomUUID();
      transaction.update(reference, {
        status: "processing",
        attemptCount,
        processingStartedAt: now,
        claimId,
        updatedAt: now,
      });
      return {
        outboxId: reference.id,
        claimId,
        attemptCount,
        event,
      };
    });
  }

  private async updateClaimed(
    claim: AnalyticsOutboxClaim,
    updates: Record<string, unknown>
  ): Promise<void> {
    const reference = this.collection().doc(claim.outboxId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (snapshot.get("status") !== "processing" ||
        snapshot.get("claimId") !== claim.claimId) {
        return;
      }
      transaction.update(reference, updates);
    });
  }
}

/**
 * Renders one queued outbox row, including its bounded retention stamp.
 * @param {LifecycleAnalyticsEvent} event - Normalized lifecycle event
 * @param {admin.firestore.Timestamp} now - Write clock
 * @return {Record<string, unknown>} Serialized queued row
 */
export function serializeAnalyticsOutboxEvent(
  event: LifecycleAnalyticsEvent,
  now: admin.firestore.Timestamp
): Record<string, unknown> {
  return {
    ...event,
    status: "queued",
    attemptCount: 0,
    readyAt: now,
    processingStartedAt: null,
    claimId: null,
    deliveredAt: null,
    lastErrorCode: null,
    createdAt: now,
    updatedAt: now,
    retainUntil: admin.firestore.Timestamp.fromMillis(
      now.toMillis() + ANALYTICS_OUTBOX_RETENTION_MS
    ),
  };
}

function retentionStamp(now: Date): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromMillis(
    now.getTime() + ANALYTICS_OUTBOX_RETENTION_MS
  );
}

function parseLifecycleAnalyticsEvent(
  value: admin.firestore.DocumentData | undefined
): LifecycleAnalyticsEvent | null {
  if (!value ||
    value.schemaVersion !== 1 ||
    !isEventName(value.eventName) ||
    value.eventVersion !== 1 ||
    value.source !== "revenuecat_webhook" ||
    !isBoundedString(value.distinctId, 128) ||
    typeof value.insertId !== "string" ||
    !/^[a-f0-9]{32}$/.test(value.insertId) ||
    !isPositiveInteger(value.eventTimestampMs) ||
    value.entitlementId !== "app_access" ||
    !isBoundedString(value.productId, 200) ||
    !isNullableBoundedString(value.previousProductId, 200) ||
    !isBoundedString(value.store, 30) ||
    !isBoundedString(value.periodType, 30) ||
    !isNullableBoundedString(value.lifecycleReason, 40) ||
    !isOptionalBoolean(value.refundAttributed) ||
    typeof value.entitlementActive !== "boolean" ||
    !isNullablePositiveInteger(value.effectiveExpirationAtMs) ||
    !isBoundedString(value.firebaseProjectId, 100) ||
    !isAppEnvironment(value.appEnvironment) ||
    value.buildConfig !== "server" ||
    value.appVersion !== "cloud_functions" ||
    !isBoundedString(value.buildNumber, 100)) {
    return null;
  }
  return {
    schemaVersion: 1,
    eventName: value.eventName,
    eventVersion: 1,
    source: "revenuecat_webhook",
    distinctId: value.distinctId,
    insertId: value.insertId,
    eventTimestampMs: value.eventTimestampMs,
    entitlementId: "app_access",
    productId: value.productId,
    previousProductId: value.previousProductId,
    store: value.store,
    periodType: value.periodType,
    lifecycleReason: value.lifecycleReason,
    refundAttributed: value.refundAttributed === true,
    entitlementActive: value.entitlementActive,
    effectiveExpirationAtMs: value.effectiveExpirationAtMs,
    firebaseProjectId: value.firebaseProjectId,
    appEnvironment: value.appEnvironment,
    buildConfig: "server",
    appVersion: "cloud_functions",
    buildNumber: value.buildNumber,
  };
}

function isEventName(value: unknown): value is LifecycleAnalyticsEventName {
  return typeof value === "string" &&
    EVENT_NAMES.has(value as LifecycleAnalyticsEventName);
}

function isAppEnvironment(
  value: unknown
): value is "dev" | "staging" | "production" {
  return value === "dev" || value === "staging" || value === "production";
}

function isOptionalBoolean(value: unknown): value is boolean | undefined {
  return value === undefined || typeof value === "boolean";
}

function isBoundedString(value: unknown, max: number): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= max;
}

function isNullableBoundedString(
  value: unknown,
  max: number
): value is string | null {
  return value === null || isBoundedString(value, max);
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" &&
    Number.isSafeInteger(value) && value > 0;
}

function isNullablePositiveInteger(value: unknown): value is number | null {
  return value === null || isPositiveInteger(value);
}

function integerAtLeast(value: unknown, minimum: number): number {
  return typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= minimum ? value : minimum;
}
