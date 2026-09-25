/**
 * A small authenticated JSON client for the Google REST APIs the deploy gates
 * read: Secret Manager, Cloud Functions and Firestore.
 *
 * Every read has a deadline and a bounded retry budget, because a gate that
 * waits forever on one request holds a production deploy with it, and a read
 * that could not run must never be mistaken for one that found nothing. Only
 * transient failures are retried; a refusal (400, 401, 403, 404) is an answer
 * and is returned to the caller at once.
 *
 * Error messages carry the method, the URL and Google's own error text, never a
 * response body: a Secret Manager `:access` response IS the secret.
 */

export const GOOGLE_REQUEST_TIMEOUT_MS = 30_000;
export const GOOGLE_RETRY_DELAYS_MS = Object.freeze([2_000, 8_000]);

const TRANSIENT_STATUS_CODES = new Set([408, 425, 429, 500, 502, 503, 504]);

export class GoogleApiError extends Error {
  /**
   * @param {object} input Error input.
   * @param {string} input.message Human-readable description.
   * @param {?number} input.status HTTP status, or null when none arrived.
   * @param {boolean} input.transient Whether a retry could succeed.
   */
  constructor({message, status, transient}) {
    super(message);
    this.name = "GoogleApiError";
    this.status = status;
    this.transient = transient;
  }
}

/**
 * Creates the client.
 * @param {object} input Client input.
 * @param {function(): Promise<string>} input.getAccessToken Bearer source.
 * @param {string} input.quotaProjectId Project billed for the requests. The
 *   Firebase CLI's OAuth client belongs to Google's own project, where
 *   Firestore is not enabled, so an unattributed request is refused.
 * @param {typeof fetch} [input.fetchImpl] Fetch implementation.
 * @param {function(number): Promise<void>} [input.sleep] Waits between tries.
 * @param {number} [input.timeoutMs] Per-attempt deadline.
 * @param {Array<number>} [input.retryDelaysMs] Delay before each retry.
 * @return {{getJson: Function, postJson: Function}} The client.
 */
export function createGoogleRestClient({
  getAccessToken,
  quotaProjectId,
  fetchImpl = fetch,
  sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
  timeoutMs = GOOGLE_REQUEST_TIMEOUT_MS,
  retryDelaysMs = GOOGLE_RETRY_DELAYS_MS,
}) {
  if (typeof getAccessToken !== "function") {
    throw new TypeError("createGoogleRestClient requires getAccessToken");
  }
  if (typeof quotaProjectId !== "string" || quotaProjectId.length === 0) {
    throw new TypeError("createGoogleRestClient requires quotaProjectId");
  }

  async function attempt(method, url, body) {
    const accessToken = await getAccessToken();
    let response;
    try {
      response = await fetchImpl(url, {
        method,
        headers: {
          "Accept": "application/json",
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
          "x-goog-user-project": quotaProjectId,
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      throw new GoogleApiError({
        message: `${method} ${url} could not complete: ` +
          `${error?.name === "TimeoutError" ?
            `no response within ${Math.round(timeoutMs / 1000)}s` :
            error?.message ?? String(error)}`,
        status: null,
        transient: true,
      });
    }

    const text = await response.text();
    if (!response.ok) {
      throw new GoogleApiError({
        message: `${method} ${url} failed with HTTP ${response.status}` +
          `${googleErrorMessage(text)}`,
        status: response.status,
        transient: TRANSIENT_STATUS_CODES.has(response.status),
      });
    }

    try {
      return JSON.parse(text);
    } catch {
      throw new GoogleApiError({
        message: `${method} ${url} returned HTTP ${response.status} with a ` +
          "body that is not JSON",
        status: response.status,
        transient: false,
      });
    }
  }

  async function request(method, url, body) {
    for (let index = 0; ; index += 1) {
      try {
        return await attempt(method, url, body);
      } catch (error) {
        const retryable = error instanceof GoogleApiError && error.transient;
        if (!retryable || index >= retryDelaysMs.length) {
          throw error;
        }
        await sleep(retryDelaysMs[index]);
      }
    }
  }

  return {
    getJson: (url) => request("GET", url),
    postJson: (url, body) => request("POST", url, body),
  };
}

/**
 * Pulls Google's own error message out of an error body.
 *
 * Only the `error.message` string is quoted. A successful body is never passed
 * here, and an error body carries no payload, so nothing secret can surface.
 * @param {string} text Raw error body.
 * @return {string} ": <message>", or "" when there is none.
 */
function googleErrorMessage(text) {
  try {
    const message = JSON.parse(text)?.error?.message;
    return typeof message === "string" && message.length > 0 ?
      `: ${message.replace(/\s+/g, " ").slice(0, 300)}` :
      "";
  } catch {
    return "";
  }
}
