import type {StravaServerConfig} from "./config";

/**
 * OAuth lives on www.strava.com. The REST base moves to
 * https://www.api-v3.strava.com (live from 2027-01-04) and the old host is
 * retired on 2027-06-01, so STRAVA_API_BASE has to change before then.
 * Tokens already travel in headers, which that same retirement requires.
 */
export const STRAVA_OAUTH_BASE = "https://www.strava.com/oauth";
export const STRAVA_API_BASE = "https://www.strava.com/api/v3";

/** The only scope Ascend asks for: create uploads, read nothing. */
export const STRAVA_WRITE_SCOPE = "activity:write";

const REQUEST_TIMEOUT_MS = 15 * 1000;

/**
 * How a failed Strava call should be treated by its caller.
 *
 * - `unauthorized`: the athlete revoked Ascend or the token is dead. Retrying
 *   cannot help; the connection is gone.
 * - `rate_limited`: 429. Retry after the next 15-minute window.
 * - `transient`: network, timeout, or 5xx. Retry with backoff.
 * - `rejected`: Strava refused the request itself (a 4xx other than the
 *   above). Retrying the same request cannot help.
 */
export type StravaFailureKind =
  "unauthorized" | "rate_limited" | "transient" | "rejected";

export class StravaApiError extends Error {
  constructor(
    readonly kind: StravaFailureKind,
    readonly status: number | null,
    message: string
  ) {
    super(message);
    this.name = "StravaApiError";
  }
}

export interface StravaTokenGrant {
  accessToken: string;
  refreshToken: string;
  expiresAtMillis: number;
}

export interface StravaAuthorization extends StravaTokenGrant {
  athleteId: string;
  athleteFirstName: string;
  athleteLastName: string;
  /** The scopes the athlete actually granted, which may be fewer. */
  grantedScopes: string[];
}

export interface StravaUploadRequest {
  name: string;
  description: string;
  externalId: string;
  tcx: string;
}

export interface StravaUploadStatus {
  uploadId: string;
  /** Present once Strava has turned the upload into an activity. */
  activityId: string | null;
  /** Strava's human-readable processing error, when there is one. */
  error: string | null;
}

export interface StravaClient {
  exchangeCode(code: string): Promise<StravaAuthorization>;
  refresh(refreshToken: string): Promise<StravaTokenGrant>;
  revoke(token: string): Promise<void>;
  createUpload(
    accessToken: string,
    upload: StravaUploadRequest
  ): Promise<StravaUploadStatus>;
  getUpload(accessToken: string, uploadId: string): Promise<StravaUploadStatus>;
}

type Fetch = typeof fetch;

/**
 * The production Strava client. Every call is bounded by a timeout and maps
 * its failure onto a {@link StravaFailureKind}, so callers decide retry
 * policy from the kind rather than from raw status codes.
 */
export class HttpStravaClient implements StravaClient {
  constructor(
    private readonly config: StravaServerConfig,
    private readonly fetchImpl: Fetch = fetch
  ) {}

  async exchangeCode(code: string): Promise<StravaAuthorization> {
    const body = await this.tokenRequest({
      grant_type: "authorization_code",
      code,
    });
    const athlete = asRecord(body.athlete);
    const athleteId = integerString(athlete?.id);
    if (!athleteId) {
      throw new StravaApiError(
        "rejected",
        null,
        "Strava token exchange returned no athlete"
      );
    }
    return {
      ...parseTokenGrant(body),
      athleteId,
      athleteFirstName: stringOrEmpty(athlete?.firstname),
      athleteLastName: stringOrEmpty(athlete?.lastname),
      grantedScopes: parseScopes(body.scope),
    };
  }

  async refresh(refreshToken: string): Promise<StravaTokenGrant> {
    return parseTokenGrant(await this.tokenRequest({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }));
  }

  async revoke(token: string): Promise<void> {
    const credentials = Buffer.from(
      `${this.config.clientId}:${this.config.clientSecret}`
    ).toString("base64");
    const response = await this.send(`${STRAVA_OAUTH_BASE}/revoke`, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${credentials}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({token}).toString(),
    });
    await ensureOk(response, "revoke");
  }

  async createUpload(
    accessToken: string,
    upload: StravaUploadRequest
  ): Promise<StravaUploadStatus> {
    const form = new FormData();
    form.set("name", upload.name);
    form.set("description", upload.description);
    form.set("sport_type", "StairStepper");
    form.set("trainer", "1");
    form.set("data_type", "tcx");
    form.set("external_id", upload.externalId);
    form.set(
      "file",
      new Blob([upload.tcx], {type: "application/vnd.garmin.tcx+xml"}),
      `${upload.externalId}.tcx`
    );
    const response = await this.send(`${STRAVA_API_BASE}/uploads`, {
      method: "POST",
      headers: {"Authorization": `Bearer ${accessToken}`},
      body: form,
    });
    return parseUploadStatus(await readJsonText(response, "upload"));
  }

  async getUpload(
    accessToken: string,
    uploadId: string
  ): Promise<StravaUploadStatus> {
    const response = await this.send(
      `${STRAVA_API_BASE}/uploads/${encodeURIComponent(uploadId)}`,
      {headers: {"Authorization": `Bearer ${accessToken}`}}
    );
    return parseUploadStatus(await readJsonText(response, "upload status"));
  }

  private async tokenRequest(
    fields: Record<string, string>
  ): Promise<Record<string, unknown>> {
    const response = await this.send(`${STRAVA_OAUTH_BASE}/token`, {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: new URLSearchParams({
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        ...fields,
      }).toString(),
    });
    // A dead refresh token or a spent authorization code answers 400 with an
    // "invalid" error rather than 401. Either way the grant is gone.
    if (response.status === 400) {
      throw new StravaApiError(
        "unauthorized",
        400,
        `Strava token request refused: ${await safeText(response)}`
      );
    }
    const record = asRecord(JSON.parse(await readJsonText(response, "token")));
    if (!record) {
      throw new StravaApiError("transient", response.status,
        "Strava token response was not an object");
    }
    return record;
  }

  private async send(url: string, init: RequestInit): Promise<Response> {
    try {
      return await this.fetchImpl(url, {
        ...init,
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      throw new StravaApiError(
        "transient",
        null,
        `Strava request failed: ${error instanceof Error ?
          error.message : String(error)}`
      );
    }
  }
}

/**
 * Maps an HTTP status onto how a caller should react to it.
 * @param {number} status HTTP status.
 * @return {StravaFailureKind} The failure kind.
 */
export function failureKindForStatus(status: number): StravaFailureKind {
  if (status === 401 || status === 403) {
    return "unauthorized";
  }
  if (status === 429) {
    return "rate_limited";
  }
  if (status >= 500 || status === 408) {
    return "transient";
  }
  return "rejected";
}

/**
 * Parses an upload status body, keeping every id as a decimal string.
 *
 * Strava warns that upload and activity ids will outgrow a JavaScript number,
 * so they are lifted out of the raw text rather than read after JSON.parse.
 * @param {string} text Raw response body.
 * @return {StravaUploadStatus} Parsed status.
 */
export function parseUploadStatus(text: string): StravaUploadStatus {
  const record = asRecord(safeJsonParse(text));
  const uploadId = typeof record?.id_str === "string" && record.id_str ?
    record.id_str :
    rawIntegerField(text, "id");
  if (!record || !uploadId) {
    throw new StravaApiError("transient", null,
      "Strava upload response carried no upload id");
  }
  return {
    uploadId,
    activityId: record.activity_id === null ||
      record.activity_id === undefined ?
      null :
      rawIntegerField(text, "activity_id"),
    error: typeof record.error === "string" && record.error.length > 0 ?
      record.error :
      null,
  };
}

/**
 * Whether a Strava processing error means the activity already exists.
 * @param {string} error Strava's processing error message.
 * @return {boolean} True for a duplicate.
 */
export function isDuplicateUploadError(error: string): boolean {
  return /duplicate of/i.test(error);
}

/**
 * Splits Strava's scope string, which arrives comma- or space-delimited.
 * @param {unknown} value Raw scope field.
 * @return {Array<string>} Individual scopes.
 */
export function parseScopes(value: unknown): string[] {
  if (typeof value !== "string") {
    return [];
  }
  return value.split(/[\s,]+/).filter((scope) => scope.length > 0);
}

/**
 * Reads a token grant out of a token endpoint body.
 * @param {Record<string, unknown>} body Parsed body.
 * @return {StravaTokenGrant} The grant.
 */
function parseTokenGrant(body: Record<string, unknown>): StravaTokenGrant {
  const accessToken = body.access_token;
  const refreshToken = body.refresh_token;
  const expiresAt = body.expires_at;
  if (typeof accessToken !== "string" || !accessToken ||
    typeof refreshToken !== "string" || !refreshToken ||
    typeof expiresAt !== "number" || !Number.isFinite(expiresAt)) {
    throw new StravaApiError("transient", null,
      "Strava token response was incomplete");
  }
  return {accessToken, refreshToken, expiresAtMillis: expiresAt * 1000};
}

/**
 * Throws the mapped failure for a non-2xx response.
 * @param {Response} response Response.
 * @param {string} label What was being requested, for the message.
 * @return {Promise<void>} Resolves for a 2xx.
 */
async function ensureOk(response: Response, label: string): Promise<void> {
  if (response.ok) {
    return;
  }
  throw new StravaApiError(
    failureKindForStatus(response.status),
    response.status,
    `Strava ${label} failed with ${response.status}: ` +
      await safeText(response)
  );
}

/**
 * Returns the body of a 2xx response, or throws the mapped failure.
 * @param {Response} response Response.
 * @param {string} label What was being requested, for the message.
 * @return {Promise<string>} The raw body.
 */
async function readJsonText(
  response: Response,
  label: string
): Promise<string> {
  await ensureOk(response, label);
  return response.text();
}

/**
 * Reads a body for an error message, bounded so a large HTML error page
 * cannot flood the logs.
 * @param {Response} response Response.
 * @return {Promise<string>} Up to 300 characters of body.
 */
async function safeText(response: Response): Promise<string> {
  try {
    return (await response.text()).slice(0, 300);
  } catch {
    return "";
  }
}

/**
 * Finds an integer-valued field in raw JSON text without losing precision.
 * @param {string} text Raw JSON.
 * @param {string} field Field name.
 * @return {string | null} The digits, or null.
 */
function rawIntegerField(text: string, field: string): string | null {
  const match = new RegExp(`"${field}"\\s*:\\s*(\\d+)`).exec(text);
  return match ? match[1] : null;
}

/**
 * JSON.parse that answers null instead of throwing.
 * @param {string} text Raw JSON.
 * @return {unknown} Parsed value or null.
 */
function safeJsonParse(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/**
 * Narrows an unknown to a plain object.
 * @param {unknown} value Candidate.
 * @return {Record<string, unknown> | null} The object, or null.
 */
function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    null;
}

/**
 * Renders an athlete id as a decimal string.
 * @param {unknown} value Raw id.
 * @return {string | null} Decimal string, or null.
 */
function integerString(value: unknown): string | null {
  if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) {
    return String(value);
  }
  if (typeof value === "string" && /^\d+$/.test(value)) {
    return value;
  }
  return null;
}

/**
 * Narrows an unknown to a string, defaulting to empty.
 * @param {unknown} value Candidate.
 * @return {string} The string or "".
 */
function stringOrEmpty(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
