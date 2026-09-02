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

const SENTRY_CLI_VERSION = "3.6.0";

let cachedHelp;

function realSentryCLIHelp() {
  if (cachedHelp === undefined) {
    const result = spawnSync("sentry-cli", ["debug-files", "upload", "--help"], {encoding: "utf8"});
    cachedHelp = result.status === 0 ? result.stdout : null;
  }

  return cachedHelp;
}

// Real option rows put "--name" at column 6, either after four filler spaces or
// after a "-x, " short alias. Wrapped description prose is indented far deeper,
// so this bound keeps sentences like "if --wait or --wait-for is specified"
// from being mistaken for supported options.
function supportedOptions(help) {
  return new Set([...help.matchAll(/^ {2}(?:-[A-Za-z], )? {0,4}(--[a-z][a-z0-9-]*)/gm)].map(([, option]) => option));
}

function uploadCommandOptions() {
  const script = readFileSync(uploadScript, "utf8");
  const invocation = script.match(/"\$\{SENTRY_CLI\}" debug-files upload(?: *\\\n(?:.*\\\n)*.*)?/)?.[0];

  assert.ok(invocation, "could not locate the sentry-cli debug-files upload invocation");
  return [...new Set(invocation.match(/--[a-z][a-z0-9-]*/g) ?? [])];
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

// Run 33434685667 failed twice with nothing but sentry-cli's fallback text,
// "An unknown error occurred", against a file Sentry had merely left queued.
// The distinction the release engineer needs - upload rejected vs. Sentry not
// finished in time - is not in that text, so the script has to add it.
function fakeSentryCLI({exitCode, sleepSeconds = 0}) {
  const root = makeDSYMDirectory();
  const cliPath = join(root, "sentry-cli");
  writeFileSync(cliPath, `#!/bin/sh\nsleep ${sleepSeconds}\nexit ${exitCode}\n`);
  chmodSync(cliPath, 0o755);
  return {root, cliPath};
}

test("a wait budget that expires is reported as a Sentry-side delay, not a rejection", () => {
  const {root, cliPath} = fakeSentryCLI({exitCode: 1, sleepSeconds: 2});

  const result = runUpload({
    CI: "true",
    SENTRY_AUTH_TOKEN: "test-token",
    SENTRY_CLI_PATH: cliPath,
    SENTRY_WAIT_TIMEOUT: "1",
  }, root);

  assert.equal(result.status, 1, "the fail-or-warn behaviour is unchanged");
  assert.match(result.stderr, /most likely uploaded and left queued rather than rejected/);
  assert.match(result.stderr, /most likely reads as "still queued"/);
  assert.match(result.stderr, /status\.sentry\.io/);
  assert.match(result.stderr, /sentry-cli debug-files upload --org ascend-uk --project ascend-ios/);
});

test("a failure inside the wait budget is reported as a likely rejection, with the same re-upload command", () => {
  const {root, cliPath} = fakeSentryCLI({exitCode: 1});

  const result = runUpload({
    CI: "true",
    SENTRY_AUTH_TOKEN: "test-token",
    SENTRY_CLI_PATH: cliPath,
    SENTRY_WAIT_TIMEOUT: "300",
  }, root);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /No SENTRY_WAIT_TIMEOUT=300s wait-budget expiry was reached/);
  assert.match(result.stderr, /most likely a real upload or processing rejection/);
  assert.match(result.stderr, /sentry-cli debug-files upload --org ascend-uk --project ascend-ios/);
  assert.doesNotMatch(result.stderr, /status\.sentry\.io/);
});

// --log-level=debug is the only way to make sentry-cli name the server-side
// state, and it logs request headers whose Authorization redaction keeps the
// token's first 8 characters. This repository is public.
test("the upload never turns on the verbosity that would log part of the auth token", () => {
  assert.ok(!uploadCommandOptions().includes("--log-level"));
});

test("every option the script passes exists in the real sentry-cli", () => {
  const help = realSentryCLIHelp();

  if (help === null) {
    assert.notEqual(
      process.env.CI,
      "true",
      `sentry-cli must be on PATH in CI so this guard runs; install @sentry/cli@${SENTRY_CLI_VERSION}`,
    );
    return;
  }

  const supported = supportedOptions(help);
  const options = uploadCommandOptions();

  assert.ok(supported.has("--wait-for"), "help parsing failed to find a known option");
  assert.ok(options.includes("--wait-for"));
  assert.ok(!options.includes("--wait"), "--wait is mutually exclusive with --wait-for");

  for (const option of options) {
    assert.ok(supported.has(option), `${option} is not a sentry-cli debug-files upload option`);
  }
});

test("every workflow pins the same Sentry CLI version the guard validates against", () => {
  const workflows = ["ci.yml", "deploy-staging.yml", "deploy-production.yml"];

  for (const name of workflows) {
    const workflow = readFileSync(join(repoRoot, ".github/workflows", name), "utf8");
    const pins = [...new Set(workflow.match(/@sentry\/cli@[\w.-]+/g) ?? [])];

    assert.deepEqual(pins, [`@sentry/cli@${SENTRY_CLI_VERSION}`], `${name} must pin @sentry/cli@${SENTRY_CLI_VERSION}`);
  }
});

// A zero budget passes a bare digits-only check and then makes the
// elapsed-vs-budget comparison always true, which would report an instant auth
// rejection as a Sentry-side queue delay.
for (const waitTimeout of ["5m", "-1", "0"]) {
  test(`a wait budget of '${waitTimeout}' is rejected before anything is uploaded`, () => {
    const {root, cliPath} = fakeSentryCLI({exitCode: 0});

    const result = runUpload({
      CI: "true",
      SENTRY_AUTH_TOKEN: "test-token",
      SENTRY_CLI_PATH: cliPath,
      SENTRY_WAIT_TIMEOUT: waitTimeout,
    }, root);

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /SENTRY_WAIT_TIMEOUT must be a whole number of seconds greater than zero/);
  });
}

test("both signed Fastlane lanes upload archive dSYMs", () => {
  const fastfile = readFileSync(join(repoRoot, "fastlane/Fastfile"), "utf8");
  const uploadCalls = fastfile.match(/^\s+upload_sentry_dsyms\(/gm) ?? [];

  assert.equal(uploadCalls.length, 2);
});

for (const workflowName of ["deploy-staging.yml", "deploy-production.yml"]) {
  test(`${workflowName} installs Sentry CLI before building`, () => {
    const workflow = readFileSync(join(repoRoot, ".github/workflows", workflowName), "utf8");
    const installIndex = workflow.indexOf(`npm install --global @sentry/cli@${SENTRY_CLI_VERSION}`);
    const buildIndex = workflow.indexOf("bundle exec fastlane build_");

    assert.notEqual(installIndex, -1);
    assert.ok(installIndex < buildIndex);
  });
}
