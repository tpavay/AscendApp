/**
 * The silence watchdog that turns a wedged test pass into a diagnosed failure.
 *
 * A host that has exhausted the runner's memory stops writing and stays alive
 * (jobs 100425139180 and 100448384458, 2026-09-02: 10 and 29 minutes of total
 * silence before the job cap killed them as `cancelled`). The watchdog's whole
 * value is in three behaviours a refactor could quietly lose:
 *
 * - a command that keeps writing is never touched, and its exit status passes
 *   straight through, failure included;
 * - a command that goes silent is killed after the silence limit, with the
 *   `--on-stall` hook run first, while the process is still there to inspect;
 * - the kill reaches the command's children, not just the shell that started
 *   them, because `xcodebuild`'s host and bridge are what hold the log open.
 *
 * Run under the same `/bin/bash` 3.2 the macOS runner uses, since the script
 * relies on `set -m` and PIPESTATUS-free constructs for that reason.
 */

import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtempSync, readFileSync} from "node:fs";
import {tmpdir} from "node:os";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {test} from "node:test";

const here = path.dirname(fileURLToPath(import.meta.url));
const watchdog = path.resolve(here, "../ci/run-with-silence-watchdog.sh");

function run({silence, poll = 1, grace = 2, onStall, progressPattern, command}) {
  const dir = mkdtempSync(path.join(tmpdir(), "silence-watchdog-"));
  const log = path.join(dir, "pass.log");
  const args = [watchdog, "--silence", String(silence), "--log", log, "--poll", String(poll), "--grace", String(grace)];
  if (onStall) args.push("--on-stall", onStall);
  if (progressPattern) args.push("--progress-pattern", progressPattern);
  args.push("--", "bash", "-c", command);

  const result = spawnSync("/bin/bash", args, {encoding: "utf8", timeout: 60_000});
  return {...result, dir, log, logText: readFileSync(log, "utf8")};
}

test("a chatty command runs to completion and keeps its own exit status", () => {
  const ok = run({
    silence: 3,
    command: 'for i in 1 2 3 4 5; do echo "tick $i"; sleep 1; done; echo done',
  });
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.logText, /tick 5\ndone/);
  assert.match(ok.stdout, /tick 5/, "output streams to stdout as well as the log");

  const failing = run({silence: 3, command: 'echo "tick"; sleep 1; echo "boom" >&2; exit 7'});
  assert.equal(failing.status, 7, "the command's own failure passes through unchanged");
  assert.match(failing.logText, /boom/, "stderr is captured into the log too");
});

test("a silent command is killed after the silence limit, hook first, children included", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "silence-watchdog-hook-"));
  const marker = path.join(dir, "child.pid");
  const hookOutput = path.join(dir, "hook.txt");
  const started = Date.now();

  const result = run({
    silence: 3,
    onStall: `echo "stall hook ran" >> "${hookOutput}"; echo "stall hook ran"`,
    // A child process that would outlive its parent shell if only the shell
    // were killed; its pid is recorded so the test can check it is gone.
    command: `echo "one line then nothing"; sleep 300 & echo $! > "${marker}"; wait`,
  });

  const elapsed = (Date.now() - started) / 1000;

  assert.equal(result.status, 124, `expected the watchdog's own status, got ${result.status}: ${result.stderr}`);
  assert.ok(elapsed < 30, `killed in ${elapsed}s, not at the command's own 300 s`);
  assert.match(result.stdout, /No output for \d+s while the command is still running/);
  assert.equal(readFileSync(hookOutput, "utf8").trim(), "stall hook ran");
  assert.ok(
    result.stdout.indexOf("stall hook ran") < result.stdout.length,
    "the hook's output reaches the step log"
  );

  const childPid = Number(readFileSync(marker, "utf8").trim());
  assert.ok(childPid > 0);
  const alive = spawnSync("kill", ["-0", String(childPid)]);
  assert.notEqual(alive.status, 0, `child ${childPid} survived the process-group kill`);
});

test("a command that resumes writing before the limit is not killed", () => {
  const result = run({
    silence: 4,
    command: 'echo start; sleep 2; echo again; sleep 2; echo again; sleep 2; echo end',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.logText, /end/);
});

test("with a progress pattern, noise does not count as liveness once progress has begun", () => {
  // A wedged host keeps logging network noise every minute or two; only a
  // test event resets the clock.
  const started = Date.now();
  const result = run({
    silence: 3,
    progressPattern: "^PROGRESS ",
    command: 'echo "PROGRESS one"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "noise $i"; sleep 1; done; echo "PROGRESS two"',
  });
  const elapsed = (Date.now() - started) / 1000;

  assert.equal(result.status, 124, result.stderr);
  assert.ok(elapsed < 9, `killed after ${elapsed}s despite the noise, not at the command's own end`);
  assert.match(result.stdout, /No test progress for \d+s .*\(1 progress lines so far\)/);
});

test("with a progress pattern, any output keeps the command alive until the first progress line", () => {
  // The launch phase before the first test event prints only xcodebuild and
  // simulator chatter, and must not be mistaken for a wedge.
  const result = run({
    silence: 3,
    progressPattern: "^PROGRESS ",
    command: 'for i in 1 2 3 4 5; do echo "launch chatter $i"; sleep 1; done; echo "PROGRESS first"; sleep 1; echo "PROGRESS last"',
  });

  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.logText, /PROGRESS last/);
});

test("with a progress pattern, steady progress is never killed", () => {
  const result = run({
    silence: 3,
    progressPattern: "^PROGRESS ",
    command: 'for i in 1 2 3 4 5 6; do echo "PROGRESS $i"; sleep 1; done',
  });

  assert.equal(result.status, 0, result.stderr);
});

test("usage errors are reported rather than silently running nothing", () => {
  const missing = spawnSync("/bin/bash", [watchdog, "--silence", "5"], {encoding: "utf8"});
  assert.equal(missing.status, 2);
  assert.match(missing.stderr, /usage: run-with-silence-watchdog\.sh/);

  const unknown = spawnSync("/bin/bash", [watchdog, "--bogus", "1", "--", "true"], {encoding: "utf8"});
  assert.equal(unknown.status, 2);
  assert.match(unknown.stderr, /unknown option --bogus/);
});
