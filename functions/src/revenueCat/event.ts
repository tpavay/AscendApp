import {createHash} from "node:crypto";
import type {RevenueCatWebhookEvent} from "./types";

const MAX_WEBHOOK_BYTES = 256 * 1024;
const MAX_IDENTITY_COUNT = 20;
const EVENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const EVENT_TYPE_PATTERN = /^[A-Z][A-Z0-9_]{0,99}$/;

export interface ParsedRevenueCatWebhook {
  event: RevenueCatWebhookEvent;
  payloadSha256: string;
}

/**
 * Parses the small trusted envelope needed to reconcile subscriber state.
 * Unknown fields and event types are deliberately tolerated.
 * @param {Buffer} rawBody - Authenticated RevenueCat request body
 * @param {string} expectedAppId - Environment-specific RevenueCat app id
 * @return {ParsedRevenueCatWebhook} Validated event and payload digest
 */
export function parseRevenueCatWebhook(
  rawBody: Buffer,
  expectedAppId: string
): ParsedRevenueCatWebhook {
  if (rawBody.length === 0 || rawBody.length > MAX_WEBHOOK_BYTES) {
    throw new RevenueCatWebhookValidationError("invalid_body_size");
  }

  let parsedBody: unknown;
  try {
    parsedBody = JSON.parse(rawBody.toString("utf8")) as unknown;
  } catch {
    throw new RevenueCatWebhookValidationError("invalid_json");
  }

  if (!isRecord(parsedBody) ||
    typeof parsedBody.api_version !== "string" ||
    !isRecord(parsedBody.event)) {
    throw new RevenueCatWebhookValidationError("invalid_envelope");
  }

  const event = parsedBody.event;
  if (typeof event.id !== "string" || !EVENT_ID_PATTERN.test(event.id)) {
    throw new RevenueCatWebhookValidationError("invalid_event_id");
  }
  if (typeof event.type !== "string" ||
    !EVENT_TYPE_PATTERN.test(event.type)) {
    throw new RevenueCatWebhookValidationError("invalid_event_type");
  }
  const hasAppId = event.app_id !== null && event.app_id !== undefined;
  if (hasAppId && event.app_id !== expectedAppId) {
    throw new RevenueCatWebhookValidationError("unexpected_app_id");
  }
  if (typeof event.event_timestamp_ms !== "number" ||
    !Number.isSafeInteger(event.event_timestamp_ms) ||
    event.event_timestamp_ms <= 0) {
    throw new RevenueCatWebhookValidationError("invalid_event_timestamp");
  }

  const identities = collectAppUserIds(event);
  return {
    event: {
      id: event.id,
      type: event.type,
      appId: expectedAppId,
      eventTimestampMs: event.event_timestamp_ms,
      appUserIds: identities.appUserIds,
      identityOverflowCount: identities.overflowCount,
    },
    payloadSha256: createHash("sha256").update(rawBody).digest("hex"),
  };
}

export class RevenueCatWebhookValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "RevenueCatWebhookValidationError";
  }
}

/**
 * Collects the bounded Firebase UID candidates an event can reconcile.
 *
 * Candidates are ordered by how much access depends on them: the current and
 * original IDs, then both sides of a transfer, then historical aliases. A
 * subscriber who accumulated more aliases than the bound is truncated rather
 * than rejected, because rejecting the delivery would discard the real
 * identities too and RevenueCat would not retry a 400.
 * @param {Record<string, unknown>} event - Authenticated event object
 * @return {{appUserIds: string[], overflowCount: number}} Bounded identities
 */
function collectAppUserIds(
  event: Record<string, unknown>
): {appUserIds: string[]; overflowCount: number} {
  const candidates: unknown[] = [
    event.app_user_id,
    event.original_app_user_id,
    ...arrayOrEmpty(event.transferred_from),
    ...arrayOrEmpty(event.transferred_to),
    ...arrayOrEmpty(event.aliases),
  ];
  const identities = new Set<string>();
  const overflow = new Set<string>();

  for (const candidate of candidates) {
    if (typeof candidate !== "string" ||
      candidate.length === 0 ||
      candidate.length > 128 ||
      candidate.startsWith("$RCAnonymousID:") ||
      identities.has(candidate)) {
      continue;
    }
    if (identities.size >= MAX_IDENTITY_COUNT) {
      overflow.add(candidate);
      continue;
    }
    identities.add(candidate);
  }

  return {appUserIds: [...identities], overflowCount: overflow.size};
}

function arrayOrEmpty(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
