import {createHmac, timingSafeEqual} from "crypto";

const TOKEN_VERSION = "v1";

/**
 * Encodes a UTF-8 string as base64url without padding.
 * @param {string} value - Raw string value
 * @return {string} base64url-encoded value
 */
function encodeBase64Url(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

/**
 * Decodes a base64url segment back into a UTF-8 string.
 * @param {string} value - base64url-encoded value
 * @return {string | null} Decoded string, or null when malformed
 */
function decodeBase64Url(value: string): string | null {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    return null;
  }

  const decoded = Buffer.from(value, "base64url").toString("utf8");
  return decoded.length > 0 ? decoded : null;
}

/**
 * Signs the token body with the unsubscribe signing key.
 * @param {string} body - Versioned token body
 * @param {string} signingKey - Server-held HMAC signing key
 * @return {string} base64url-encoded HMAC-SHA256 signature
 */
function signTokenBody(body: string, signingKey: string): string {
  return createHmac("sha256", signingKey).update(body).digest("base64url");
}

/**
 * Compares two signatures without leaking timing information.
 * @param {string} expected - Signature computed from the signing key
 * @param {string} provided - Signature supplied by the request
 * @return {boolean} True when the signatures match
 */
function signaturesMatch(expected: string, provided: string): boolean {
  const expectedBuffer = Buffer.from(expected, "utf8");
  const providedBuffer = Buffer.from(provided, "utf8");
  if (expectedBuffer.length !== providedBuffer.length) {
    return false;
  }

  return timingSafeEqual(expectedBuffer, providedBuffer);
}

/**
 * Builds a signed, non-expiring unsubscribe token for a user.
 *
 * Unsubscribe links must keep working for the life of the message, so the
 * token intentionally carries no expiry. It only ever authorizes disabling
 * lifecycle emails for the encoded uid.
 * @param {string} uid - Firebase Auth user ID
 * @param {string} signingKey - Server-held HMAC signing key
 * @return {string} Signed unsubscribe token
 */
export function buildUnsubscribeToken(
  uid: string,
  signingKey: string
): string {
  if (!uid || !signingKey) {
    throw new Error("unsubscribe_token_requires_uid_and_key");
  }

  const body = `${TOKEN_VERSION}.${encodeBase64Url(uid)}`;
  return `${body}.${signTokenBody(body, signingKey)}`;
}

/**
 * Verifies a signed unsubscribe token and recovers its uid.
 * @param {unknown} token - Untrusted token from the request
 * @param {string} signingKey - Server-held HMAC signing key
 * @return {string | null} Verified uid, or null when the token is invalid
 */
export function verifyUnsubscribeToken(
  token: unknown,
  signingKey: string
): string | null {
  if (typeof token !== "string" || !signingKey) {
    return null;
  }

  const segments = token.split(".");
  if (segments.length !== 3) {
    return null;
  }

  const [version, encodedUid, signature] = segments;
  if (version !== TOKEN_VERSION) {
    return null;
  }

  const body = `${version}.${encodedUid}`;
  if (!signaturesMatch(signTokenBody(body, signingKey), signature)) {
    return null;
  }

  return decodeBase64Url(encodedUid);
}

/**
 * Builds the public one-click unsubscribe URL for a signed token.
 * @param {string} websiteUrl - Normalized public website origin
 * @param {string} token - Signed unsubscribe token
 * @return {string} Absolute unsubscribe URL
 */
export function buildUnsubscribeUrl(
  websiteUrl: string,
  token: string
): string {
  const url = new URL("/api/unsubscribe", websiteUrl);
  url.searchParams.set("token", token);
  return url.toString();
}
