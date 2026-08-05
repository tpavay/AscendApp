import assert from "node:assert/strict";
import test from "node:test";
import {
  analyticsEnvironmentForFirebaseProject,
  optionalAnalyticsEnvironment,
} from "../src/revenueCat/analyticsEnvironment";
import {
  buildLifecycleAnalyticsEvent,
} from "../src/revenueCat/analyticsEvent";
import {
  processAnalyticsOutbox,
  retryDelayMs,
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
        type: "EXPIRATION",
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

test("a refund keeps its cancellation and its access removal distinct", () => {
  const cancellation = buildLifecycleAnalyticsEvent(
    webhookEvent({
      id: "event-refund-cancellation",
      type: "CANCELLATION",
      lifecycleReason: "customer_support",
    }),
    projection({isActive: true}),
    CONFIG,
    ENVIRONMENT
  );
  const expiration = buildLifecycleAnalyticsEvent(
    webhookEvent({
      id: "event-refund-expiration",
      type: "EXPIRATION",
      lifecycleReason: "customer_support",
    }),
    projection({isActive: false}),
    CONFIG,
    ENVIRONMENT
  );

  assert.equal(cancellation?.eventName, "subscription_cancelled");
  assert.equal(cancellation?.entitlementActive, true);
  assert.equal(cancellation?.refundAttributed, true);
  assert.equal(expiration?.eventName, "subscription_refunded");
  assert.equal(expiration?.entitlementActive, false);
  assert.equal(expiration?.refundAttributed, true);
  assert.notEqual(cancellation?.insertId, expiration?.insertId);
});

test("each refund webhook stays exactly one event across redeliveries", () => {
  const cancellation = webhookEvent({
    id: "event-refund-cancellation",
    type: "CANCELLATION",
    lifecycleReason: "customer_support",
  });
  const expiration = webhookEvent({
    id: "event-refund-expiration",
    type: "EXPIRATION",
    lifecycleReason: "customer_support",
  });
  const build = (
    event: RevenueCatWebhookEvent,
    isActive: boolean
  ) => buildLifecycleAnalyticsEvent(
    event,
    projection({isActive}),
    CONFIG,
    ENVIRONMENT
  );

  assert.deepEqual(
    build(cancellation, true),
    build(cancellation, true)
  );
  assert.deepEqual(
    build(expiration, false),
    build(expiration, false)
  );
});

test("a support cancellation that already removed access still cancels", () => {
  const analyticsEvent = buildLifecycleAnalyticsEvent(
    webhookEvent({type: "CANCELLATION", lifecycleReason: "customer_support"}),
    projection({isActive: false}),
    CONFIG,
    ENVIRONMENT
  );

  assert.equal(analyticsEvent?.eventName, "subscription_cancelled");
  assert.equal(analyticsEvent?.refundAttributed, true);
});

test("an ordinary expiration is neither a refund nor refund-attributed", () => {
  const analyticsEvent = buildLifecycleAnalyticsEvent(
    webhookEvent({type: "EXPIRATION", lifecycleReason: "unsubscribe"}),
    projection({isActive: false}),
    CONFIG,
    ENVIRONMENT
  );

  assert.equal(analyticsEvent?.eventName, "subscription_expired");
  assert.equal(analyticsEvent?.refundAttributed, false);
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

test("an unresolvable analytics destination degrades instead of throwing", async () => {
  const errors = await capturedErrors(async () => {
    assert.equal(optionalAnalyticsEnvironment(undefined, "revision-1"), null);
    assert.equal(
      optionalAnalyticsEnvironment("unexpected-project", "revision-1"),
      null
    );
  });

  assert.equal(errors.length, 2);
  assert.equal(
    optionalAnalyticsEnvironment("ascend-prod-9c8f2", "revision-1")
      ?.mixpanelProjectId,
    "4051100"
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
  assert.equal(payload[0].properties.refund_attributed, false);
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
    deferredCount: 0,
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

test("a run past its budget requeues claims instead of stranding them", async () => {
  const event = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  assert.ok(event);
  const store = new MultiRowAnalyticsOutboxStore(event, 3);
  store.rows[2].lastErrorCode = "rate_limited";
  let clockMs = NOW.getTime();
  const client: LifecycleAnalyticsClient = {
    async send(): Promise<void> {
      clockMs += 40_000;
    },
  };

  const summary = await processAnalyticsOutbox({
    store,
    client,
    environment: ENVIRONMENT,
    now: () => new Date(clockMs),
    runBudgetMs: 75_000,
  });

  assert.equal(summary.claimedCount, 3);
  assert.equal(summary.deliveredCount, 2);
  assert.equal(summary.deferredCount, 1);
  assert.deepEqual(store.statuses(), ["delivered", "delivered", "queued"]);
  assert.equal(store.rows[2].readyAt.getTime(), clockMs);
});

test("a deferred claim is not charged a delivery attempt or a false error", async () => {
  const event = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  assert.ok(event);
  const store = new MultiRowAnalyticsOutboxStore(event, 1);
  const client: LifecycleAnalyticsClient = {
    async send(): Promise<void> {
      assert.fail("a deferred run must not deliver");
    },
  };

  const summary = await processAnalyticsOutbox({
    store,
    client,
    environment: ENVIRONMENT,
    now: () => NOW,
    runBudgetMs: 0,
  });

  assert.equal(summary.deferredCount, 1);
  assert.equal(summary.deliveredCount, 0);
  assert.equal(store.rows[0].status, "queued");
  assert.equal(store.rows[0].attemptCount, 0);
  assert.equal(store.rows[0].lastErrorCode, null);
  assert.equal(retryDelayMs(store.rows[0].attemptCount + 1), 60_000);
});

test("a delivery that never converges is reported while it keeps retrying", async () => {
  const event = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  assert.ok(event);
  const store = new MultiRowAnalyticsOutboxStore(event, 1);
  store.rows[0].attemptCount = 11;
  const client: LifecycleAnalyticsClient = {
    async send(): Promise<void> {
      throw new MixpanelDeliveryError("http_401", true);
    },
  };

  const errors = await capturedErrors(async () => {
    const summary = await processAnalyticsOutbox({
      store,
      client,
      environment: ENVIRONMENT,
      now: () => NOW,
    });
    assert.equal(summary.retriedCount, 1);
  });

  assert.equal(store.rows[0].status, "queued");
  assert.equal(errors.length, 1);
  assert.deepEqual(errors[0][1], {
    outboxId: "outbox-1",
    eventName: "subscription_renewed",
    attemptCount: 12,
    lastErrorCode: "http_401",
  });
  assert.equal(JSON.stringify(errors).includes(event.distinctId), false);
});

test("a permanently discarded row is reported, not silently dropped", async () => {
  const event = buildLifecycleAnalyticsEvent(
    webhookEvent(),
    projection(),
    CONFIG,
    ENVIRONMENT
  );
  assert.ok(event);
  const store = new MultiRowAnalyticsOutboxStore(event, 1);
  const client: LifecycleAnalyticsClient = {
    async send(): Promise<void> {
      throw new MixpanelDeliveryError("validation_failed", false);
    },
  };

  const errors = await capturedErrors(async () => {
    const summary = await processAnalyticsOutbox({
      store,
      client,
      environment: ENVIRONMENT,
      now: () => NOW,
    });
    assert.equal(summary.failedCount, 1);
  });

  assert.deepEqual(store.statuses(), ["failed"]);
  assert.equal(errors.length, 1);
  assert.deepEqual(errors[0][1], {
    outboxId: "outbox-1",
    eventName: "subscription_renewed",
    attemptCount: 1,
    lastErrorCode: "validation_failed",
  });
  assert.equal(JSON.stringify(errors).includes(event.distinctId), false);
});

async function capturedErrors(
  run: () => Promise<void>
): Promise<unknown[][]> {
  const captured: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    captured.push(args);
  };
  try {
    await run();
  } finally {
    console.error = original;
  }
  return captured;
}

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

  async release(claim: AnalyticsOutboxClaim, now: Date): Promise<void> {
    this.status = "queued";
    this.readyAt = now;
    this.attemptCount = Math.max(claim.attemptCount - 1, 0);
  }

  async markFailed(): Promise<void> {
    this.status = "failed";
  }
}

interface AnalyticsOutboxRow {
  outboxId: string;
  status: "queued" | "processing" | "delivered" | "failed";
  attemptCount: number;
  readyAt: Date;
  lastErrorCode: string | null;
}

class MultiRowAnalyticsOutboxStore implements AnalyticsOutboxStore {
  readonly rows: AnalyticsOutboxRow[];

  constructor(
    private readonly event: LifecycleAnalyticsEvent,
    rowCount: number
  ) {
    this.rows = Array.from({length: rowCount}, (_unused, index) => ({
      outboxId: `outbox-${index + 1}`,
      status: "queued" as const,
      attemptCount: 0,
      readyAt: NOW,
      lastErrorCode: null,
    }));
  }

  statuses(): string[] {
    return this.rows.map((row) => row.status);
  }

  async reclaimStale(): Promise<number> {
    return 0;
  }

  async claimDue(now: Date, limit = 25): Promise<AnalyticsOutboxClaim[]> {
    return this.rows
      .filter((row) => row.status === "queued" && row.readyAt <= now)
      .slice(0, limit)
      .map((row) => {
        row.status = "processing";
        row.attemptCount += 1;
        return {
          outboxId: row.outboxId,
          claimId: `claim-${row.outboxId}-${row.attemptCount}`,
          attemptCount: row.attemptCount,
          event: this.event,
        };
      });
  }

  async markDelivered(claim: AnalyticsOutboxClaim): Promise<void> {
    this.row(claim).status = "delivered";
  }

  async requeue(
    claim: AnalyticsOutboxClaim,
    readyAt: Date,
    errorCode: string
  ): Promise<void> {
    const row = this.row(claim);
    row.status = "queued";
    row.readyAt = readyAt;
    row.lastErrorCode = errorCode;
  }

  async release(claim: AnalyticsOutboxClaim, now: Date): Promise<void> {
    const row = this.row(claim);
    row.status = "queued";
    row.readyAt = now;
    row.attemptCount = Math.max(claim.attemptCount - 1, 0);
  }

  async markFailed(
    claim: AnalyticsOutboxClaim,
    errorCode: string
  ): Promise<void> {
    const row = this.row(claim);
    row.status = "failed";
    row.lastErrorCode = errorCode;
  }

  private row(claim: AnalyticsOutboxClaim): AnalyticsOutboxRow {
    const row = this.rows.find(
      (candidate) => candidate.outboxId === claim.outboxId
    );
    assert.ok(row);
    return row;
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
