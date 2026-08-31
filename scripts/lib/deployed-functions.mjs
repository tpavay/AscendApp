/**
 * Reconciles the Cloud Functions a project actually has against the ones the
 * source says it should have.
 *
 * `firebase deploy --only functions` reports success for the work it performed;
 * it cannot report the work a cancelled pipeline never asked it to do. On
 * 2026-07-31 production was missing `cleanupDeletedUserData`, `onWorkoutWritten`
 * and `unsubscribeFromEmails` while every deploy step that ever ran had passed,
 * and dev still held four `strava*` functions removed from source in `2ca544d`.
 * Neither condition is observable from a deploy log, so the deploy has to
 * assert its own result afterwards.
 *
 * Pure functions here; `verify-deployed-functions.mjs` supplies the inputs.
 */

/**
 * Extracts the function names `functions/src/index.ts` exports.
 *
 * Covers the two shapes the file actually uses - re-exports (`export {a, b}
 * from "./x"`, single- or multi-line) and direct declarations - and resolves
 * `as` aliases to the exported name, because that is the name Firebase deploys.
 *
 * @param {string} source Contents of the functions entry point.
 * @return {Array<string>} Sorted, de-duplicated exported function names.
 */
export function parseExportedFunctionNames(source) {
  if (typeof source !== "string") {
    throw new TypeError("parseExportedFunctionNames requires a string.");
  }

  const names = new Set();

  for (const match of source.matchAll(/export\s*\{([^}]*)\}\s*from\s*["']/g)) {
    for (const clause of match[1].split(",")) {
      const name = exportedNameFromClause(clause);
      if (name) {
        names.add(name);
      }
    }
  }

  const declaration =
    /export\s+(?:const|let|var|function|async\s+function|class)\s+([A-Za-z_$][\w$]*)/g;
  for (const match of source.matchAll(declaration)) {
    names.add(match[1]);
  }

  return [...names].sort();
}

/**
 * Resolves one `{ ... }` clause to the name it exports.
 * @param {string} clause A single specifier, e.g. `a as b` or `type T`.
 * @return {string | null} The exported name, or null when it exports nothing.
 */
function exportedNameFromClause(clause) {
  const trimmed = clause.trim();
  if (!trimmed || trimmed.startsWith("type ")) {
    return null;
  }

  const parts = trimmed.split(/\s+as\s+/);
  const exported = (parts.length > 1 ? parts[1] : parts[0]).trim();
  return /^[A-Za-z_$][\w$]*$/.test(exported) ? exported : null;
}

/**
 * Extracts deployed function ids from `firebase functions:list --json`.
 * @param {string | object} payload Raw JSON text or the parsed object.
 * @return {Array<string>} Sorted deployed function names.
 */
export function parseDeployedFunctionNames(payload) {
  const names = new Set(
    parseDeployedFunctions(payload).map((entry) => entry.id)
  );
  return [...names].sort();
}

/**
 * Extracts deployed functions with the state Firebase reports for each.
 *
 * A function can be present and still broken - v2 deploys report `state` and
 * only `ACTIVE` means it will serve. "Deployed" and "working" are different
 * claims, and a reconciliation that checks only names makes the weaker one.
 *
 * De-duplication is on `id` *and* `region`: one name can be deployed to several
 * regions, and collapsing them on name alone lets whichever region the CLI
 * happened to list last speak for all of them - so a function `ACTIVE` in one
 * region and `FAILED` in another would be reported as serving.
 *
 * @param {string | object} payload Raw JSON text or the parsed object.
 * @return {Array<{id: string, region: string | null, state: string | null}>}
 *   Deployed functions, one entry per region.
 */
export function parseDeployedFunctions(payload) {
  const parsed = typeof payload === "string" ? JSON.parse(payload) : payload;
  const result = parsed?.result;

  if (!Array.isArray(result)) {
    // The CLI can exit 0 and still write `{"status":"error","error":"..."}`,
    // in which case its own words are the whole diagnostic and a generic
    // shape complaint would throw them away exactly as the catch path used to.
    const envelope = typeof parsed?.error === "string" ?
      collapseWhitespace(parsed.error).slice(0, 400) :
      "";
    throw new Error(
      "Unexpected `firebase functions:list --json` payload: no `result` " +
        `array.${envelope ? ` ${envelope}` : ""}`
    );
  }

  const byIdAndRegion = new Map();
  for (const entry of result) {
    if (typeof entry?.id === "string" && entry.id.length > 0) {
      const region = typeof entry.region === "string" ? entry.region : null;
      byIdAndRegion.set(`${entry.id}@${region ?? ""}`, {
        id: entry.id,
        region,
        state: entry.state ?? null,
      });
    }
  }

  return [...byIdAndRegion.values()];
}

/**
 * Finds deployed functions that exist but are not serving.
 *
 * A null `state` is treated as healthy: v1 functions and older CLI payloads
 * omit it, and inventing a failure from a missing field would block deploys
 * for a reason that is not evidence of anything.
 *
 * Every region is judged separately, so one bad region is a failure even when
 * its siblings are serving.
 *
 * @param {Array<{id: string, region?: string | null, state: string | null}>}
 *   deployed Deployed set, one entry per id and region.
 * @param {Array<string>} expected Names the source exports.
 * @return {Array<{id: string, region?: string | null, state: string | null}>}
 *   Not-serving functions.
 */
export function inactiveDeployedFunctions(deployed, expected) {
  const expectedSet = new Set(expected);
  return deployed
    .filter((entry) => expectedSet.has(entry.id))
    .filter((entry) => entry.state !== null && entry.state !== "ACTIVE")
    .sort(
      (a, b) =>
        a.id.localeCompare(b.id) ||
        (a.region ?? "").localeCompare(b.region ?? "")
    );
}

/**
 * Diffs source exports against deployed functions.
 *
 * Both directions are defects. `missing` means a deploy did not happen or did
 * not finish. `orphaned` means a removed function is still live and still
 * serving traffic against whatever data contract it was written for.
 *
 * @param {object} input Diff input.
 * @param {Array<string>} input.exported Names the source exports.
 * @param {Array<string>} input.deployed Names the project has deployed.
 * @return {{missing: Array<string>, orphaned: Array<string>,
 *   matched: Array<string>}} The reconciliation.
 */
export function diffDeployedFunctions({exported, deployed}) {
  const exportedSet = new Set(exported);
  const deployedSet = new Set(deployed);

  return {
    missing: [...exportedSet].filter((name) => !deployedSet.has(name)).sort(),
    orphaned: [...deployedSet].filter((name) => !exportedSet.has(name)).sort(),
    matched: [...exportedSet].filter((name) => deployedSet.has(name)).sort(),
  };
}

/**
 * Renders the diff as the lines a deploy job should print.
 * @param {object} input Report input.
 * @param {string} input.projectId The Firebase project the diff describes.
 * @param {{missing: Array<string>, orphaned: Array<string>,
 *   matched: Array<string>}} input.diff The reconciliation.
 * @param {Array<{id: string, state: string | null}>} [input.inactive] Deployed
 *   but not serving.
 * @return {{ok: boolean, lines: Array<string>}} Result and printable lines.
 */
export function formatFunctionsDiff({projectId, diff, inactive = []}) {
  const lines = [
    `Functions reconciliation for ${projectId}: ` +
      `${diff.matched.length} matched, ${diff.missing.length} missing, ` +
      `${diff.orphaned.length} orphaned, ${inactive.length} not serving.`,
  ];

  for (const name of diff.missing) {
    lines.push(
      `::error::${name} is exported from functions/src/index.ts but is not ` +
        `deployed to ${projectId}.`
    );
  }

  for (const name of diff.orphaned) {
    lines.push(
      `::error::${name} is deployed to ${projectId} but is no longer exported ` +
        "from functions/src/index.ts."
    );
  }

  for (const entry of inactive) {
    const where = entry.region ? ` (${entry.region})` : "";
    lines.push(
      `::error::${entry.id}${where} is deployed to ${projectId} in state ` +
        `${entry.state}, not ACTIVE, so it is not serving.`
    );
  }

  return {
    ok:
      diff.missing.length === 0 &&
      diff.orphaned.length === 0 &&
      inactive.length === 0,
    lines,
  };
}

/**
 * Delays between `functions:list` attempts, in milliseconds.
 *
 * The reconciliation is a read, and a read that could not run is not evidence
 * that the deploy was wrong. On 2026-08-31 the staging pipeline deployed all
 * 22 functions clean and the `functions:list` two seconds later exited 1, which
 * failed the job - and `upload-testflight` `needs` that job, so a verification
 * read took down the TestFlight upload of a build that was already fine.
 *
 * Three attempts across ~20s absorb a transient refusal from the Cloud
 * Functions API without softening the gate: every attempt has to fail before
 * the job fails, and a read that *succeeds* is still judged exactly as
 * strictly as before. Retrying is safe because listing is idempotent - it
 * deploys nothing and changes nothing.
 */
export const FUNCTIONS_LIST_ATTEMPT_DELAYS_MS = [5_000, 15_000];

/**
 * Per-attempt wall clock for one `functions:list` read, in milliseconds.
 *
 * The retry budget above covers a read that fails; without a timeout it covers
 * nothing at all for a read that never returns, and a wedged npx or a hung
 * Cloud Functions API call would sit there until the job's own
 * `timeout-minutes: 45` killed the whole deploy - the same outcome, by the
 * sibling failure mode.
 *
 * Two minutes is roughly 60x headroom: the healthy staging read takes ~2.3s.
 * With the schedule above that caps the worst case near 6-7 minutes. A
 * timed-out attempt is a failed attempt and nothing more - it is retried by the
 * same budget, and an exhausted budget still fails the job, because a
 * non-responding Firebase must never let a build through.
 */
export const FUNCTIONS_LIST_ATTEMPT_TIMEOUT_MS = 120_000;

/**
 * Flattens text to one line so an Actions annotation can carry all of it.
 * @param {string | undefined | null} text Arbitrary captured output.
 * @return {string} The text with runs of whitespace collapsed to one space.
 */
function collapseWhitespace(text) {
  return String(text ?? "").replace(/\s+/g, " ").trim();
}

/**
 * Pulls the human-readable message out of a `--json` error envelope.
 * @param {string | undefined | null} stdout Captured stdout.
 * @return {string} The envelope's message, or "" when there isn't one.
 */
function errorEnvelopeMessage(stdout) {
  const text = String(stdout ?? "").trim();
  if (!text.startsWith("{")) {
    return "";
  }

  try {
    const parsed = JSON.parse(text);
    return typeof parsed?.error === "string" ?
      collapseWhitespace(parsed.error) :
      "";
  } catch {
    return "";
  }
}

/**
 * Names the fields that survive a child the OS or Node killed.
 *
 * A timeout leaves `status` null and the signal set, and a maxBuffer overflow
 * leaves ENOBUFS beside a stdout truncated mid-payload - both cases where the
 * streams alone describe the failure as something it is not.
 *
 * @param {object} error The error `execFileSync` threw.
 * @return {string} A short detail, or "" when neither field is populated.
 */
function killedChildDetail(error) {
  const details = [];
  if (error?.code) {
    details.push(`code ${error.code}`);
  }
  if (error?.signal) {
    details.push(`killed by ${error.signal}`);
  }
  return details.join(", ");
}

/**
 * Builds the diagnostic for a `firebase functions:list` that failed.
 *
 * `--json` moves *everything* to stdout - the success payload and the error
 * envelope alike - and leaves stderr completely empty. An error path that
 * reads only stderr therefore reports `no diagnostic output` for every failure
 * that exists, which is what the 2026-08-31 staging deploy left behind: exit 1,
 * an empty stderr, and no trace of the cause anywhere in the job log.
 *
 * Order matters. The envelope's `error` string is the CLI's own words; raw
 * stdout is the fallback when the payload is not the envelope shape; stderr
 * still comes next because a crash before argument parsing never reaches
 * `--json` handling.
 *
 * `code`/`signal` are appended rather than ranked last, because they are not
 * only what survives a stream-less spawn failure - they are also the only
 * field that names a *killed* child. A read Node timed out or overflowed past
 * `maxBuffer` leaves a truncated, unparsable stdout behind, and letting half a
 * JSON payload win the ranking would describe a SIGTERM or an ENOBUFS as a
 * malformed response.
 *
 * Whitespace is collapsed before the slice: an Actions annotation is a single
 * line, so a multi-line stderr would truncate at its first newline and orphan
 * the retry suffix the caller appends after it.
 *
 * Nothing quoted here can carry FIREBASE_TOKEN: it reaches the CLI through the
 * environment, so it is absent from the `--json` envelope, from stderr and
 * from argv. `error.message` is deliberately never used - execFileSync
 * reproduces the whole argv in it, so it is the one field that would start
 * leaking the moment somebody moved the token onto the command line.
 *
 * @param {object} input Failure input.
 * @param {string} input.projectId The project the read was for.
 * @param {object} input.error The error `execFileSync` threw.
 * @return {string} A single-line diagnostic naming the real cause.
 */
export function describeFunctionsListFailure({projectId, error}) {
  const streams = [
    errorEnvelopeMessage(error?.stdout),
    collapseWhitespace(error?.stdout),
    collapseWhitespace(error?.stderr),
  ];

  const cause = [
    (streams.find((entry) => entry.length > 0) ?? "").slice(0, 400),
    killedChildDetail(error),
  ]
    .filter((entry) => entry.length > 0)
    .join(" ");

  return (
    `firebase functions:list failed for ${projectId} ` +
    `(exit ${error?.status ?? "unknown"}). ${cause || "no diagnostic output"}`
  );
}

/**
 * Reads the deployed function list, retrying a read that could not run.
 *
 * Only the *read* is retried. A read that returns a payload is handed straight
 * back for reconciliation, so a project genuinely missing a function still
 * fails on the first attempt - the retry budget buys tolerance for the API,
 * never for the deploy.
 *
 * @param {object} input Runner input.
 * @param {function(number): string} input.listOnce Performs one read; receives
 *   the 1-based attempt number.
 * @param {function(number): void} input.sleep Blocks for the given
 *   milliseconds.
 * @param {Array<number>} [input.delaysMs] Delay before each retry. Its length
 *   is the number of *retries*, so attempts are one more than that.
 * @param {function(object): void} [input.onRetry] Called before each wait.
 * @return {string} Raw `functions:list --json` output.
 */
export function listDeployedFunctionsWithRetry({
  listOnce,
  sleep,
  delaysMs = FUNCTIONS_LIST_ATTEMPT_DELAYS_MS,
  onRetry,
}) {
  if (typeof listOnce !== "function" || typeof sleep !== "function") {
    throw new TypeError(
      "listDeployedFunctionsWithRetry requires `listOnce` and `sleep`."
    );
  }

  let lastError;
  for (let attempt = 0; attempt <= delaysMs.length; attempt += 1) {
    try {
      return listOnce(attempt + 1);
    } catch (error) {
      lastError = error;
      if (attempt === delaysMs.length) {
        break;
      }
      if (onRetry) {
        onRetry({attempt: attempt + 1, delayMs: delaysMs[attempt], error});
      }
      sleep(delaysMs[attempt]);
    }
  }

  throw lastError;
}
