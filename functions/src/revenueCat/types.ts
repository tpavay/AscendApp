import type {
  LifecycleAnalyticsEvent,
  RevenueCatAnalyticsEnvironment,
} from "./analyticsTypes";

export interface RevenueCatServerConfig {
  apiKey: string;
  webhookAuthorization: string;
  webhookSigningSecret: string;
  appId: string;
  entitlementId: string;
  allowedProductIds: string[];
}

export interface RevenueCatWebhookEvent {
  id: string;
  type: string;
  appId: string;
  eventTimestampMs: number;
  appUserIds: string[];
  identityOverflowCount: number;
  productId: string | null;
  newProductId: string | null;
  store: string;
  periodType: string;
  expirationAtMs: number | null;
  gracePeriodExpirationAtMs: number | null;
  isTrialConversion: boolean;
  lifecycleReason: string | null;
}

export interface RevenueCatSubscriberResponse {
  requestDateMs: number;
  subscriber: {
    entitlements: Record<string, RevenueCatEntitlement>;
    subscriptions: Record<string, RevenueCatSubscription>;
  };
}

export interface RevenueCatEntitlement {
  expiresDate: string | null;
  gracePeriodExpiresDate: string | null;
  productIdentifier: string | null;
}

export interface RevenueCatSubscription {
  expiresDate: string | null;
  gracePeriodExpiresDate: string | null;
}

export interface AppAccessProjection {
  schemaVersion: 1;
  uid: string;
  entitlementId: string;
  isActive: boolean;
  productId: string | null;
  expiresAt: Date | null;
  accessUntil: Date;
  revenueCatAppId: string;
  revenueCatRequestDateMs: number;
  sourceEventId: string;
  sourceEventType: string;
  verifiedAt: Date;
}

export type WebhookClaimOutcome =
  | "claimed"
  | "duplicate"
  | "busy";

/**
 * The ledger's first-seen digest is canonical, so a redelivery whose bytes
 * differ still completes against the digest the ledger already holds.
 */
export interface WebhookClaim {
  outcome: WebhookClaimOutcome;
  claimDigest: string;
}

export interface RevenueCatEntitlementStore {
  claimEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    now: Date
  ): Promise<WebhookClaim>;
  completeEvent(
    event: RevenueCatWebhookEvent,
    claimDigest: string,
    projections: AppAccessProjection[],
    analyticsEvents: LifecycleAnalyticsEvent[],
    now: Date
  ): Promise<void>;
  failEvent(
    eventId: string,
    claimDigest: string,
    errorCode: string,
    now: Date
  ): Promise<void>;
  writeProjection(projection: AppAccessProjection): Promise<boolean>;
}

export interface RevenueCatSubscriberClient {
  fetchSubscriber(appUserId: string): Promise<RevenueCatSubscriberResponse>;
}

export interface FirebaseUserVerifier {
  isFirebaseUser(uid: string): Promise<boolean>;
}

export interface RevenueCatWebhookDependencies {
  store: RevenueCatEntitlementStore;
  subscriberClient: RevenueCatSubscriberClient;
  userVerifier: FirebaseUserVerifier;
  config: RevenueCatServerConfig;
  analyticsEnvironment: RevenueCatAnalyticsEnvironment;
  now: () => Date;
}

export interface RevenueCatReconciliationDependencies {
  store: Pick<RevenueCatEntitlementStore, "writeProjection">;
  subscriberClient: RevenueCatSubscriberClient;
  userVerifier: FirebaseUserVerifier;
  config: RevenueCatServerConfig;
  now: () => Date;
}

export type RevenueCatProcessingOutcome =
  | "processed"
  | "duplicate"
  | "busy";
