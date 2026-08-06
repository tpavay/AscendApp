export type LifecycleAnalyticsEventName =
  | "subscription_started"
  | "subscription_trial_started"
  | "subscription_trial_converted"
  | "subscription_renewed"
  | "subscription_cancelled"
  | "subscription_uncancelled"
  | "subscription_billing_issue"
  | "subscription_expired"
  | "subscription_refunded"
  | "subscription_product_changed";

export interface RevenueCatAnalyticsEnvironment {
  firebaseProjectId: string;
  mixpanelProjectId: string;
  appEnvironment: "dev" | "staging" | "production";
  buildConfig: "server";
  appVersion: "cloud_functions";
  buildNumber: string;
}

export interface LifecycleAnalyticsEvent {
  schemaVersion: 1;
  eventName: LifecycleAnalyticsEventName;
  eventVersion: 1;
  source: "revenuecat_webhook";
  distinctId: string;
  insertId: string;
  eventTimestampMs: number;
  entitlementId: "app_access";
  productId: string;
  previousProductId: string | null;
  store: string;
  periodType: string;
  lifecycleReason: string | null;
  refundAttributed: boolean;
  entitlementActive: boolean;
  effectiveExpirationAtMs: number | null;
  firebaseProjectId: string;
  appEnvironment: "dev" | "staging" | "production";
  buildConfig: "server";
  appVersion: "cloud_functions";
  buildNumber: string;
}

export interface AnalyticsOutboxClaim {
  outboxId: string;
  claimId: string;
  attemptCount: number;
  event: LifecycleAnalyticsEvent;
}

export interface AnalyticsOutboxStore {
  reclaimStale(now: Date, limit?: number): Promise<number>;
  claimDue(now: Date, limit?: number): Promise<AnalyticsOutboxClaim[]>;
  markDelivered(claim: AnalyticsOutboxClaim, now: Date): Promise<void>;
  requeue(
    claim: AnalyticsOutboxClaim,
    readyAt: Date,
    errorCode: string,
    now: Date
  ): Promise<void>;
  markFailed(
    claim: AnalyticsOutboxClaim,
    errorCode: string,
    now: Date
  ): Promise<void>;
  /**
   * Returns a claim the run never attempted, so the row keeps the delivery
   * attempt count and last delivery error it had before it was claimed.
   */
  release(claim: AnalyticsOutboxClaim, now: Date): Promise<void>;
}

export interface LifecycleAnalyticsClient {
  send(event: LifecycleAnalyticsEvent): Promise<void>;
}

export interface AnalyticsOutboxProcessingSummary {
  reclaimedCount: number;
  claimedCount: number;
  deliveredCount: number;
  retriedCount: number;
  failedCount: number;
  deferredCount: number;
}
