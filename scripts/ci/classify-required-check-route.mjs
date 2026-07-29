#!/usr/bin/env node
// Decides whether the CI required-check fallback may claim the required
// `iOS Verify (Staging)` name. Every failure path exits non-zero so the routing
// job fails and the fallback job's `if:` guard keeps it from claiming the name.

import { appendFileSync, readFileSync } from "node:fs";

import { classifyChangedPaths } from "../lib/required-check-routing.mjs";

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(1);
}

const [changedFilesPath, expectedChangedFiles] = process.argv.slice(2);

if (!changedFilesPath || !expectedChangedFiles) {
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

if (!Array.isArray(entries)) {
  fail("The pull request file list was not a JSON array.");
}

const expected = Number.parseInt(expectedChangedFiles, 10);

if (!Number.isInteger(expected) || expected < 0) {
  fail(`"${expectedChangedFiles}" is not a valid changed-file count.`);
}

const filenames = entries.map((entry) => entry?.filename);

if (filenames.some((name) => typeof name !== "string" || name.length === 0)) {
  fail("The pull request file list contained an entry with no filename.");
}

// The files endpoint caps out at 3000 entries, and a silently truncated diff
// would classify the paths it never saw as absent.
if (filenames.length !== expected) {
  fail(
    `The pull request reports ${expected} changed files but the API listed ${filenames.length}. Refusing to classify a truncated diff.`,
  );
}

// A rename reports only its new path in `filename`, so the old path is pulled in
// separately - moving a Swift file out of AscendApp/ is still an iOS change.
const changedPaths = [
  ...new Set(
    entries.flatMap((entry) =>
      [entry.filename, entry.previous_filename].filter(
        (path) => typeof path === "string" && path.length > 0,
      ),
    ),
  ),
];

let result;

try {
  result = classifyChangedPaths(changedPaths);
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
