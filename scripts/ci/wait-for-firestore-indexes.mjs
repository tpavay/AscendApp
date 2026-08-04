#!/usr/bin/env node

import {realpathSync} from "node:fs";
import {readFile} from "node:fs/promises";
import {resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {
  evaluateFirestoreIndexReadiness,
  formatFirestoreIndexIssues,
  structuralFirestoreIndexIssues,
} from "../lib/firestore-index-readiness.mjs";
import {
  classifyFirestoreReadError,
  createFirestoreIndexStateReader,
} from "../lib/firestore-index-state-reader.mjs";

const DEFAULT_TIMEOUT_MS = 60 * 60 * 1000;
const DEFAULT_INTERVAL_MS = 20 * 1000;
const DEFAULT_MAX_READ_FAILURES = 15;
const STRUCTURAL_ERROR_EXIT_CODE = 2;

// Two minutes is an estimate, not a measurement: a cold field override only
// becomes visible to listFieldOverrides once Firestore flips
// indexConfig.usesAncestorConfig, and that window cannot be measured without
// writing to a project. STRUCTURAL_GRACE_ENV_VAR lets an operator raise it
// during an incident without shipping code.
export const DEFAULT_STRUCTURAL_GRACE_MS = 2 * 60 * 1000;
export const STRUCTURAL_GRACE_ENV_VAR =
  "FIRESTORE_INDEX_STRUCTURAL_GRACE_MS";

export function resolveStructuralGraceMs(
  rawValue,
  {timeoutMs = DEFAULT_TIMEOUT_MS} = {}
) {
  if (rawValue === undefined || rawValue === null ||
    String(rawValue).trim().length === 0) {
    return DEFAULT_STRUCTURAL_GRACE_MS;
  }

  const trimmed = String(rawValue).trim();
  const parsed = Number(trimmed);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(
      `${STRUCTURAL_GRACE_ENV_VAR} must be a finite, strictly positive number ` +
        `of milliseconds, got "${trimmed}"`
    );
  }
  if (parsed >= timeoutMs) {
    throw new Error(
      `${STRUCTURAL_GRACE_ENV_VAR} of ${parsed} ms must stay below the ` +
        `${timeoutMs} ms readiness window, or a structural failure could ` +
        "never be reported before the wait times out"
    );
  }

  return parsed;
}

export async function waitForFirestoreIndexes({
  config,
  readState,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  intervalMs = DEFAULT_INTERVAL_MS,
  maxConsecutiveReadFailures = DEFAULT_MAX_READ_FAILURES,
  structuralGraceMs = DEFAULT_STRUCTURAL_GRACE_MS,
  classifyReadError = classifyFirestoreReadError,
  now = Date.now,
  sleep = defaultSleep,
  log = console,
}) {
  if (!Number.isFinite(structuralGraceMs) || structuralGraceMs <= 0) {
    throw new Error(
      `structuralGraceMs must be a finite, strictly positive number of ` +
        `milliseconds, got ${structuralGraceMs}`
    );
  }

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
      lastReadError = error instanceof Error ? error : new Error(String(error));
      const classification = classifyReadError(lastReadError);

      // Credentials and permissions fail identically on every later poll, so
      // retrying one only converts a visible error into a wasted hour.
      if (classification === "deterministic") {
        log.error(
          `Firestore index state read was rejected: ${lastReadError.message}`
        );
        log.error(
          "Cannot verify Firestore index readiness because the serving-state " +
            "API could not be read. Retrying cannot resolve an authentication " +
            "or permission failure."
        );
        return {status: "read-failed", error: lastReadError, classification};
      }

      consecutiveReadFailures += 1;
      log.error(
        `Transient Firestore index state read failure ` +
          `(${consecutiveReadFailures}/${maxConsecutiveReadFailures}): ` +
          lastReadError.message
      );

      if (consecutiveReadFailures >= maxConsecutiveReadFailures) {
        log.error(
          "Cannot verify Firestore index readiness because the serving-state " +
            "API could not be read."
        );
        return {status: "read-failed", error: lastReadError, classification};
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

      const structuralIssues = structuralFirestoreIndexIssues(
        lastReadiness.issues
      );
      if (
        structuralIssues.length > 0 &&
        now() - startedAt >= structuralGraceMs
      ) {
        log.error(
          `Firestore index configuration is still wrong after ` +
            `${formatDuration(structuralGraceMs)}. Waiting only resolves ` +
            "CREATING indexes, so these are verification failures:"
        );
        log.error(formatFirestoreIndexIssues(structuralIssues));
        return {
          status: "structural",
          readiness: lastReadiness,
          issues: structuralIssues,
        };
      }
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

  const structuralGraceMs = resolveStructuralGraceMs(
    process.env[STRUCTURAL_GRACE_ENV_VAR]
  );
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const readState = createFirestoreIndexStateReader({
    firebaseToolsRoot,
    refreshToken,
    projectId,
    databaseId,
  });
  const result = await waitForFirestoreIndexes({
    config,
    readState,
    structuralGraceMs,
  });

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

// A percent-encoded or symlinked invocation path must still run the gate.
// Comparing the raw URL pathname to argv[1] silently exits 0 in both cases,
// which reads as a passed readiness check that never contacted Firestore.
export function isCommandLineEntryPoint(moduleUrl, entryPath) {
  if (typeof entryPath !== "string" || entryPath.length === 0) {
    return false;
  }

  const modulePath = fileURLToPath(moduleUrl);
  const resolvedEntryPath = resolve(entryPath);
  if (modulePath === resolvedEntryPath) {
    return true;
  }

  try {
    return realpathSync(modulePath) === realpathSync(resolvedEntryPath);
  } catch {
    return false;
  }
}

if (isCommandLineEntryPoint(import.meta.url, process.argv[1])) {
  try {
    await runCommandLine();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = STRUCTURAL_ERROR_EXIT_CODE;
  }
}
