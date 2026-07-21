import assert from "node:assert/strict";
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

test("deploy build numbers use the repository-wide run identifier", async () => {
  for (const name of ["deploy-staging.yml", "deploy-production.yml"]) {
    const workflow = await readWorkflow(name);

    assert.match(workflow, /BUILD_NUMBER: \$\{\{ github\.run_id \}\}/, name);
    assert.doesNotMatch(workflow, /BUILD_NUMBER: \$\{\{ github\.run_number \}\}/, name);
  }
});
