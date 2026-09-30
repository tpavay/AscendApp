/**
 * The reads the Functions secret guard makes, over Google's REST APIs.
 *
 * Every read either returns what it found or throws. None of them turns a
 * failure into an empty answer: a grant listing that failed and one that found
 * nothing print the same nothing, and the guard would then approve a deploy
 * with no grants to protect.
 */

import {GoogleApiError} from "./google-rest-client.mjs";
import {secretVersionId} from "./functions-secret-guard.mjs";

const SECRET_MANAGER = "https://secretmanager.googleapis.com/v1";
const CLOUD_FUNCTIONS = "https://cloudfunctions.googleapis.com/v2";
const FIRESTORE = "https://firestore.googleapis.com/v1";
const PAGE_SIZE = 300;

/**
 * Creates the backend for one project.
 * @param {object} input Backend input.
 * @param {{getJson: Function, postJson: Function}} input.client A
 *   `createGoogleRestClient` result.
 * @param {string} input.projectId Firebase project id.
 * @return {object} The reads.
 */
export function createFunctionsSecretBackend({client, projectId}) {
  const documents = `${FIRESTORE}/projects/${projectId}/databases/(default)/documents`;

  return {
    /**
     * Resolves `latest` exactly the way the pinned firebase-tools deploy does,
     * so the answer is the version a deploy would bind.
     * @param {string} secret Secret name.
     * @return {Promise<?{version: string, state: string}>} Null when the
     *   secret does not exist.
     */
    async latestSecretVersion(secret) {
      try {
        const body = await client.getJson(
          `${SECRET_MANAGER}/projects/${projectId}/secrets/${secret}/versions/latest`
        );
        return {version: secretVersionId(body.name), state: String(body.state)};
      } catch (error) {
        if (error instanceof GoogleApiError && error.status === 404) {
          return null;
        }
        throw error;
      }
    },

    /**
     * Reads a version's payload. The caller must never print it.
     * @param {string} secret Secret name.
     * @param {string} version Version id.
     * @return {Promise<string>} The payload.
     */
    async accessSecretVersion(secret, version) {
      const body = await client.getJson(
        `${SECRET_MANAGER}/projects/${projectId}/secrets/${secret}/versions/` +
          `${version}:access`
      );
      const data = body?.payload?.data;
      if (typeof data !== "string") {
        throw new Error(`${secret} version ${version} returned no payload.`);
      }
      return Buffer.from(data, "base64").toString("utf8");
    },

    /**
     * Lists every deployed function with its configuration.
     * @return {Promise<Array<object>>} Cloud Functions v2 resources.
     */
    async listFunctions() {
      const functions = [];
      let pageToken;
      do {
        const query = new URLSearchParams({pageSize: "200"});
        if (pageToken) query.set("pageToken", pageToken);
        const body = await client.getJson(
          `${CLOUD_FUNCTIONS}/projects/${projectId}/locations/-/functions?${query}`
        );
        if (Array.isArray(body.unreachable) && body.unreachable.length > 0) {
          throw new Error(
            `The Cloud Functions API could not reach ${body.unreachable.join(", ")} ` +
              `in ${projectId}, so the bound secret versions are unknown.`
          );
        }
        functions.push(...(body.functions ?? []));
        pageToken = body.nextPageToken;
      } while (pageToken);
      return functions;
    },

    /**
     * Reads every `users/{uid}/entitlements/{entitlementId}` grant.
     * @param {string} entitlementId The entitlement document id.
     * @return {Promise<Array<{uid: string, productId: ?string,
     *   accessUntil: ?string}>>} Grants.
     */
    async listGrants(entitlementId) {
      const grantName = new RegExp(
        `/documents/users/([^/]+)/entitlements/${escapeRegExp(entitlementId)}$`
      );
      const grants = [];
      let cursor = null;
      for (;;) {
        const structuredQuery = {
          from: [{collectionId: "entitlements", allDescendants: true}],
          orderBy: [{field: {fieldPath: "__name__"}, direction: "ASCENDING"}],
          limit: PAGE_SIZE,
        };
        if (cursor) {
          structuredQuery.startAt = {values: [{referenceValue: cursor}], before: false};
        }
        const rows = await client.postJson(`${documents}:runQuery`, {structuredQuery});
        if (!Array.isArray(rows)) {
          throw new Error("A Firestore runQuery response was not an array.");
        }
        const page = rows.filter((row) => row?.document);
        for (const {document} of page) {
          const match = grantName.exec(document.name);
          if (!match) continue;
          const fields = decodeFirestoreFields(document.fields);
          grants.push({
            uid: match[1],
            productId: typeof fields.productId === "string" ? fields.productId : null,
            accessUntil: typeof fields.accessUntil === "string" ? fields.accessUntil : null,
          });
        }
        if (page.length < PAGE_SIZE) break;
        cursor = page[page.length - 1].document.name;
      }
      return grants;
    },

    /**
     * Reads the `comp_grants` ledger `scripts/comp-access.mjs` appends to.
     * @return {Promise<Array<{uid: string, lastAction: ?string,
     *   productId: ?string, landing: ?string}>>} One entry per climber.
     */
    async listCompLedger() {
      const ledger = [];
      let pageToken;
      do {
        const query = new URLSearchParams({pageSize: String(PAGE_SIZE)});
        if (pageToken) query.set("pageToken", pageToken);
        const body = await client.getJson(`${documents}/comp_grants?${query}`);
        for (const document of body.documents ?? []) {
          const fields = decodeFirestoreFields(document.fields);
          const history = Array.isArray(fields.history) ? fields.history : [];
          const last = history.at(-1) ?? {};
          ledger.push({
            uid: document.name.split("/").pop(),
            lastAction: typeof fields.lastAction === "string" ? fields.lastAction : null,
            productId: typeof last.productId === "string" ? last.productId : null,
            landing: typeof last.landing === "string" ? last.landing : null,
          });
        }
        pageToken = body.nextPageToken;
      } while (pageToken);
      return ledger;
    },

    /**
     * Reads one climber's entitlement status, to triage a lost grant.
     * @param {string} uid Firebase uid.
     * @param {string} entitlementId The entitlement document id.
     * @return {Promise<?object>} The status, or null when it does not exist.
     */
    async readEntitlementStatus(uid, entitlementId) {
      try {
        const document = await client.getJson(
          `${documents}/users/${encodeURIComponent(uid)}/entitlement_status/` +
            encodeURIComponent(entitlementId)
        );
        return decodeFirestoreFields(document.fields);
      } catch (error) {
        if (error instanceof GoogleApiError && error.status === 404) {
          return null;
        }
        throw error;
      }
    },
  };
}

/**
 * Decodes a Firestore REST `fields` map into plain values. Timestamps stay
 * ISO strings.
 * @param {object} fields REST fields.
 * @return {object} Plain values.
 */
export function decodeFirestoreFields(fields = {}) {
  return Object.fromEntries(
    Object.entries(fields ?? {}).map(([key, value]) => [key, decodeFirestoreValue(value)])
  );
}

/**
 * Decodes one Firestore REST value.
 * @param {object} value REST value.
 * @return {*} The plain value.
 */
export function decodeFirestoreValue(value) {
  if (value === null || typeof value !== "object") return null;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return value.timestampValue;
  if ("referenceValue" in value) return value.referenceValue;
  if ("nullValue" in value) return null;
  if ("mapValue" in value) return decodeFirestoreFields(value.mapValue.fields);
  if ("arrayValue" in value) {
    return (value.arrayValue.values ?? []).map(decodeFirestoreValue);
  }
  return null;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
