/**
 * The boundary this repository's release automation stops at.
 *
 * Everything up to a prepared App Store version record is automated. Pressing Submit for
 * Review is not, and is not going to be: the captain reads the version himself before a
 * build goes in front of App Review, and an iOS binary that reaches the store cannot be
 * rolled back if he was not looking.
 *
 * That is a decision, not an unfinished feature, so it is enforced mechanically rather than
 * left as a comment for the next contributor to "finish". This suite fails if any part of
 * the pipeline gains the power to submit, to release on its own, or to steer a phased
 * rollout unattended.
 */

import assert from "node:assert/strict";
import {readFile, readdir} from "node:fs/promises";
import {join, relative} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

/**
 * Prose describing the boundary has to be allowed to name what it forbids, or the rule
 * could not be documented where it is enforced. Whole-line comments are therefore dropped;
 * a trailing comment after code is not, so `submitForReview() # oops` still fails.
 */
function executableLines(source) {
  return source
    .split("\n")
    .filter((line) => {
      const trimmed = line.trim();
      return (
        trimmed !== "" &&
        !trimmed.startsWith("#") &&
        !trimmed.startsWith("//") &&
        !trimmed.startsWith("*") &&
        !trimmed.startsWith("/*") &&
        !trimmed.startsWith("<!--")
      );
    })
    .join("\n");
}

async function filesUnder(directory, matches) {
  const entries = await readdir(join(repositoryRoot, directory), {
    recursive: true,
    withFileTypes: true,
  });

  return entries
    .filter((entry) => entry.isFile() && matches(entry.name))
    .map((entry) => relative(repositoryRoot, join(entry.parentPath, entry.name)));
}

async function readExecutable(paths) {
  return Promise.all(
    paths.map(async (path) => ({
      path,
      source: executableLines(await readFile(join(repositoryRoot, path), "utf8")),
    })),
  );
}

/** Ways to put a build in front of App Review. None of them may appear anywhere. */
const SUBMISSION_POWERS = [
  {pattern: /reviewSubmissions/, why: "POSTs a review submission to App Store Connect"},
  {pattern: /appStoreVersionSubmissions/, why: "submits an App Store version for review"},
  {pattern: /submit_for_review/, why: "is fastlane's submit-for-review switch"},
  {pattern: /upload_to_app_store/, why: "is fastlane `deliver`, which can submit for review"},
];

/** Ways to ship to users without a human. Forbidden in the automated pipeline. */
const UNATTENDED_RELEASE_POWERS = [
  {pattern: /AFTER_APPROVAL/, why: "releases automatically once Apple approves"},
  {pattern: /appStoreVersionPhasedReleases/, why: "steers a phased rollout"},
  {pattern: /appstore-phased-release\.mjs/, why: "is the manual phased-release operator tool"},
];

test("no script the pipeline runs can submit a build for review", async () => {
  const paths = (await filesUnder("scripts", (name) => name.endsWith(".mjs") || name.endsWith(".sh")))
    // The suite itself has to name what it forbids in order to look for it.
    .filter((path) => !path.startsWith("scripts/test/"));

  assert.ok(paths.length > 20, `expected the scripts directory to be scanned, found ${paths.length}`);

  for (const {path, source} of await readExecutable(paths)) {
    for (const {pattern, why} of SUBMISSION_POWERS) {
      assert.doesNotMatch(
        source,
        pattern,
        `${path} matches ${pattern}, which ${why}. Submitting for review is the captain's, ` +
          "by an explicit decision. Do not automate it.",
      );
    }
  }
});

test("no workflow or fastlane lane can submit, auto-release, or steer a rollout", async () => {
  const paths = [
    // GitHub accepts either extension, so a workflow added as `.yaml` must be scanned too;
    // one that was not would carry a submission step past this guard.
    ...(await filesUnder(
      ".github/workflows",
      (name) => name.endsWith(".yml") || name.endsWith(".yaml"),
    )),
    "fastlane/Fastfile",
  ];

  assert.ok(paths.length > 5, `expected the workflows to be scanned, found ${paths.length}`);

  for (const {path, source} of await readExecutable(paths)) {
    for (const {pattern, why} of [...SUBMISSION_POWERS, ...UNATTENDED_RELEASE_POWERS]) {
      assert.doesNotMatch(
        source,
        pattern,
        `${path} matches ${pattern}, which ${why}. The pipeline stops at a prepared version ` +
          "record; a human takes it from there.",
      );
    }
  }
});

test("the version-preparation workflow prepares a version and nothing further", async () => {
  const workflow = await readFile(
    join(repositoryRoot, ".github/workflows/prepare-app-store-version.yml"),
    "utf8",
  );

  assert.match(
    workflow,
    /node scripts\/appstore-prepare-version\.mjs "\$\{arguments\[@\]\}"/,
    "the workflow must run the preparation script",
  );
  assert.match(
    workflow,
    /workflows: \["Deploy Production"\]/,
    "preparation must chain off the production deploy",
  );
  assert.match(
    workflow,
    /^concurrency:\n  group: prepare-app-store-version\n  cancel-in-progress: false$/m,
    "preparation runs must serialize, and must not be cancelled mid-write",
  );
  assert.doesNotMatch(
    workflow,
    /group: deploy-production\b/,
    "preparation must not sit in the deploy-production concurrency group; waiting for Apple " +
      "to process a build there would displace a queued production deploy",
  );
});

test("a version record this pipeline creates waits for a human to release it", async () => {
  const script = await readFile(
    join(repositoryRoot, "scripts/appstore-prepare-version.mjs"),
    "utf8",
  );

  assert.match(
    executableLines(script),
    /releaseType: "MANUAL"/,
    "a created version must not release itself once Apple approves",
  );
});
