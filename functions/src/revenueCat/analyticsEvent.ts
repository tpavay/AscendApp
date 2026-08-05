import {createHash} from "node:crypto";
import type {
  LifecycleAnalyticsEvent,
  LifecycleAnalyticsEventName,
  RevenueCatAnalyticsEnvironment,
} from "./analyticsTypes";
import type {
  AppAccessProjection,
  RevenueCatServerConfig,
  RevenueCatWebhookEvent,
} from "./types";

/**
 * Normalizes one authenticated RevenueCat lifecycle transition for Mixpanel.
 * @param {RevenueCatWebhookEvent} event - Bounded webhook event
 * @param {AppAccessProjection} projection - Fresh subscriber truth
 * @param {RevenueCatServerConfig} config - Environment entitlement contract
 * @param {RevenueCatAnalyticsEnvironment} environment - Server envelope
 * @return {LifecycleAnalyticsEvent | null} Reportable event, if any
 */
export function buildLifecycleAnalyticsEvent(
  event: RevenueCatWebhookEvent,
  projection: AppAccessProjection,
  config: RevenueCatServerConfig,
  environment: RevenueCatAnalyticsEnvironment
): LifecycleAnalyticsEvent | null {
  const eventName = lifecycleEventName(event, projection);
  if (!eventName || config.entitlementId !== "app_access") {
    return null;
  }

  const productId = event.type === "PRODUCT_CHANGE" ?
    event.newProductId ?? projection.productId :
    event.productId ?? projection.productId;
  if (!productId || !config.allowedProductIds.includes(productId)) {
    return null;
  }

  const previousProductId = event.type === "PRODUCT_CHANGE" &&
    event.productId &&
    config.allowedProductIds.includes(event.productId) ?
    event.productId : null;
  const insertId = createHash("sha256")
    .update(event.id, "utf8")
    .update("\0", "utf8")
    .update(projection.uid, "utf8")
    .digest("hex")
    .slice(0, 32);

  return {
    schemaVersion: 1,
    eventName,
    eventVersion: 1,
    source: "revenuecat_webhook",
    distinctId: projection.uid,
    insertId,
    eventTimestampMs: event.eventTimestampMs,
    entitlementId: "app_access",
    productId,
    previousProductId,
    store: event.store,
    periodType: event.periodType,
    lifecycleReason: event.lifecycleReason,
    entitlementActive: projection.isActive,
    effectiveExpirationAtMs: effectiveExpirationAtMs(event, projection),
    firebaseProjectId: environment.firebaseProjectId,
    appEnvironment: environment.appEnvironment,
    buildConfig: environment.buildConfig,
    appVersion: environment.appVersion,
    buildNumber: environment.buildNumber,
  };
}

function lifecycleEventName(
  event: RevenueCatWebhookEvent,
  projection: AppAccessProjection
): LifecycleAnalyticsEventName | null {
  switch (event.type) {
  case "INITIAL_PURCHASE":
    return event.periodType === "trial" ?
      "subscription_trial_started" : "subscription_started";
  case "RENEWAL":
    return event.isTrialConversion ?
      "subscription_trial_converted" : "subscription_renewed";
  case "CANCELLATION":
    if (event.lifecycleReason === "billing_error") {
      // RevenueCat emits BILLING_ISSUE for this same transition. Exporting
      // both webhook rows would make one billing failure look like two.
      return null;
    }
    return event.lifecycleReason === "customer_support" &&
      !projection.isActive ?
      "subscription_refunded" : "subscription_cancelled";
  case "UNCANCELLATION":
    return "subscription_uncancelled";
  case "BILLING_ISSUE":
    return "subscription_billing_issue";
  case "EXPIRATION":
    return event.lifecycleReason === "customer_support" ?
      "subscription_refunded" : "subscription_expired";
  case "PRODUCT_CHANGE":
    return "subscription_product_changed";
  default:
    return null;
  }
}

function effectiveExpirationAtMs(
  event: RevenueCatWebhookEvent,
  projection: AppAccessProjection
): number | null {
  return projection.expiresAt?.getTime() ??
    event.gracePeriodExpirationAtMs ??
    event.expirationAtMs;
}
