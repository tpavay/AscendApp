#!/usr/bin/env node
/**
 * Guards a Cloud Functions deploy against the secret versions it would bind.
 *
 * A Functions deploy binds every function to the LATEST version of each
 * secret it declares, whether or not anybody meant that version to ship. On
 * 2026-09-25 that is how the 1.1 production deploy put an undeployed,
 * stale-built `REVENUECAT_SERVER_CONFIG` live and deleted comped climbers'
 * paid-access grants. `docs/functions-secret-versions.md` owns the procedure;
 * `scripts/lib/functions-secret-guard.mjs` owns every decision made here.
 *
 * Usage:
 *   node scripts/verify-functions-secrets.mjs preflight --project <id> [--snapshot <path>]
 *   node scripts/verify-functions-secrets.mjs verify-deploy --project <id> --snapshot <path>
 *
 *   preflight       Before any backend change. Fails unless every secret's
 *                   latest version is the one functions/secret-versions.json
 *                   pins for this commit, unless the RevenueCat allowlist
 *                   the deploy will bind keeps every product that grants
 *                   access, and unless it keeps every product a bound
 *                   version allowlists that the commit does not acknowledge
 *                   dropping. With --snapshot it records every live grant and
 *                   the comp ledger for verify-deploy. Read-only.
 *   verify-deploy   After the Functions deploy, before rules. Fails unless
 *                   every function is bound to the pinned versions and every
 *                   grant from the snapshot still exists and is still
 *                   allowlisted. Read-only.
 *
 * Honours FIREBASE_TOKEN, matching the deploy steps, and FIREBASE_TOOLS_ROOT.
 * Never prints a secret value: a changed secret is reported by key name only.
 *
 * Exit codes: 0 safe, 1 the deploy must not proceed, 2 could not verify.
 */

import {readFileSync, readdirSync, renameSync, writeFileSync} from "node:fs";
import {dirname, join, resolve} from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";

import {annotate} from "./lib/ci-annotations.mjs";
import {createFunctionsSecretBackend} from "./lib/functions-secret-backend.mjs";
import {
  REVENUECAT_SECRET,
  SECRET_VERSION_MANIFEST_PATH,
  boundSecretVersions,
  buildGrantSnapshot,
  diffSecretPayloadKeys,
  distinctBoundVersions,
  evaluateAllowlistInvariant,
  evaluateAllowlistSuperset,
  evaluateDeployedBindings,
  evaluateGrantSurvival,
  evaluateSecretDrift,
  guardedProject,
  parseDeclaredSecretNames,
  parseAllowedProductIds,
  parseGrantSnapshot,
  parseSecretVersionManifest,
  requiredAllowlistFloor,
  requiredProducts,
} from "./lib/functions-secret-guard.mjs";
import {createGoogleRestClient} from "./lib/google-rest-client.mjs";
import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {
  createGoogleAccessTokenSource,
  resolvePinnedFirebaseToolsRoot,
} from "./lib/pinned-firebase-tools.mjs";

export const EXIT = Object.freeze({safe: 0, unsafe: 1, unverified: 2});

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const FUNCTIONS_SOURCE_DIRECTORY = "functions/src";
const PBXPROJ_PATH = "AscendApp.xcodeproj/project.pbxproj";
const MONETIZATION_SOURCE_PATH =
  "AscendApp/Features/Monetization/Models/MonetizationConfiguration.swift";
const COMMANDS = ["preflight", "verify-deploy"];

/**
 * Runs the command line.
 * @param {Array<string>} argv Arguments after the script path.
 * @return {Promise<number>} The exit code.
 */
async function main(argv) {
  let options;
  try {
    options = parseArgs(argv);
    guardedProject(options.projectId);
  } catch (error) {
    annotate("error", error.message);
    return EXIT.unverified;
  }

  let backend;
  try {
    const getAccessToken = createGoogleAccessTokenSource({
      firebaseToolsRoot: resolvePinnedFirebaseToolsRoot(),
      refreshToken: process.env.FIREBASE_TOKEN || undefined,
    });
    backend = createFunctionsSecretBackend({
      client: createGoogleRestClient({
        getAccessToken,
        quotaProjectId: options.projectId,
      }),
      projectId: options.projectId,
    });
  } catch (error) {
    annotate("error", `Could not authenticate to Google: ${error.message}`);
    return EXIT.unverified;
  }

  const run = options.command === "preflight" ? runPreflight : runVerifyDeploy;
  return run({
    projectId: options.projectId,
    backend,
    repository: readRepositoryInputs(REPOSITORY_ROOT),
    snapshotPath: options.snapshotPath,
    now: () => new Date(),
    log: consoleLog,
  });
}

/**
 * The preflight: may this commit's Functions deploy run at all?
 * @param {object} input Run input.
 * @return {Promise<number>} The exit code.
 */
export async function runPreflight({projectId, backend, repository, snapshotPath, now, log}) {
  let inputs;
  try {
    inputs = deriveInputs(projectId, repository);
  } catch (error) {
    log.error(error.message);
    return EXIT.unverified;
  }
  const {declaredSecrets, pins, acknowledgedDrops, floor} = inputs;
  log.info(`Functions secret preflight for ${projectId}, against ${SECRET_VERSION_MANIFEST_PATH} at this commit.`);

  let latest;
  let bound;
  let keyChanges;
  let revenueCatPayload;
  let boundAllowlists;
  let grants;
  let ledger;
  try {
    const [latestEntries, functions] = await Promise.all([
      Promise.all(declaredSecrets.map(async (secret) =>
        [secret, await backend.latestSecretVersion(secret)])),
      backend.listFunctions(),
    ]);
    latest = Object.fromEntries(latestEntries.filter(([, head]) => head !== null));
    bound = boundSecretVersions(functions);
    ({keyChanges, revenueCatPayload, boundAllowlists} = await readKeyChanges({backend, declaredSecrets, latest, bound}));
    [grants, ledger] = await Promise.all([
      backend.listGrants(floor.entitlementId),
      backend.listCompLedger(),
    ]);
  } catch (error) {
    log.error(`Could not read ${projectId}, so nothing is verified: ${error.message}`);
    return EXIT.unverified;
  }

  for (const secret of declaredSecrets) {
    const head = latest[secret];
    const bindings = bound[secret] ?? [];
    log.info(
      `  ${secret}: pinned ${pins[secret]}, latest ${head ? head.version : "missing"}, bound ` +
        `${bindings.length === 0 ? "nowhere" : distinctBoundVersions(bindings).join(" and ")}` +
        `${bindings.length === 0 ? "" : ` (${bindings.map((binding) => binding.functionId).join(", ")})`}`
    );
  }

  const drift = evaluateSecretDrift({projectId, declaredSecrets, pins, latest, bound, keyChanges});
  const errors = [...drift.errors];
  const notices = [...drift.notices];
  const takenAt = now();

  const revenueCatHead = latest[REVENUECAT_SECRET];
  if (revenueCatHead && revenueCatPayload !== null) {
    const invariant = evaluateAllowlistInvariant({
      projectId,
      version: revenueCatHead.version,
      payloadText: revenueCatPayload,
      entitlementId: floor.entitlementId,
      required: requiredProducts(floor, grants, takenAt),
    });
    errors.push(...invariant.errors);
    if (invariant.allowedProductIds !== null) {
      const superset = evaluateAllowlistSuperset({
        projectId,
        pin: pins[REVENUECAT_SECRET],
        latestVersion: revenueCatHead.version,
        latestAllowed: invariant.allowedProductIds,
        boundAllowlists,
        acknowledgedDrops,
      });
      errors.push(...superset.errors);
      notices.push(...superset.notices);
    }
  }

  for (const notice of notices) {
    log.notice(notice);
  }
  log.info(`  ${grants.length} live ${floor.entitlementId} grant(s), ${ledger.length} comp_grants ledger entr${ledger.length === 1 ? "y" : "ies"}.`);

  if (errors.length > 0) {
    for (const error of errors) {
      log.error(error);
    }
    log.error(
      `The Functions deploy to ${projectId} must not run: ${errors.length} problem(s) above. ` +
        "Nothing has been deployed. See docs/functions-secret-versions.md."
    );
    return EXIT.unsafe;
  }

  if (snapshotPath) {
    const snapshot = buildGrantSnapshot({
      projectId,
      takenAt,
      entitlementId: floor.entitlementId,
      grants,
      ledger,
    });
    const temporary = `${snapshotPath}.partial`;
    writeFileSync(temporary, `${JSON.stringify(snapshot, null, 2)}\n`, {mode: 0o600});
    renameSync(temporary, snapshotPath);
    log.info(`  Recorded ${grants.length} grant(s) for the post-deploy check.`);
  }

  log.info(`Every Functions secret in ${projectId} is the version this commit pins, and the RevenueCat allowlist keeps every product that grants access or that a bound version allowlists.`);
  return EXIT.safe;
}

/**
 * The post-deploy check: did the Functions deploy keep every grant?
 * @param {object} input Run input.
 * @return {Promise<number>} The exit code.
 */
export async function runVerifyDeploy({projectId, backend, repository, snapshotPath, now, log}) {
  let inputs;
  let snapshot;
  try {
    inputs = deriveInputs(projectId, repository);
    if (!snapshotPath) {
      throw new Error("verify-deploy needs the --snapshot the preflight wrote.");
    }
    snapshot = parseGrantSnapshot(readFileSync(snapshotPath, "utf8"), projectId);
  } catch (error) {
    log.error(error.message);
    return EXIT.unverified;
  }
  const {declaredSecrets, pins, floor} = inputs;
  log.info(`Post-deploy Functions secret and grant check for ${projectId}.`);

  let bound;
  let revenueCatPayload;
  let currentGrants;
  try {
    [bound, revenueCatPayload, currentGrants] = await Promise.all([
      backend.listFunctions().then(boundSecretVersions),
      backend.accessSecretVersion(REVENUECAT_SECRET, pins[REVENUECAT_SECRET]),
      backend.listGrants(snapshot.entitlementId),
    ]);
  } catch (error) {
    log.error(`Could not read ${projectId} after the deploy, so nothing is verified: ${error.message}`);
    return EXIT.unverified;
  }

  const checkedAt = now();
  const errors = evaluateDeployedBindings({projectId, declaredSecrets, pins, bound});
  const invariant = evaluateAllowlistInvariant({
    projectId,
    version: pins[REVENUECAT_SECRET],
    payloadText: revenueCatPayload,
    entitlementId: floor.entitlementId,
    required: requiredProducts(floor, snapshot.grants, checkedAt),
  });
  errors.push(...invariant.errors);

  const held = new Set(currentGrants.map((grant) => grant.uid));
  const lost = snapshot.grants.filter((grant) => !held.has(grant.uid));
  let statusByUid;
  try {
    statusByUid = Object.fromEntries(await Promise.all(lost.map(async (grant) =>
      [grant.uid, await backend.readEntitlementStatus(grant.uid, snapshot.entitlementId)])));
  } catch (error) {
    log.warning(`Could not read the entitlement status of a lost grant: ${error.message}`);
    statusByUid = {};
  }

  const survival = evaluateGrantSurvival({
    snapshot,
    currentGrants,
    allowedProductIds: invariant.allowedProductIds ?? [],
    statusByUid,
    now: checkedAt,
  });
  errors.push(...survival.errors);

  for (const warning of survival.warnings) {
    log.warning(warning);
  }
  log.info(`  ${survival.summary}`);

  if (errors.length > 0) {
    for (const error of errors) {
      log.error(error);
    }
    log.error(
      `The Functions deploy to ${projectId} lost or endangered paid access: ${errors.length} ` +
        "problem(s) above. Stopping before rules, Storage and Hosting. See " +
        "docs/functions-secret-versions.md."
    );
    return EXIT.unsafe;
  }

  log.info(`Every function in ${projectId} is bound to the pinned secret versions, and every pre-deploy grant survived.`);
  return EXIT.safe;
}

/**
 * Reads the repository files the guard derives its expectations from.
 * @param {string} root Repository root.
 * @return {object} File contents.
 */
export function readRepositoryInputs(root) {
  const sourceDirectory = join(root, FUNCTIONS_SOURCE_DIRECTORY);
  const functionSources = readdirSync(sourceDirectory, {recursive: true})
    .map(String)
    .filter((path) => path.endsWith(".ts"))
    .sort()
    .map((path) => readFileSync(join(sourceDirectory, path), "utf8"));

  return {
    manifestText: readFileSync(join(root, SECRET_VERSION_MANIFEST_PATH), "utf8"),
    functionSources,
    pbxproj: readFileSync(join(root, PBXPROJ_PATH), "utf8"),
    monetizationSource: readFileSync(join(root, MONETIZATION_SOURCE_PATH), "utf8"),
  };
}

function deriveInputs(projectId, repository) {
  const declaredSecrets = parseDeclaredSecretNames(repository.functionSources);
  if (!declaredSecrets.includes(REVENUECAT_SECRET)) {
    throw new Error(
      `${FUNCTIONS_SOURCE_DIRECTORY} no longer declares ${REVENUECAT_SECRET}, so ` +
        "the paid-access invariant has nothing to check. Refusing to pass vacuously."
    );
  }
  const {pins, acknowledgedDrops} = parseSecretVersionManifest(repository.manifestText, declaredSecrets)[projectId];
  const floor = requiredAllowlistFloor({
    projectId,
    pbxproj: repository.pbxproj,
    monetizationSource: repository.monetizationSource,
  });
  return {declaredSecrets, pins, acknowledgedDrops, floor};
}

/**
 * Compares every bound version that differs from `latest` against it, by key
 * name, and returns the RevenueCat payload the invariant checks and the
 * allowlist of every bound RevenueCat version the superset check compares.
 *
 * The comparison only explains a move, so a version that can no longer be
 * read degrades the explanation rather than blocking the deploy; the
 * RevenueCat payloads are different, because the invariant and the superset
 * check decide on them, so failing to read one - or to find an allowlist in a
 * bound one - throws, and the preflight reports that it could not verify.
 * Payloads are held only in this function's memory.
 * @param {object} input Read input.
 * @return {Promise<{keyChanges: object, revenueCatPayload: ?string,
 *   boundAllowlists: Object<string, Array<string>>}>} Diffs by secret and
 *   bound version, the latest RevenueCat payload, and bound allowlists by
 *   version.
 */
async function readKeyChanges({backend, declaredSecrets, latest, bound}) {
  const payloads = new Map();
  const payload = (secret, version) => {
    const key = `${secret}@${version}`;
    if (!payloads.has(key)) {
      payloads.set(key, backend.accessSecretVersion(secret, version));
    }
    return payloads.get(key);
  };

  const keyChanges = {};
  for (const secret of declaredSecrets) {
    const head = latest[secret];
    if (!head || head.state !== "ENABLED") continue;
    for (const version of distinctBoundVersions(bound[secret])) {
      if (version === head.version || version === "latest") continue;
      let change;
      try {
        const [before, after] = await Promise.all([
          payload(secret, version),
          payload(secret, head.version),
        ]);
        change = diffSecretPayloadKeys(before, after);
      } catch (error) {
        change = {kind: "unreadable", reason: error.message};
      }
      (keyChanges[secret] ??= {})[version] = change;
    }
  }

  const revenueCatHead = latest[REVENUECAT_SECRET];
  if (!revenueCatHead || revenueCatHead.state !== "ENABLED") {
    return {keyChanges, revenueCatPayload: null, boundAllowlists: {}};
  }
  const revenueCatPayload = await payload(REVENUECAT_SECRET, revenueCatHead.version);
  const boundAllowlists = {};
  for (const version of distinctBoundVersions(bound[REVENUECAT_SECRET])) {
    if (version === revenueCatHead.version || version === "latest") continue;
    const allowed = parseAllowedProductIds(await payload(REVENUECAT_SECRET, version));
    if (allowed === null) {
      throw new Error(
        `${REVENUECAT_SECRET} version ${version}, which the deployed functions are bound to, ` +
          "has no readable allowedProductIds, so what the latest version drops cannot be known"
      );
    }
    boundAllowlists[version] = allowed;
  }
  return {keyChanges, revenueCatPayload, boundAllowlists};
}

function parseArgs(argv) {
  const options = {command: argv[0], projectId: null, snapshotPath: null};
  if (!COMMANDS.includes(options.command)) {
    throw new Error(`Pass one of: ${COMMANDS.join(", ")}.`);
  }
  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    switch (argument) {
      case "--project":
        options.projectId = argv[++index] ?? null;
        break;
      case "--snapshot":
        options.snapshotPath = argv[++index] ?? null;
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }
  if (!options.projectId) {
    throw new Error("--project <firebaseProjectId> is required.");
  }
  if (options.command === "verify-deploy" && !options.snapshotPath) {
    throw new Error("verify-deploy needs --snapshot <path>.");
  }
  return options;
}

const consoleLog = Object.freeze({
  info: (message) => console.log(message),
  notice: (message) => annotate("notice", message),
  warning: (message) => annotate("warning", message),
  error: (message) => annotate("error", message),
});

// Last, so every module-level binding above exists before the run starts. An
// unexpected throw is "could not verify", never a pass and never exit 1's
// "the deploy is unsafe".
if (isEntrypoint(import.meta.url)) {
  try {
    process.exitCode = await main(process.argv.slice(2));
  } catch (error) {
    annotate("error", `The Functions secret guard crashed: ${error?.stack ?? error}`);
    process.exitCode = EXIT.unverified;
  }
}
