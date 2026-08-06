import * as admin from "firebase-admin";
import {onRequest} from "firebase-functions/v2/https";
import {
  authenticateRevenueCatWebhook,
} from "./authentication";
import {
  optionalAnalyticsEnvironment,
} from "./analyticsEnvironment";
import {
  getRevenueCatServerConfig,
  revenueCatServerConfig,
} from "./config";
import {
  parseRevenueCatWebhook,
  RevenueCatWebhookValidationError,
} from "./event";
import {AdminFirebaseUserVerifier} from "./firebaseUserVerifier";
import {FirestoreRevenueCatEntitlementStore} from "./firestoreStore";
import {processRevenueCatWebhookEvent} from "./processor";
import {HttpRevenueCatSubscriberClient} from "./subscriber";
import type {RevenueCatAnalyticsEnvironment} from "./analyticsTypes";
import type {
  RevenueCatProcessingOutcome,
  RevenueCatServerConfig,
  RevenueCatWebhookEvent,
} from "./types";

export interface WebhookHttpRequest {
  method: string;
  rawBody?: Buffer;
  get(name: string): string | undefined;
}

export interface WebhookHttpResponse {
  set(field: string, value: string): WebhookHttpResponse;
  status(code: number): WebhookHttpResponse;
  json(body: Record<string, string>): WebhookHttpResponse;
}

export interface RevenueCatWebhookRuntime {
  loadConfig(): RevenueCatServerConfig;
  processEvent(
    event: RevenueCatWebhookEvent,
    payloadSha256: string,
    config: RevenueCatServerConfig,
    analyticsEnvironment: RevenueCatAnalyticsEnvironment | null
  ): Promise<RevenueCatProcessingOutcome>;
  now(): Date;
}

const deployedRuntime: RevenueCatWebhookRuntime = {
  loadConfig: getRevenueCatServerConfig,
  processEvent: (event, payloadSha256, config, analyticsEnvironment) =>
    processRevenueCatWebhookEvent(event, payloadSha256, {
      store: new FirestoreRevenueCatEntitlementStore(admin.firestore()),
      subscriberClient: new HttpRevenueCatSubscriberClient(config.apiKey),
      userVerifier: new AdminFirebaseUserVerifier(),
      config,
      analyticsEnvironment,
      now: () => new Date(),
    }),
  now: () => new Date(),
};

/**
 * Authenticates and processes one RevenueCat webhook request.
 * @param {WebhookHttpRequest} request - HTTP request
 * @param {WebhookHttpResponse} response - HTTP response
 * @param {RevenueCatWebhookRuntime} runtime - Deployment-owned collaborators
 * @return {Promise<void>}
 */
export async function handleRevenueCatWebhook(
  request: WebhookHttpRequest,
  response: WebhookHttpResponse,
  runtime: RevenueCatWebhookRuntime = deployedRuntime
): Promise<void> {
  response.set("Cache-Control", "no-store");
  if (request.method !== "POST") {
    response.set("Allow", "POST");
    response.status(405).json({status: "method_not_allowed"});
    return;
  }

  let config;
  try {
    config = runtime.loadConfig();
  } catch {
    console.error("RevenueCat webhook server configuration is invalid");
    response.status(500).json({status: "server_configuration_error"});
    return;
  }

  const analyticsEnvironment = optionalAnalyticsEnvironment(
    deployedFirebaseProjectId(),
    process.env.K_REVISION ?? "unknown"
  );

  const rawBody = request.rawBody;
  if (!Buffer.isBuffer(rawBody)) {
    response.status(400).json({status: "invalid_request"});
    return;
  }

  const authentication = authenticateRevenueCatWebhook(
    request.get("authorization"),
    request.get("x-revenuecat-webhook-signature"),
    rawBody,
    config.webhookAuthorization,
    config.webhookSigningSecret,
    runtime.now()
  );
  if (authentication !== "authenticated") {
    response.status(401).json({status: "unauthorized"});
    return;
  }

  const contentType = request.get("content-type")
    ?.split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (contentType !== "application/json") {
    response.status(400).json({status: "invalid_request"});
    return;
  }

  let parsed;
  try {
    parsed = parseRevenueCatWebhook(rawBody, config.appId);
  } catch (error) {
    if (error instanceof RevenueCatWebhookValidationError) {
      response.status(400).json({status: "invalid_request"});
      return;
    }
    throw error;
  }

  if (parsed.event.identityOverflowCount > 0) {
    console.warn("RevenueCat webhook identity candidates truncated", {
      overflowCount: parsed.event.identityOverflowCount,
    });
  }

  try {
    const outcome = await runtime.processEvent(
      parsed.event,
      parsed.payloadSha256,
      config,
      analyticsEnvironment
    );

    if (outcome === "busy") {
      response.set("Retry-After", "300");
      response.status(503).json({status: "retry"});
      return;
    }
    response.status(200).json({status: outcome});
  } catch {
    console.error("RevenueCat webhook reconciliation failed");
    response.status(500).json({status: "retry"});
  }
}

function deployedFirebaseProjectId(): string | undefined {
  try {
    return admin.app().options.projectId;
  } catch {
    return undefined;
  }
}

export const revenueCatWebhook = onRequest(
  {
    secrets: [revenueCatServerConfig],
    timeoutSeconds: 60,
  },
  (request, response) => handleRevenueCatWebhook(request, response)
);
