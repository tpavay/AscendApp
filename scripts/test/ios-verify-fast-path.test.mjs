/**
 * The contract that keeps `iOS Verify (Staging)` at its measured shape.
 *
 * Every line here is a minute or a colour someone could lose by tidying:
 *
 * - The test build's four command-line overrides are worth ~7.5 of the job's
 *   minutes (17.7 -> ~10 of compile, measured 2026-09-02/03). They live on
 *   the command line and NOT in the project's Staging configuration, because
 *   `deploy-staging.yml` archives that configuration through fastlane and a
 *   TestFlight build has to stay `-O` whole-module.
 * - The `Run tests` and `Build app` steps carry a `timeout-minutes` below the
 *   job's, which is the entire difference between a hung run concluding
 *   `failure` and `cancelled`.
 * - The simulator boot starts in `Select simulator`, and the test script waits
 *   on `bootstatus -b` before its first pass, so the runner's ~4-minute first
 *   boot overlaps the compile instead of following it.
 * - Every pass runs with per-test timeouts, and the allowance is wide enough
 *   for the queue-inflated durations a healthy pass reports (189 s max on the
 *   green run), or a green pass turns red on a fast day.
 * - Each PR job resolves only its own Mixpanel configuration (~55 s each).
 * - The package graph is fetched once per job. Every later `xcodebuild` passes
 *   `-skipPackageUpdates`, which saved 10-66 s per invocation, and only once a
 *   full resolve has run in the same job: a cache restored from an older
 *   `Package.resolved` holds checkouts the flag would not move.
 * - The documented local test command carries the same overrides, so an agent
 *   copying it builds what CI builds.
 */

import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync} from "node:fs";
import {readFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {buildConfigurations, settingValue} from "../lib/monetization-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

const TEST_BUILD_OVERRIDES = [
  "ENABLE_TESTABILITY=YES",
  "SWIFT_OPTIMIZATION_LEVEL=-Onone",
  "SWIFT_COMPILATION_MODE=singlefile",
  "DEBUG_INFORMATION_FORMAT=dwarf",
  "ONLY_ACTIVE_ARCH=YES",
];

async function read(relative) {
  return readFile(`${repositoryRoot}/${relative}`, "utf8");
}

/** The job block from `  <id>:` to the next job at the same indentation. */
function jobBlock(workflow, jobId) {
  const start = workflow.indexOf(`\n  ${jobId}:\n`);
  assert.notEqual(start, -1, `ci.yml must declare the ${jobId} job`);
  const rest = workflow.slice(start + 1);
  const next = rest.slice(1).search(/\n  [a-z][\w-]*:\n/);
  return next === -1 ? rest : rest.slice(0, next + 1);
}

function stepBlock(job, stepName) {
  const lines = job.split("\n");
  const start = lines.indexOf(`      - name: ${stepName}`);
  assert.notEqual(start, -1, `missing step: ${stepName}`);
  const block = [lines[start]];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith("      - ")) break;
    block.push(line);
  }
  return block.join("\n");
}

function minutes(block, pattern) {
  const match = block.match(pattern);
  assert.ok(match, `expected ${pattern} in:\n${block.slice(0, 400)}`);
  return Number(match[1]);
}

test("the test build overrides the Staging configuration on the command line only", async () => {
  const script = await read("scripts/ci/run-ios-test-passes.sh");
  const commonArray = script.match(/common=\(([\s\S]*?)\n\)/)?.[1];
  assert.ok(commonArray, "run-ios-test-passes.sh must build its xcodebuild arguments in a `common` array");

  for (const override of TEST_BUILD_OVERRIDES) {
    assert.match(commonArray, new RegExp(`^\\s*${override.replace(/[-.]/g, "\\$&")}\\s*$`, "m"), override);
  }

  const project = await read("AscendApp.xcodeproj/project.pbxproj");
  const staging = buildConfigurations(project).filter(({name}) => name === "Staging");
  assert.ok(staging.length > 0, "the project must declare Staging build configurations");
  for (const {buildSettings} of staging) {
    assert.notEqual(settingValue(buildSettings, "SWIFT_OPTIMIZATION_LEVEL"), "-Onone", "Staging in the project must stay optimised for the TestFlight archive");
    assert.notEqual(settingValue(buildSettings, "SWIFT_COMPILATION_MODE"), "singlefile", "Staging in the project must stay whole-module for the TestFlight archive");
  }
});

test("both xcodebuild steps time out below their job, so a hang concludes failure", async () => {
  const workflow = await read(".github/workflows/ci.yml");

  for (const [jobId, stepName] of [
    ["ios-verify", "Run tests"],
    ["ios-verify-release", "Build app (Release, unsigned)"],
  ]) {
    const job = jobBlock(workflow, jobId);
    const jobCap = minutes(job, /^    timeout-minutes: (\d+)$/m);
    const stepCap = minutes(stepBlock(job, stepName), /^        timeout-minutes: (\d+)$/m);

    assert.ok(
      stepCap < jobCap,
      `${jobId}: the "${stepName}" step cap (${stepCap}) must sit below the job cap (${jobCap}), or the job-level kill wins and the run is cancelled`
    );
  }
});

test("the simulator boots during the compile and the script waits on it before the first pass", async () => {
  const workflow = await read(".github/workflows/ci.yml");
  const select = stepBlock(jobBlock(workflow, "ios-verify"), "Select simulator");
  const script = await read("scripts/ci/run-ios-test-passes.sh");

  assert.match(select, /xcrun simctl boot "\$simulator_id" >\/dev\/null 2>&1 &/, "the boot must be started and detached from the step's output");

  const build = script.indexOf("build-for-testing");
  const bootstatus = script.indexOf('xcrun simctl bootstatus "$simulator_id" -b');
  const firstPass = script.indexOf("for pass in");
  assert.ok(build !== -1 && bootstatus !== -1 && firstPass !== -1);
  assert.ok(build < bootstatus && bootstatus < firstPass, "bootstatus must wait after the build and before the first pass");
});

/** Each step of a job, in order, with its name and its `env:` mapping. */
function jobSteps(job) {
  const steps = [];
  let inEnv = false;
  for (const line of job.split("\n")) {
    const name = line.match(/^      - name: (.+)$/)?.[1];
    if (name) {
      steps.push({name, env: {}});
      inEnv = false;
    } else if (line.startsWith("      - ")) {
      steps.push({name: null, env: {}});
      inEnv = false;
    } else if (steps.length > 0 && /^        env:\s*$/.test(line)) {
      inEnv = true;
    } else if (inEnv) {
      const entry = line.match(/^          ([A-Z_][A-Z0-9_]*): (.+)$/);
      if (entry) {
        steps.at(-1).env[entry[1]] = entry[2].replace(/^"(.*)"$/, "$1");
      } else if (!/^\s*(#.*)?$/.test(line)) {
        inEnv = false;
      }
    }
  }
  return steps;
}

function writeExecutable(path, contents) {
  writeFileSync(path, contents);
  chmodSync(path, 0o755);
}

/**
 * Runs `run-ios-test-passes.sh` against stub `xcodebuild`, `xcrun` and `sudo`,
 * with its sibling planner, verifier and watchdog replaced by stand-ins that
 * plan two passes and report every pass green. Returns each `xcodebuild`
 * invocation's argv.
 */
function runTestPasses(extraEnv) {
  const sandbox = mkdtempSync(join(tmpdir(), "ios-test-passes-"));
  const ciDir = join(sandbox, "ci");
  const binDir = join(sandbox, "bin");
  const workDir = join(sandbox, "work");
  mkdirSync(ciDir);
  mkdirSync(binDir);
  mkdirSync(workDir);
  const invocations = join(sandbox, "xcodebuild-invocations.jsonl");

  copyFileSync(join(repositoryRoot, "scripts/ci/run-ios-test-passes.sh"), join(ciDir, "run-ios-test-passes.sh"));
  chmodSync(join(ciDir, "run-ios-test-passes.sh"), 0o755);
  writeFileSync(
    join(ciDir, "plan-test-passes.mjs"),
    `import {writeFileSync} from "node:fs";
export const EXECUTED_TEST_FLOOR = 0;
const [prefix] = process.argv.slice(2);
if (prefix) {
  writeFileSync(prefix + "1.txt", "-only-testing:AscendAppTests/IsolatedSuite\\n-parallel-testing-enabled\\nNO\\n");
  writeFileSync(prefix + "2.txt", "-skip-testing:AscendAppTests/IsolatedSuite\\n-parallel-testing-enabled\\nNO\\n");
}
`
  );
  writeFileSync(join(ciDir, "verify-test-pass-result.mjs"), `console.log("executed-tests=1");\n`);
  writeFileSync(join(ciDir, "unfinished-tests.mjs"), "");
  writeExecutable(
    join(ciDir, "run-with-silence-watchdog.sh"),
    `#!/bin/bash
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
shift
exec "$@"
`
  );

  writeExecutable(
    join(binDir, "xcodebuild"),
    `#!/usr/bin/env node
const {appendFileSync, mkdirSync} = require("node:fs");
const argv = process.argv.slice(2);
appendFileSync(${JSON.stringify(invocations)}, JSON.stringify(argv) + "\\n");
const bundle = argv.indexOf("-resultBundlePath");
if (bundle !== -1) mkdirSync(argv[bundle + 1], {recursive: true});
`
  );
  writeExecutable(join(binDir, "xcrun"), "#!/bin/bash\nexit 0\n");
  writeExecutable(join(binDir, "sudo"), "#!/bin/bash\nexit 1\n");
  writeExecutable(join(binDir, "vm_stat"), "#!/bin/bash\nexit 0\n");

  const env = {...process.env, PATH: `${binDir}:${process.env.PATH}`, GITHUB_ACTIONS: "true"};
  delete env.ASCEND_PACKAGE_GRAPH_RESOLVED;
  Object.assign(env, extraEnv);

  const result = spawnSync(join(ciDir, "run-ios-test-passes.sh"), ["SIMULATOR-UDID"], {cwd: workDir, env, encoding: "utf8"});
  assert.equal(result.status, 0, `run-ios-test-passes.sh failed:\n${result.stdout}\n${result.stderr}`);

  return readFileSync(invocations, "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
}

function invocationsFor(invocations, action) {
  return invocations.filter((argv) => argv.at(-1) === action);
}

test("the package graph is fetched once per job and never skipped before a full resolve", () => {
  // Without a caller's word that the graph was resolved, the build is the resolve.
  const cold = runTestPasses({});
  const [coldBuild, ...extraColdBuilds] = invocationsFor(cold, "build-for-testing");
  assert.ok(coldBuild, "the script must build for testing");
  assert.deepEqual(extraColdBuilds, []);
  assert.ok(!coldBuild.includes("-skipPackageUpdates"), "the first resolve in a job must be a full one");

  // Every pass skips updates: the build in front of it resolved the graph.
  const coldPasses = invocationsFor(cold, "test-without-building");
  assert.equal(coldPasses.length, 2, "every planned pass must run");
  for (const pass of coldPasses) {
    assert.ok(pass.includes("-skipPackageUpdates"), `a pass must skip package updates: ${pass.join(" ")}`);
  }

  // Told a full resolve already ran, the build skips it too.
  const warm = runTestPasses({ASCEND_PACKAGE_GRAPH_RESOLVED: "1"});
  const [warmBuild] = invocationsFor(warm, "build-for-testing");
  assert.ok(warmBuild.includes("-skipPackageUpdates"), "the build must skip package updates once the caller resolved the graph");
  for (const pass of invocationsFor(warm, "test-without-building")) {
    assert.ok(pass.includes("-skipPackageUpdates"));
  }
});

test("CI tells the test script the graph is resolved only after a full resolve ran in the job", () => {
  const workflow = readFileSync(join(repositoryRoot, ".github/workflows/ci.yml"), "utf8");
  const steps = jobSteps(jobBlock(workflow, "ios-verify"));
  const runTests = steps.findIndex(({name}) => name === "Run tests");
  const mixpanel = steps.findIndex(({name}) => name === "Verify Mixpanel build destinations");

  assert.notEqual(runTests, -1, "ios-verify must run its tests");
  assert.equal(steps[runTests].env.ASCEND_PACKAGE_GRAPH_RESOLVED, "1");
  assert.ok(mixpanel !== -1 && mixpanel < runTests, "the Mixpanel step must resolve the graph before Run tests");

  // That step's `xcodebuild` must itself be a full resolve.
  const binDir = mkdtempSync(join(tmpdir(), "mixpanel-resolve-"));
  const invocations = join(binDir, "invocations.jsonl");
  writeExecutable(
    join(binDir, "xcodebuild"),
    `#!/usr/bin/env node
require("node:fs").appendFileSync(${JSON.stringify(invocations)}, JSON.stringify(process.argv.slice(2)) + "\\n");
process.stdout.write("[]");
`
  );
  spawnSync(process.execPath, [join(repositoryRoot, "scripts/ci/assert-mixpanel-build-settings.mjs"), "Staging"], {
    cwd: repositoryRoot,
    env: {...process.env, PATH: `${binDir}:${process.env.PATH}`, GITHUB_ACTIONS: "true"},
    encoding: "utf8",
  });
  const resolves = readFileSync(invocations, "utf8").trim().split("\n").map((line) => JSON.parse(line));
  assert.ok(resolves.length > 0, "the Mixpanel step must invoke xcodebuild");
  for (const argv of resolves) {
    assert.ok(!argv.includes("-skipPackageUpdates"), "the resolve the build relies on must be a full one");
  }
});

test("every pass runs with per-test timeouts wide enough for a healthy queue-inflated duration", async () => {
  const script = await read("scripts/ci/run-ios-test-passes.sh");
  const timeouts = script.match(/test_timeouts=\(([\s\S]*?)\n\)/)?.[1];
  assert.ok(timeouts, "the per-test timeout arguments must be declared once, in `test_timeouts`");

  assert.match(timeouts, /-test-timeouts-enabled YES/);
  const allowance = Number(timeouts.match(/-default-test-execution-time-allowance (\d+)/)?.[1]);
  const maximum = Number(timeouts.match(/-maximum-test-execution-time-allowance (\d+)/)?.[1]);

  // 189 s was the longest duration a passing test reported on job
  // 100376172708, and a local pass with the render suites concentrated in
  // one host pushed two past 300 s. The allowance kills and restarts the
  // host and drops the tests in flight, so it must clear those by a margin.
  assert.ok(allowance >= 600, `a ${allowance} s allowance is under the queue-inflated durations a hosted test can report`);
  assert.ok(maximum >= allowance);
  assert.match(script, /"\$\{test_timeouts\[@\]\}"/, "the passes must pass the timeout arguments to xcodebuild");
});

test("the silence watchdog wraps every pass and prints its diagnostics before the kill", async () => {
  const script = await read("scripts/ci/run-ios-test-passes.sh");

  assert.match(script, /run-with-silence-watchdog\.sh/);
  assert.match(script, /--on-stall "\$on_stall"/);
  assert.match(script, /vm_stat/);
  assert.match(script, /unfinished-tests\.mjs/);

  const silence = Number(script.match(/ASCEND_TEST_PASS_SILENCE_SECONDS:-(\d+)/)?.[1]);
  // A healthy pass went at most 96 s between lines on the green run; the
  // wedged ones went 10-29 minutes.
  assert.ok(silence >= 180 && silence <= 600, `a ${silence} s silence limit is outside the measured window`);
});

test("every pass is verified from its result bundle and the job holds an executed-test floor", async () => {
  const script = await read("scripts/ci/run-ios-test-passes.sh");

  assert.match(script, /verify-test-pass-result\.mjs/);
  assert.match(script, /EXECUTED_TEST_FLOOR/);
  assert.match(script, /"\$executed_total" -lt "\$floor"/);
});

test("each PR job resolves only its own Mixpanel configuration", async () => {
  const workflow = await read(".github/workflows/ci.yml");

  for (const [jobId, configuration] of [["ios-verify", "Staging"], ["ios-verify-release", "Release"]]) {
    const step = stepBlock(jobBlock(workflow, jobId), "Verify Mixpanel build destinations");
    assert.match(step, new RegExp(`assert-mixpanel-build-settings\\.mjs ${configuration}$`, "m"), jobId);
  }

  // The processed-bundle proof on the Release job is not the settings check
  // and must survive the trim.
  assert.match(jobBlock(workflow, "ios-verify-release"), /assert-mixpanel-bundle\.mjs Release/);
});

test("the documented local test command carries the same overrides as CI", async () => {
  const claude = await read("CLAUDE.md");
  const command = claude.match(/xcodebuild -project AscendApp\.xcodeproj -scheme "AscendApp-Staging"[\s\S]*?\btest\b/)?.[0];
  assert.ok(command, "CLAUDE.md must document the iOS test command");

  for (const override of TEST_BUILD_OVERRIDES) {
    assert.ok(command.includes(override), `CLAUDE.md's test command must carry ${override}`);
  }
});
