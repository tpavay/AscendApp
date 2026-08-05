import {
  createHash,
  createHmac,
  timingSafeEqual,
} from "node:crypto";

const SIGNATURE_TOLERANCE_SECONDS = 5 * 60;
const SIGNATURE_PATTERN = /^[0-9a-f]{64}$/;

export type WebhookAuthenticationOutcome =
  | "authenticated"
  | "invalid_authorization"
  | "invalid_signature"
  | "stale_signature";

/**
 * Verifies both RevenueCat webhook credentials over the unparsed request body.
 * @param {string | undefined} authorization - Authorization request header
 * @param {string | undefined} signatureHeader - RevenueCat signature header
 * @param {Buffer} rawBody - Exact request bytes received
 * @param {string} expectedAuthorization - Configured authorization value
 * @param {string} signingSecret - RevenueCat webhook signing secret
 * @param {Date} now - Verification clock
 * @return {WebhookAuthenticationOutcome} Stable authentication outcome
 */
export function authenticateRevenueCatWebhook(
  authorization: string | undefined,
  signatureHeader: string | undefined,
  rawBody: Buffer,
  expectedAuthorization: string,
  signingSecret: string,
  now: Date
): WebhookAuthenticationOutcome {
  if (!authorization ||
    !constantTimeTextEqual(authorization, expectedAuthorization)) {
    return "invalid_authorization";
  }

  const signature = parseSignatureHeader(signatureHeader);
  if (!signature) {
    return "invalid_signature";
  }

  const ageSeconds = Math.abs(
    Math.floor(now.getTime() / 1000) - signature.timestamp
  );
  if (ageSeconds > SIGNATURE_TOLERANCE_SECONDS) {
    return "stale_signature";
  }

  const expectedSignature = createHmac("sha256", signingSecret)
    .update(`${signature.timestamp}.`, "utf8")
    .update(rawBody)
    .digest("hex");
  const isValid = signature.signatures.some(
    (candidate) => timingSafeEqual(
      Buffer.from(candidate, "hex"),
      Buffer.from(expectedSignature, "hex")
    )
  );

  return isValid ? "authenticated" : "invalid_signature";
}

function parseSignatureHeader(
  header: string | undefined
): {timestamp: number; signatures: string[]} | null {
  if (!header) {
    return null;
  }

  let timestamp: number | null = null;
  const signatures: string[] = [];
  for (const segment of header.split(",")) {
    const [key, value, ...extra] = segment.trim().split("=");
    if (extra.length > 0 || !value) {
      return null;
    }
    if (key === "t" && timestamp === null && /^\d{1,12}$/.test(value)) {
      timestamp = Number(value);
    } else if (key === "v1" && SIGNATURE_PATTERN.test(value)) {
      signatures.push(value);
    }
  }

  if (timestamp === null || !Number.isSafeInteger(timestamp) ||
    signatures.length === 0) {
    return null;
  }
  return {timestamp, signatures};
}

function constantTimeTextEqual(left: string, right: string): boolean {
  const leftDigest = createHash("sha256").update(left).digest();
  const rightDigest = createHash("sha256").update(right).digest();
  return timingSafeEqual(leftDigest, rightDigest);
}
