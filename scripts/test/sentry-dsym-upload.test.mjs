import test from "node:test";
import assert from "node:assert/strict";
import {chmodSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "../..");
const uploadScript = join(repoRoot, "scripts/upload-sentry-dsyms.sh");

function makeDSYMDirectory() {
  const root = mkdtempSync(join(tmpdir(), "ascend-sentry-dsym-"));
  mkdirSync(join(root, "AscendApp.app.dSYM"));
  return root;
}

let cachedHelp;

function realSentryCLIHelp() {
  if (cachedHelp === undefined) {
    const result = spawnSync("sentry-cli", ["debug-files", "upload", "--help"], {encoding: "utf8"});
    cachedHelp = result.status === 0 ? result.stdout : null;
  }

  return cachedHelp;
}

function runUpload(environment, dsymPath = makeDSYMDirectory()) {
  return spawnSync(uploadScript, [dsymPath], {
    encoding: "utf8",
    env: {
      PATH: "/usr/bin:/bin",
      ...environment,
    },
  });
}

test("CI fails instead of silently shipping when Sentry CLI is unavailable", () => {
  const root = makeDSYMDirectory();
  const result = runUpload({
    CI: "true",
    SENTRY_AUTH_TOKEN: "test-token",
    SENTRY_CLI_PATH: join(root, "missing-sentry-cli"),
  }, root);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /SENTRY_CLI_PATH is not executable/);
});

test("CI fails when the Sentry auth token is unavailable", () => {
  const result = runUpload({CI: "true"});

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /SENTRY_AUTH_TOKEN is not set/);
});

test("local archives without a token still skip upload", () => {
  const result = runUpload({});

  assert.equal(result.status, 0);
  assert.match(result.stdout, /upload skipped/);
});

test("upload passes the archive dSYMs to Sentry and waits for processing", () => {
  const root = makeDSYMDirectory();
  const cliPath = join(root, "sentry-cli");
  const capturePath = join(root, "arguments.txt");
  writeFileSync(cliPath, "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$SENTRY_TEST_CAPTURE_PATH\"\n");
  chmodSync(cliPath, 0o755);

  const result = runUpload({
    CI: "true",
    SENTRY_AUTH_TOKEN: "test-token",
    SENTRY_CLI_PATH: cliPath,
    SENTRY_TEST_CAPTURE_PATH: capturePath,
  }, root);

  assert.equal(result.status, 0, result.stderr);
  const argumentsText = readFileSync(capturePath, "utf8");
  const argumentsList = argumentsText.trim().split("\n");
  assert.match(argumentsText, /debug-files\nupload/);
  assert.match(argumentsText, /--org\nascend-uk/);
  assert.match(argumentsText, /--project\nascend-ios/);
  assert.match(argumentsText, /--wait-for\n300/);
  assert.ok(!argumentsList.includes("--wait"), "--wait is mutually exclusive with --wait-for");
  assert.equal(argumentsList.at(-1), root);
  assert.doesNotMatch(argumentsText, /test-token/);
});

test("every option the script passes exists in the real sentry-cli", {skip: realSentryCLIHelp() === null}, () => {
  const help = realSentryCLIHelp();
  const script = readFileSync(uploadScript, "utf8");
  const options = [...new Set(script.match(/--[a-z][a-z-]*/g) ?? [])];

  assert.ok(options.includes("--wait-for"));
  for (const option of options) {
    assert.ok(help.includes(`${option} `) || help.includes(`${option}\n`), `${option} is not a sentry-cli option`);
  }
});

test("both signed Fastlane lanes upload archive dSYMs", () => {
  const fastfile = readFileSync(join(repoRoot, "fastlane/Fastfile"), "utf8");
  const uploadCalls = fastfile.match(/^\s+upload_sentry_dsyms\(/gm) ?? [];

  assert.equal(uploadCalls.length, 2);
});

for (const workflowName of ["deploy-staging.yml", "deploy-production.yml"]) {
  test(`${workflowName} installs Sentry CLI before building`, () => {
    const workflow = readFileSync(join(repoRoot, ".github/workflows", workflowName), "utf8");
    const installIndex = workflow.indexOf("npm install --global @sentry/cli@3.6.0");
    const buildIndex = workflow.indexOf("bundle exec fastlane build_");

    assert.notEqual(installIndex, -1);
    assert.ok(installIndex < buildIndex);
    assert.match(workflow, /scripts\/upload-sentry-dsyms\.sh/);
  });
}
