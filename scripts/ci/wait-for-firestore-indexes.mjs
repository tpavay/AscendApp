#!/usr/bin/env node

import {readFile} from "node:fs/promises";

import {
  evaluateFirestoreIndexReadiness,
  formatFirestoreIndexIssues,
} from "../lib/firestore-index-readiness.mjs";
import {createFirestoreIndexStateReader} from
  "../lib/firestore-index-state-reader.mjs";

const DEFAULT_TIMEOUT_MS = 60 * 60 * 1000;
const DEFAULT_INTERVAL_MS = 20 * 1000;
const DEFAULT_MAX_READ_FAILURES = 3;
const STRUCTURAL_ERROR_EXIT_CODE = 2;

export async function waitForFirestoreIndexes({
  config,
  readState,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  intervalMs = DEFAULT_INTERVAL_MS,
  maxConsecutiveReadFailures = DEFAULT_MAX_READ_FAILURES,
  now = Date.now,
  sleep = defaultSleep,
  log = console,
}) {
  const startedAt = now();
  const deadline = startedAt + timeoutMs;
  let consecutiveReadFailures = 0;
  let lastReadError;
  let lastReadiness;

  while (true) {
    let deployedState;
    let didReadState = false;
    try {
      deployedState = await readState();
      didReadState = true;
      consecutiveReadFailures = 0;
      lastReadError = undefined;
    } catch (error) {
      consecutiveReadFailures += 1;
      lastReadError = error instanceof Error ? error : new Error(String(error));
      log.error(
        `Firestore index state read failed ` +
          `(${consecutiveReadFailures}/${maxConsecutiveReadFailures}): ` +
          lastReadError.message
      );

      if (consecutiveReadFailures >= maxConsecutiveReadFailures) {
        log.error(
          "Cannot verify Firestore index readiness because the serving-state " +
            "API could not be read."
        );
        return {status: "read-failed", error: lastReadError};
      }
    }

    if (didReadState) {
      // Config and response-shape errors are structural, not transient reads.
      // Let them escape immediately so the CLI exits 2 instead of retrying.
      lastReadiness = evaluateFirestoreIndexReadiness(config, deployedState);

      if (lastReadiness.ready) {
        log.log(
          `All ${lastReadiness.compositeCount} composite indexes and ` +
            `${lastReadiness.fieldOverrideCount} field overrides are READY.`
        );
        return {status: "ready", readiness: lastReadiness};
      }

      log.error("Firestore indexes are not READY:");
      log.error(formatFirestoreIndexIssues(lastReadiness.issues));
    }

    const remainingMs = deadline - now();
    if (remainingMs <= 0) {
      break;
    }
    await sleep(Math.min(intervalMs, remainingMs));
  }

  log.error(
    `Firestore indexes did not become READY within ${formatDuration(timeoutMs)}.`
  );
  if (lastReadiness !== undefined) {
    log.error("Still waiting for:");
    log.error(formatFirestoreIndexIssues(lastReadiness.issues));
  } else if (lastReadError !== undefined) {
    log.error(`Last serving-state read failed: ${lastReadError.message}`);
  }

  return {status: "timeout", readiness: lastReadiness, error: lastReadError};
}

async function runCommandLine() {
  const configPath = process.argv[2] ?? "firestore.indexes.json";
  const projectId = process.argv[3];
  const databaseId = process.argv[4] ?? "(default)";
  const firebaseToolsRoot = process.env.FIREBASE_TOOLS_ROOT;
  const refreshToken = process.env.FIREBASE_TOKEN;

  if (typeof projectId !== "string" || projectId.length === 0) {
    throw new Error("Pass the Firebase project ID as the second argument");
  }
  if (
    typeof firebaseToolsRoot !== "string" ||
    firebaseToolsRoot.length === 0
  ) {
    throw new Error("FIREBASE_TOOLS_ROOT is required");
  }

  const config = JSON.parse(await readFile(configPath, "utf8"));
  const readState = createFirestoreIndexStateReader({
    firebaseToolsRoot,
    refreshToken,
    projectId,
    databaseId,
  });
  const result = await waitForFirestoreIndexes({config, readState});

  if (result.status === "ready") {
    return;
  }
  process.exitCode = result.status === "timeout" ? 1 :
    STRUCTURAL_ERROR_EXIT_CODE;
}

function defaultSleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function formatDuration(milliseconds) {
  if (milliseconds % (60 * 1000) === 0) {
    return `${milliseconds / (60 * 1000)} minutes`;
  }
  if (milliseconds % 1000 === 0) {
    return `${milliseconds / 1000} seconds`;
  }
  return `${milliseconds} milliseconds`;
}

const isCommandLine = process.argv[1] !== undefined &&
  new URL(import.meta.url).pathname === process.argv[1];

if (isCommandLine) {
  try {
    await runCommandLine();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = STRUCTURAL_ERROR_EXIT_CODE;
  }
}
