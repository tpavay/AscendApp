/**
 * The pass-plan contract of `scripts/ci/plan-test-passes.mjs`.
 *
 * `iOS Verify (Staging)` exhausts its runner by memory, not minutes, and the
 * one lever that has ever fixed it is taking the suites that dominate a shared
 * host's memory out of the shared hosts. The plan names them, and the
 * properties this test holds are the ones whose loss is silent:
 *
 * - Every isolated group is one host process, runs its suites serially, runs
 *   before the remainder, and is skipped by the complement pass. A group that
 *   leaked a suite back into the remainder would undo the measurement the
 *   list was built from, and every pass - the remainder included - runs with
 *   `-parallel-testing-enabled NO`, because parallelism measured no faster and
 *   no leaner and is where the main-actor races came from.
 * - The plan is exactly two passes: the movie-export host and everything
 *   else. Since the render suites read screens through `RenderedScreen`
 *   (2026-09-03) the whole remainder fits one host, and every extra pass
 *   costs the job ~2 minutes of host launch for no memory it needs; a third
 *   pass reappearing here is a regression to measure, not a default.
 * - The complement pass skips exactly the suites every other pass names, so a
 *   suite that exists nowhere in the plan still runs, and no suite runs twice.
 * - The executed-test floor stays under the measured baseline and above the
 *   number a silently shrunken plan would produce.
 *
 * The plan is pure data plus a function, so nothing here needs a built test
 * bundle. Whether every name still matches a real suite is proved on CI, from
 * each pass's `.xcresult`, by `verify-test-pass-result.mjs`.
 */

import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtempSync, readFileSync, readdirSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {test} from "node:test";

import {
  EXECUTED_TEST_FLOOR,
  ISOLATED_PASSES,
  namedSuites,
  planTestPasses,
} from "../ci/plan-test-passes.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.resolve(here, "../ci/plan-test-passes.mjs");

function selectors(pass, flag) {
  return pass.arguments
    .filter((argument) => argument.startsWith(`${flag}:`))
    .map((argument) => argument.slice(flag.length + 1));
}

function isSerial(pass) {
  const index = pass.arguments.indexOf("-parallel-testing-enabled");
  return index >= 0 && pass.arguments[index + 1] === "NO";
}

test("every suite is named exactly once, and the movie-export suite keeps its own host", () => {
  const suites = namedSuites();

  assert.equal(new Set(suites).size, suites.length, "a suite is named in more than one pass");
  // The movie suite keeps its own host: three of its five tests each export a
  // real movie, and that cost is the assertion.
  assert.deepEqual(ISOLATED_PASSES, [["ShareComposerBackgroundFillEvidenceTests"]]);
  for (const suite of suites) {
    assert.doesNotMatch(suite, /\//, `${suite} must be a bare suite name; the planner adds the target`);
  }
});

test("each isolated group is one serial pass that runs first", () => {
  const passes = planTestPasses();

  assert.equal(passes.length, ISOLATED_PASSES.length + 1);

  ISOLATED_PASSES.forEach((group, index) => {
    const pass = passes[index];
    assert.deepEqual(
      selectors(pass, "-only-testing"),
      [...group].sort().map((suite) => `AscendAppTests/${suite}`)
    );
    assert.deepEqual(selectors(pass, "-skip-testing"), []);
    assert.equal(isSerial(pass), true, `isolated pass ${index + 1} runs serially`);
    assert.deepEqual(pass.expectedSuites, selectors(pass, "-only-testing"));
  });
});

test("the last pass is the complement: it skips exactly what every other pass runs", () => {
  const passes = planTestPasses();
  const complement = passes[passes.length - 1];
  const runElsewhere = passes
    .slice(0, -1)
    .flatMap((pass) => selectors(pass, "-only-testing"))
    .sort();

  assert.deepEqual(selectors(complement, "-skip-testing"), runElsewhere);
  assert.deepEqual(selectors(complement, "-only-testing"), []);
  // Measured 2026-09-03: the whole remainder took 377 s parallel against 378 s serial and
  // peaked within 20 MB either way, and serial is what makes a hosted test's duration its own.
  assert.equal(isSerial(complement), true, "the remainder runs serially");
  assert.deepEqual(
    complement.expectedSuites,
    [],
    "the complement cannot know its suites in advance; only its executed count is checked"
  );
});

test("the plan is two passes: the movie host and one host for everything else", () => {
  const passes = planTestPasses();

  assert.equal(passes.length, 2, "every extra pass costs ~2 minutes of host launch; measure before adding one");
  assert.deepEqual(selectors(passes[1], "-skip-testing"), [
    "AscendAppTests/ShareComposerBackgroundFillEvidenceTests",
  ]);
});

test("the executed-test floor sits under the measured baseline, not at zero", () => {
  // 1,999 executed on job 100376172708 (2026-09-02). The floor must catch a
  // hundred tests going missing without turning ordinary churn red.
  assert.ok(EXECUTED_TEST_FLOOR <= 1999, "the floor cannot exceed the measured baseline");
  assert.ok(EXECUTED_TEST_FLOOR >= 1800, "a floor this low would let a whole pass vanish");
});

test("the CLI writes one argument-per-line file per pass, in run order", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "plan-test-passes-"));
  const result = spawnSync(process.execPath, [scriptPath, path.join(dir, "test-pass-")], {
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);

  const files = readdirSync(dir)
    .filter((name) => name.startsWith("test-pass-"))
    .sort((a, b) => Number(a.match(/\d+/)[0]) - Number(b.match(/\d+/)[0]));
  const passes = planTestPasses();

  assert.equal(files.length, passes.length);
  files.forEach((name, index) => {
    const lines = readFileSync(path.join(dir, name), "utf8").split("\n").filter(Boolean);
    assert.deepEqual(lines, passes[index].arguments, name);
  });
  assert.match(result.stdout, new RegExp(`executed-test floor: ${EXECUTED_TEST_FLOOR}`));
});

test("a suite named twice refuses to plan", () => {
  const source = readFileSync(scriptPath, "utf8");
  const duplicated = source.replace(
    'export const ISOLATED_PASSES = [["ShareComposerBackgroundFillEvidenceTests"]];',
    'export const ISOLATED_PASSES = [["ShareComposerBackgroundFillEvidenceTests"], ["ShareComposerBackgroundFillEvidenceTests"]];'
  );
  assert.notEqual(duplicated, source);

  const dir = mkdtempSync(path.join(tmpdir(), "plan-test-passes-dup-"));
  const copy = path.join(dir, "plan-test-passes.mjs");
  writeFileSync(copy, duplicated);

  const result = spawnSync(process.execPath, [copy, path.join(dir, "test-pass-")], {
    encoding: "utf8",
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /named in only one pass: ShareComposerBackgroundFillEvidenceTests/);
  assert.equal(readdirSync(dir).filter((name) => name.startsWith("test-pass-")).length, 0);
});

test("the runner and the deploy skill point at the plan, not the enumeration", () => {
  const runner = readFileSync(path.resolve(here, "../ci/run-ios-test-passes.sh"), "utf8");
  const skill = readFileSync(path.resolve(here, "../../.claude/skills/ascend-deploy/SKILL.md"), "utf8");

  for (const [name, text] of [["run-ios-test-passes.sh", runner], ["ascend-deploy", skill]]) {
    assert.match(text, /plan-test-passes\.mjs/, `${name} names the planner`);
    assert.match(text, /ISOLATED_PASSES/, `${name} names the isolated groups`);
    assert.doesNotMatch(text, /split-enumerated-tests/, `${name} still names the deleted splitter`);
  }

  // The header may explain why enumeration is gone; no command may run it.
  assert.doesNotMatch(runner, /^\s*-enumerate-tests\b/m, "the runner still enumerates");
});
