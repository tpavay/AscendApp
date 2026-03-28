import {defineSecret} from "firebase-functions/params";
import type {TransactionalEmailConfig} from "./types";

export const transactionalEmailConfig =
  defineSecret("TRANSACTIONAL_EMAIL_CONFIG");
export const DEFAULT_MARKETING_WEBSITE_URL = "https://ascendstepper.com";

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

  return {
    provider: config.provider,
    apiKey: config.apiKey,
    betaInviteUrl: config.betaInviteUrl,
    fromEmail: config.fromEmail,
    fromName: config.fromName,
    replyTo: config.replyTo,
    websiteUrl: config.websiteUrl,
  };
}

/**
 * Returns the public marketing website used in customer-facing email copy.
 * Falls back to the primary marketing site when the secret is unavailable.
 * @return {string} Normalized website URL
 */
export function getMarketingWebsiteUrl(): string {
  if (!process.env.TRANSACTIONAL_EMAIL_CONFIG) {
    return DEFAULT_MARKETING_WEBSITE_URL;
  }

  try {
    const configuredUrl = normalizePublicUrl(
      getTransactionalEmailConfig().websiteUrl
    );
    if (configuredUrl) {
      return configuredUrl;
    }
  } catch {
    // Ignore missing secret access in test-only render paths.
  }

  return DEFAULT_MARKETING_WEBSITE_URL;
}

/**
 * Returns the TestFlight or beta invite URL when configured.
 * @return {string | null} Normalized beta invite URL
 */
export function getBetaInviteUrl(): string | null {
  if (!process.env.TRANSACTIONAL_EMAIL_CONFIG) {
    return null;
  }

  try {
    return normalizePublicUrl(getTransactionalEmailConfig().betaInviteUrl);
  } catch {
    return null;
  }
}
