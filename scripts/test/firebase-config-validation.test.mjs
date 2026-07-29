import assert from "node:assert/strict";
import {mkdtempSync} from "node:fs";
import {tmpdir} from "node:os";
import {join, resolve} from "node:path";
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

test("Firebase config names the missing key rather than an invented entry", () => {
  const baseConfig = {
    firestore: {rules: "firestore.rules", indexes: "firestore.indexes.json"},
    storage: {rules: "storage.rules"},
    functions: [{source: "functions"}],
    hosting: {public: "web/dist"},
  };
  const fileExists = () => true;

  for (const key of ["functions", "hosting"]) {
    const {[key]: _omitted, ...withoutKey} = baseConfig;

    assert.throws(
      () => validateFirebaseConfig(withoutKey, {repoRoot, fileExists}),
      new RegExp(`firebase\\.json ${key} is missing`),
    );
  }
});

test("a missing configuration file reads as unreadable, not as invalid JSON", () => {
  const emptyRoot = mkdtempSync(join(tmpdir(), "firebase-config-"));

  assert.throws(
    () => validateRepositoryFirebaseConfiguration(emptyRoot),
    /firebase\.json could not be read: ENOENT/,
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

  const {fieldOverrides: _omitted, ...withoutFieldOverrides} = baseConfig;

  assert.doesNotThrow(() => validateFirestoreIndexes(withoutFieldOverrides));
  assert.throws(
    () =>
      validateFirestoreIndexes({...baseConfig, fieldOverrides: {}}),
    /fieldOverrides must be an array/,
  );
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
