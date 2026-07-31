#!/usr/bin/env node

import {readFile} from "node:fs/promises";

const STRUCTURAL_ERROR_EXIT_CODE = 2;

const configPath = process.argv[2] ?? "firestore.indexes.json";
const operationsPath = process.argv[3];
const deployedSpecPath = process.argv[4];
const output = await readStandardInput();

let config;
let missingComposites;
let missingFieldOverrides;
let unreadyFieldOperations;

try {
  config = JSON.parse(await readFile(configPath, "utf8"));
  const lines = stripAnsi(output).split("\n");

  if (!Array.isArray(config.indexes)) {
    throw new Error(`${configPath} does not contain an indexes array`);
  }
  if (!Array.isArray(config.fieldOverrides)) {
    throw new Error(`${configPath} does not contain a fieldOverrides array`);
  }

  const unsupportedScopes = config.indexes.filter(
    (index) => index.queryScope !== "COLLECTION"
  );

  if (unsupportedScopes.length > 0) {
    throw new Error(
      "The Firebase CLI readiness output does not expose query scope, so only " +
        "COLLECTION indexes can be verified by this script"
    );
  }

  missingComposites = config.indexes.filter((index) => {
    const prefix = `[READY] (${index.collectionGroup}) -- `;
    // firebase firestore:indexes --pretty omits the __name__ tiebreak field,
    // including when its direction is explicitly declared in the config.
    const fields = index.fields
      .filter((field) => field.fieldPath !== "__name__")
      .map(fieldToken)
      .join(" ");

    return !lines.some((line) => {
      if (!line.startsWith(prefix + fields)) {
        return false;
      }

      const rest = line.slice(prefix.length + fields.length);
      return rest === "" || rest.startsWith(" ");
    });
  });

  // A field override replaces the field's entire index configuration, so a
  // COLLECTION_GROUP declaration also has to restate every COLLECTION-scoped
  // single-field index the field's queries rely on. Both scopes are verified
  // against the deployed spec below.
  const unsupportedFieldScopes = config.fieldOverrides.flatMap(
    (fieldOverride) => fieldOverride.indexes
      .filter(
        (index) => index.queryScope !== "COLLECTION_GROUP" &&
          index.queryScope !== "COLLECTION"
      )
      .map(() => fieldOverride)
  );
  if (unsupportedFieldScopes.length > 0) {
    throw new Error(
      "Field override query scope must be COLLECTION or COLLECTION_GROUP"
    );
  }

  if (
    config.fieldOverrides.length > 0 &&
    (operationsPath === undefined || deployedSpecPath === undefined)
  ) {
    throw new Error(
      "Pass Firebase firestore:operations:list --json output and " +
        "firestore:indexes --json output so field scope and backfill " +
        "readiness cannot be skipped"
    );
  }

  const deployedSpecPayload = deployedSpecPath === undefined ?
    {status: "success", result: {fieldOverrides: []}} :
    JSON.parse(await readFile(deployedSpecPath, "utf8"));
  if (
    deployedSpecPayload.status !== "success" ||
    !Array.isArray(deployedSpecPayload.result?.fieldOverrides)
  ) {
    throw new Error(
      "Firebase firestore:indexes --json did not return successful " +
        "fieldOverrides"
    );
  }
  missingFieldOverrides = config.fieldOverrides.filter(
    (fieldOverride) => !deployedSpecPayload.result.fieldOverrides.some(
      (deployed) => fieldOverrideMatches(deployed, fieldOverride)
    )
  );

  const operationsPayload = operationsPath === undefined ?
    {status: "success", result: []} :
    JSON.parse(await readFile(operationsPath, "utf8"));
  if (
    operationsPayload.status !== "success" ||
    !Array.isArray(operationsPayload.result)
  ) {
    throw new Error(
      "Firebase firestore:operations:list did not return a successful " +
        "result array"
    );
  }
  const requiredFields = new Set(
    config.fieldOverrides.map(fieldResourceSuffix)
  );
  const latestFieldOperations = new Map();
  for (const operation of operationsPayload.result) {
    const isRelevant =
    typeof operation?.metadata?.["@type"] === "string" &&
    operation.metadata["@type"].endsWith("FieldOperationMetadata") &&
    typeof operation.metadata.field === "string" &&
    [...requiredFields].some((suffix) =>
      operation.metadata.field.endsWith(suffix)
    );
    if (!isRelevant) {
      continue;
    }

    const previous = latestFieldOperations.get(operation.metadata.field);
    if (
      previous === undefined ||
      operationStartTime(operation) >= operationStartTime(previous)
    ) {
      latestFieldOperations.set(operation.metadata.field, operation);
    }
  }
  unreadyFieldOperations = [...latestFieldOperations.values()].filter(
    (operation) =>
      operation.done !== true ||
      operation.error !== undefined ||
      operation.metadata.state !== "SUCCESSFUL"
  );
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(STRUCTURAL_ERROR_EXIT_CODE);
}

const missing = [
  ...missingComposites.map((index) => indexSignature(index)),
  ...missingFieldOverrides.map((fieldOverride) =>
    fieldOverrideSignature(fieldOverride)
  ),
];
const total = config.indexes.length + config.fieldOverrides.length;

if (missing.length > 0 || unreadyFieldOperations.length > 0) {
  console.error(
    `Firestore index readiness failed for ${missing.length} missing or ` +
      `non-READY declaration(s) and ${unreadyFieldOperations.length} ` +
      "unready field operation(s):"
  );

  for (const signature of missing) {
    console.error(`- ${signature}`);
  }
  for (const operation of unreadyFieldOperations) {
    console.error(
      `- ${fieldOperationStatus(operation)} field-index operation: ` +
        operation.metadata.field
    );
  }

  process.exitCode = 1;
} else {
  console.log(`All ${total} declared Firestore indexes are READY.`);
}

function fieldToken(field) {
  const mode = field.order ?? field.arrayConfig;

  if (typeof field.fieldPath !== "string" || typeof mode !== "string") {
    throw new Error(`Unsupported Firestore index field: ${JSON.stringify(field)}`);
  }

  return `(${field.fieldPath},${mode})`;
}

function indexSignature(index) {
  return `(${index.collectionGroup}) -- ${index.fields.map(fieldToken).join(" ")}`;
}

function fieldOverrideMatches(deployed, required) {
  if (
    deployed.collectionGroup !== required.collectionGroup ||
    deployed.fieldPath !== required.fieldPath ||
    !Array.isArray(deployed.indexes) ||
    deployed.indexes.length !== required.indexes.length
  ) {
    return false;
  }

  return required.indexes.every((requiredIndex) =>
    deployed.indexes.some((deployedIndex) =>
      deployedIndex.queryScope === requiredIndex.queryScope &&
      deployedIndex.order === requiredIndex.order &&
      deployedIndex.arrayConfig === requiredIndex.arrayConfig
    )
  );
}

function fieldOverrideMode(index) {
  const mode = index.order ?? index.arrayConfig;
  if (typeof mode !== "string") {
    throw new Error(
      `Unsupported Firestore field override: ${JSON.stringify(index)}`
    );
  }
  return mode;
}

function fieldOverrideSignature(fieldOverride) {
  const modes = fieldOverride.indexes
    .map((index) => `(${fieldOverrideMode(index)},${index.queryScope})`)
    .join(" ");
  return `[${fieldOverride.collectionGroup}.${fieldOverride.fieldPath}] -- ${modes}`;
}

function fieldResourceSuffix(fieldOverride) {
  return `/collectionGroups/${encodeURIComponent(
    fieldOverride.collectionGroup
  )}/fields/${encodeURIComponent(fieldOverride.fieldPath)}`;
}

function operationStartTime(operation) {
  const value = Date.parse(operation?.metadata?.startTime ?? "");
  return Number.isNaN(value) ? 0 : value;
}

function fieldOperationStatus(operation) {
  if (operation.done !== true) {
    return "pending";
  }
  if (operation.error !== undefined) {
    const message = operation.error?.message;
    return typeof message === "string" && message.length > 0 ?
      `failed (${message})` :
      "failed";
  }
  return `terminal-${operation.metadata.state ?? "UNKNOWN"}`;
}

function stripAnsi(value) {
  // eslint-disable-next-line no-control-regex
  return value.replace(/\u001b\[[0-9;]*m/g, "");
}

async function readStandardInput() {
  const chunks = [];

  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  return Buffer.concat(chunks).toString("utf8");
}
