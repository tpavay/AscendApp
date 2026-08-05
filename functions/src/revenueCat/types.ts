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
  | "busy"
  | "conflict";

export interface RevenueCatEntitlementStore {
  claimEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    now: Date
  ): Promise<WebhookClaimOutcome>;
  completeEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    projections: AppAccessProjection[],
    now: Date
  ): Promise<void>;
  failEvent(
    eventId: string,
    payloadSha256: string,
    errorCode: string,
    now: Date
  ): Promise<void>;
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
  now: () => Date;
}

export type RevenueCatProcessingOutcome =
  | "processed"
  | "duplicate"
  | "busy"
  | "conflict";
