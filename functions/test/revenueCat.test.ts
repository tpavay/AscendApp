import assert from "node:assert/strict";
import {createHmac} from "node:crypto";
import test from "node:test";
import {
  authenticateRevenueCatWebhook,
} from "../src/revenueCat/authentication";
import {parseRevenueCatServerConfig} from "../src/revenueCat/config";
import {
  parseRevenueCatWebhook,
  RevenueCatWebhookValidationError,
} from "../src/revenueCat/event";
import {
  processRevenueCatWebhookEvent,
  shouldReplaceProjection,
} from "../src/revenueCat/processor";
import {buildAppAccessProjection} from "../src/revenueCat/subscriber";
import type {
  AppAccessProjection,
  FirebaseUserVerifier,
  RevenueCatEntitlementStore,
  RevenueCatServerConfig,
  RevenueCatSubscriberClient,
  RevenueCatSubscriberResponse,
  RevenueCatWebhookEvent,
  WebhookClaimOutcome,
} from "../src/revenueCat/types";

const NOW = new Date("2026-08-05T12:00:00.000Z");
const NOW_MS = NOW.getTime();
const AUTHORIZATION = "Bearer test-authorization-secret-1234567890";
const SIGNING_SECRET = "test-signing-secret-12345678901234567890";
const CONFIG: RevenueCatServerConfig = {
  apiKey: "test-api-key-123456789012345678901234",
  webhookAuthorization: AUTHORIZATION,
  webhookSigningSecret: SIGNING_SECRET,
  appId: "app123",
  entitlementId: "app_access",
  allowedProductIds: ["ascend_yearly", "ascend_monthly"],
};

test("webhook authentication requires authorization and a current HMAC", () => {
  const body = Buffer.from("{\"event\":{}}", "utf8");
  const timestamp = Math.floor(NOW_MS / 1000);
  const signature = signedHeader(body, timestamp);

  assert.equal(authenticateRevenueCatWebhook(
    AUTHORIZATION,
    signature,
    body,
    AUTHORIZATION,
    SIGNING_SECRET,
    NOW
  ), "authenticated");
  assert.equal(authenticateRevenueCatWebhook(
    "Bearer wrong-authorization-secret-1234567890",
    signature,
    body,
    AUTHORIZATION,
    SIGNING_SECRET,
    NOW
  ), "invalid_authorization");
  assert.equal(authenticateRevenueCatWebhook(
    AUTHORIZATION,
    signature,
    Buffer.from("tampered", "utf8"),
    AUTHORIZATION,
    SIGNING_SECRET,
    NOW
  ), "invalid_signature");
  assert.equal(authenticateRevenueCatWebhook(
    AUTHORIZATION,
    signedHeader(body, timestamp - 301),
    body,
    AUTHORIZATION,
    SIGNING_SECRET,
    NOW
  ), "stale_signature");
});

test("server config requires strong secrets and environment product ids", () => {
  const parsed = parseRevenueCatServerConfig(JSON.stringify(CONFIG));
  assert.deepEqual(parsed, CONFIG);

  assert.throws(() => parseRevenueCatServerConfig(JSON.stringify({
    ...CONFIG,
    webhookSigningSecret: "short",
  })));
  assert.throws(() => parseRevenueCatServerConfig(JSON.stringify({
    ...CONFIG,
    allowedProductIds: [],
  })));
});

test("malformed and cross-app webhook envelopes are rejected", () => {
  assert.throws(
    () => parseRevenueCatWebhook(Buffer.from("not-json"), CONFIG.appId),
    RevenueCatWebhookValidationError
  );
  assert.throws(
    () => parseRevenueCatWebhook(eventBody({app_id: "wrong-app"}), CONFIG.appId),
    (error: unknown) => error instanceof RevenueCatWebhookValidationError &&
      error.code === "unexpected_app_id"
  );
});

test("authenticated app-less events are safe but cross-app events are not", () => {
  const promotion = parseRevenueCatWebhook(eventBody({
    app_id: undefined,
    store: "PROMOTIONAL",
  }), CONFIG.appId);
  assert.equal(promotion.event.appId, CONFIG.appId);

  const experiment = parseRevenueCatWebhook(eventBody({
    app_id: undefined,
    type: "EXPERIMENT_ENROLLMENT",
  }), CONFIG.appId);
  assert.equal(experiment.event.appId, CONFIG.appId);
});

test("normal and transfer events collect every Firebase identity once", () => {
  const normal = parseRevenueCatWebhook(eventBody({
    app_user_id: "firebase-user-1",
    original_app_user_id: "firebase-user-1",
    aliases: ["$RCAnonymousID:ignored", "firebase-user-2"],
  }), CONFIG.appId);
  assert.deepEqual(normal.event.appUserIds, [
    "firebase-user-1",
    "firebase-user-2",
  ]);

  const transfer = parseRevenueCatWebhook(eventBody({
    type: "TRANSFER",
    app_user_id: undefined,
    transferred_from: ["firebase-user-1"],
    transferred_to: ["firebase-user-3"],
  }), CONFIG.appId);
  assert.deepEqual(transfer.event.appUserIds, [
    "firebase-user-1",
    "firebase-user-3",
  ]);
});

test("fresh subscriber truth grants active access and carries grace expiry", () => {
  const projection = buildAppAccessProjection(
    "firebase-user-1",
    subscriberResponse({
      productId: "ascend_yearly",
      expiresDate: "2026-08-04T12:00:00.000Z",
      gracePeriodExpiresDate: "2026-08-12T12:00:00.000Z",
    }),
    CONFIG,
    webhookEvent(),
    NOW
  );

  assert.equal(projection.isActive, true);
  assert.equal(projection.productId, "ascend_yearly");
  assert.equal(
    projection.accessUntil.toISOString(),
    "2026-08-12T12:00:00.000Z"
  );
});

test("expired, refunded, and other-environment products do not grant access", () => {
  const expired = buildAppAccessProjection(
    "firebase-user-1",
    subscriberResponse({
      productId: "ascend_yearly",
      expiresDate: "2026-08-04T12:00:00.000Z",
    }),
    CONFIG,
    webhookEvent(),
    NOW
  );
  const otherEnvironment = buildAppAccessProjection(
    "firebase-user-1",
    subscriberResponse({
      productId: "ascend_staging_yearly",
      expiresDate: "2027-08-05T12:00:00.000Z",
    }),
    CONFIG,
    webhookEvent(),
    NOW
  );
  const refunded = buildAppAccessProjection(
    "firebase-user-1",
    {
      requestDateMs: NOW_MS,
      subscriber: {entitlements: {}, subscriptions: {}},
    },
    CONFIG,
    webhookEvent({type: "CANCELLATION"}),
    NOW
  );

  assert.equal(expired.isActive, false);
  assert.equal(expired.accessUntil.getTime(), 0);
  assert.equal(refunded.isActive, false);
  assert.equal(otherEnvironment.isActive, false);
});

test("an unrelated active product cannot activate a different entitlement", () => {
  const mixedProjectResponse: RevenueCatSubscriberResponse = {
    requestDateMs: NOW_MS,
    subscriber: {
      entitlements: {
        app_access: {
          expiresDate: "2027-08-05T12:00:00.000Z",
          gracePeriodExpiresDate: null,
          productIdentifier: "ascend_staging_yearly",
        },
      },
      subscriptions: {
        ascend_yearly: {
          expiresDate: "2027-08-05T12:00:00.000Z",
          gracePeriodExpiresDate: null,
        },
      },
    },
  };

  const projection = buildAppAccessProjection(
    "firebase-user-1",
    mixedProjectResponse,
    CONFIG,
    webhookEvent(),
    NOW
  );

  assert.equal(projection.isActive, false);
  assert.equal(projection.productId, null);
});

test("a duplicate event is idempotent and re-fetches RevenueCat only once", async () => {
  const store = new InMemoryEntitlementStore();
  const subscriberClient = new CountingSubscriberClient(
    subscriberResponse({productId: "ascend_yearly"})
  );
  const dependencies = {
    store,
    subscriberClient,
    userVerifier: new StubUserVerifier(),
    config: CONFIG,
    now: () => NOW,
  };
  const event = webhookEvent();

  assert.equal(await processRevenueCatWebhookEvent(
    event,
    "same-payload-sha256",
    dependencies
  ), "processed");
  assert.equal(await processRevenueCatWebhookEvent(
    event,
    "same-payload-sha256",
    dependencies
  ), "duplicate");
  assert.equal(subscriberClient.fetchCount, 1);
  assert.equal(store.projections.size, 1);
});

test("failed reconciliation is retry-safe", async () => {
  const store = new InMemoryEntitlementStore();
  const subscriberClient = new CountingSubscriberClient(
    subscriberResponse({productId: "ascend_yearly"})
  );
  subscriberClient.failNext = true;
  const dependencies = {
    store,
    subscriberClient,
    userVerifier: new StubUserVerifier(),
    config: CONFIG,
    now: () => NOW,
  };

  await assert.rejects(processRevenueCatWebhookEvent(
    webhookEvent(),
    "retry-payload-sha256",
    dependencies
  ));
  assert.equal(await processRevenueCatWebhookEvent(
    webhookEvent(),
    "retry-payload-sha256",
    dependencies
  ), "processed");
  assert.equal(subscriberClient.fetchCount, 2);
  assert.equal(store.projections.size, 1);
});

test("out-of-order delivery cannot replace newer subscriber truth", async () => {
  const store = new InMemoryEntitlementStore();
  const subscriberClient = new CountingSubscriberClient(
    subscriberResponse({
      requestDateMs: NOW_MS + 2_000,
      productId: "ascend_yearly",
      expiresDate: "2027-08-05T12:00:00.000Z",
    })
  );
  const dependencies = {
    store,
    subscriberClient,
    userVerifier: new StubUserVerifier(),
    config: CONFIG,
    now: () => NOW,
  };

  await processRevenueCatWebhookEvent(
    webhookEvent({id: "newer-event"}),
    "newer-payload",
    dependencies
  );
  subscriberClient.response = subscriberResponse({
    requestDateMs: NOW_MS - 2_000,
    productId: "ascend_yearly",
    expiresDate: "2026-08-06T12:00:00.000Z",
  });
  await processRevenueCatWebhookEvent(
    webhookEvent({id: "older-event"}),
    "older-payload",
    dependencies
  );

  const stored = store.projections.get("firebase-user-1");
  assert.equal(stored?.sourceEventId, "newer-event");
  assert.equal(stored?.revenueCatRequestDateMs, NOW_MS + 2_000);
});

function signedHeader(body: Buffer, timestamp: number): string {
  const signature = createHmac("sha256", SIGNING_SECRET)
    .update(`${timestamp}.`, "utf8")
    .update(body)
    .digest("hex");
  return `t=${timestamp},v1=${signature}`;
}

function eventBody(overrides: Record<string, unknown> = {}): Buffer {
  return Buffer.from(JSON.stringify({
    api_version: "1.0",
    event: {
      id: "event-123",
      type: "RENEWAL",
      app_id: CONFIG.appId,
      event_timestamp_ms: NOW_MS,
      app_user_id: "firebase-user-1",
      ...overrides,
    },
  }), "utf8");
}

function webhookEvent(
  overrides: Partial<RevenueCatWebhookEvent> = {}
): RevenueCatWebhookEvent {
  return {
    id: "event-123",
    type: "RENEWAL",
    appId: CONFIG.appId,
    eventTimestampMs: NOW_MS,
    appUserIds: ["firebase-user-1"],
    ...overrides,
  };
}

function subscriberResponse(options: {
  requestDateMs?: number;
  productId: string;
  expiresDate?: string | null;
  gracePeriodExpiresDate?: string | null;
}): RevenueCatSubscriberResponse {
  const expiresDate = options.expiresDate === undefined ?
    "2027-08-05T12:00:00.000Z" : options.expiresDate;
  const gracePeriodExpiresDate = options.gracePeriodExpiresDate ?? null;
  return {
    requestDateMs: options.requestDateMs ?? NOW_MS,
    subscriber: {
      entitlements: {
        app_access: {
          expiresDate,
          gracePeriodExpiresDate,
          productIdentifier: options.productId,
        },
      },
      subscriptions: {
        [options.productId]: {expiresDate, gracePeriodExpiresDate},
      },
    },
  };
}

class StubUserVerifier implements FirebaseUserVerifier {
  async isFirebaseUser(): Promise<boolean> {
    return true;
  }
}

class CountingSubscriberClient implements RevenueCatSubscriberClient {
  fetchCount = 0;
  failNext = false;

  constructor(public response: RevenueCatSubscriberResponse) {}

  async fetchSubscriber(): Promise<RevenueCatSubscriberResponse> {
    this.fetchCount += 1;
    if (this.failNext) {
      this.failNext = false;
      throw new Error("temporary subscriber failure");
    }
    return this.response;
  }
}

class InMemoryEntitlementStore implements RevenueCatEntitlementStore {
  readonly projections = new Map<string, AppAccessProjection>();
  private readonly events = new Map<string, {
    payloadSha256: string;
    status: "processing" | "completed" | "failed";
  }>();

  async claimEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string
  ): Promise<WebhookClaimOutcome> {
    const existing = this.events.get(event.id);
    if (!existing) {
      this.events.set(event.id, {payloadSha256, status: "processing"});
      return "claimed";
    }
    if (existing.payloadSha256 !== payloadSha256) {
      return "conflict";
    }
    if (existing.status === "completed") {
      return "duplicate";
    }
    existing.status = "processing";
    return "claimed";
  }

  async completeEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    projections: AppAccessProjection[]
  ): Promise<void> {
    const storedEvent = this.events.get(event.id);
    assert.equal(storedEvent?.payloadSha256, payloadSha256);
    for (const projection of projections) {
      const existing = this.projections.get(projection.uid);
      if (shouldReplaceProjection(existing, projection)) {
        this.projections.set(projection.uid, projection);
      }
    }
    if (storedEvent) {
      storedEvent.status = "completed";
    }
  }

  async failEvent(
    eventId: string,
    payloadSha256: string
  ): Promise<void> {
    const event = this.events.get(eventId);
    assert.equal(event?.payloadSha256, payloadSha256);
    if (event) {
      event.status = "failed";
    }
  }
}
