import {onRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  buildEmailJobId,
  buildWaitlistWelcomeDedupeKey,
  createQueuedEmailJob,
} from "./email/queue";
import {
  extractRequesterIp,
  evaluateWaitlistRateLimit,
  hashRateLimitIp,
  toEmailRateLimitDocument,
  toEmailRateLimitState,
  type WaitlistRateLimitReason,
} from "./email/rateLimit";
import {normalizeEmail, sha256Hex} from "./email/crypto";
import type {EmailRateLimitDocument} from "./email/types";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Signals that the public waitlist endpoint hit an abuse limit.
 */
class RateLimitExceededError extends Error {
  reason: WaitlistRateLimitReason;

  /**
   * Creates a stable rate-limit error for HTTP response handling.
   * @param {WaitlistRateLimitReason} reason - Window that blocked the request
   */
  constructor(reason: WaitlistRateLimitReason) {
    super(reason);
    this.reason = reason;
  }
}

/**
 * Checks if a Firestore write failed due to an existing document.
 * @param {unknown} error - Error thrown by Firestore Admin SDK
 * @return {boolean} True if the error indicates an existing doc
 */
function isAlreadyExistsError(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }

  const code = "code" in error ? String(error.code) : "";
  if (code === "6" || code === "already-exists") {
    return true;
  }

  const message = "message" in error ? String(error.message) : "";
  return message.includes("Already exists");
}

/**
 * Parses the HTTP request body into a plain object.
 * @param {unknown} body - Raw request body
 * @return {Record<string, unknown> | null} Parsed body or null
 */
function parseBody(body: unknown): Record<string, unknown> | null {
  if (typeof body === "string") {
    try {
      return JSON.parse(body) as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  if (body && typeof body === "object") {
    return body as Record<string, unknown>;
  }

  return null;
}

/**
 * Normalizes and validates a waitlist signup source label.
 * @param {unknown} value - Raw source value
 * @return {string} Validated source label
 */
function parseSource(value: unknown): string {
  if (typeof value !== "string") {
    return "landing_page";
  }

  const trimmedValue = value.trim();
  if (trimmedValue.length === 0 || trimmedValue.length >= 100) {
    return "landing_page";
  }

  return trimmedValue;
}

/**
 * Handles public waitlist signups and enqueues the welcome email job.
 */
export const joinWaitlist = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "method_not_allowed"});
    return;
  }

  const body = parseBody(req.body);
  const emailInput = body?.email;
  const email = typeof emailInput === "string" ?
    normalizeEmail(emailInput) :
    "";

  if (!email || email.length > 255 || !EMAIL_PATTERN.test(email)) {
    res.status(400).json({error: "invalid_email"});
    return;
  }

  const source = parseSource(body?.source);
  const emailHash = sha256Hex(email);
  const dedupeKey = buildWaitlistWelcomeDedupeKey(emailHash);
  const emailJobId = buildEmailJobId(dedupeKey);
  const requesterIp = extractRequesterIp(
    req.get("x-forwarded-for") ?? undefined,
    req.ip ?? req.socket.remoteAddress ?? undefined
  );
  const ipHash = hashRateLimitIp(requesterIp);
  const now = new Date();
  const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
  const waitlistRef = admin.firestore().collection("waitlist").doc(emailHash);
  const emailJobRef = admin.firestore()
    .collection("email_jobs")
    .doc(emailJobId);
  const rateLimitRef = admin.firestore()
    .collection("email_rate_limits")
    .doc(ipHash);

  try {
    const responseStatus = await admin.firestore().runTransaction(
      async (transaction) => {
        const rateLimitSnapshot = await transaction.get(rateLimitRef);
        const waitlistSnapshot = await transaction.get(waitlistRef);
        const emailJobSnapshot = await transaction.get(emailJobRef);
        const rateLimitDocument = rateLimitSnapshot.exists ?
          rateLimitSnapshot.data() as EmailRateLimitDocument :
          null;
        const rateLimitEvaluation = evaluateWaitlistRateLimit(
          toEmailRateLimitState(rateLimitDocument),
          now.getTime(),
          ipHash
        );

        if (!rateLimitEvaluation.allowed) {
          throw new RateLimitExceededError(
            rateLimitEvaluation.reason ?? "short_window"
          );
        }

        transaction.set(
          rateLimitRef,
          toEmailRateLimitDocument(
            rateLimitEvaluation.state,
            nowTimestamp,
            rateLimitDocument?.createdAt ?? null
          )
        );

        if (waitlistSnapshot.exists) {
          return "already_subscribed";
        }

        transaction.create(waitlistRef, {
          createdAt: nowTimestamp,
          email,
          emailHash,
          source,
          welcomeEmailJobId: emailJobId,
        });

        if (!emailJobSnapshot.exists) {
          transaction.create(
            emailJobRef,
            createQueuedEmailJob(
              "waitlist_welcome",
              email,
              emailHash,
              dedupeKey,
              {source},
              nowTimestamp,
              `waitlist/${emailHash}`
            )
          );
        }

        return "subscribed";
      }
    );

    res.status(200).json({status: responseStatus});
  } catch (error) {
    if (error instanceof RateLimitExceededError) {
      res.status(429).json({error: "rate_limited"});
      return;
    }

    if (isAlreadyExistsError(error)) {
      res.status(200).json({status: "already_subscribed"});
      return;
    }

    console.error("joinWaitlist failed", {
      errorCode: error instanceof Error ? error.name : "unknown_error",
      message: error instanceof Error ? error.message : "unknown_error",
    });
    res.status(500).json({error: "internal"});
  }
});
