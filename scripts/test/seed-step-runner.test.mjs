import assert from "node:assert/strict";
import {test} from "node:test";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {writeFileSync} from "node:fs";
import {tmpdir} from "node:os";

import {DEFAULT_STEP_TIMEOUT_MS, runSeedStep} from "../lib/seed-step-runner.mjs";

const TEST_DIR = dirname(fileURLToPath(import.meta.url));

/**
 * Writes a throwaway script and returns its path.
 * @param {string} name File name.
 * @param {string} body Script source.
 * @return {string} Absolute path.
 */
function scratchScript(name, body) {
  const path = resolve(tmpdir(), `ascend-seed-step-${process.pid}-${name}`);
  writeFileSync(path, body, "utf8");
  return path;
}

test("a step that finishes reports how long it took", () => {
  const seconds = runSeedStep(
    scratchScript("ok.mjs", "process.exit(0);\n"),
    [],
    {cwd: TEST_DIR, label: "ok-step"}
  );

  assert.ok(seconds >= 0);
});

test("a step that fails fails the recipe and names itself", () => {
  assert.throws(
    () => runSeedStep(scratchScript("fail.mjs", "process.exit(3);\n"), [], {
      cwd: TEST_DIR,
      label: "failing-step",
    }),
    /failing-step exited 3 after/
  );
});

// The reason this module exists. `spawnSync` with no timeout waited on the
// wedged Live Replay seed forever, so the recipe printed nothing and exited
// nothing, and the only way to tell a working seed from a dead one was to sample
// the process with a debugger.
test("a step that never finishes is killed and reported, not waited on", () => {
  const startedAt = Date.now();

  assert.throws(
    () => runSeedStep(resolve(TEST_DIR, "support/wedged-step.mjs"), [], {
      cwd: TEST_DIR,
      label: "wedged-step",
      timeoutMs: 400,
    }),
    /wedged-step made no progress and was killed after .*Nothing after it ran\./s
  );

  assert.ok(Date.now() - startedAt < 20_000, "the runner waited far longer than its own deadline");
});

test("the default wall clock leaves room for a cold half-million-document seed", () => {
  assert.ok(DEFAULT_STEP_TIMEOUT_MS >= 10 * 60 * 1000);
});
