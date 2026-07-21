import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
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

test("deploy build numbers come from the shared run-id derivation, before the archive", async () => {
  for (const name of ["deploy-staging.yml", "deploy-production.yml"]) {
    const workflow = await readWorkflow(name);
    const deriveIndex = workflow.indexOf("scripts/ci/derive-build-number.sh");
    const buildIndex = workflow.indexOf("bundle exec fastlane build_");

    assert.notEqual(deriveIndex, -1, name);
    assert.ok(deriveIndex < buildIndex, `${name} must derive the build number before archiving`);
    assert.doesNotMatch(workflow, /BUILD_NUMBER: \$\{\{ github\.run_number \}\}/, name);
    assert.doesNotMatch(workflow, /BUILD_NUMBER: \$\{\{ github\.run_id \}\}/, name);
  }
});

const deriveScript = `${repositoryRoot}scripts/ci/derive-build-number.sh`;

function deriveBuildNumber(runId) {
  return spawnSync(deriveScript, [], {encoding: "utf8", env: {PATH: "/usr/bin:/bin", GITHUB_RUN_ID: String(runId)}});
}

async function scriptConstant(name) {
  const source = await readFile(deriveScript, "utf8");
  const value = source.match(new RegExp(`^${name}=(\\d+)$`, "m"))?.[1];

  assert.ok(value, `Missing constant ${name}`);
  return Number(value);
}

test("derived build numbers clear the last build number uploaded from run_number", async () => {
  const epoch = await scriptConstant("RUN_ID_EPOCH");
  const floor = await scriptConstant("PREVIOUS_BUILD_NUMBER_FLOOR");
  // The run ID of the last deploy before this change; every future run ID is larger.
  const result = deriveBuildNumber(29_863_763_672);

  assert.equal(result.status, 0, result.stderr);
  assert.ok(Number(result.stdout.trim()) > floor);
  assert.ok(epoch < 29_863_763_672, "epoch must sit below observed run IDs");
});

test("derivation is monotonic and collision-free for increasing run IDs", async () => {
  const epoch = await scriptConstant("RUN_ID_EPOCH");
  const runIds = [epoch + 1_000, epoch + 1_001, epoch + 500_000, epoch + 4_000_000_000];
  const derived = runIds.map((runId) => {
    const result = deriveBuildNumber(runId);
    assert.equal(result.status, 0, result.stderr);
    return Number(result.stdout.trim());
  });

  assert.equal(new Set(derived).size, derived.length);
  for (let index = 1; index < derived.length; index += 1) {
    assert.ok(derived[index] > derived[index - 1], `${runIds[index]} must derive above ${runIds[index - 1]}`);
  }
});

test("out-of-range run IDs fail the build instead of wrapping", async () => {
  const epoch = await scriptConstant("RUN_ID_EPOCH");
  const max = await scriptConstant("MAX_BUILD_NUMBER");
  const floor = await scriptConstant("PREVIOUS_BUILD_NUMBER_FLOOR");

  assert.equal(max, 4_294_967_295);

  const atLimit = deriveBuildNumber(epoch + max);
  assert.equal(atLimit.status, 0, atLimit.stderr);
  assert.equal(Number(atLimit.stdout.trim()), max);

  const overLimit = deriveBuildNumber(epoch + max + 1);
  assert.notEqual(overLimit.status, 0);
  assert.match(overLimit.stderr, /exceeds the App Store limit/);

  const atEpoch = deriveBuildNumber(epoch);
  assert.notEqual(atEpoch.status, 0);
  assert.match(atEpoch.stderr, /at or below the build-number epoch/);

  const belowFloor = deriveBuildNumber(epoch + floor);
  assert.notEqual(belowFloor.status, 0);
  assert.match(belowFloor.stderr, /not above the last uploaded build number/);

  const notANumber = deriveBuildNumber("29863763672abc");
  assert.notEqual(notANumber.status, 0);
  assert.match(notANumber.stderr, /must be a positive integer/);
});
