#!/usr/bin/env node

import { appendFileSync, readFileSync } from "node:fs";

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(1);
}

const [workflowPath] = process.argv.slice(2);

if (!workflowPath) {
  fail("Usage: list-required-check-contexts.mjs <ci-workflow.yml>");
}

let workflow;

try {
  workflow = readFileSync(workflowPath, "utf8");
} catch (error) {
  fail(`Could not read the CI workflow: ${error.message}`);
}

const startMarker = "# required-check-contexts:start\n";
const endMarker = "# required-check-contexts:end";
const startIndex = workflow.indexOf(startMarker);
const endIndex = workflow.indexOf(endMarker, startIndex + startMarker.length);

if (startIndex === -1 || endIndex === -1) {
  fail("The CI workflow must contain one required-check-contexts marker block.");
}

const markedJobs = workflow.slice(startIndex + startMarker.length, endIndex);
const contexts = [...markedJobs.matchAll(/^ {4}name:\s+(?<name>.+?)\s*$/gm)].map(
  (match) => match.groups.name,
);

if (contexts.length === 0) {
  fail("The required-check-contexts marker block must contain at least one named job.");
}

if (contexts.some((context) => context.includes("${{"))) {
  fail("Required check context names must be static strings.");
}

if (new Set(contexts).size !== contexts.length) {
  fail("Required check context names must be unique.");
}

const serialized = JSON.stringify(contexts);

if (process.env.GITHUB_OUTPUT) {
  appendFileSync(process.env.GITHUB_OUTPUT, `required_contexts=${serialized}\n`);
} else {
  console.log(serialized);
}
