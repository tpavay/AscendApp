import assert from "node:assert/strict";
import {resolve} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {
  validateFirebaseConfig,
  validateFirebaseRc,
  validateFirestoreIndexes,
  validateRepositoryFirebaseConfiguration,
} from "../ci/validate-firebase-config.mjs";

const repoRoot = resolve(fileURLToPath(new URL("../..", import.meta.url)));

test("the repository Firebase configuration is structurally valid", () => {
  assert.doesNotThrow(() => validateRepositoryFirebaseConfiguration(repoRoot));
});

test("Firebase config rejects missing or escaping rule files", () => {
  const baseConfig = {
    firestore: {
      rules: "firestore.rules",
      indexes: "firestore.indexes.json",
    },
    storage: {rules: "storage.rules"},
    functions: [{source: "functions"}],
    hosting: {public: "web/dist"},
  };
  const existingFiles = new Set([
    resolve(repoRoot, "firestore.rules"),
    resolve(repoRoot, "firestore.indexes.json"),
    resolve(repoRoot, "storage.rules"),
  ]);
  const fileExists = (path) => existingFiles.has(path);

  assert.doesNotThrow(() =>
    validateFirebaseConfig(baseConfig, {repoRoot, fileExists}),
  );
  assert.throws(
    () =>
      validateFirebaseConfig(
        {
          ...baseConfig,
          firestore: {...baseConfig.firestore, rules: "../firestore.rules"},
        },
        {repoRoot, fileExists},
      ),
    /must stay inside the repository/,
  );
  assert.throws(
    () =>
      validateFirebaseConfig(
        {
          ...baseConfig,
          storage: {rules: "missing-storage.rules"},
        },
        {repoRoot, fileExists},
      ),
    /points to missing file/,
  );
});

test("Firebase aliases require targets for every configured project", () => {
  assert.throws(
    () =>
      validateFirebaseRc({
        projects: {default: "demo-project"},
        targets: {},
      }),
    /targets\.demo-project must be an object/,
  );

  assert.doesNotThrow(() =>
    validateFirebaseRc({
      projects: {default: "demo-project"},
      targets: {
        "demo-project": {
          hosting: {web: ["demo-project"]},
        },
      },
    }),
  );
});

test("Firestore index fields require exactly one supported index mode", () => {
  const baseConfig = {
    indexes: [
      {
        collectionGroup: "workouts",
        queryScope: "COLLECTION",
        fields: [
          {fieldPath: "userId", order: "ASCENDING"},
          {fieldPath: "createdAt", order: "DESCENDING"},
        ],
      },
    ],
    fieldOverrides: [],
  };

  assert.doesNotThrow(() => validateFirestoreIndexes(baseConfig));
  assert.throws(
    () =>
      validateFirestoreIndexes({
        ...baseConfig,
        indexes: [
          {
            ...baseConfig.indexes[0],
            fields: [
              {
                fieldPath: "userId",
                order: "ASCENDING",
                arrayConfig: "CONTAINS",
              },
              {fieldPath: "createdAt", order: "DESCENDING"},
            ],
          },
        ],
      }),
    /must declare exactly one of order or arrayConfig/,
  );
});
