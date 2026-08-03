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

function sectionBetween(source, start, end) {
  const startIndex = source.indexOf(start);
  assert.notEqual(startIndex, -1, `Missing section start: ${start}`);

  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `Missing section end: ${end}`);

  return source.slice(startIndex, endIndex);
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

const deriveScript = `${repositoryRoot}scripts/ci/derive-build-number.sh`;
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

function deriveStep(workflow) {
  return sectionBetween(workflow, "      - name: Derive build number\n", "\n      - name: ");
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
    mkdirSync(dirname(stubPath), {recursive: true});
    writeFileSync(environmentFile, "");

    writeFileSync(stubPath, "#!/bin/sh\necho '::error::boom' >&2\nexit 1\n");
    chmodSync(stubPath, 0o755);
    const failed = spawnSync("bash", ["-c", stepScript], {
      cwd: root,
      encoding: "utf8",
      env: {
        PATH: "/usr/bin:/bin",
        GITHUB_ENV: environmentFile,
        APP_STORE_CONNECT_APP_ID: "1234567890",
        APP_STORE_CONNECT_BUNDLE_ID: "com.example.App",
      },
    });

    assert.notEqual(failed.status, 0, `${name} must fail when derivation fails`);
    assert.doesNotMatch(readFileSync(environmentFile, "utf8"), /BUILD_NUMBER=/, name);

    writeFileSync(stubPath, "#!/bin/sh\necho 4321\n");
    chmodSync(stubPath, 0o755);
    const succeeded = spawnSync("bash", ["-c", stepScript], {
      cwd: root,
      encoding: "utf8",
      env: {
        PATH: "/usr/bin:/bin",
        GITHUB_ENV: environmentFile,
        APP_STORE_CONNECT_APP_ID: "1234567890",
        APP_STORE_CONNECT_BUNDLE_ID: "com.example.App",
      },
    });

    assert.equal(succeeded.status, 0, succeeded.stderr);
    assert.match(readFileSync(environmentFile, "utf8"), /^BUILD_NUMBER=4321$/m, name);
  }
});
