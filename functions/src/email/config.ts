import {defineSecret} from "firebase-functions/params";
import {EMAIL_TYPES} from "./types";
import type {
  EmailType,
  EnabledEmailTypes,
  TransactionalEmailConfig,
} from "./types";

export const transactionalEmailConfig =
  defineSecret("TRANSACTIONAL_EMAIL_CONFIG");
export const DEFAULT_MARKETING_WEBSITE_URL = "https://ascendstepper.com";
export const DEFAULT_TRANSACTIONAL_REPLY_TO_EMAIL =
  "support@ascendstepper.com";
export const MIN_UNSUBSCRIBE_SIGNING_KEY_LENGTH = 32;

/**
 * Normalizes a public-facing HTTPS URL from config.
 * @param {string | undefined} value - Raw configured URL
 * @return {string | null} Normalized URL or null if invalid
 */
function normalizePublicUrl(value: string | undefined): string | null {
  if (!value) {
    return null;
  }

  try {
    const url = new URL(value.trim());
    if (url.protocol !== "https:") {
      return null;
    }

    url.hash = "";
    return url.toString().replace(/\/+$/, "");
  } catch {
    return null;
  }
}

/**
 * Reads which email types this environment delivers from config.
 * @param {unknown} value - Raw `enabledEmailTypes`
 * @return {EnabledEmailTypes | null} The setting, or null if invalid
 */
function parseEnabledEmailTypes(value: unknown): EnabledEmailTypes | null {
  if (value === "all") {
    return "all";
  }

  const known: readonly string[] = EMAIL_TYPES;
  if (
    !Array.isArray(value) ||
    !value.every((type) => typeof type === "string" && known.includes(type))
  ) {
    return null;
  }

  return value as EmailType[];
}

/**
 * Parses and validates the transactional email secret payload.
 * @return {TransactionalEmailConfig} Provider config for email delivery
 */
export function getTransactionalEmailConfig(): TransactionalEmailConfig {
  const rawConfig = transactionalEmailConfig.value();
  let parsedConfig: unknown;

  try {
    parsedConfig = JSON.parse(rawConfig) as unknown;
  } catch {
    throw new Error("TRANSACTIONAL_EMAIL_CONFIG must be valid JSON");
  }

  if (!parsedConfig || typeof parsedConfig !== "object") {
    throw new Error("TRANSACTIONAL_EMAIL_CONFIG is missing or invalid");
  }

  const config = parsedConfig as Partial<TransactionalEmailConfig>;

  if (config.provider !== "resend") {
    throw new Error("TRANSACTIONAL_EMAIL_CONFIG.provider must be 'resend'");
  }

  if (!config.apiKey || !config.fromEmail || !config.fromName) {
    throw new Error(
      "TRANSACTIONAL_EMAIL_CONFIG must include apiKey, fromEmail, and fromName"
    );
  }

  // Required so a misconfigured secret fails loudly instead of quietly
  // sending mail that carries no working unsubscribe path.
  if (
    !config.unsubscribeSigningKey ||
    config.unsubscribeSigningKey.length < MIN_UNSUBSCRIBE_SIGNING_KEY_LENGTH
  ) {
    throw new Error(
      "TRANSACTIONAL_EMAIL_CONFIG.unsubscribeSigningKey must be at least " +
      `${MIN_UNSUBSCRIBE_SIGNING_KEY_LENGTH} characters`
    );
  }

  // Required for the same reason as the signing key: this host is what the
  // unsubscribe link points at, and the token is signed with this
  // environment's key. Falling back to the production host would emit staging
  // links that verify against the wrong key and never work.
  const websiteUrl = normalizePublicUrl(config.websiteUrl);
  if (!websiteUrl) {
    throw new Error(
      "TRANSACTIONAL_EMAIL_CONFIG.websiteUrl must be an https URL"
    );
  }

  // Required, never defaulted: this is what keeps an email type that ships in
  // code - and whose producer already runs - from reaching climbers in an
  // environment where nobody has decided it should. A default of "all" would
  // make a secret rebuilt without the field switch every type on, and a
  // default of none would switch email off without a sound.
  const enabledEmailTypes = parseEnabledEmailTypes(config.enabledEmailTypes);
  if (!enabledEmailTypes) {
    throw new Error(
      "TRANSACTIONAL_EMAIL_CONFIG.enabledEmailTypes must be \"all\" or a " +
      "list of email types"
    );
  }

  return {
    provider: config.provider,
    apiKey: config.apiKey,
    enabledEmailTypes,
    feedbackNotificationEmail: config.feedbackNotificationEmail,
    fromEmail: config.fromEmail,
    fromName: config.fromName,
    replyTo: config.replyTo,
    unsubscribeSigningKey: config.unsubscribeSigningKey,
    websiteUrl,
  };
}

/**
 * Throws unless the transactional email secret is present and valid.
 *
 * Lets a sender check the deploy config up front and fail on it directly,
 * instead of leaving it to surface deeper in a render or send path that would
 * misread it as a problem with the individual message.
 */
export function assertTransactionalEmailConfig(): void {
  getTransactionalEmailConfig();
}

/**
 * Whether this environment delivers queued email of the given type.
 *
 * Takes a string, not an `EmailType`: a queued job outlives the build that
 * wrote it and can name a type this build no longer knows.
 * @param {string} emailType - A queued job's type
 * @return {boolean} True when the type may be delivered here
 */
export function isEmailTypeEnabled(emailType: string): boolean {
  const {enabledEmailTypes} = getTransactionalEmailConfig();
  if (enabledEmailTypes === "all") {
    return true;
  }

  const enabled: readonly string[] = enabledEmailTypes;
  return enabled.includes(emailType);
}

/**
 * Returns the HMAC signing key used for one-click unsubscribe tokens.
 * @return {string} Unsubscribe signing key
 */
export function getUnsubscribeSigningKey(): string {
  return getTransactionalEmailConfig().unsubscribeSigningKey;
}

/**
 * Returns the public marketing website used in customer-facing email copy.
 *
 * The fallback covers only render paths that never set the secret, such as
 * template tests. A secret that is present but invalid throws instead: it is
 * the host the unsubscribe link points at, so guessing it wrong would emit
 * links that verify against another environment's key and never work.
 * @return {string} Normalized website URL
 */
export function getMarketingWebsiteUrl(): string {
  if (!process.env.TRANSACTIONAL_EMAIL_CONFIG) {
    return DEFAULT_MARKETING_WEBSITE_URL;
  }

  return getTransactionalEmailConfig().websiteUrl;
}

/**
 * Returns the admin email address for feedback notifications.
 * Falls back to replyTo, then fromEmail.
 * @return {string} Admin notification recipient
 */
export function getFeedbackNotificationEmail(): string {
  const config = getTransactionalEmailConfig();
  return config.feedbackNotificationEmail ?? config.replyTo ?? config.fromEmail;
}

/**
 * Returns the email address used for customer reply CTAs.
 * Falls back safely in test-only render paths where the secret is unavailable.
 * @return {string} Reply-to email address
 */
export function getTransactionalReplyToEmail(): string {
  if (!process.env.TRANSACTIONAL_EMAIL_CONFIG) {
    return DEFAULT_TRANSACTIONAL_REPLY_TO_EMAIL;
  }

  try {
    const config = getTransactionalEmailConfig();
    return config.replyTo ?? config.fromEmail;
  } catch {
    return DEFAULT_TRANSACTIONAL_REPLY_TO_EMAIL;
  }
}
