#!/usr/bin/env node

import {existsSync, readFileSync} from "node:fs";
import {dirname, isAbsolute, relative, resolve} from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

function requireCondition(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function requireObject(value, label) {
  requireCondition(
    value !== null && typeof value === "object" && !Array.isArray(value),
    `${label} must be an object.`,
  );
}

function requireArray(value, label) {
  requireCondition(Array.isArray(value), `${label} must be an array.`);
}

function requireNonEmptyString(value, label) {
  requireCondition(
    typeof value === "string" && value.length > 0,
    `${label} must be a non-empty string.`,
  );
}

function requireConfiguredFile(repoRoot, configuredPath, label, fileExists) {
  requireNonEmptyString(configuredPath, label);

  const absolutePath = resolve(repoRoot, configuredPath);
  const pathFromRoot = relative(repoRoot, absolutePath);

  requireCondition(
    pathFromRoot.length > 0 &&
      !pathFromRoot.startsWith("..") &&
      !isAbsolute(pathFromRoot),
    `${label} must stay inside the repository.`,
  );
  requireCondition(
    fileExists(absolutePath),
    `${label} points to missing file "${configuredPath}".`,
  );
}

export function validateFirebaseConfig(
  config,
  {repoRoot, fileExists = existsSync},
) {
  requireObject(config, "firebase.json");
  requireObject(config.firestore, "firebase.json firestore");
  requireConfiguredFile(
    repoRoot,
    config.firestore.rules,
    "firebase.json firestore.rules",
    fileExists,
  );
  requireConfiguredFile(
    repoRoot,
    config.firestore.indexes,
    "firebase.json firestore.indexes",
    fileExists,
  );

  requireObject(config.storage, "firebase.json storage");
  requireConfiguredFile(
    repoRoot,
    config.storage.rules,
    "firebase.json storage.rules",
    fileExists,
  );

  requireCondition(
    config.functions !== undefined,
    "firebase.json functions is missing.",
  );

  const functionsConfigs = Array.isArray(config.functions)
    ? config.functions
    : [config.functions];
  requireCondition(
    functionsConfigs.length > 0,
    "firebase.json functions must declare at least one codebase.",
  );

  for (const [index, functionsConfig] of functionsConfigs.entries()) {
    requireObject(functionsConfig, `firebase.json functions[${index}]`);
    requireNonEmptyString(
      functionsConfig.source,
      `firebase.json functions[${index}].source`,
    );
  }

  requireCondition(
    config.hosting !== undefined,
    "firebase.json hosting is missing.",
  );

  const hostingConfigs = Array.isArray(config.hosting)
    ? config.hosting
    : [config.hosting];
  requireCondition(
    hostingConfigs.length > 0,
    "firebase.json hosting must declare at least one site.",
  );

  for (const [index, hostingConfig] of hostingConfigs.entries()) {
    requireObject(hostingConfig, `firebase.json hosting[${index}]`);
    requireNonEmptyString(
      hostingConfig.public,
      `firebase.json hosting[${index}].public`,
    );

    for (const field of ["headers", "ignore", "rewrites"]) {
      if (hostingConfig[field] !== undefined) {
        requireArray(
          hostingConfig[field],
          `firebase.json hosting[${index}].${field}`,
        );
      }
    }
  }
}

export function validateFirebaseRc(config) {
  requireObject(config, ".firebaserc");
  requireObject(config.projects, ".firebaserc projects");

  const projectEntries = Object.entries(config.projects);
  requireCondition(
    projectEntries.length > 0,
    ".firebaserc projects must not be empty.",
  );

  for (const [alias, projectId] of projectEntries) {
    requireNonEmptyString(alias, ".firebaserc project alias");
    requireNonEmptyString(projectId, `.firebaserc projects.${alias}`);
  }

  requireObject(config.targets, ".firebaserc targets");

  for (const projectId of new Set(projectEntries.map(([, value]) => value))) {
    const projectTargets = config.targets[projectId];
    requireObject(projectTargets, `.firebaserc targets.${projectId}`);
    requireObject(
      projectTargets.hosting,
      `.firebaserc targets.${projectId}.hosting`,
    );

    for (const [targetName, sites] of Object.entries(projectTargets.hosting)) {
      requireNonEmptyString(
        targetName,
        `.firebaserc targets.${projectId}.hosting target`,
      );
      requireArray(
        sites,
        `.firebaserc targets.${projectId}.hosting.${targetName}`,
      );
      requireCondition(
        sites.length > 0,
        `.firebaserc targets.${projectId}.hosting.${targetName} must not be empty.`,
      );

      for (const site of sites) {
        requireNonEmptyString(
          site,
          `.firebaserc targets.${projectId}.hosting.${targetName} site`,
        );
      }
    }
  }
}

export function validateFirestoreIndexes(config) {
  requireObject(config, "firestore.indexes.json");
  requireArray(config.indexes, "firestore.indexes.json indexes");

  if (config.fieldOverrides !== undefined) {
    requireArray(config.fieldOverrides, "firestore.indexes.json fieldOverrides");
  }

  for (const [index, definition] of config.indexes.entries()) {
    const label = `firestore.indexes.json indexes[${index}]`;
    requireObject(definition, label);
    requireNonEmptyString(
      definition.collectionGroup,
      `${label}.collectionGroup`,
    );
    requireCondition(
      definition.queryScope === "COLLECTION" ||
        definition.queryScope === "COLLECTION_GROUP",
      `${label}.queryScope must be COLLECTION or COLLECTION_GROUP.`,
    );
    requireArray(definition.fields, `${label}.fields`);
    requireCondition(
      definition.fields.length >= 2,
      `${label}.fields must contain at least two fields.`,
    );

    for (const [fieldIndex, field] of definition.fields.entries()) {
      const fieldLabel = `${label}.fields[${fieldIndex}]`;
      requireObject(field, fieldLabel);
      requireNonEmptyString(field.fieldPath, `${fieldLabel}.fieldPath`);

      const hasOrder = field.order !== undefined;
      const hasArrayConfig = field.arrayConfig !== undefined;
      requireCondition(
        hasOrder !== hasArrayConfig,
        `${fieldLabel} must declare exactly one of order or arrayConfig.`,
      );

      if (hasOrder) {
        requireCondition(
          field.order === "ASCENDING" || field.order === "DESCENDING",
          `${fieldLabel}.order must be ASCENDING or DESCENDING.`,
        );
      }

      if (hasArrayConfig) {
        requireCondition(
          field.arrayConfig === "CONTAINS",
          `${fieldLabel}.arrayConfig must be CONTAINS.`,
        );
      }
    }
  }
}

function readJson(repoRoot, fileName) {
  const filePath = resolve(repoRoot, fileName);
  let contents;

  try {
    contents = readFileSync(filePath, "utf8");
  } catch (error) {
    throw new Error(`${fileName} could not be read: ${error.message}`);
  }

  try {
    return JSON.parse(contents);
  } catch (error) {
    throw new Error(`${fileName} is not valid JSON: ${error.message}`);
  }
}

export function validateRepositoryFirebaseConfiguration(repoRoot) {
  validateFirebaseConfig(readJson(repoRoot, "firebase.json"), {repoRoot});
  validateFirebaseRc(readJson(repoRoot, ".firebaserc"));
  validateFirestoreIndexes(readJson(repoRoot, "firestore.indexes.json"));
}

const modulePath = fileURLToPath(import.meta.url);

if (
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url
) {
  const repoRoot = resolve(dirname(modulePath), "../..");
  validateRepositoryFirebaseConfiguration(repoRoot);
  console.log("Firebase configuration is structurally valid.");
}
