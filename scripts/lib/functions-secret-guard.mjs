/**
 * The decision layer for the Functions secret guard.
 *
 * A Cloud Functions deploy binds every function to the LATEST version of each
 * secret it declares, so creating a secret version is a deferred production
 * change that the next unrelated deploy ships. On 2026-09-08
 * `REVENUECAT_SERVER_CONFIG` version 3 was built from a stale local copy that
 * had lost `rc_promo_app_access_lifetime`, and was deliberately left
 * undeployed. The 1.1 deploy on 2026-09-25 rebound `revenueCatWebhook` and
 * `reconcileAppAccess` to it, and reconciliation deleted comped climbers'
 * `users/{uid}/entitlements/app_access`, so every paid screen failed for them.
 *
 * Three checks close that, and they are all pure here so they are tested
 * without credentials or a network:
 *
 * - Drift: a deploy may only bind the version `functions/secret-versions.json`
 *   pins for that project at the commit being deployed. Anything else is an
 *   unreviewed change, reported by the names of the keys that changed and
 *   never by their values.
 * - The allowlist invariant: `allowedProductIds` must keep every product that
 *   grants access - the ones the app sells, the comp duration, and every
 *   product a live grant holds - and `entitlementId` must name the app's.
 * - Grant survival: after the Functions deploy, every grant that existed
 *   before it must still exist and still be allowlisted by the version the
 *   functions are now bound to, or the deploy stops before rules.
 */

import {
  DEFAULT_COMP_DURATION,
  promotionalProductId,
} from "./comp-access-policy.mjs";
import {
  appBuildConfigurations,
} from "./monetization-build-settings.mjs";

export const SECRET_VERSION_MANIFEST_PATH = "functions/secret-versions.json";
export const REVENUECAT_SECRET = "REVENUECAT_SERVER_CONFIG";
export const GUARD_DOC = "docs/functions-secret-versions.md";
export const GRANT_SNAPSHOT_SCHEMA_VERSION = 1;

/**
 * The projects that run a Functions deploy, and where each one's expected
 * product set comes from.
 *
 * `requiresCompProduct` is true where comps are issued: `scripts/comp-access.mjs`
 * grants `rc_promo_{entitlement}_{DEFAULT_COMP_DURATION}` in production, and
 * that product has to stay allowlisted even at a moment nobody holds one, or
 * the next comp half-works. Staging's allowlist has never carried a promo id,
 * so the comp tool refuses every duration there and there is nothing to keep.
 * Every product a live grant holds is required on top of this in both.
 */
export const GUARDED_PROJECTS = Object.freeze({
  // Staging.
  "ascend-staging-fa7d5": Object.freeze({
    buildConfiguration: "Staging",
    requiresCompProduct: false,
  }),
  // Production.
  "ascend-prod-9c8f2": Object.freeze({
    buildConfiguration: "Release",
    requiresCompProduct: true,
  }),
});

/**
 * Resolves a guarded project, refusing anything else.
 * @param {string} projectId Firebase project id.
 * @return {object} The guarded project's definition.
 */
export function guardedProject(projectId) {
  if (!Object.hasOwn(GUARDED_PROJECTS, projectId)) {
    throw new Error(
      `"${projectId}" is not a project the Functions secret guard covers. ` +
        `Use one of: ${Object.keys(GUARDED_PROJECTS).join(", ")}.`
    );
  }
  return {projectId, ...GUARDED_PROJECTS[projectId]};
}

/**
 * Extracts every secret the Functions source declares.
 * @param {Array<string>} sources Contents of every `functions/src` file.
 * @return {Array<string>} Sorted, de-duplicated secret names.
 */
export function parseDeclaredSecretNames(sources) {
  const names = new Set();
  const declaration = /\bdefine\w*Secret\(\s*["'`]([A-Za-z0-9_-]+)["'`]/g;
  for (const source of sources) {
    for (const match of String(source).matchAll(declaration)) {
      names.add(match[1]);
    }
  }
  return [...names].sort();
}

/**
 * Parses `functions/secret-versions.json`.
 *
 * Every guarded project maps every declared secret to a positive integer
 * version. A missing project, a missing secret and a stale extra secret are all
 * refusals: a pin nobody wrote is a version nobody reviewed.
 * @param {string} text Raw manifest.
 * @param {Array<string>} declaredSecrets Names the source declares.
 * @return {Object<string, Object<string, string>>} Pins by project, as
 *   Secret Manager version ids.
 */
export function parseSecretVersionManifest(text, declaredSecrets) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    throw new Error(
      `${SECRET_VERSION_MANIFEST_PATH} is not valid JSON: ${error.message}`
    );
  }
  if (!isPlainObject(parsed)) {
    throw new Error(`${SECRET_VERSION_MANIFEST_PATH} must be a JSON object.`);
  }

  const problems = [];
  const manifest = {};
  for (const projectId of Object.keys(parsed)) {
    if (!Object.hasOwn(GUARDED_PROJECTS, projectId)) {
      problems.push(`"${projectId}" is not a guarded project.`);
    }
  }

  for (const projectId of Object.keys(GUARDED_PROJECTS)) {
    const pins = parsed[projectId];
    if (!isPlainObject(pins)) {
      problems.push(`${projectId} has no pins.`);
      continue;
    }
    manifest[projectId] = {};
    for (const secret of declaredSecrets) {
      const version = pins[secret];
      if (!Number.isSafeInteger(version) || version <= 0) {
        problems.push(
          `${projectId} must pin ${secret} to a positive integer version.`
        );
        continue;
      }
      manifest[projectId][secret] = String(version);
    }
    for (const secret of Object.keys(pins)) {
      if (!declaredSecrets.includes(secret)) {
        problems.push(
          `${projectId} pins ${secret}, which no function in functions/src ` +
            "declares. Remove the stale pin."
        );
      }
    }
  }

  if (problems.length > 0) {
    throw new Error(
      `${SECRET_VERSION_MANIFEST_PATH} is invalid:\n  ${problems.join("\n  ")}`
    );
  }
  return manifest;
}

/**
 * Normalizes a Secret Manager version resource into its version id.
 * @param {string} name `projects/{p}/secrets/{s}/versions/{v}`.
 * @return {string} The version id.
 */
export function secretVersionId(name) {
  const match = /\/versions\/([^/]+)$/.exec(String(name ?? ""));
  if (!match) {
    throw new Error(`"${name}" is not a Secret Manager version resource.`);
  }
  return match[1];
}

/**
 * Groups the deployed functions' secret bindings by secret.
 * @param {Array<object>} functions Cloud Functions v2 `Function` resources.
 * @return {Object<string, Array<{functionId: string, version: string}>>}
 *   Bindings by secret name, each sorted by function id.
 */
export function boundSecretVersions(functions) {
  const bound = {};
  for (const fn of functions) {
    const functionId = String(fn?.name ?? "").split("/").pop();
    for (const binding of fn?.serviceConfig?.secretEnvironmentVariables ?? []) {
      const secret = String(binding?.secret ?? "").split("/").pop();
      if (!functionId || !secret) {
        continue;
      }
      (bound[secret] ??= []).push({
        functionId,
        version: String(binding.version ?? "latest"),
      });
    }
  }
  for (const bindings of Object.values(bound)) {
    bindings.sort((a, b) => a.functionId.localeCompare(b.functionId));
  }
  return bound;
}

/**
 * The distinct versions a secret is bound to, highest first.
 * @param {Array<{version: string}>} bindings One secret's bindings.
 * @return {Array<string>} Distinct version ids.
 */
export function distinctBoundVersions(bindings = []) {
  return [...new Set(bindings.map((binding) => binding.version))]
    .sort((a, b) => Number(b) - Number(a));
}

/**
 * Names the top-level keys that differ between two versions of a secret.
 *
 * Only key NAMES ever leave this function. Values are compared in memory and
 * dropped, so the result is safe to print in a deploy log.
 * @param {string} beforeText The bound version's payload.
 * @param {string} afterText The version being compared.
 * @return {{kind: string, added?: Array<string>, removed?: Array<string>,
 *   changed?: Array<string>}} What changed.
 */
export function diffSecretPayloadKeys(beforeText, afterText) {
  if (beforeText === afterText) {
    return {kind: "identical"};
  }
  const before = parseJsonObject(beforeText);
  const after = parseJsonObject(afterText);
  if (before === null || after === null) {
    return {kind: "opaque"};
  }

  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])];
  return {
    kind: "json",
    added: keys.filter((key) => !Object.hasOwn(before, key)).sort(),
    removed: keys.filter((key) => !Object.hasOwn(after, key)).sort(),
    changed: keys
      .filter((key) => Object.hasOwn(before, key) && Object.hasOwn(after, key))
      .filter((key) => canonicalJson(before[key]) !== canonicalJson(after[key]))
      .sort(),
  };
}

/**
 * Renders a key diff as a clause for a deploy log.
 * @param {object} change A `diffSecretPayloadKeys` result.
 * @return {string} The clause.
 */
export function describeKeyChange(change) {
  if (!change) {
    return "what changed could not be compared";
  }
  if (change.kind === "identical") {
    return "the payload is byte-identical";
  }
  if (change.kind === "unreadable") {
    return `the versions could not be read to compare (${change.reason})`;
  }
  if (change.kind === "opaque") {
    return "the payload changed and is not a JSON object, so no key names " +
      "can be given";
  }
  const parts = [];
  if (change.changed.length > 0) parts.push(`changed ${change.changed.join(", ")}`);
  if (change.added.length > 0) parts.push(`added ${change.added.join(", ")}`);
  if (change.removed.length > 0) parts.push(`removed ${change.removed.join(", ")}`);
  return parts.length > 0 ?
    `keys ${parts.join("; ")}` :
    "no key's value changed (formatting only)";
}

/**
 * Decides whether a deploy may bind each declared secret.
 *
 * The deploy binds `latest`, so the question is whether `latest` is the
 * version this commit pinned. When it is, a move away from the currently bound
 * version is an acknowledged change and is reported as a notice. When it is
 * not, the deploy would ship a version nobody reviewed - or not ship the one
 * they did - and that is an error.
 * @param {object} input Evaluation input.
 * @param {string} input.projectId The project being deployed.
 * @param {Array<string>} input.declaredSecrets Names the source declares.
 * @param {Object<string, string>} input.pins This project's manifest pins.
 * @param {Object<string, {version: string, state: string}>} input.latest
 *   Secret Manager's `latest` for each secret.
 * @param {Object<string, Array<{functionId: string, version: string}>>}
 *   input.bound Current bindings by secret.
 * @param {Object<string, Object<string, object>>} [input.keyChanges] Key diffs
 *   by secret, then by bound version, against `latest`.
 * @return {{errors: Array<string>, notices: Array<string>}} The verdict.
 */
export function evaluateSecretDrift({
  projectId,
  declaredSecrets,
  pins,
  latest,
  bound,
  keyChanges = {},
}) {
  const errors = [];
  const notices = [];

  for (const secret of declaredSecrets) {
    const pin = pins[secret];
    const head = latest[secret];
    const bindings = bound[secret] ?? [];
    const boundVersions = distinctBoundVersions(bindings);
    const changesFrom = (version) => keyChanges[secret]?.[version];

    if (pin === undefined) {
      errors.push(
        `${secret} is declared in functions/src but ` +
          `${SECRET_VERSION_MANIFEST_PATH} pins no version of it for ` +
          `${projectId}.`
      );
      continue;
    }
    if (!head) {
      errors.push(`${secret} has no readable latest version in ${projectId}.`);
      continue;
    }
    if (head.state !== "ENABLED") {
      errors.push(
        `${secret} version ${head.version} is the latest in ${projectId} but ` +
          `is ${head.state}. Secret Manager's latest alias still resolves ` +
          "to it, so the deploy refuses to bind anything. Add a newer version " +
          `rebuilt from the bound one and pin that (${GUARD_DOC}).`
      );
      continue;
    }

    if (head.version !== pin) {
      errors.push(
        Number(head.version) > Number(pin) ?
          unacknowledgedVersionError({
            secret,
            projectId,
            pin,
            head,
            bindings,
            boundVersions,
            changesFrom,
          }) :
          `${secret} in ${projectId}: ${SECRET_VERSION_MANIFEST_PATH} pins ` +
            `version ${pin}, but the latest version is ${head.version}, and a ` +
            `deploy binds the latest. Version ${pin} does not exist yet; ` +
            `create it before deploying this commit (${GUARD_DOC}).`
      );
      continue;
    }

    if (bindings.length === 0) {
      notices.push(
        `${secret} in ${projectId}: no deployed function binds it yet; the ` +
          `deploy will bind the pinned version ${pin}.`
      );
      continue;
    }
    for (const version of boundVersions.filter((entry) => entry !== pin)) {
      const functions = bindings
        .filter((binding) => binding.version === version)
        .map((binding) => binding.functionId)
        .join(", ");
      notices.push(
        `${secret} in ${projectId}: this deploy moves ${functions} from ` +
          `version ${version} to the pinned version ${pin} ` +
          `(${describeKeyChange(changesFrom(version))}).`
      );
    }
  }

  return {errors, notices};
}

/**
 * Explains a latest version newer than the pin.
 *
 * Disabling the version is deliberately not offered as the way out: Secret
 * Manager's `latest` alias still resolves to a disabled version, and the
 * deploy then refuses to bind it at all. The way back is a newer version
 * rebuilt from the bound one.
 * @param {object} input Message input.
 * @return {string} The error.
 */
function unacknowledgedVersionError({
  secret,
  projectId,
  pin,
  head,
  bindings,
  boundVersions,
  changesFrom,
}) {
  const moves = boundVersions
    .filter((version) => version !== head.version)
    .map((version) => {
      const functions = bindings
        .filter((binding) => binding.version === version)
        .map((binding) => binding.functionId)
        .join(", ");
      return `${functions} from version ${version} to version ` +
        `${head.version} (${describeKeyChange(changesFrom(version))})`;
    });
  let effect;
  if (moves.length > 0) {
    effect = "A Functions deploy binds the latest version, so this deploy " +
      `would move ${moves.join("; and ")}.`;
  } else if (bindings.length === 0) {
    effect = "No deployed function binds it yet, so this deploy would bind " +
      `version ${head.version}.`;
  } else {
    effect = "Every deployed function that declares it is already bound to " +
      `version ${head.version}, so this commit's pin no longer describes ` +
      "what is live.";
  }
  return `${secret} in ${projectId}: version ${head.version} is the latest, ` +
    `but ${SECRET_VERSION_MANIFEST_PATH} pins version ${pin} at this commit, ` +
    `so version ${head.version} was never acknowledged. ${effect} Review ` +
    `version ${head.version} against the version the deployed functions are ` +
    "bound to and pin it, or add a newer version rebuilt from the bound one " +
    `and pin that (${GUARD_DOC}).`;
}

/**
 * After a deploy, every binding must be exactly the pinned version.
 *
 * A version created while the deploy was running would be bound instead of
 * the one the preflight approved, and only a read of the result can see it.
 * @param {object} input Evaluation input.
 * @param {string} input.projectId The deployed project.
 * @param {Array<string>} input.declaredSecrets Names the source declares.
 * @param {Object<string, string>} input.pins This project's manifest pins.
 * @param {Object<string, Array<{functionId: string, version: string}>>}
 *   input.bound Bindings read after the deploy.
 * @return {Array<string>} Errors.
 */
export function evaluateDeployedBindings({projectId, declaredSecrets, pins, bound}) {
  const errors = [];
  for (const secret of declaredSecrets) {
    const bindings = bound[secret] ?? [];
    if (bindings.length === 0) {
      errors.push(
        `${secret}: no function deployed to ${projectId} binds it, but ` +
          "functions/src declares it."
      );
      continue;
    }
    for (const binding of bindings) {
      if (binding.version !== pins[secret]) {
        errors.push(
          `${binding.functionId} in ${projectId} is bound to ${secret} ` +
            `version ${binding.version}, not the pinned version ` +
            `${pins[secret]}, so it is running configuration this commit ` +
            "never reviewed - which is what a version created while the " +
            "deploy ran looks like."
        );
      }
    }
  }
  return errors;
}

/**
 * The products and entitlement the app's own configuration requires the
 * RevenueCat allowlist to honor, derived from code rather than remembered.
 * @param {object} input Derivation input.
 * @param {string} input.projectId The guarded project.
 * @param {string} input.pbxproj Contents of the Xcode project file.
 * @param {string} input.monetizationSource Contents of
 *   `MonetizationConfiguration.swift`.
 * @return {{entitlementId: string,
 *   products: Array<{productId: string, reasons: Array<string>}>}} The floor.
 */
export function requiredAllowlistFloor({projectId, pbxproj, monetizationSource}) {
  const project = guardedProject(projectId);
  const configuration = appBuildConfigurations(pbxproj).get(
    project.buildConfiguration
  );
  if (!configuration) {
    throw new Error(
      `The Xcode project has no ${project.buildConfiguration} configuration ` +
        "for the app target, so the products it sells cannot be derived."
    );
  }

  const products = new Map();
  const addRequirement = (productId, reason) => {
    if (!products.has(productId)) products.set(productId, []);
    products.get(productId).push(reason);
  };

  const setting = /^\s*(ASCEND_REVENUECAT_\w+_PRODUCT_ID) = "?([^";]*)"?;$/gm;
  for (const [, name, value] of configuration.buildSettings.matchAll(setting)) {
    const productId = value.trim();
    if (productId === "" || productId.startsWith("$(")) {
      throw new Error(
        `${name} is not a literal product id in the ` +
          `${project.buildConfiguration} configuration.`
      );
    }
    addRequirement(
      productId,
      `the ${project.buildConfiguration} build sells it (${name})`
    );
  }
  if (products.size === 0) {
    throw new Error(
      `The ${project.buildConfiguration} configuration declares no ` +
        "ASCEND_REVENUECAT_*_PRODUCT_ID, so the invariant would assert nothing."
    );
  }

  const entitlements = [
    ...String(monetizationSource).matchAll(
      /revenueCatEntitlementID:\s*String\s*=\s*"([^"]+)"/g
    ),
  ].map((match) => match[1]);
  if (entitlements.length !== 1) {
    throw new Error(
      "MonetizationConfiguration.swift must declare exactly one default " +
        `revenueCatEntitlementID; found ${entitlements.length}.`
    );
  }
  const [entitlementId] = entitlements;

  if (project.requiresCompProduct) {
    addRequirement(
      promotionalProductId(entitlementId, DEFAULT_COMP_DURATION),
      `scripts/comp-access.mjs grants it (${DEFAULT_COMP_DURATION} comps)`
    );
  }

  return {
    entitlementId,
    products: [...products.entries()]
      .map(([productId, reasons]) => ({productId, reasons}))
      .sort((a, b) => a.productId.localeCompare(b.productId)),
  };
}

/**
 * Whether a grant still confers access at `now`.
 *
 * A grant with no readable `accessUntil` is treated as live: calling it
 * expired would excuse exactly the loss this guard exists to catch.
 * @param {{accessUntil: ?string}} grant A grant.
 * @param {Date} now The moment of the check.
 * @return {boolean} True while it grants access.
 */
export function isUnexpiredGrant(grant, now) {
  if (grant.accessUntil === null || grant.accessUntil === undefined) {
    return true;
  }
  const until = Date.parse(grant.accessUntil);
  return Number.isNaN(until) || until > now.getTime();
}

/**
 * Adds every product a live grant holds to the required set.
 * @param {object} floor A `requiredAllowlistFloor` result.
 * @param {Array<{uid: string, productId: ?string, accessUntil: ?string}>}
 *   grants Grants read from the project.
 * @param {Date} now The moment of the check.
 * @return {Array<{productId: string, reasons: Array<string>}>} Required
 *   products.
 */
export function requiredProducts(floor, grants, now) {
  const products = new Map(
    floor.products.map((entry) => [entry.productId, [...entry.reasons]])
  );
  const holders = new Map();
  for (const grant of grants.filter((entry) => isUnexpiredGrant(entry, now))) {
    const productId = grant.productId ?? "(no productId)";
    holders.set(productId, (holders.get(productId) ?? 0) + 1);
  }
  for (const [productId, count] of holders) {
    if (!products.has(productId)) products.set(productId, []);
    products.get(productId).push(
      `${count} live app_access grant${count === 1 ? "" : "s"} hold it`
    );
  }
  return [...products.entries()]
    .map(([productId, reasons]) => ({productId, reasons}))
    .sort((a, b) => a.productId.localeCompare(b.productId));
}

/**
 * Checks one version of `REVENUECAT_SERVER_CONFIG` against the required set.
 *
 * Product ids are identifiers the app ships and grants carry, not secrets, so
 * a missing one is named. Nothing is ever read out of the payload into a
 * message.
 * @param {object} input Evaluation input.
 * @param {string} input.projectId The project.
 * @param {string} input.version The version checked.
 * @param {string} input.payloadText The version's payload.
 * @param {string} input.entitlementId The app's entitlement id.
 * @param {Array<{productId: string, reasons: Array<string>}>} input.required
 *   Products that must stay allowlisted.
 * @return {{errors: Array<string>, allowedProductIds: ?Array<string>}} The
 *   verdict and the allowlist it read.
 */
export function evaluateAllowlistInvariant({
  projectId,
  version,
  payloadText,
  entitlementId,
  required,
}) {
  const subject = `${REVENUECAT_SECRET} version ${version} in ${projectId}`;
  const config = parseJsonObject(payloadText);
  if (config === null) {
    return {
      errors: [`${subject} is not a JSON object, so it cannot be checked.`],
      allowedProductIds: null,
    };
  }

  const errors = [];
  if (config.entitlementId !== entitlementId) {
    errors.push(
      `${subject} does not name the app's entitlement "${entitlementId}" ` +
        "in entitlementId, so every subscriber would be projected inactive " +
        "and every users/{uid}/entitlements grant deleted."
    );
  }

  const allowed = config.allowedProductIds;
  if (
    !Array.isArray(allowed) ||
    allowed.length === 0 ||
    !allowed.every((entry) => typeof entry === "string")
  ) {
    errors.push(`${subject} has no allowedProductIds array of strings.`);
    return {errors, allowedProductIds: null};
  }

  for (const {productId, reasons} of required) {
    if (!allowed.includes(productId)) {
      errors.push(
        `${subject} does not allowlist ${productId}, which ` +
          `${reasons.join(" and ")}. The webhook and reconcileAppAccess would ` +
          "project those climbers inactive and delete their " +
          "users/{uid}/entitlements/app_access grant, and every paid screen " +
          "would fail for them."
      );
    }
  }

  return {errors, allowedProductIds: [...allowed]};
}

/**
 * Builds the pre-deploy grant snapshot the post-deploy check compares with.
 * @param {object} input Snapshot input.
 * @return {object} The snapshot.
 */
export function buildGrantSnapshot({projectId, takenAt, entitlementId, grants, ledger}) {
  return {
    schemaVersion: GRANT_SNAPSHOT_SCHEMA_VERSION,
    projectId,
    takenAt: takenAt.toISOString(),
    entitlementId,
    grants: [...grants].sort((a, b) => a.uid.localeCompare(b.uid)),
    ledger: [...ledger].sort((a, b) => a.uid.localeCompare(b.uid)),
  };
}

/**
 * Parses a snapshot, refusing one taken for a different project.
 * @param {string} text Raw snapshot.
 * @param {string} projectId The project being verified.
 * @return {object} The snapshot.
 */
export function parseGrantSnapshot(text, projectId) {
  const snapshot = parseJsonObject(text);
  if (
    snapshot === null ||
    snapshot.schemaVersion !== GRANT_SNAPSHOT_SCHEMA_VERSION ||
    !Array.isArray(snapshot.grants) ||
    !Array.isArray(snapshot.ledger) ||
    typeof snapshot.entitlementId !== "string"
  ) {
    throw new Error("The grant snapshot is not one the preflight wrote.");
  }
  if (snapshot.projectId !== projectId) {
    throw new Error(
      `The grant snapshot was taken for ${snapshot.projectId}, not ` +
        `${projectId}.`
    );
  }
  return snapshot;
}

/**
 * Decides whether every pre-deploy grant survived the Functions deploy.
 *
 * A grant is only deleted when a webhook delivery or a reconciliation next
 * runs for that climber, which can be minutes or days after the deploy - the
 * captain's went 64 minutes after the 1.1 deploy. So a grant that still
 * exists is not enough: it also has to be allowlisted by the version the
 * functions are now bound to, or the loss is only waiting for its trigger.
 * @param {object} input Evaluation input.
 * @param {object} input.snapshot The preflight's snapshot.
 * @param {Array<object>} input.currentGrants Grants read after the deploy.
 * @param {Array<string>} input.allowedProductIds The bound allowlist.
 * @param {Object<string, object>} [input.statusByUid] Entitlement status for
 *   each lost grant, to help triage.
 * @param {Date} input.now The moment of the check.
 * @return {{errors: Array<string>, warnings: Array<string>,
 *   summary: string}} The verdict.
 */
export function evaluateGrantSurvival({
  snapshot,
  currentGrants,
  allowedProductIds,
  statusByUid = {},
  now,
}) {
  const errors = [];
  const warnings = [];
  const current = new Map(currentGrants.map((grant) => [grant.uid, grant]));
  const allowed = new Set(allowedProductIds);
  const comped = new Set(
    snapshot.ledger
      .filter((entry) => entry.lastAction === "grant")
      .map((entry) => entry.uid)
  );
  const grantPath = `users/{uid}/entitlements/${snapshot.entitlementId}`;

  let verified = 0;
  let expired = 0;
  for (const before of snapshot.grants) {
    if (!isUnexpiredGrant(before, now)) {
      expired += 1;
      continue;
    }
    const who = `${before.uid}${comped.has(before.uid) ? " (comped)" : ""}`;
    const after = current.get(before.uid);
    if (!after) {
      errors.push(
        `LOST: ${who} held ${grantPath} (${before.productId}) before this ` +
          `deploy and no longer does. ${describeStatus(statusByUid[before.uid])}`
      );
      continue;
    }
    const productId = after.productId ?? before.productId;
    if (!allowed.has(productId)) {
      errors.push(
        `WILL BE LOST: ${who} holds ${grantPath} for ${productId}, which the ` +
          "version the functions are now bound to does not allowlist. Their " +
          "next webhook delivery or reconcileAppAccess call deletes it."
      );
      continue;
    }
    verified += 1;
  }

  const held = new Set(snapshot.grants.map((grant) => grant.uid));
  for (const entry of snapshot.ledger) {
    if (entry.lastAction === "grant" && !held.has(entry.uid)) {
      warnings.push(
        `comp_grants records a comp for ${entry.uid} ` +
          `(${entry.productId ?? "unknown product"}, landing ` +
          `${entry.landing ?? "unknown"}), but it held no ${grantPath} before ` +
          "this deploy either. That gap predates this deploy; check it with " +
          "scripts/comp-access.mjs."
      );
    }
  }

  const compedHeld = [...comped].filter((uid) => held.has(uid)).length;
  return {
    errors,
    warnings,
    summary:
      `${verified} of ${snapshot.grants.length} pre-deploy grant(s) still ` +
      `held and allowlisted (${compedHeld} of them comped per comp_grants)` +
      (expired > 0 ? `; ${expired} expired during the deploy` : "") +
      ".",
  };
}

function describeStatus(status) {
  if (!status) {
    return "Its entitlement_status document is missing too.";
  }
  return `Its entitlement_status says isActive ${status.isActive}, ` +
    `sourceEventType ${status.sourceEventType ?? "unknown"}, verified ` +
    `${status.verifiedAt ?? "unknown"}. A refund or an expiry is ` +
    "legitimate, and re-running the job takes a fresh snapshot; anything " +
    "else means the functions refused a product RevenueCat still grants.";
}

function parseJsonObject(text) {
  try {
    const value = JSON.parse(text);
    return isPlainObject(value) ? value : null;
  } catch {
    return null;
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (isPlainObject(value)) {
    return `{${Object.keys(value).sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}
