/**
 * Cloud Functions for AscendApp
 *
 * - Strava: OAuth and activity sync integration
 */

import {setGlobalOptions} from "firebase-functions/v2";
import {onRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {createHash} from "crypto";

// Initialize Firebase Admin (only once)
admin.initializeApp();

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Normalizes an email for deduplication comparisons.
 * @param {string} value - Raw email input
 * @return {string} Trimmed lowercase email
 */
function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

/**
 * Creates a stable SHA-256 hash for an email.
 * @param {string} value - Normalized email value
 * @return {string} Hex-encoded hash
 */
function hashEmail(value: string): string {
  return createHash("sha256").update(value).digest("hex");
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

// ============================================
// HTTP: Waitlist Signup (deduplicated)
// ============================================

export const joinWaitlist = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "method_not_allowed"});
    return;
  }

  let body: Record<string, unknown> | null = null;
  if (typeof req.body === "string") {
    try {
      body = JSON.parse(req.body) as Record<string, unknown>;
    } catch {
      body = null;
    }
  } else if (req.body && typeof req.body === "object") {
    body = req.body as Record<string, unknown>;
  }

  const emailInput = body?.email;
  const email = typeof emailInput === "string" ?
    normalizeEmail(emailInput) :
    "";
  if (!email || email.length > 255 || !EMAIL_PATTERN.test(email)) {
    res.status(400).json({error: "invalid_email"});
    return;
  }

  const sourceInput = body?.source;
  const source = typeof sourceInput === "string" &&
    sourceInput.trim().length > 0 &&
    sourceInput.length < 100 ?
    sourceInput.trim() :
    "landing_page";

  try {
    const waitlistCollection = admin.firestore().collection("waitlist");
    const existingByEmail = await waitlistCollection
      .where("email", "==", email)
      .limit(1)
      .get();

    if (!existingByEmail.empty) {
      res.status(200).json({status: "already_subscribed"});
      return;
    }

    const emailHash = hashEmail(email);
    const waitlistRef = waitlistCollection.doc(emailHash);

    await waitlistRef.create({
      email,
      emailHash,
      source,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    res.status(200).json({status: "subscribed"});
  } catch (error) {
    if (isAlreadyExistsError(error)) {
      res.status(200).json({status: "already_subscribed"});
      return;
    }

    console.error("joinWaitlist failed:", error);
    res.status(500).json({error: "internal"});
  }
});

// ============================================
// RE-EXPORT STRAVA FUNCTIONS
// ============================================

export {
  stravaCallback,
  stravaCreateOAuthState,
  stravaCreateActivity,
  stravaDisconnect,
} from "./strava";

// Global options for cost control
setGlobalOptions({maxInstances: 10});
