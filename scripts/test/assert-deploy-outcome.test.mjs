import assert from "node:assert/strict";
import test from "node:test";
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";

const SCRIPT = fileURLToPath(
  new URL("../ci/assert-deploy-outcome.sh", import.meta.url)
);

const ALL_STAGES = [
  "production-approval",
  "build-ios",
  "deploy-firebase",
  "upload-testflight",
];

/**
 * Runs the outcome assertion the way the Deploy Status job does.
 * @param {object} input Invocation input.
 * @param {string} input.gate The gate job's result.
 * @param {string} input.ready The gate's readiness output.
 * @param {Record<string, string>} input.stages Stage name to job result.
 * @return {{status: number, output: string}} Exit code and combined output.
 */
function assertOutcome({gate = "success", ready = "true", stages}) {
  const args = [
    SCRIPT,
    gate,
    ready,
    ...Object.entries(stages).map(([name, result]) => `${name}=${result}`),
  ];
  const run = spawnSync("bash", args, {
    encoding: "utf8",
    env: {...process.env, DEPLOY_COMMIT: "b3fe797"},
  });

  return {status: run.status, output: `${run.stdout}${run.stderr}`};
}

/**
 * Builds a stage map with every stage set to the same result.
 * @param {string} result The result to apply.
 * @return {Record<string, string>} The stage map.
 */
function allStages(result) {
  return Object.fromEntries(ALL_STAGES.map((name) => [name, result]));
}

test("a fully successful deploy passes", () => {
  const {status, output} = assertOutcome({stages: allStages("success")});

  assert.equal(status, 0);
  assert.match(output, /Deploy completed/);
});

test("a cancelled stage fails the run, exactly like a failed one", () => {
  const cancelled = assertOutcome({
    stages: {...allStages("success"), "upload-testflight": "cancelled"},
  });
  const failed = assertOutcome({
    stages: {...allStages("success"), "upload-testflight": "failure"},
  });

  assert.equal(cancelled.status, 1);
  assert.equal(failed.status, 1);
  assert.match(cancelled.output, /upload-testflight concluded 'cancelled'/);
  assert.match(failed.output, /upload-testflight concluded 'failure'/);
});

test("a whole-run cancellation names every stage it stopped", () => {
  const {status, output} = assertOutcome({stages: allStages("cancelled")});

  assert.equal(status, 1);
  for (const stage of ALL_STAGES) {
    assert.match(output, new RegExp(`${stage} concluded 'cancelled'`));
  }
  assert.match(output, /did not reach production/);
});

test("the failure annotation names the commit that did not ship", () => {
  const {output} = assertOutcome({
    stages: {...allStages("success"), "deploy-firebase": "cancelled"},
  });

  assert.match(output, /Production did not receive b3fe797/);
});

test("a skipped deploy stage is a failure when the gate is on", () => {
  // `skipped` is how a job whose `needs` were cancelled reports, so treating it
  // as benign would restore exactly the silence this script exists to remove.
  const {status, output} = assertOutcome({
    stages: {...allStages("success"), "upload-testflight": "skipped"},
  });

  assert.equal(status, 1);
  assert.match(output, /upload-testflight concluded 'skipped'/);
});

test("the gate being off is a clean no-op, not a failure", () => {
  const {status, output} = assertOutcome({
    ready: "false",
    stages: allStages("skipped"),
  });

  assert.equal(status, 0);
  assert.match(output, /nothing was deployed, by design/);
});

test("the gate being off does not excuse a stage that ran anyway", () => {
  const {status, output} = assertOutcome({
    ready: "false",
    stages: {...allStages("skipped"), "build-ios": "cancelled"},
  });

  assert.equal(status, 1);
  assert.match(output, /build-ios concluded 'cancelled' rather than being skipped/);
});

test("a cancelled gate is a failure, and no readiness is inferred", () => {
  // A cancelled gate job produces an empty `outputs.ready`; the script must not
  // read that emptiness as "the gate was off, so this no-op is fine".
  const {status, output} = assertOutcome({
    gate: "cancelled",
    ready: "",
    stages: allStages("skipped"),
  });

  assert.equal(status, 1);
  assert.match(output, /deploy gate concluded 'cancelled'/);
});

test("too few arguments is a usage error, not a silent pass", () => {
  const run = spawnSync("bash", [SCRIPT, "success"], {encoding: "utf8"});

  assert.equal(run.status, 2);
});
