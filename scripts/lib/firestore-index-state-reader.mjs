import {createRequire} from "node:module";
import {join} from "node:path";

export function createFirestoreIndexStateReader({
  firebaseToolsRoot,
  refreshToken,
  projectId,
  databaseId = "(default)",
}) {
  const require = createRequire(import.meta.url);
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
