import {defineSecret} from "firebase-functions/params";

export const beehiivConfig = defineSecret("BEEHIIV_CONFIG");

interface BeehiivConfig {
  apiKey: string;
  automationIds?: string[];
  newsletterListIds?: string[];
  publicationId: string;
  reactivateExisting?: boolean;
  sendWelcomeEmail?: boolean;
}

export interface BeehiivSubscriptionResult {
  rawStatus: string | null;
  status: "subscribed" | "already_subscribed";
  subscriptionId: string | null;
}

/**
 * Error thrown when Beehiiv rejects or fails a subscription request.
 */
export class BeehiivSubscriptionError extends Error {
  code: string;
  httpStatus: number;
  retryable: boolean;

  /**
   * Creates a stable Beehiiv API error for endpoint response handling.
   * @param {string} code - Stable internal error code
   * @param {number} httpStatus - Beehiiv HTTP status
   * @param {string} message - Diagnostic error message
   * @param {boolean} retryable - Whether retrying may succeed later
   */
  constructor(
    code: string,
    httpStatus: number,
    message: string,
    retryable: boolean
  ) {
    super(message);
    this.code = code;
    this.httpStatus = httpStatus;
    this.retryable = retryable;
  }
}

/**
 * Parses and validates the Beehiiv secret payload.
 * @return {BeehiivConfig} Provider config for waitlist subscriptions
 */
function getBeehiivConfig(): BeehiivConfig {
  const rawConfig = beehiivConfig.value();
  let parsedConfig: unknown;

  try {
    parsedConfig = JSON.parse(rawConfig) as unknown;
  } catch {
    throw new Error("BEEHIIV_CONFIG must be valid JSON");
  }

  if (!parsedConfig || typeof parsedConfig !== "object") {
    throw new Error("BEEHIIV_CONFIG is missing or invalid");
  }

  const config = parsedConfig as Partial<BeehiivConfig>;

  if (!config.apiKey || !config.publicationId) {
    throw new Error("BEEHIIV_CONFIG must include apiKey and publicationId");
  }

  return {
    apiKey: config.apiKey,
    automationIds: normalizeStringArray(config.automationIds),
    newsletterListIds: normalizeStringArray(config.newsletterListIds),
    publicationId: config.publicationId,
    reactivateExisting: config.reactivateExisting,
    sendWelcomeEmail: config.sendWelcomeEmail,
  };
}

/**
 * Keeps optional Beehiiv ID arrays clean before sending them to the API.
 * @param {unknown} value - Raw array candidate
 * @return {string[] | undefined} Trimmed string IDs or undefined
 */
function normalizeStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const values = value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);

  return values.length > 0 ? values : undefined;
}

/**
 * Safely parses a Beehiiv JSON response body.
 * @param {Response} response - Fetch response
 * @return {Promise<unknown>} Parsed JSON or text fallback
 */
async function parseResponseBody(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) {
    return null;
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

/**
 * Extracts a readable API error message without trusting the exact shape.
 * @param {unknown} body - Parsed Beehiiv response body
 * @return {string} Diagnostic message
 */
function errorMessageFromBody(body: unknown): string {
  if (typeof body === "string") {
    return body;
  }

  if (!body || typeof body !== "object") {
    return "Unknown Beehiiv error";
  }

  const record = body as Record<string, unknown>;
  const candidates = [
    record.error,
    record.message,
    record.detail,
    record.title,
  ];

  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate.trim().length > 0) {
      return candidate;
    }
  }

  return JSON.stringify(body);
}

/**
 * Checks whether Beehiiv is reporting an existing subscription.
 * @param {number} status - HTTP status
 * @param {string} message - Error message body
 * @return {boolean} True when the user is already subscribed
 */
function isExistingSubscriptionResponse(
  status: number,
  message: string
): boolean {
  if (status !== 400 && status !== 409) {
    return false;
  }

  return /already|duplicate|exists|subscribed/i.test(message);
}

/**
 * Reads a string path from a generic response object.
 * @param {unknown} value - Root response object
 * @param {string[]} path - Property path
 * @return {string | null} String value or null
 */
function readStringPath(value: unknown, path: string[]): string | null {
  let current = value;

  for (const key of path) {
    if (!current || typeof current !== "object") {
      return null;
    }

    current = (current as Record<string, unknown>)[key];
  }

  return typeof current === "string" ? current : null;
}

/**
 * Subscribes an email address to the configured Beehiiv publication.
 * @param {string} email - Normalized recipient email
 * @param {string} source - Signup source label
 * @return {Promise<BeehiivSubscriptionResult>} Subscription result
 */
export async function subscribeToBeehiiv(
  email: string,
  source: string
): Promise<BeehiivSubscriptionResult> {
  const config = getBeehiivConfig();
  const payload: Record<string, unknown> = {
    email,
    reactivate_existing: config.reactivateExisting ?? false,
    send_welcome_email: config.sendWelcomeEmail ?? true,
    utm_campaign: "early_access",
    utm_medium: "website",
    utm_source: source,
  };

  if (config.automationIds) {
    payload.automation_ids = config.automationIds;
  }

  if (config.newsletterListIds) {
    payload.newsletter_list_ids = config.newsletterListIds;
  }

  const response = await fetch(
    "https://api.beehiiv.com/v2/publications/" +
      `${encodeURIComponent(config.publicationId)}/subscriptions`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    }
  );
  const responseBody = await parseResponseBody(response);

  if (!response.ok) {
    const message = errorMessageFromBody(responseBody);
    if (isExistingSubscriptionResponse(response.status, message)) {
      return {
        rawStatus: "already_subscribed",
        status: "already_subscribed",
        subscriptionId: null,
      };
    }

    throw new BeehiivSubscriptionError(
      `beehiiv_http_${response.status}`,
      response.status,
      message,
      response.status === 429 || response.status >= 500
    );
  }

  return {
    rawStatus: readStringPath(responseBody, ["data", "status"]) ??
      readStringPath(responseBody, ["status"]),
    status: "subscribed",
    subscriptionId: readStringPath(responseBody, ["data", "id"]) ??
      readStringPath(responseBody, ["id"]),
  };
}
