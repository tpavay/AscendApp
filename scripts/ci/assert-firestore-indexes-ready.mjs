#!/usr/bin/env node

import {readFile} from "node:fs/promises";

const configPath = process.argv[2] ?? "firestore.indexes.json";
const output = await readStandardInput();
const config = JSON.parse(await readFile(configPath, "utf8"));
const lines = stripAnsi(output).split("\n");

if (!Array.isArray(config.indexes)) {
  throw new Error(`${configPath} does not contain an indexes array`);
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

const missing = config.indexes.filter((index) => {
  const prefix = `[READY] (${index.collectionGroup}) -- `;
  // firebase firestore:indexes --pretty omits the __name__ tiebreak field,
  // including when its direction is explicitly declared in the config.
  const fields = index.fields
    .filter((field) => field.fieldPath !== "__name__")
    .map(fieldToken)
    .join(" ");

  return !lines.some((line) => line.startsWith(prefix) && line.includes(fields));
});

if (missing.length > 0) {
  console.error(
    `${missing.length} of ${config.indexes.length} declared Firestore indexes ` +
      "are not READY:"
  );

  for (const index of missing) {
    console.error(`- ${indexSignature(index)}`);
  }

  process.exitCode = 1;
} else {
  console.log(`All ${config.indexes.length} declared Firestore indexes are READY.`);
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
