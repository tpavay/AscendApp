import type {
  AppAccessProjection,
  RevenueCatEntitlement,
  RevenueCatServerConfig,
  RevenueCatSubscriberClient,
  RevenueCatSubscriberResponse,
  RevenueCatSubscription,
  RevenueCatWebhookEvent,
} from "./types";

const REVENUECAT_API_BASE_URL = "https://api.revenuecat.com/v1";
const SUBSCRIBER_FETCH_TIMEOUT_MS = 10_000;
const INACTIVE_ACCESS_UNTIL = new Date(0);
const NON_EXPIRING_ACCESS_UNTIL = new Date("9999-12-31T23:59:59.999Z");

export class HttpRevenueCatSubscriberClient
implements RevenueCatSubscriberClient {
  constructor(
    private readonly apiKey: string,
    private readonly fetchImplementation: typeof fetch = fetch
  ) {}

  async fetchSubscriber(
    appUserId: string
  ): Promise<RevenueCatSubscriberResponse> {
    const url = `${REVENUECAT_API_BASE_URL}/subscribers/` +
      encodeURIComponent(appUserId);
    const response = await this.fetchImplementation(url, {
      headers: {
        "Accept": "application/json",
        "Authorization": `Bearer ${this.apiKey}`,
      },
      method: "GET",
      signal: AbortSignal.timeout(SUBSCRIBER_FETCH_TIMEOUT_MS),
    });

    if (!response.ok) {
      throw new RevenueCatSubscriberFetchError(response.status);
    }

    return parseSubscriberResponse(await response.json());
  }
}

export class RevenueCatSubscriberFetchError extends Error {
  constructor(readonly status: number) {
    super(`RevenueCat subscriber request failed with status ${status}`);
    this.name = "RevenueCatSubscriberFetchError";
  }
}

/**
 * Converts fresh RevenueCat truth into the minimal server-owned rule input.
 * @param {string} uid - Verified Firebase user id
 * @param {RevenueCatSubscriberResponse} response - Current subscriber state
 * @param {RevenueCatServerConfig} config - Environment product contract
 * @param {RevenueCatWebhookEvent} event - Triggering webhook event
 * @param {Date} verifiedAt - Local verification time
 * @return {AppAccessProjection} Server-owned access projection
 */
export function buildAppAccessProjection(
  uid: string,
  response: RevenueCatSubscriberResponse,
  config: RevenueCatServerConfig,
  event: RevenueCatWebhookEvent,
  verifiedAt: Date
): AppAccessProjection {
  const entitlement = response.subscriber.entitlements[config.entitlementId];
  const entitlementProductId = entitlement?.productIdentifier ?? null;
  const entitlementExpiresAt = entitlement ?
    effectiveExpiration(entitlement) : null;
  const isActive = Boolean(
    entitlement &&
    entitlementProductId &&
    config.allowedProductIds.includes(entitlementProductId) &&
    isActiveAt(entitlementExpiresAt, response.requestDateMs)
  );
  const expiresAt = isActive ? entitlementExpiresAt : null;
  return {
    schemaVersion: 1,
    uid,
    entitlementId: config.entitlementId,
    isActive,
    productId: isActive ? entitlementProductId : null,
    expiresAt,
    accessUntil: isActive ?
      expiresAt ?? NON_EXPIRING_ACCESS_UNTIL :
      INACTIVE_ACCESS_UNTIL,
    revenueCatAppId: config.appId,
    revenueCatRequestDateMs: response.requestDateMs,
    sourceEventId: event.id,
    sourceEventType: event.type,
    verifiedAt,
  };
}

function parseSubscriberResponse(value: unknown): RevenueCatSubscriberResponse {
  if (!isRecord(value) ||
    typeof value.request_date_ms !== "number" ||
    !Number.isSafeInteger(value.request_date_ms) ||
    value.request_date_ms <= 0 ||
    !isRecord(value.subscriber) ||
    !isRecord(value.subscriber.entitlements) ||
    !isRecord(value.subscriber.subscriptions)) {
    throw new Error("RevenueCat subscriber response is malformed");
  }

  const entitlements: Record<string, RevenueCatEntitlement> = {};
  for (const [id, entitlement] of
    Object.entries(value.subscriber.entitlements)) {
    if (!isRecord(entitlement)) {
      throw new Error("RevenueCat entitlement response is malformed");
    }
    entitlements[id] = {
      expiresDate: nullableString(entitlement.expires_date),
      gracePeriodExpiresDate:
        nullableString(entitlement.grace_period_expires_date),
      productIdentifier: nullableString(entitlement.product_identifier),
    };
  }

  const subscriptions: Record<string, RevenueCatSubscription> = {};
  for (const [id, subscription] of
    Object.entries(value.subscriber.subscriptions)) {
    if (!isRecord(subscription)) {
      throw new Error("RevenueCat subscription response is malformed");
    }
    subscriptions[id] = {
      expiresDate: nullableString(subscription.expires_date),
      gracePeriodExpiresDate:
        nullableString(subscription.grace_period_expires_date),
    };
  }

  return {
    requestDateMs: value.request_date_ms,
    subscriber: {entitlements, subscriptions},
  };
}

function effectiveExpiration(
  value: RevenueCatSubscription | RevenueCatEntitlement
): Date | null {
  const timestamps = [value.expiresDate, value.gracePeriodExpiresDate]
    .filter((candidate): candidate is string => Boolean(candidate))
    .map((candidate) => new Date(candidate));
  if (timestamps.some((candidate) => Number.isNaN(candidate.getTime()))) {
    throw new Error("RevenueCat subscriber response contains an invalid date");
  }
  return timestamps.reduce<Date | null>(
    (latest, candidate) => !latest || candidate > latest ? candidate : latest,
    null
  );
}

function isActiveAt(expiresAt: Date | null, requestDateMs: number): boolean {
  return expiresAt === null || expiresAt.getTime() > requestDateMs;
}

function nullableString(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== "string") {
    throw new Error("RevenueCat subscriber response field is malformed");
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
