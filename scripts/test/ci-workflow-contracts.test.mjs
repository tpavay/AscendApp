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
// or the upload lane. Every such workflow shares the one TestFlight app and so
// must serialize on a fixed concurrency group and own a distinct allocator slot.
function isUploadableWorkflow(workflow) {
  return /bundle exec fastlane build_(staging|production)\b/.test(workflow)
    || /\bupload_to_testflight\b/.test(workflow)
    || /\bupload_testflight\b/.test(workflow);
}

function concurrencyGroup(workflow) {
  return workflow.match(/\nconcurrency:\n[ \t]+group:[ \t]*(.+)/)?.[1]?.trim() ?? null;
}

function buildNumberSlot(workflow) {
  const slot = workflow.match(/derive-build-number\.sh[ \t]+(\d+)\b/)?.[1];
  return slot === undefined ? null : Number(slot);
}

async function uploadableWorkflows() {
  const names = (await readdir(workflowsDirectory)).filter((name) => /\.ya?ml$/.test(name)).sort();
  const uploadable = [];

  for (const name of names) {
    const workflow = await readWorkflow(name);
    if (!isUploadableWorkflow(workflow)) continue;

    uploadable.push({name, workflow, group: concurrencyGroup(workflow), slot: buildNumberSlot(workflow)});
  }

  return uploadable;
}

test("every uploadable workflow serializes on a fixed group and owns a unique build-number slot", async () => {
  const slotCount = await scriptConstant("WORKFLOW_SLOT_COUNT");
  const uploadable = await uploadableWorkflows();
  const names = uploadable.map(({name}) => name);

  assert.deepEqual(names, ["deploy-production.yml", "deploy-staging.yml"], `unexpected uploadable workflow set: ${names}`);

  const slots = [];
  for (const {name, workflow, group, slot} of uploadable) {
    assert.ok(group, `${name} must declare a concurrency group so its runs serialize`);
    assert.doesNotMatch(group, /\$\{\{/, `${name} concurrency group must be fixed, not ref-scoped: "${group}"`);

    const deriveIndex = workflow.indexOf("scripts/ci/derive-build-number.sh");
    assert.notEqual(deriveIndex, -1, `${name} must derive its build number`);
    const buildIndex = workflow.search(/bundle exec fastlane build_/);
    if (buildIndex !== -1) {
      assert.ok(deriveIndex < buildIndex, `${name} must derive the build number before archiving`);
    }

    assert.ok(Number.isInteger(slot) && slot >= 0, `${name} must pass a numeric allocator slot`);
    assert.ok(slot < slotCount, `${name} slot ${slot} is outside the allocator range [0, ${slotCount})`);
    slots.push(slot);
  }

  assert.equal(new Set(slots).size, slots.length, `uploadable workflows must use unique slots, got ${slots}`);
});

function deriveBuildNumber(slot, timestamp) {
  const argumentList = timestamp === undefined ? [String(slot)] : [String(slot), String(timestamp)];

  return spawnSync(deriveScript, argumentList, {encoding: "utf8", env: {PATH: "/usr/bin:/bin"}});
}

function derivedValue(slot, timestamp) {
  const result = deriveBuildNumber(slot, timestamp);

  assert.equal(result.status, 0, result.stderr);
  return Number(result.stdout.trim());
}

async function scriptConstant(name) {
  const source = await readFile(deriveScript, "utf8");
  const value = source.match(new RegExp(`^${name}=(\\d+)$`, "m"))?.[1];

  assert.ok(value, `Missing constant ${name}`);
  return Number(value);
}

function deriveStepScript(workflow) {
  const step = sectionBetween(workflow, "      - name: Derive build number\n", "\n      - name: ");
  const body = step.slice(step.indexOf("        run: |\n") + "        run: |\n".length);

  return body.replace(/^ {10}/gm, "");
}

test("deploy build numbers come from the shared derivation, before the archive", async () => {
  for (const {name, workflow, slot} of await uploadableWorkflows()) {
    const deriveIndex = workflow.indexOf("scripts/ci/derive-build-number.sh");
    const buildIndex = workflow.indexOf("bundle exec fastlane build_");

    assert.notEqual(deriveIndex, -1, name);
    assert.ok(deriveIndex < buildIndex, `${name} must derive the build number before archiving`);
    assert.match(deriveStepScript(workflow), new RegExp(`derive-build-number\\.sh ${slot}\\b`), name);
    assert.doesNotMatch(workflow, /BUILD_NUMBER: \$\{\{ github\.run_number \}\}/, name);
    assert.doesNotMatch(workflow, /BUILD_NUMBER: \$\{\{ github\.run_id \}\}/, name);
  }
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
      env: {PATH: "/usr/bin:/bin", GITHUB_ENV: environmentFile},
    });

    assert.notEqual(failed.status, 0, `${name} must fail when derivation fails`);
    assert.doesNotMatch(readFileSync(environmentFile, "utf8"), /BUILD_NUMBER=/, name);

    writeFileSync(stubPath, "#!/bin/sh\necho 4321\n");
    chmodSync(stubPath, 0o755);
    const succeeded = spawnSync("bash", ["-c", stepScript], {
      cwd: root,
      encoding: "utf8",
      env: {PATH: "/usr/bin:/bin", GITHUB_ENV: environmentFile},
    });

    assert.equal(succeeded.status, 0, succeeded.stderr);
    assert.match(readFileSync(environmentFile, "utf8"), /^BUILD_NUMBER=4321$/m, name);
  }
});

test("staging and production never collide, even deriving in the same second", async () => {
  const epoch = await scriptConstant("BUILD_NUMBER_EPOCH_SECONDS");
  const sameSecond = epoch + 20_000_000;
  const staging = derivedValue(0, sameSecond);
  const production = derivedValue(1, sameSecond);

  assert.notEqual(staging, production);
  assert.equal(production, staging + 1);
});

test("later seconds outrank earlier ones regardless of workflow slot", async () => {
  const epoch = await scriptConstant("BUILD_NUMBER_EPOCH_SECONDS");
  const second = epoch + 20_000_000;

  assert.ok(derivedValue(0, second + 1) > derivedValue(1, second));
  assert.ok(derivedValue(0, second + 2) > derivedValue(1, second + 1));
});

test("derived build numbers clear the last build number uploaded from run_number", async () => {
  const floor = await scriptConstant("PREVIOUS_BUILD_NUMBER_FLOOR");
  const epoch = await scriptConstant("BUILD_NUMBER_EPOCH_SECONDS");

  assert.equal(epoch, Date.parse("2026-01-01T00:00:00Z") / 1000);

  for (const slot of [0, 1]) {
    assert.ok(derivedValue(slot) > floor, `slot ${slot} must clear the previous build number floor`);
  }

  const atFloor = deriveBuildNumber(0, epoch + Math.floor(floor / 2));
  assert.notEqual(atFloor.status, 0);
  assert.match(atFloor.stderr, /not above the last uploaded build number/);
});

test("invalid and out-of-range inputs fail the build instead of wrapping", async () => {
  const epoch = await scriptConstant("BUILD_NUMBER_EPOCH_SECONDS");
  const max = await scriptConstant("MAX_BUILD_NUMBER");

  assert.equal(max, 4_294_967_295);
  assert.equal(derivedValue(1, epoch + (max - 1) / 2), max);

  const overLimit = deriveBuildNumber(0, epoch + (max + 1) / 2);
  assert.notEqual(overLimit.status, 0);
  assert.match(overLimit.stderr, /exceeds the App Store limit/);

  const beforeEpoch = deriveBuildNumber(0, epoch - 1);
  assert.notEqual(beforeEpoch.status, 0);
  assert.match(beforeEpoch.stderr, /predates the build-number epoch/);

  for (const slot of ["", "2", "-1", "0x1"]) {
    const badSlot = deriveBuildNumber(slot, epoch + 20_000_000);
    assert.notEqual(badSlot.status, 0, `slot '${slot}' must be rejected`);
    assert.match(badSlot.stderr, /Workflow slot must be 0 \(staging\) or 1 \(production\)/);
  }

  for (const timestamp of ["not-a-number", "1767225600.5"]) {
    const badTimestamp = deriveBuildNumber(0, timestamp);
    assert.notEqual(badTimestamp.status, 0, `timestamp '${timestamp}' must be rejected`);
    assert.match(badTimestamp.stderr, /UTC timestamp must be a non-negative integer/);
  }
});
