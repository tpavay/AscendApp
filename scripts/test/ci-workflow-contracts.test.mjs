import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { readFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

async function readWorkflow(name) {
  return readFile(`${repositoryRoot}/.github/workflows/${name}`, "utf8");
}

const requiredCheckStartMarker = "# required-check-contexts:start\n";
const requiredCheckEndMarker = "# required-check-contexts:end";
const jobNamePattern = /^ {4}name:\s+(?<name>.+?)\s*$/gm;

function requiredCheckContexts(ciWorkflow) {
  const block = sectionBetween(ciWorkflow, requiredCheckStartMarker, requiredCheckEndMarker);
  const contexts = [...block.matchAll(jobNamePattern)].map((match) => match.groups.name);

  assert.ok(contexts.length > 0, "CI must declare at least one required check context");
  assert.equal(
    new Set(contexts).size,
    contexts.length,
    "required check contexts must be unique",
  );

  return contexts;
}

function sectionBetween(source, start, end) {
  const startIndex = source.indexOf(start);
  assert.notEqual(startIndex, -1, `Missing section start: ${start}`);

  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `Missing section end: ${end}`);

  return source.slice(startIndex, endIndex);
}

test("the eligible fallback publishes every required iOS verification context", async () => {
  const ciWorkflow = await readWorkflow("ci.yml");
  const fallbackWorkflow = await readWorkflow("ci-required-check-fallback.yml");
  const contexts = requiredCheckContexts(ciWorkflow);

  assert.deepEqual(contexts, ["iOS Verify (Staging)", "iOS Verify (Release)"]);
  assert.match(
    fallbackWorkflow,
    /required_contexts: \$\{\{ steps\.required-contexts\.outputs\.required_contexts \|\| '\[\]' \}\}/,
  );
  assert.match(
    fallbackWorkflow,
    /context: \$\{\{ fromJSON\(needs\.route\.outputs\.required_contexts\) \}\}/,
  );

  const script = `${repositoryRoot}/scripts/ci/list-required-check-contexts.mjs`;
  const workspace = mkdtempSync(join(tmpdir(), "ascend-required-contexts-"));
  const outputPath = join(workspace, "github-output");
  writeFileSync(outputPath, "");

  const result = spawnSync(process.execPath, [script, `${repositoryRoot}/.github/workflows/ci.yml`], {
    encoding: "utf8",
    env: {...process.env, GITHUB_OUTPUT: outputPath},
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    readFileSync(outputPath, "utf8").trim(),
    `required_contexts=${JSON.stringify(contexts)}`,
  );

  const expandedWorkflowPath = join(workspace, "ci-with-third-required-check.yml");
  const expandedOutputPath = join(workspace, "expanded-github-output");
  writeFileSync(
    expandedWorkflowPath,
    ciWorkflow.replace(
      "# required-check-contexts:end",
      "  ios-verify-third:\n    name: iOS Verify (Third)\n# required-check-contexts:end",
    ),
  );
  writeFileSync(expandedOutputPath, "");

  const expanded = spawnSync(process.execPath, [script, expandedWorkflowPath], {
    encoding: "utf8",
    env: {...process.env, GITHUB_OUTPUT: expandedOutputPath},
  });

  assert.equal(expanded.status, 0, expanded.stderr);
  assert.equal(
    readFileSync(expandedOutputPath, "utf8").trim(),
    `required_contexts=${JSON.stringify([...contexts, "iOS Verify (Third)"])}`,
  );
});

test("an ineligible fallback cannot publish a required verification context", async () => {
  const fallbackWorkflow = await readWorkflow("ci-required-check-fallback.yml");
  const contexts = requiredCheckContexts(await readWorkflow("ci.yml"));
  const safeRoute =
    "needs.route.result == 'success' && needs.route.outputs.fallback_eligible == 'true'";

  assert.ok(fallbackWorkflow.includes(`if: ${safeRoute}`));
  assert.doesNotMatch(fallbackWorkflow, /^\s+paths(?:-ignore)?:/m);

  const inertName = fallbackWorkflow.match(
    new RegExp(
      `^ {4}name: \\$\\{\\{ ${escapeForRegExp(safeRoute)} && matrix\\.context \\|\\| '(?<inert>[^']+)' \\}\\}$`,
      "m",
    ),
  )?.groups?.inert;

  assert.ok(inertName, "the fallback job must fall back to a static non-verification name");
  assert.ok(
    !contexts.includes(inertName),
    `the ineligible fallback name "${inertName}" must not be a required check context`,
  );
});

// The marker block is a positional contract. A required iOS job declared outside
// it is invisible to the derived matrix, so branch protection would demand a
// context the eligible fallback never publishes - the exact defect this routing
// exists to prevent.
test("every required iOS verification job lives inside the marker block", async () => {
  const ciWorkflow = await readWorkflow("ci.yml");
  const startIndex = ciWorkflow.indexOf(requiredCheckStartMarker);
  const endIndex = ciWorkflow.indexOf(requiredCheckEndMarker, startIndex + requiredCheckStartMarker.length);

  assert.notEqual(startIndex, -1, "ci.yml must declare the required-check marker block");
  assert.notEqual(endIndex, -1, "ci.yml must close the required-check marker block");

  const iosJobNames = [];
  for (const match of ciWorkflow.matchAll(jobNamePattern)) {
    const inside = match.index > startIndex && match.index < endIndex;
    const name = match.groups.name;

    if (name.startsWith("iOS Verify")) {
      assert.ok(
        inside,
        `"${name}" must sit inside the required-check-contexts marker block to reach the fallback matrix`,
      );
      iosJobNames.push(name);
    } else {
      assert.ok(
        !inside,
        `"${name}" is inside the required-check-contexts marker block but is not a required iOS verification job`,
      );
    }
  }

  assert.deepEqual(iosJobNames, requiredCheckContexts(ciWorkflow));
});

function escapeForRegExp(source) {
  return source.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

test("CI watches every iOS source and Firebase index definition", async () => {
  const workflow = await readWorkflow("ci.yml");
  const trigger = sectionBetween(workflow, "on:\n", "\nconcurrency:");
  const iosFilter = sectionBetween(workflow, "            ios:\n", "            functions:\n");
  const functionsFilter = sectionBetween(workflow, "            functions:\n", "            scripts:\n");

  assert.match(trigger, /- "AscendLiveActivityWidgets\/\*\*"/);
  assert.match(trigger, /- "scripts\/\*\*"/);
  assert.match(trigger, /- "firestore\.indexes\.json"/);
  assert.match(iosFilter, /- "AscendLiveActivityWidgets\/\*\*"/);
  assert.match(functionsFilter, /- "firestore\.indexes\.json"/);
});

test("deploy workflows watch every artifact and Firebase deployment input", async () => {
  for (const name of ["deploy-staging.yml", "deploy-production.yml"]) {
    const workflow = await readWorkflow(name);
    const trigger = sectionBetween(workflow, "on:\n", "\nconcurrency:");

    assert.match(trigger, /- "AscendLiveActivityWidgets\/\*\*"/, name);
    assert.match(trigger, /- "scripts\/\*\*"/, name);
    assert.match(trigger, /- "firestore\.indexes\.json"/, name);
  }
});

test("production readiness failure is visible to GitHub Actions", async () => {
  const workflow = await readWorkflow("deploy-production.yml");
  const disabledBranch = sectionBetween(
    workflow,
    '          if [ "${{ vars.PRODUCTION_READY }}" != "true" ]; then\n',
    "          else\n"
  );

  assert.match(disabledBranch, /^\s+exit 1$/m);
});

const workflowsDirectory = `${repositoryRoot}.github/workflows`;

// A workflow can put a build on TestFlight if it drives a signed archive lane
// or the upload lane. Every such workflow must serialize for its own App Store
// Connect app and name that app explicitly for allocation and upload.
function isUploadableWorkflow(workflow) {
  return /bundle exec fastlane build_(staging|production)\b/.test(workflow)
    || /\bupload_to_testflight\b/.test(workflow)
    || /\bupload_testflight\b/.test(workflow);
}

function concurrencyGroup(workflow) {
  return workflow.match(/\nconcurrency:\n[ \t]+group:[ \t]*(.+)/)?.[1]?.trim() ?? null;
}

function appStoreTarget(workflow) {
  return {
    appId: workflow.match(/^  APP_STORE_CONNECT_APP_ID: "?(\d+)"?$/m)?.[1] ?? null,
    bundleId: workflow.match(/^  APP_STORE_CONNECT_BUNDLE_ID: ([^\s]+)$/m)?.[1] ?? null,
  };
}

async function uploadableWorkflows() {
  const names = (await readdir(workflowsDirectory)).filter((name) => /\.ya?ml$/.test(name)).sort();
  const uploadable = [];

  for (const name of names) {
    const workflow = await readWorkflow(name);
    if (!isUploadableWorkflow(workflow)) continue;

    uploadable.push({name, workflow, group: concurrencyGroup(workflow), target: appStoreTarget(workflow)});
  }

  return uploadable;
}

test("every uploadable workflow serializes on a fixed group and owns a distinct App Store app", async () => {
  const uploadable = await uploadableWorkflows();
  const names = uploadable.map(({name}) => name);

  assert.deepEqual(names, ["deploy-production.yml", "deploy-staging.yml"], `unexpected uploadable workflow set: ${names}`);

  const appIds = [];
  const bundleIds = [];
  for (const {name, workflow, group, target} of uploadable) {
    assert.ok(group, `${name} must declare a concurrency group so its runs serialize`);
    assert.doesNotMatch(group, /\$\{\{/, `${name} concurrency group must be fixed, not ref-scoped: "${group}"`);

    const deriveIndex = workflow.indexOf("scripts/ci/derive-build-number.sh");
    assert.notEqual(deriveIndex, -1, `${name} must derive its build number`);
    const buildIndex = workflow.search(/bundle exec fastlane build_/);
    if (buildIndex !== -1) {
      assert.ok(deriveIndex < buildIndex, `${name} must derive the build number before archiving`);
    }

    assert.match(target.appId ?? "", /^\d+$/, `${name} must name its App Store Connect app ID`);
    assert.match(target.bundleId ?? "", /^com\./, `${name} must name its App Store bundle ID`);
    appIds.push(target.appId);
    bundleIds.push(target.bundleId);
  }

  assert.deepEqual(appIds.sort(), ["6757202987", "6759919365"]);
  assert.deepEqual(bundleIds.sort(), [
    "com.TylerPavay.AscendApp",
    "com.TylerPavay.AscendApp.staging",
  ]);
  assert.equal(new Set(appIds).size, appIds.length);
  assert.equal(new Set(bundleIds).size, bundleIds.length);
  assert.deepEqual(
    Object.fromEntries(uploadable.map(({name, target}) => [name, target])),
    {
      "deploy-production.yml": {
        appId: "6757202987",
        bundleId: "com.TylerPavay.AscendApp",
      },
      "deploy-staging.yml": {
        appId: "6759919365",
        bundleId: "com.TylerPavay.AscendApp.staging",
      },
    },
  );
});

// A step block runs from its `- name:` line to the next step or to any line that
// dedents out of the step list.
function stepBlock(workflow, stepName) {
  const lines = workflow.split("\n");
  const startIndex = lines.indexOf(`      - name: ${stepName}`);
  assert.notEqual(startIndex, -1, `Missing step: ${stepName}`);

  const block = [lines[startIndex]];
  for (const line of lines.slice(startIndex + 1)) {
    if (line.startsWith("      - ")) break;
    if (line.trim() !== "" && !line.startsWith("       ")) break;
    block.push(line);
  }

  return block.join("\n");
}

function deriveStep(workflow) {
  return stepBlock(workflow, "Derive build number");
}

function deriveStepScript(workflow) {
  const step = deriveStep(workflow);
  const body = step.slice(step.indexOf("        run: |\n") + "        run: |\n".length);

  return body.replace(/^ {10}/gm, "");
}

test("deploy build numbers come from remote app truth before the archive", async () => {
  for (const {name, workflow} of await uploadableWorkflows()) {
    const deriveIndex = workflow.indexOf("scripts/ci/derive-build-number.sh");
    const buildIndex = workflow.indexOf("bundle exec fastlane build_");
    const step = deriveStep(workflow);
    const stepScript = deriveStepScript(workflow);

    assert.notEqual(deriveIndex, -1, name);
    assert.ok(deriveIndex < buildIndex, `${name} must derive the build number before archiving`);
    assert.match(
      stepScript,
      /derive-build-number\.sh "\$APP_STORE_CONNECT_APP_ID" "\$APP_STORE_CONNECT_BUNDLE_ID"/,
      name,
    );
    assert.match(step, /APP_STORE_CONNECT_API_KEY_ID:/, name);
    assert.match(step, /APP_STORE_CONNECT_API_ISSUER_ID:/, name);
    assert.match(step, /APP_STORE_CONNECT_API_KEY:/, name);
    assert.doesNotMatch(workflow, /BUILD_NUMBER: \$\{\{ github\.run_number \}\}/, name);
    assert.doesNotMatch(workflow, /BUILD_NUMBER: \$\{\{ github\.run_id \}\}/, name);
  }
});

test("the TestFlight lane uploads to the same explicit app used by the allocator", async () => {
  const fastfile = await readFile(`${repositoryRoot}/fastlane/Fastfile`, "utf8");

  assert.match(fastfile, /app_identifier: ENV\.fetch\("APP_STORE_CONNECT_BUNDLE_ID"\)/);
  assert.match(fastfile, /apple_id: ENV\.fetch\("APP_STORE_CONNECT_APP_ID"\)/);
});

test("a failed derivation stops the deploy instead of exporting an empty build number", async () => {
  for (const {name, workflow} of await uploadableWorkflows()) {
    const stepScript = deriveStepScript(workflow);
    const root = mkdtempSync(join(tmpdir(), "ascend-build-number-"));
    const stubPath = join(root, "scripts/ci/derive-build-number.sh");
    const environmentFile = join(root, "github-env");
    const outputFile = join(root, "github-output");
    mkdirSync(dirname(stubPath), {recursive: true});
    writeFileSync(environmentFile, "");
    writeFileSync(outputFile, "");

    const runStep = () =>
      spawnSync("bash", ["-c", stepScript], {
        cwd: root,
        encoding: "utf8",
        env: {
          PATH: "/usr/bin:/bin",
          GITHUB_ENV: environmentFile,
          GITHUB_OUTPUT: outputFile,
          APP_STORE_CONNECT_APP_ID: "1234567890",
          APP_STORE_CONNECT_BUNDLE_ID: "com.example.App",
        },
      });

    writeFileSync(stubPath, "#!/bin/sh\necho '::error::boom' >&2\nexit 1\n");
    chmodSync(stubPath, 0o755);
    const failed = runStep();

    assert.notEqual(failed.status, 0, `${name} must fail when derivation fails`);
    assert.doesNotMatch(readFileSync(environmentFile, "utf8"), /BUILD_NUMBER=/, name);

    // A zero exit with no output is the shape that would archive an empty
    // CFBundleVersion, because Ruby treats "" as truthy.
    writeFileSync(stubPath, "#!/bin/sh\nexit 0\n");
    chmodSync(stubPath, 0o755);
    const silent = runStep();

    assert.notEqual(silent.status, 0, `${name} must fail on an empty derived build number`);
    assert.doesNotMatch(readFileSync(environmentFile, "utf8"), /BUILD_NUMBER=/, name);
    assert.doesNotMatch(readFileSync(outputFile, "utf8"), /build_number=/, name);

    writeFileSync(stubPath, "#!/bin/sh\necho 4321\n");
    chmodSync(stubPath, 0o755);
    const succeeded = runStep();

    assert.equal(succeeded.status, 0, succeeded.stderr);
    assert.match(readFileSync(environmentFile, "utf8"), /^BUILD_NUMBER=4321$/m, name);
    assert.match(readFileSync(outputFile, "utf8"), /^build_number=4321$/m, name);
  }
});

// Workflow concurrency serializes runs, not App Store Connect's ingestion of an
// upload that skipped build processing. Without this wait the next queued run
// derives against the pre-upload maximum and mints a duplicate.
test("every uploadable workflow holds its concurrency group until the upload is visible", async () => {
  for (const {name, workflow} of await uploadableWorkflows()) {
    const uploadIndex = workflow.indexOf("bundle exec fastlane upload_testflight");
    const waitIndex = workflow.indexOf("scripts/ci/await-build-visible.mjs");

    assert.notEqual(uploadIndex, -1, `${name} must upload to TestFlight`);
    assert.notEqual(
      waitIndex,
      -1,
      `${name} must wait for the uploaded build to appear in App Store Connect`,
    );
    assert.ok(uploadIndex < waitIndex, `${name} must wait after the upload, not before it`);

    const waitStep = stepBlock(workflow, "Wait for the uploaded build to be visible in App Store Connect");

    assert.match(
      waitStep,
      /BUILD_NUMBER: \$\{\{ needs\.build-ios\.outputs\.build-number \}\}/,
      `${name} must wait on the exact build number the archive job derived`,
    );
    assert.match(
      waitStep,
      /await-build-visible\.mjs "\$APP_STORE_CONNECT_APP_ID" "\$APP_STORE_CONNECT_BUNDLE_ID" "\$BUILD_NUMBER"/,
      name,
    );
    assert.match(waitStep, /if \[ -z "\$BUILD_NUMBER" \]; then/, name);
    assert.match(
      workflow,
      /^    outputs:\n      build-number: \$\{\{ steps\.derive-build-number\.outputs\.build_number \}\}$/m,
      `${name} must publish its derived build number as a job output`,
    );
  }
});
