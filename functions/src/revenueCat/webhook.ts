import * as admin from "firebase-admin";
import {onRequest} from "firebase-functions/v2/https";
import {
  authenticateRevenueCatWebhook,
} from "./authentication";
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

interface WebhookHttpRequest {
  method: string;
  rawBody?: Buffer;
  get(name: string): string | undefined;
}

interface WebhookHttpResponse {
  set(field: string, value: string): WebhookHttpResponse;
  status(code: number): WebhookHttpResponse;
  json(body: Record<string, string>): WebhookHttpResponse;
}

/**
 * Authenticates and processes one RevenueCat webhook request.
 * @param {WebhookHttpRequest} request - HTTP request
 * @param {WebhookHttpResponse} response - HTTP response
 * @return {Promise<void>}
 */
export async function handleRevenueCatWebhook(
  request: WebhookHttpRequest,
  response: WebhookHttpResponse
): Promise<void> {
  response.set("Cache-Control", "no-store");
  if (request.method !== "POST") {
    response.set("Allow", "POST");
    response.status(405).json({status: "method_not_allowed"});
    return;
  }

  let config;
  try {
    config = getRevenueCatServerConfig();
  } catch {
    console.error("RevenueCat webhook server configuration is invalid");
    response.status(500).json({status: "server_configuration_error"});
    return;
  }

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
    new Date()
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

  try {
    const outcome = await processRevenueCatWebhookEvent(
      parsed.event,
      parsed.payloadSha256,
      {
        store: new FirestoreRevenueCatEntitlementStore(admin.firestore()),
        subscriberClient: new HttpRevenueCatSubscriberClient(config.apiKey),
        userVerifier: new AdminFirebaseUserVerifier(),
        config,
        now: () => new Date(),
      }
    );

    if (outcome === "busy") {
      response.set("Retry-After", "300");
      response.status(503).json({status: "retry"});
      return;
    }
    if (outcome === "conflict") {
      response.status(409).json({status: "event_id_conflict"});
      return;
    }
    response.status(200).json({status: outcome});
  } catch {
    console.error("RevenueCat webhook reconciliation failed");
    response.status(500).json({status: "retry"});
  }
}

export const revenueCatWebhook = onRequest(
  {
    secrets: [revenueCatServerConfig],
    timeoutSeconds: 60,
  },
  handleRevenueCatWebhook
);
