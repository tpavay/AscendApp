import {defineSecret} from "firebase-functions/params";

/**
 * One Strava API application serves every environment: Strava allows a
 * developer a single app, and its capacity is counted across all of them.
 * The secret therefore carries everything that differs by project, and a
 * project that must stay inert holds `{"configured": false}` instead of
 * credentials - which is how staging and production satisfy the secret
 * guard before the integration is live there.
 */
export const stravaServerConfig = defineSecret("STRAVA_SERVER_CONFIG");

export interface StravaServerConfig {
  clientId: string;
  clientSecret: string;
  /**
   * The OAuth redirect the app's authentication session listens for. Its
   * host must equal the "Authorization Callback Domain" on the Strava app,
   * and its scheme must be the URL scheme of the build that talks to this
   * project (`STRAVA_REDIRECT_SCHEMES`).
   */
  redirectUri: string;
  /** Echoed back by Strava when a webhook subscription is created. */
  webhookVerifyToken: string;
}

/**
 * The URL scheme each Ascend build registers: the App Store build, staging,
 * and dev. Every build used to share `ascendapp`, so with more than one
 * installed iOS handed Strava's redirect to whichever it chose, and a
 * production climber's connect landed in the staging build. Strava checks
 * only the redirect's host against its callback domain, so each project
 * names its own build's scheme and Strava accepts all three.
 */
export const STRAVA_REDIRECT_SCHEMES: readonly string[] = [
  "ascendapp",
  "ascendapp-stg",
  "ascendapp-dev",
];
const MIN_VERIFY_TOKEN_LENGTH = 16;

/**
 * Parses the Strava secret payload.
 *
 * Returns null, never throws, for a project that is deliberately not
 * configured, so every Strava surface there reports "unavailable" rather than
 * erroring. A payload that claims to be configured but is incomplete throws,
 * because a half-filled credential is an operator mistake worth an alert.
 * @param {string} raw The secret's value.
 * @return {StravaServerConfig | null} Parsed config, or null when inert.
 */
export function parseStravaServerConfig(
  raw: string
): StravaServerConfig | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("STRAVA_SERVER_CONFIG must be valid JSON");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("STRAVA_SERVER_CONFIG must be a JSON object");
  }
  const config = parsed as Record<string, unknown>;
  if (config.configured === false) {
    return null;
  }

  const clientId = nonEmptyString(config.clientId);
  const clientSecret = nonEmptyString(config.clientSecret);
  const redirectUri = nonEmptyString(config.redirectUri);
  const webhookVerifyToken = nonEmptyString(config.webhookVerifyToken);
  if (!clientId || !/^\d+$/.test(clientId) || !clientSecret) {
    throw new Error(
      "STRAVA_SERVER_CONFIG needs a numeric clientId and a clientSecret"
    );
  }
  if (!redirectUri || stravaCallbackScheme(redirectUri) === null) {
    throw new Error(
      "STRAVA_SERVER_CONFIG.redirectUri must use one of the " +
      `${STRAVA_REDIRECT_SCHEMES.join(", ")} schemes and name the Strava ` +
      "app's callback domain as its host"
    );
  }
  if (!webhookVerifyToken ||
    webhookVerifyToken.length < MIN_VERIFY_TOKEN_LENGTH) {
    throw new Error(
      "STRAVA_SERVER_CONFIG.webhookVerifyToken must be at least " +
      `${MIN_VERIFY_TOKEN_LENGTH} characters`
    );
  }
  return {clientId, clientSecret, redirectUri, webhookVerifyToken};
}

/**
 * Reads and parses the bound secret.
 * @return {StravaServerConfig | null} Parsed config, or null when inert.
 */
export function getStravaServerConfig(): StravaServerConfig | null {
  return parseStravaServerConfig(stravaServerConfig.value());
}

/**
 * The URL scheme the app's authentication session must listen on for a
 * redirect URI, or null when no Ascend build could catch it.
 * @param {string} redirectUri Candidate redirect URI.
 * @return {string | null} The scheme, for `<scheme>://<host>/<path>`.
 */
export function stravaCallbackScheme(redirectUri: string): string | null {
  try {
    const url = new URL(redirectUri);
    const scheme = url.protocol.replace(/:$/, "");
    return STRAVA_REDIRECT_SCHEMES.includes(scheme) &&
      url.hostname.length > 0 ? scheme : null;
  } catch {
    return null;
  }
}

/**
 * Narrows an unknown to a trimmed non-empty string.
 * @param {unknown} value Candidate.
 * @return {string | null} The string, or null.
 */
function nonEmptyString(value: unknown): string | null {
  if (typeof value === "number" && Number.isInteger(value)) {
    return String(value);
  }
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
