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
import {readFile} from "node:fs/promises";
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

test("the package graph is fetched once per job and never skipped before a full resolve", async () => {
  const workflow = await read(".github/workflows/ci.yml");
  const job = jobBlock(workflow, "ios-verify");
  const script = await read("scripts/ci/run-ios-test-passes.sh");

  // Every pass skips updates: the build in front of it resolved the graph.
  assert.match(script, /^skip_package_updates=\(-skipPackageUpdates\)$/m);
  assert.match(script, /xcodebuild "\$\{common\[@\]\}" "\$\{skip_package_updates\[@\]\}"[^\n]*\\\n(?:[^\n]*\\\n)*\s*test-without-building/);

  // The build skips them only when the caller says a full resolve already ran.
  assert.match(script, /if \[ "\$\{ASCEND_PACKAGE_GRAPH_RESOLVED:-\}" = "1" \]; then\n\s*build_package_resolution=\("\$\{skip_package_updates\[@\]\}"\)/);
  assert.match(script, /xcodebuild "\$\{common\[@\]\}" \$\{build_package_resolution\[@\]\+"\$\{build_package_resolution\[@\]\}"\} build-for-testing/);
  assert.doesNotMatch(script.match(/common=\(([\s\S]*?)\n\)/)?.[1] ?? "", /skipPackageUpdates/, "the flag must never reach the build unconditionally");

  // In CI that caller is the Mixpanel step, which resolves the graph for real
  // and must therefore run before the step that is told it did.
  const runTests = stepBlock(job, "Run tests");
  assert.match(runTests, /^\s+ASCEND_PACKAGE_GRAPH_RESOLVED: "1"$/m);
  const mixpanel = job.indexOf("      - name: Verify Mixpanel build destinations");
  assert.ok(mixpanel !== -1 && mixpanel < job.indexOf("      - name: Run tests"), "the Mixpanel step must resolve the graph before Run tests");
  assert.doesNotMatch(await read("scripts/ci/assert-mixpanel-build-settings.mjs"), /skipPackageUpdates/, "the resolve the build relies on must be a full one");
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
