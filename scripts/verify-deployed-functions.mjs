#!/usr/bin/env node
/**
 * Asserts that a Firebase project has exactly the Cloud Functions the checked
 * out source exports - no more, no fewer.
 *
 * A deploy step reports on the work it was asked to do. It cannot report the
 * work a cancelled pipeline never asked for, which is why production spent two
 * weeks missing `cleanupDeletedUserData`, `onWorkoutWritten` and
 * `unsubscribeFromEmails` with a green deploy log behind it. Run this after
 * `firebase deploy` so the job's exit code reflects the project's real state.
 *
 * Usage:
 *   node scripts/verify-deployed-functions.mjs --project <projectId> [options]
 *
 *   --project <id>        Firebase project id. Required.
 *   --index <path>        Functions entry point. Default functions/src/index.ts.
 *   --deployed-json <p>   Read `functions:list --json` output from a file
 *                         instead of invoking the CLI.
 *   --warn-only           Report the diff but exit 0.
 *
 * Honours FIREBASE_TOKEN, matching the deploy step.
 */

import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import process from "node:process";
import {
  diffDeployedFunctions,
  formatFunctionsDiff,
  inactiveDeployedFunctions,
  parseDeployedFunctions,
  parseExportedFunctionNames,
} from "./lib/deployed-functions.mjs";

/** Pinned to the version both deploy workflows use. */
const FIREBASE_TOOLS = "firebase-tools@15.22.1";

/**
 * Parses the supported flags out of argv.
 * @param {Array<string>} argv Raw arguments.
 * @return {object} Parsed options.
 */
function parseArgs(argv) {
  const options = {
    projectId: null,
    indexPath: "functions/src/index.ts",
    deployedJsonPath: null,
    warnOnly: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--project":
        options.projectId = argv[++index];
        break;
      case "--index":
        options.indexPath = argv[++index];
        break;
      case "--deployed-json":
        options.deployedJsonPath = argv[++index];
        break;
      case "--warn-only":
        options.warnOnly = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.projectId) {
    throw new Error("--project <firebaseProjectId> is required.");
  }

  return options;
}

/**
 * Reads the deployed function list, from a file or from the Firebase CLI.
 * @param {object} options Parsed options.
 * @return {string} Raw `functions:list --json` output.
 */
function readDeployedPayload(options) {
  if (options.deployedJsonPath) {
    return readFileSync(options.deployedJsonPath, "utf8");
  }

  const args = [
    "-y",
    FIREBASE_TOOLS,
    "functions:list",
    "--project",
    options.projectId,
    "--json",
  ];

  // FIREBASE_TOKEN is passed through the inherited environment, which
  // firebase-tools already reads, and never on argv: argv is world-readable
  // through the process table and is reproduced verbatim in the Error message
  // execFileSync throws on a non-zero exit. Outside Actions nothing masks it.
  try {
    // `maxBuffer` because the v2 payload carries full function configs.
    return execFileSync("npx", args, {
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch (error) {
    // On a spawn failure - npx missing, or a signal kill - `status` and
    // `stderr` are both null and the only diagnostic left is `code`/`signal`.
    // Neither carries the token, so naming them costs nothing.
    const stderr = String(error.stderr ?? "").trim();
    const cause =
      stderr ||
      [error.code, error.signal].filter(Boolean).join(" ") ||
      "no diagnostic output";
    throw new Error(
      `firebase functions:list failed for ${options.projectId} ` +
        `(exit ${error.status ?? "unknown"}). ${cause.slice(0, 400)}`
    );
  }
}

/**
 * Runs the reconciliation.
 * @return {number} The process exit code.
 */
function main() {
  const options = parseArgs(process.argv.slice(2));

  const exported = parseExportedFunctionNames(
    readFileSync(options.indexPath, "utf8")
  );
  if (exported.length === 0) {
    throw new Error(
      `${options.indexPath} exports no functions - refusing to treat an ` +
        "empty expectation as a passing reconciliation."
    );
  }

  const deployed = parseDeployedFunctions(readDeployedPayload(options));
  const diff = diffDeployedFunctions({
    exported,
    deployed: deployed.map((entry) => entry.id),
  });
  const inactive = inactiveDeployedFunctions(deployed, exported);
  const {ok, lines} = formatFunctionsDiff({
    projectId: options.projectId,
    diff,
    inactive,
  });

  for (const line of lines) {
    console.log(line);
  }

  if (ok) {
    return 0;
  }

  console.log(
    options.warnOnly ?
      "Reconciliation failed; --warn-only, so not failing the job." :
      "The deploy did not leave this project in the state the source describes."
  );
  return options.warnOnly ? 0 : 1;
}

try {
  process.exitCode = main();
} catch (error) {
  console.error(`::error::${error.message}`);
  process.exitCode = 1;
}
