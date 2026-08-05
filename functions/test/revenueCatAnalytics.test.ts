import assert from "node:assert/strict";
import test from "node:test";
import {
  analyticsEnvironmentForFirebaseProject,
} from "../src/revenueCat/analyticsEnvironment";
import {
  buildLifecycleAnalyticsEvent,
} from "../src/revenueCat/analyticsEvent";
import {
  processAnalyticsOutbox,
} from "../src/revenueCat/analyticsOutboxProcessor";
import {
  MixpanelLifecycleAnalyticsClient,
  MixpanelDeliveryError,
} from "../src/revenueCat/analyticsMixpanelClient";
import {
  parseMixpanelServerConfig,
} from "../src/revenueCat/analyticsConfig";
import type {
  AnalyticsOutboxClaim,
  AnalyticsOutboxStore,
  LifecycleAnalyticsClient,
  LifecycleAnalyticsEvent,
  RevenueCatAnalyticsEnvironment,
} from "../src/revenueCat/analyticsTypes";
import type {
  AppAccessProjection,
  RevenueCatServerConfig,
  RevenueCatWebhookEvent,
} from "../src/revenueCat/types";

const NOW = new Date("2026-08-05T12:00:00.000Z");
const CONFIG: RevenueCatServerConfig = {
  apiKey: "test-api-key-123456789012345678901234",
  webhookAuthorization: "Bearer test-authorization-secret-1234567890",
  webhookSigningSecret: "test-signing-secret-12345678901234567890",
  appId: "app123",
  entitlementId: "app_access",
  allowedProductIds: ["ascend_yearly", "ascend_monthly"],
};
const ENVIRONMENT: RevenueCatAnalyticsEnvironment = {
  appEnvironment: "production",
  buildConfig: "server",
  appVersion: "cloud_functions",
  buildNumber: "revenuecat-webhook-00001",
  firebaseProjectId: "ascend-prod-9c8f2",
  mixpanelProjectId: "4051100",
};

test("every server lifecycle transition has its own event name", () => {
  const cases: Array<{
    event: Partial<RevenueCatWebhookEvent>;
    expectedName: string;
  }> = [
    {
      event: {type: "INITIAL_PURCHASE", periodType: "normal"},
      expectedName: "subscription_started",
    },
    {
      event: {type: "INITIAL_PURCHASE", periodType: "trial"},
      expectedName: "subscription_trial_started",
    },
    {
      event: {type: "RENEWAL", isTrialConversion: true},
      expectedName: "subscription_trial_converted",
    },
    {
      event: {type: "RENEWAL"},
      expectedName: "subscription_renewed",
    },
    {
      event: {type: "CANCELLATION", lifecycleReason: "unsubscribe"},
      expectedName: "subscription_cancelled",
    },
    {
      event: {type: "UNCANCELLATION"},
      expectedName: "subscription_uncancelled",
    },
    {
      event: {type: "BILLING_ISSUE"},
      expectedName: "subscription_billing_issue",
    },
    {
      event: {type: "EXPIRATION"},
      expectedName: "subscription_expired",
    },
    {
      event: {
        type: "CANCELLATION",
        lifecycleReason: "customer_support",
      },
      expectedName: "subscription_refunded",
    },
    {
      event: {
        type: "PRODUCT_CHANGE",
        newProductId: "ascend_monthly",
      },
      expectedName: "subscription_product_changed",
    },
  ];

  for (const entry of cases) {
    const analyticsEvent = buildLifecycleAnalyticsEvent(
      webhookEvent(entry.event),
      projection({
        isActive: entry.expectedName !== "subscription_refunded",
      }),
      CONFIG,
      ENVIRONMENT
    );
    assert.equal(analyticsEvent?.eventName, entry.expectedName);
  }
});

test("cancellation remains active and is never relabeled as expiration", () => {
  const analyticsEvent = buildLifecycleAnalyticsEvent(
    webhookEvent({
      type: "CANCELLATION",
      expirationAtMs: Date.parse("2026-09-05T12:00:00.000Z"),
      lifecycleReason: "unsubscribe",
    }),
    projection({isActive: true}),
    CONFIG,
    ENVIRONMENT
  );

  assert.equal(analyticsEvent?.eventName, "subscription_cancelled");
  assert.equal(analyticsEvent?.entitlementActive, true);
  assert.equal(
    analyticsEvent?.effectiveExpirationAtMs,
    Date.parse("2027-08-05T12:00:00.000Z")
  );
});

test("support cancellation is a refund only after access is removed", () => {
  const event = webhookEvent({
    type: "CANCELLATION",
    lifecycleReason: "customer_support",
  });

  assert.equal(buildLifecycleAnalyticsEvent(
    event,
    projection({isActive: true}),
    CONFIG,
    ENVIRONMENT
  )?.eventName, "subscription_cancelled");
  assert.equal(buildLifecycleAnalyticsEvent(
    event,
    projection({isActive: false}),
    CONFIG,
    ENVIRONMENT
  )?.eventName, "subscription_refunded");
});

test("billing-error cancellation is not double-counted beside billing issue", () => {
  assert.equal(buildLifecycleAnalyticsEvent(
    webhookEvent({type: "CANCELLATION", lifecycleReason: "billing_error"}),
    projection(),
    CONFIG,
    ENVIRONMENT
  ), null);
  assert.equal(buildLifecycleAnalyticsEvent(
    webhookEvent({type: "BILLING_ISSUE"}),
    projection(),
    CONFIG,
    ENVIRONMENT
  )?.eventName, "subscription_billing_issue");
});

test("outbox identity is stable and carries the complete server envelope", () => {
  const first = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  const replay = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );

  assert.deepEqual(replay, first);
  assert.match(first?.insertId ?? "", /^[a-f0-9]{32}$/);
  assert.equal(first?.source, "revenuecat_webhook");
  assert.equal(first?.eventVersion, 1);
  assert.equal(first?.entitlementId, "app_access");
  assert.equal(first?.productId, "ascend_yearly");
  assert.equal(first?.store, "app_store");
  assert.equal(first?.periodType, "normal");
  assert.equal(first?.appEnvironment, "production");
  assert.equal(first?.buildConfig, "server");
  assert.equal(first?.appVersion, "cloud_functions");
  assert.equal(first?.buildNumber, "revenuecat-webhook-00001");
});

test("Firebase project selects exactly one matching Mixpanel project", () => {
  assert.equal(
    analyticsEnvironmentForFirebaseProject("ascend-f2e4f", "revision-1")
      .mixpanelProjectId,
    "4032860"
  );
  assert.equal(
    analyticsEnvironmentForFirebaseProject(
      "ascend-staging-fa7d5",
      "revision-2"
    ).mixpanelProjectId,
    "4051102"
  );
  assert.equal(
    analyticsEnvironmentForFirebaseProject("ascend-prod-9c8f2", "revision-3")
      .mixpanelProjectId,
    "4051100"
  );
  assert.throws(
    () => analyticsEnvironmentForFirebaseProject("unexpected-project", "r")
  );
});

test("Mixpanel config accepts only a bounded server credential", () => {
  const config = parseMixpanelServerConfig(JSON.stringify({
    serviceAccountUsername: "production-writer.mp-service-account",
    serviceAccountPassword: "test-password-123456789012345678901234",
  }));
  assert.equal(
    config.serviceAccountUsername,
    "production-writer.mp-service-account"
  );
  assert.throws(() => parseMixpanelServerConfig(JSON.stringify({
    serviceAccountUsername: "production-writer.mp-service-account",
    serviceAccountPassword: "short",
  })));
});

test("Mixpanel import is strict, environment-bound, and retry-safe", async () => {
  let requestedUrl = "";
  let requestBody = "";
  const fetchImplementation: typeof fetch = async (input, init) => {
    requestedUrl = input.toString();
    requestBody = String(init?.body ?? "");
    assert.match(String(new Headers(init?.headers).get("authorization")),
      /^Basic /);
    return new Response(JSON.stringify({
      code: 200,
      num_records_imported: 1,
      status: "OK",
    }), {status: 200});
  };
  const event = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  assert.ok(event);
  const client = new MixpanelLifecycleAnalyticsClient({
    serviceAccountUsername: "production-writer.mp-service-account",
    serviceAccountPassword: "test-password-123456789012345678901234",
  }, ENVIRONMENT, fetchImplementation);

  await client.send(event);

  const parsedUrl = new URL(requestedUrl);
  assert.equal(parsedUrl.searchParams.get("strict"), "1");
  assert.equal(parsedUrl.searchParams.get("project_id"), "4051100");
  const payload = JSON.parse(requestBody) as Array<{
    event: string;
    properties: Record<string, unknown>;
  }>;
  assert.equal(payload[0].event, "subscription_renewed");
  assert.equal(payload[0].properties.$insert_id, event.insertId);
  assert.equal(payload[0].properties.app_environment, "production");
  assert.equal(payload[0].properties.ip, 0);
  assert.equal(requestBody.includes("serviceAccount"), false);
  assert.equal(requestBody.includes("test-password"), false);
});

test("Mixpanel transient status is retryable but validation is terminal", async () => {
  const event = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  assert.ok(event);
  const config = {
    serviceAccountUsername: "production-writer.mp-service-account",
    serviceAccountPassword: "test-password-123456789012345678901234",
  };
  const failingClient = (status: number) =>
    new MixpanelLifecycleAnalyticsClient(
      config,
      ENVIRONMENT,
      async () => new Response(null, {status})
    );

  await assert.rejects(failingClient(503).send(event),
    (error: unknown) => error instanceof MixpanelDeliveryError &&
      error.retryable);
  await assert.rejects(failingClient(400).send(event),
    (error: unknown) => error instanceof MixpanelDeliveryError &&
      !error.retryable);
});

test("a transient analytics failure requeues and later delivers", async () => {
  const event = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  assert.ok(event);
  const store = new InMemoryAnalyticsOutboxStore(event);
  const client = new FailOnceAnalyticsClient();

  const first = await processAnalyticsOutbox({
    store,
    client,
    environment: ENVIRONMENT,
    now: () => NOW,
  });
  assert.deepEqual(first, {
    claimedCount: 1,
    deliveredCount: 0,
    failedCount: 0,
    reclaimedCount: 0,
    retriedCount: 1,
  });
  assert.equal(store.status, "queued");
  assert.equal(store.attemptCount, 1);

  store.readyAt = new Date(NOW.getTime());
  const second = await processAnalyticsOutbox({
    store,
    client,
    environment: ENVIRONMENT,
    now: () => new Date(NOW.getTime() + 60_000),
  });
  assert.equal(second.deliveredCount, 1);
  assert.equal(store.status, "delivered");
  assert.equal(store.attemptCount, 2);
  assert.equal(client.attemptCount, 2);
  assert.deepEqual(client.insertIds, [event.insertId, event.insertId]);
});

function webhookEvent(
  overrides: Partial<RevenueCatWebhookEvent> = {}
): RevenueCatWebhookEvent {
  return {
    id: "event-123",
    type: "RENEWAL",
    appId: CONFIG.appId,
    eventTimestampMs: NOW.getTime(),
    appUserIds: ["firebase-user-1"],
    identityOverflowCount: 0,
    productId: "ascend_yearly",
    newProductId: null,
    store: "app_store",
    periodType: "normal",
    expirationAtMs: Date.parse("2027-08-05T12:00:00.000Z"),
    gracePeriodExpirationAtMs: null,
    isTrialConversion: false,
    lifecycleReason: null,
    ...overrides,
  };
}

function projection(
  overrides: Partial<AppAccessProjection> = {}
): AppAccessProjection {
  const expiresAt = new Date("2027-08-05T12:00:00.000Z");
  return {
    schemaVersion: 1,
    uid: "firebase-user-1",
    entitlementId: "app_access",
    isActive: true,
    productId: "ascend_yearly",
    expiresAt,
    accessUntil: expiresAt,
    revenueCatAppId: CONFIG.appId,
    revenueCatRequestDateMs: NOW.getTime(),
    sourceEventId: "event-123",
    sourceEventType: "RENEWAL",
    verifiedAt: NOW,
    ...overrides,
  };
}

class InMemoryAnalyticsOutboxStore implements AnalyticsOutboxStore {
  status: "queued" | "processing" | "delivered" | "failed" = "queued";
  attemptCount = 0;
  readyAt = NOW;

  constructor(private readonly event: LifecycleAnalyticsEvent) {}

  async reclaimStale(): Promise<number> {
    return 0;
  }

  async claimDue(now: Date): Promise<AnalyticsOutboxClaim[]> {
    if (this.status !== "queued" || this.readyAt > now) {
      return [];
    }
    this.status = "processing";
    this.attemptCount += 1;
    return [{
      claimId: `claim-${this.attemptCount}`,
      outboxId: "outbox-1",
      attemptCount: this.attemptCount,
      event: this.event,
    }];
  }

  async markDelivered(): Promise<void> {
    this.status = "delivered";
  }

  async requeue(
    _claim: AnalyticsOutboxClaim,
    readyAt: Date
  ): Promise<void> {
    this.status = "queued";
    this.readyAt = readyAt;
  }

  async markFailed(): Promise<void> {
    this.status = "failed";
  }
}

class FailOnceAnalyticsClient implements LifecycleAnalyticsClient {
  attemptCount = 0;
  readonly insertIds: string[] = [];

  async send(event: LifecycleAnalyticsEvent): Promise<void> {
    this.attemptCount += 1;
    this.insertIds.push(event.insertId);
    if (this.attemptCount === 1) {
      throw new MixpanelDeliveryError("rate_limited", true);
    }
  }
}
