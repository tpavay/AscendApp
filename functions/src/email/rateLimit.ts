import * as admin from "firebase-admin";
import {sha256Hex} from "./crypto";
import type {
  EmailRateLimitDocument,
  EmailRateLimitState,
} from "./types";

const SHORT_WINDOW_LIMIT = 10;
const SHORT_WINDOW_MS = 10 * 60 * 1000;
const LONG_WINDOW_LIMIT = 50;
const LONG_WINDOW_MS = 24 * 60 * 60 * 1000;

export type WaitlistRateLimitReason = "short_window" | "long_window";

export interface WaitlistRateLimitEvaluation {
  allowed: boolean;
  reason: WaitlistRateLimitReason | null;
  state: EmailRateLimitState;
}

/**
 * Extracts the best-effort requester IP for abuse protection.
 * @param {string | undefined} forwardedFor - x-forwarded-for header value
 * @param {string | undefined} fallback - Fallback socket or framework IP
 * @return {string} Requester IP string, or "unknown"
 */
export function extractRequesterIp(
  forwardedFor: string | undefined,
  fallback: string | undefined
): string {
  if (forwardedFor) {
    const firstForwardedIp = forwardedFor.split(",")[0]?.trim();
    if (firstForwardedIp) {
      return firstForwardedIp;
    }
  }

  if (fallback && fallback.trim().length > 0) {
    return fallback.trim();
  }

  return "unknown";
}

/**
 * Hashes a requester IP before persistence.
 * @param {string} ipAddress - Raw requester IP
 * @return {string} SHA-256 hash of the IP
 */
export function hashRateLimitIp(ipAddress: string): string {
  return sha256Hex(ipAddress);
}

/**
 * Converts a stored Firestore rate-limit document into pure state.
 * @param {EmailRateLimitDocument | null} document - Stored Firestore doc
 * @return {EmailRateLimitState | null} Pure state for calculations
 */
export function toEmailRateLimitState(
  document: EmailRateLimitDocument | null
): EmailRateLimitState | null {
  if (!document) {
    return null;
  }

  return {
    ipHash: document.ipHash,
    shortWindowCount: document.shortWindowCount,
    shortWindowStartedAtMs: document.shortWindowStartedAt.toMillis(),
    longWindowCount: document.longWindowCount,
    longWindowStartedAtMs: document.longWindowStartedAt.toMillis(),
  };
}

/**
 * Evaluates the waitlist endpoint rate limit for a single request.
 * @param {EmailRateLimitState | null} state - Existing rate-limit state
 * @param {number} nowMs - Current time in milliseconds
 * @param {string} ipHash - Hashed requester IP
 * @return {WaitlistRateLimitEvaluation} Evaluation result and next state
 */
export function evaluateWaitlistRateLimit(
  state: EmailRateLimitState | null,
  nowMs: number,
  ipHash: string
): WaitlistRateLimitEvaluation {
  const shortWindowExpired = !state ||
    nowMs - state.shortWindowStartedAtMs >= SHORT_WINDOW_MS;
  const longWindowExpired = !state ||
    nowMs - state.longWindowStartedAtMs >= LONG_WINDOW_MS;

  const nextState: EmailRateLimitState = {
    ipHash,
    shortWindowCount: shortWindowExpired ? 0 : state.shortWindowCount,
    shortWindowStartedAtMs: shortWindowExpired ?
      nowMs :
      state.shortWindowStartedAtMs,
    longWindowCount: longWindowExpired ? 0 : state.longWindowCount,
    longWindowStartedAtMs: longWindowExpired ?
      nowMs :
      state.longWindowStartedAtMs,
  };

  if (nextState.shortWindowCount >= SHORT_WINDOW_LIMIT) {
    return {
      allowed: false,
      reason: "short_window",
      state: nextState,
    };
  }

  if (nextState.longWindowCount >= LONG_WINDOW_LIMIT) {
    return {
      allowed: false,
      reason: "long_window",
      state: nextState,
    };
  }

  return {
    allowed: true,
    reason: null,
    state: {
      ...nextState,
      shortWindowCount: nextState.shortWindowCount + 1,
      longWindowCount: nextState.longWindowCount + 1,
    },
  };
}

/**
 * Converts pure rate-limit state back into a Firestore document.
 * @param {EmailRateLimitState} state - Pure state
 * @param {Timestamp} nowTimestamp - Current timestamp
 * @param {Timestamp | null} createdAt - Existing createdAt if present
 * @return {EmailRateLimitDocument} Firestore-ready document
 */
export function toEmailRateLimitDocument(
  state: EmailRateLimitState,
  nowTimestamp: admin.firestore.Timestamp,
  createdAt: admin.firestore.Timestamp | null
): EmailRateLimitDocument {
  return {
    createdAt: createdAt ?? nowTimestamp,
    ipHash: state.ipHash,
    shortWindowCount: state.shortWindowCount,
    shortWindowStartedAt: admin.firestore.Timestamp.fromMillis(
      state.shortWindowStartedAtMs
    ),
    longWindowCount: state.longWindowCount,
    longWindowStartedAt: admin.firestore.Timestamp.fromMillis(
      state.longWindowStartedAtMs
    ),
    updatedAt: nowTimestamp,
  };
}
