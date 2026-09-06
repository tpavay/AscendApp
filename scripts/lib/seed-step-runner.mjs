/**
 * Runs one seed step as a child process, under a wall clock.
 *
 * The recipe is a parent that spawns four seed scripts and waits. When the Live
 * Replay seed wedged, `spawnSync` waited on it forever - so the parent printed
 * nothing, exited nothing, and the only way to tell a working seed from a dead
 * one was to sample the process with a debugger. A step that cannot finish now
 * gets killed, named, and turned into a non-zero exit.
 *
 * The deadline is generous because a cold Live Replay seed legitimately writes
 * half a million documents. What it catches is not slowness, it is silence.
 */

import {spawnSync} from "node:child_process";

/** Wall clock for one seed step. A cold full Live Replay seed runs about three minutes. */
export const DEFAULT_STEP_TIMEOUT_MS = 15 * 60 * 1000;

/**
 * Runs one script and fails the caller when it fails, stalls, or is killed.
 * @param {string} scriptPath Absolute path to the script.
 * @param {string[]} scriptArgs Arguments after the script path.
 * @param {object} options Runner options.
 * @param {string} options.cwd Working directory.
 * @param {string} [options.label] Name used in messages. Defaults to the script path.
 * @param {number} [options.timeoutMs] Wall clock.
 * @return {number} Seconds the step took.
 */
export function runSeedStep(scriptPath, scriptArgs, {
  cwd,
  label = scriptPath,
  timeoutMs = DEFAULT_STEP_TIMEOUT_MS,
}) {
  const startedAt = Date.now();
  const result = spawnSync(process.execPath, [scriptPath, ...scriptArgs], {
    cwd,
    stdio: "inherit",
    timeout: timeoutMs,
    killSignal: "SIGKILL",
  });
  const seconds = (Date.now() - startedAt) / 1000;

  if (result.error?.code === "ETIMEDOUT" || result.signal === "SIGKILL") {
    throw new Error(
      `${label} made no progress and was killed after ${seconds.toFixed(0)}s ` +
      `(limit ${Math.round(timeoutMs / 1000)}s). Nothing after it ran.`
    );
  }

  if (result.error) {
    throw new Error(`${label} could not be started: ${result.error.message}`);
  }

  if (result.signal) {
    throw new Error(`${label} was killed by ${result.signal} after ${seconds.toFixed(0)}s.`);
  }

  if (result.status !== 0) {
    throw new Error(`${label} exited ${result.status} after ${seconds.toFixed(0)}s.`);
  }

  console.log(`< ${label} finished in ${seconds.toFixed(1)}s`);
  return seconds;
}
