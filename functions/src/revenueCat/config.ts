import {defineSecret} from "firebase-functions/params";
import type {RevenueCatServerConfig} from "./types";

export const revenueCatServerConfig =
  defineSecret("REVENUECAT_SERVER_CONFIG");

const MIN_SECRET_LENGTH = 32;
const MAX_PRODUCT_COUNT = 20;

/**
 * Parses the environment-specific RevenueCat server contract.
 * @param {string} rawConfig - Secret JSON value
 * @return {RevenueCatServerConfig} Validated server configuration
 */
export function parseRevenueCatServerConfig(
  rawConfig: string
): RevenueCatServerConfig {
  let parsedConfig: unknown;

  try {
    parsedConfig = JSON.parse(rawConfig) as unknown;
  } catch {
    throw new Error("REVENUECAT_SERVER_CONFIG must be valid JSON");
  }

  if (!isRecord(parsedConfig)) {
    throw new Error("REVENUECAT_SERVER_CONFIG is missing or invalid");
  }

  const apiKey = requiredSecret(parsedConfig.apiKey, "apiKey");
  const webhookAuthorization = requiredSecret(
    parsedConfig.webhookAuthorization,
    "webhookAuthorization"
  );
  const webhookSigningSecret = requiredSecret(
    parsedConfig.webhookSigningSecret,
    "webhookSigningSecret"
  );
  const appId = requiredIdentifier(parsedConfig.appId, "appId");
  const entitlementId = requiredIdentifier(
    parsedConfig.entitlementId,
    "entitlementId"
  );

  if (!Array.isArray(parsedConfig.allowedProductIds) ||
    parsedConfig.allowedProductIds.length === 0 ||
    parsedConfig.allowedProductIds.length > MAX_PRODUCT_COUNT) {
    throw new Error(
      "REVENUECAT_SERVER_CONFIG.allowedProductIds must be a non-empty array"
    );
  }

  const allowedProductIds = parsedConfig.allowedProductIds.map(
    (value, index) => requiredIdentifier(
      value,
      `allowedProductIds[${index}]`
    )
  );
  if (new Set(allowedProductIds).size !== allowedProductIds.length) {
    throw new Error(
      "REVENUECAT_SERVER_CONFIG.allowedProductIds must be unique"
    );
  }

  return {
    apiKey,
    webhookAuthorization,
    webhookSigningSecret,
    appId,
    entitlementId,
    allowedProductIds,
  };
}

/**
 * Reads the deployed secret without exposing it in logs or error messages.
 * @return {RevenueCatServerConfig} Validated server configuration
 */
export function getRevenueCatServerConfig(): RevenueCatServerConfig {
  return parseRevenueCatServerConfig(revenueCatServerConfig.value());
}

function requiredSecret(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length < MIN_SECRET_LENGTH) {
    throw new Error(
      `REVENUECAT_SERVER_CONFIG.${field} must be at least ` +
      `${MIN_SECRET_LENGTH} characters`
    );
  }
  return value;
}

function requiredIdentifier(value: unknown, field: string): string {
  if (typeof value !== "string" ||
    !/^[A-Za-z0-9._:-]{1,200}$/.test(value)) {
    throw new Error(`REVENUECAT_SERVER_CONFIG.${field} is invalid`);
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
