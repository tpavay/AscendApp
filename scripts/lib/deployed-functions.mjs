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
  return parseDeployedFunctions(payload)
    .map((entry) => entry.id)
    .sort();
}

/**
 * Extracts deployed functions with the state Firebase reports for each.
 *
 * A function can be present and still broken - v2 deploys report `state` and
 * only `ACTIVE` means it will serve. "Deployed" and "working" are different
 * claims, and a reconciliation that checks only names makes the weaker one.
 *
 * @param {string | object} payload Raw JSON text or the parsed object.
 * @return {Array<{id: string, state: string | null}>} Deployed functions.
 */
export function parseDeployedFunctions(payload) {
  const parsed = typeof payload === "string" ? JSON.parse(payload) : payload;
  const result = parsed?.result;

  if (!Array.isArray(result)) {
    throw new Error(
      "Unexpected `firebase functions:list --json` payload: no `result` array."
    );
  }

  const byId = new Map();
  for (const entry of result) {
    if (typeof entry?.id === "string" && entry.id.length > 0) {
      byId.set(entry.id, {id: entry.id, state: entry.state ?? null});
    }
  }

  return [...byId.values()];
}

/**
 * Finds deployed functions that exist but are not serving.
 *
 * A null `state` is treated as healthy: v1 functions and older CLI payloads
 * omit it, and inventing a failure from a missing field would block deploys
 * for a reason that is not evidence of anything.
 *
 * @param {Array<{id: string, state: string | null}>} deployed Deployed set.
 * @param {Array<string>} expected Names the source exports.
 * @return {Array<{id: string, state: string | null}>} Not-serving functions.
 */
export function inactiveDeployedFunctions(deployed, expected) {
  const expectedSet = new Set(expected);
  return deployed
    .filter((entry) => expectedSet.has(entry.id))
    .filter((entry) => entry.state !== null && entry.state !== "ACTIVE")
    .sort((a, b) => a.id.localeCompare(b.id));
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
    lines.push(
      `::error::${entry.id} is deployed to ${projectId} in state ` +
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
