import {defineSecret} from "firebase-functions/params";

export interface MixpanelServerConfig {
  serviceAccountUsername: string;
  serviceAccountPassword: string;
}

export const mixpanelServerConfig =
  defineSecret("MIXPANEL_SERVER_CONFIG");

const MAX_USERNAME_LENGTH = 255;
const MIN_PASSWORD_LENGTH = 32;
const MAX_PASSWORD_LENGTH = 1024;

/**
 * Parses the server-only Mixpanel service-account credential.
 * @param {string} rawConfig - Secret Manager JSON value
 * @return {MixpanelServerConfig} Validated credential
 */
export function parseMixpanelServerConfig(
  rawConfig: string
): MixpanelServerConfig {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawConfig) as unknown;
  } catch {
    throw new Error("MIXPANEL_SERVER_CONFIG must be valid JSON");
  }
  if (!isRecord(parsed)) {
    throw new Error("MIXPANEL_SERVER_CONFIG is missing or invalid");
  }

  const username = parsed.serviceAccountUsername;
  const password = parsed.serviceAccountPassword;
  if (typeof username !== "string" ||
    username.length === 0 ||
    username.length > MAX_USERNAME_LENGTH ||
    username.includes(":") ||
    containsControlCharacter(username)) {
    throw new Error(
      "MIXPANEL_SERVER_CONFIG.serviceAccountUsername is invalid"
    );
  }
  if (typeof password !== "string" ||
    password.length < MIN_PASSWORD_LENGTH ||
    password.length > MAX_PASSWORD_LENGTH ||
    containsControlCharacter(password)) {
    throw new Error(
      "MIXPANEL_SERVER_CONFIG.serviceAccountPassword is invalid"
    );
  }
  return {
    serviceAccountUsername: username,
    serviceAccountPassword: password,
  };
}

/**
 * Reads the deployed credential without logging or exposing it.
 * @return {MixpanelServerConfig} Validated credential
 */
export function getMixpanelServerConfig(): MixpanelServerConfig {
  return parseMixpanelServerConfig(mixpanelServerConfig.value());
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function containsControlCharacter(value: string): boolean {
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
}
