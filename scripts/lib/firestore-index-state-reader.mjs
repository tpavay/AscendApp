import {createRequire} from "node:module";
import {join} from "node:path";

// This reader loads private firebase-tools modules, so it is only correct for
// the exact pinned version. Keep in sync with docs/dependency-security.md and
// every `firebase-tools@` pin it lists.
export const PINNED_FIREBASE_TOOLS_VERSION = "15.22.1";

export function createFirestoreIndexStateReader({
  firebaseToolsRoot,
  refreshToken,
  projectId,
  databaseId = "(default)",
}) {
  const require = createRequire(import.meta.url);
  assertPinnedFirebaseTools(require, firebaseToolsRoot);
  const auth = require(join(firebaseToolsRoot, "lib/auth.js"));
  const {FirestoreApi} = require(
    join(firebaseToolsRoot, "lib/firestore/api.js")
  );

  if (typeof auth.setRefreshToken !== "function") {
    throw new Error("Pinned firebase-tools auth API is unavailable");
  }
  if (typeof FirestoreApi !== "function") {
    throw new Error("Pinned firebase-tools Firestore API is unavailable");
  }

  const resolvedRefreshToken = refreshToken ??
    auth.getGlobalDefaultAccount?.()?.tokens?.refresh_token;
  if (
    typeof resolvedRefreshToken !== "string" ||
    resolvedRefreshToken.length === 0
  ) {
    throw new Error(
      "FIREBASE_TOKEN or an authenticated Firebase CLI session is required"
    );
  }

  // firebase-tools 15.22.1's firestore:operations:list command omits the
  // requireAuth hook, so --token is ignored on a clean CI runner. Install the
  // same refresh token explicitly before using its authenticated API client.
  auth.setRefreshToken(resolvedRefreshToken);
  const api = new FirestoreApi();

  return async function readFirestoreIndexState() {
    const [indexes, fields] = await Promise.all([
      api.listIndexes(projectId, databaseId),
      api.listFieldOverrides(projectId, databaseId),
    ]);

    return {
      indexes: indexes.map(normalizeCompositeIndex),
      fieldOverrides: fields.map(normalizeFieldOverride),
    };
  };
}

function assertPinnedFirebaseTools(require, firebaseToolsRoot) {
  let manifest;
  try {
    manifest = require(join(firebaseToolsRoot, "package.json"));
  } catch {
    throw new Error(
      `FIREBASE_TOOLS_ROOT does not hold a package: ${firebaseToolsRoot}`
    );
  }

  if (manifest.name !== "firebase-tools") {
    throw new Error(
      `FIREBASE_TOOLS_ROOT resolved ${manifest.name}, not firebase-tools: ` +
        firebaseToolsRoot
    );
  }
  if (manifest.version !== PINNED_FIREBASE_TOOLS_VERSION) {
    throw new Error(
      `This reader uses private firebase-tools ` +
        `${PINNED_FIREBASE_TOOLS_VERSION} internals, but ` +
        `${firebaseToolsRoot} resolved ${manifest.version}`
    );
  }
}

// firebase-tools throws FirebaseError with a default status of 500 even for
// authentication failures, so the message is checked before any status code.
const DETERMINISTIC_MESSAGE_PATTERN =
  /not yet authenticated|unauthenticated|unauthorized|invalid[_ -]?grant|invalid[_ -]?credential|credentials? (?:are |is )?(?:missing|invalid|expired)|permission[_ ]?denied|insufficient permission|access denied|forbidden|failed to authenticate|caller does not have permission|has not been used in project|is not enabled/i;

const TRANSIENT_STATUS_CODES = new Set([408, 425, 429]);

const TRANSIENT_ERROR_CODES = new Set([
  "EAI_AGAIN",
  "ECONNABORTED",
  "ECONNREFUSED",
  "ECONNRESET",
  "EHOSTUNREACH",
  "ENETDOWN",
  "ENETUNREACH",
  "ENOTFOUND",
  "EPIPE",
  "ETIMEDOUT",
  "UND_ERR_CONNECT_TIMEOUT",
  "UND_ERR_SOCKET",
]);

export function classifyFirestoreReadError(error) {
  const message = typeof error?.message === "string" ? error.message :
    String(error);
  if (DETERMINISTIC_MESSAGE_PATTERN.test(message)) {
    return "deterministic";
  }

  for (const candidate of [error, error?.original]) {
    if (
      typeof candidate?.code === "string" &&
      TRANSIENT_ERROR_CODES.has(candidate.code)
    ) {
      return "transient";
    }
  }

  const status = readStatusCode(error);
  if (typeof status === "number") {
    if (TRANSIENT_STATUS_CODES.has(status) || status >= 500) {
      return "transient";
    }
    if (status >= 400) {
      return "deterministic";
    }
  }

  return "transient";
}

function readStatusCode(error) {
  const candidates = [
    error?.status,
    error?.context?.response?.statusCode,
    error?.context?.response?.status,
    error?.response?.status,
    error?.original?.status,
  ];

  for (const candidate of candidates) {
    if (Number.isInteger(candidate) && candidate >= 100 && candidate < 600) {
      return candidate;
    }
  }
  return undefined;
}

function normalizeCompositeIndex(index) {
  const collectionGroup = resourceSegment(index.name, "collectionGroups");
  return {
    collectionGroup,
    queryScope: index.queryScope,
    fields: index.fields,
    state: index.state ?? "STATE_UNSPECIFIED",
  };
}

function normalizeFieldOverride(field) {
  const collectionGroup = resourceSegment(field.name, "collectionGroups");
  const fieldPath = resourceSegment(field.name, "fields");
  return {
    collectionGroup,
    fieldPath,
    indexes: (field.indexConfig?.indexes ?? []).map((index) => {
      const indexedField = index.fields?.[0] ?? {};
      return {
        queryScope: index.queryScope,
        ...(indexedField.order === undefined ? {} : {
          order: indexedField.order,
        }),
        ...(indexedField.arrayConfig === undefined ? {} : {
          arrayConfig: indexedField.arrayConfig,
        }),
        state: index.state ?? "STATE_UNSPECIFIED",
      };
    }),
  };
}

function resourceSegment(resourceName, marker) {
  if (typeof resourceName !== "string") {
    throw new Error(`Missing Firestore resource name for ${marker}`);
  }
  const parts = resourceName.split("/");
  const markerIndex = parts.lastIndexOf(marker);
  const value = parts[markerIndex + 1];
  if (markerIndex === -1 || value === undefined || value.length === 0) {
    throw new Error(`Cannot parse ${marker} from ${resourceName}`);
  }
  return decodeURIComponent(value);
}
