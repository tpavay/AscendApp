#!/usr/bin/env node
// Decides whether the CI required-check fallback may claim the required
// `iOS Verify (Staging)` name. Every failure path exits non-zero so the routing
// job fails and the fallback job's `if:` guard keeps it from claiming the name.
//
// This file is argv and stdio plumbing only. Every routing decision, including
// the truncated-diff refusal, lives in the module below so it can be tested.

import { appendFileSync, readFileSync } from "node:fs";

import {
  changedPathsFromApiEntries,
  classifyChangedPaths,
} from "../lib/required-check-routing.mjs";

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(1);
}

const [changedFilesPath, expectedChangedFiles] = process.argv.slice(2);

if (!changedFilesPath || expectedChangedFiles === undefined) {
  fail(
    "Usage: classify-required-check-route.mjs <pull-request-files.json> <expected-changed-file-count>",
  );
}

let entries;

try {
  entries = JSON.parse(readFileSync(changedFilesPath, "utf8"));
} catch (error) {
  fail(`Could not read the pull request file list: ${error.message}`);
}

const changed = changedPathsFromApiEntries(entries, expectedChangedFiles);

if (!changed.ok) {
  fail(changed.reason);
}

let result;

try {
  result = classifyChangedPaths(changed.paths);
} catch (error) {
  fail(`Could not classify the changed paths: ${error.message}`);
}

console.log(result.reason);

for (const path of result.blockedBy) {
  console.log(`  blocked by: ${path}`);
}

if (process.env.GITHUB_OUTPUT) {
  appendFileSync(
    process.env.GITHUB_OUTPUT,
    `fallback_eligible=${result.fallbackEligible}\n`,
  );
}
