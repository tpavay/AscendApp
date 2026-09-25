import assert from "node:assert/strict";
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {dirname, join, resolve} from "node:path";
import {test} from "node:test";
import {fileURLToPath} from "node:url";

import {
  createFunctionsSecretBackend,
  decodeFirestoreValue,
} from "../lib/functions-secret-backend.mjs";
import {
  GUARDED_PROJECTS,
  REVENUECAT_SECRET,
  SECRET_VERSION_MANIFEST_PATH,
  boundSecretVersions,
  buildGrantSnapshot,
  describeKeyChange,
  diffSecretPayloadKeys,
  evaluateAllowlistInvariant,
  evaluateDeployedBindings,
  evaluateGrantSurvival,
  evaluateSecretDrift,
  parseDeclaredSecretNames,
  parseGrantSnapshot,
  parseSecretVersionManifest,
  requiredAllowlistFloor,
  requiredProducts,
} from "../lib/functions-secret-guard.mjs";
import {GoogleApiError, createGoogleRestClient} from "../lib/google-rest-client.mjs";
import {
  PINNED_FIREBASE_TOOLS_VERSION,
  createGoogleAccessTokenSource,
  resolvePinnedFirebaseToolsRoot,
} from "../lib/pinned-firebase-tools.mjs";
import {
  EXIT,
  readRepositoryInputs,
  runPreflight,
  runVerifyDeploy,
} from "../verify-functions-secrets.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PRODUCTION = "ascend-prod-9c8f2";
const STAGING = "ascend-staging-fa7d5";
const PROMO = "rc_promo_app_access_lifetime";
const NOW = new Date("2026-09-25T20:00:00Z");
const LIFETIME = "2226-07-08T16:14:30Z";

// Stand-ins for the secret fields. The whole suite asserts none of them ever
// reaches a log line.
const SECRET_VALUES = Object.freeze({
  apiKey: "sk_live_api_key_value_that_must_never_be_printed",
  webhookAuthorization: "Bearer webhook-authorization-value-never-printed",
  webhookSigningSecret: "whsec_signing_secret_value_that_must_never_print",
  appId: "app1a2b3c4d5",
});

function revenueCatConfig(allowedProductIds, overrides = {}) {
  return JSON.stringify({
    ...SECRET_VALUES,
    entitlementId: "app_access",
    allowedProductIds,
    ...overrides,
  });
}

// The versions the 2026-09-25 incident moved between. Version 3 was built
// from a stale local copy and dropped the promo id every comp carries.
const V2 = revenueCatConfig(["ascend_yearly", "ascend_monthly", PROMO]);
const V3 = revenueCatConfig(["ascend_lifetime", "ascend_monthly", "ascend_yearly"]);
const V4 = revenueCatConfig(["ascend_lifetime", "ascend_monthly", "ascend_yearly", PROMO]);

const repository = readRepositoryInputs(REPO_ROOT);

function manifestWith(projectId, pins) {
  const manifest = JSON.parse(repository.manifestText);
  manifest[projectId] = {...manifest[projectId], ...pins};
  return JSON.stringify(manifest);
}

function functionResource(id, bindings) {
  return {
    name: `projects/${PRODUCTION}/locations/us-central1/functions/${id}`,
    serviceConfig: {
      secretEnvironmentVariables: Object.entries(bindings).map(([secret, version]) => ({
        key: secret,
        projectId: PRODUCTION,
        secret,
        version: String(version),
      })),
    },
  };
}

function productionFunctions({revenueCat = 4} = {}) {
  return [
    functionResource("revenueCatWebhook", {[REVENUECAT_SECRET]: revenueCat}),
    functionResource("reconcileAppAccess", {[REVENUECAT_SECRET]: revenueCat}),
    functionResource("processRevenueCatAnalyticsOutbox", {MIXPANEL_SERVER_CONFIG: 2}),
    functionResource("processEmailJobs", {TRANSACTIONAL_EMAIL_CONFIG: 1}),
    functionResource("onWorkoutWritten", {}),
  ];
}

const compedGrants = [
  {uid: "captain", productId: PROMO, accessUntil: LIFETIME},
  {uid: "viktor", productId: PROMO, accessUntil: LIFETIME},
];
const compLedger = [
  {uid: "captain", lastAction: "grant", productId: PROMO, landing: "LANDED"},
  {uid: "viktor", lastAction: "grant", productId: PROMO, landing: "LANDED"},
];

/**
 * An in-memory project the CLI's run functions read through.
 */
function fakeBackend({
  latest = {
    [REVENUECAT_SECRET]: {version: "4", state: "ENABLED"},
    MIXPANEL_SERVER_CONFIG: {version: "2", state: "ENABLED"},
    TRANSACTIONAL_EMAIL_CONFIG: {version: "1", state: "ENABLED"},
  },
  payloads = {
    [`${REVENUECAT_SECRET}@2`]: V2,
    [`${REVENUECAT_SECRET}@3`]: V3,
    [`${REVENUECAT_SECRET}@4`]: V4,
  },
  functions = productionFunctions(),
  grants = compedGrants,
  ledger = compLedger,
  status = {},
  failWith = null,
} = {}) {
  const fail = () => {
    if (failWith) throw failWith;
  };
  return {
    accessed: [],
    async latestSecretVersion(secret) {
      fail();
      return latest[secret] ?? null;
    },
    async accessSecretVersion(secret, version) {
      fail();
      this.accessed.push(`${secret}@${version}`);
      const payload = payloads[`${secret}@${version}`];
      if (payload === undefined) throw new Error(`no ${secret}@${version}`);
      return payload;
    },
    async listFunctions() {
      fail();
      return functions;
    },
    async listGrants() {
      fail();
      return grants;
    },
    async listCompLedger() {
      fail();
      return ledger;
    },
    async readEntitlementStatus(uid) {
      return status[uid] ?? null;
    },
  };
}

function capturingLog() {
  const lines = [];
  const record = (level) => (message) => lines.push({level, message});
  return {
    lines,
    log: {
      info: record("info"),
      notice: record("notice"),
      warning: record("warning"),
      error: record("error"),
    },
    text: () => lines.map((line) => `${line.level}: ${line.message}`).join("\n"),
    errors: () => lines.filter((line) => line.level === "error").map((line) => line.message),
  };
}

function assertNoSecretValues(text) {
  for (const [field, value] of Object.entries(SECRET_VALUES)) {
    assert.ok(!text.includes(value), `the ${field} value reached the log`);
  }
}

function snapshotDirectory() {
  return mkdtempSync(join(tmpdir(), "ascend-secret-guard-"));
}

// ---------------------------------------------------------------------------
// The committed contract
// ---------------------------------------------------------------------------

test("the functions source declares the secrets the manifest pins, for every guarded project", () => {
  const declared = parseDeclaredSecretNames(repository.functionSources);
  assert.deepEqual(declared, [
    "MIXPANEL_SERVER_CONFIG",
    "REVENUECAT_SERVER_CONFIG",
    "TRANSACTIONAL_EMAIL_CONFIG",
  ]);

  const manifest = parseSecretVersionManifest(repository.manifestText, declared);
  assert.deepEqual(Object.keys(manifest).sort(), Object.keys(GUARDED_PROJECTS).sort());
  for (const pins of Object.values(manifest)) {
    assert.deepEqual(Object.keys(pins).sort(), declared);
  }
});

test("every secret declaration form is found, so a new one cannot slip past the manifest", () => {
  assert.deepEqual(
    parseDeclaredSecretNames([
      'export const a = defineSecret("ALPHA_CONFIG");',
      "const b = defineJsonSecret('BETA_CONFIG');",
      "defineSecret(\n  `GAMMA_CONFIG`\n)",
      'defineSecret("ALPHA_CONFIG")',
    ]),
    ["ALPHA_CONFIG", "BETA_CONFIG", "GAMMA_CONFIG"]
  );
});

test("the manifest refuses a missing, unknown, stale or non-integer pin", () => {
  const declared = ["ALPHA", "BETA"];
  const valid = {
    [STAGING]: {ALPHA: 1, BETA: 2},
    [PRODUCTION]: {ALPHA: 3, BETA: 4},
  };
  assert.deepEqual(parseSecretVersionManifest(JSON.stringify(valid), declared), {
    [STAGING]: {ALPHA: "1", BETA: "2"},
    [PRODUCTION]: {ALPHA: "3", BETA: "4"},
  });

  const cases = [
    [{[STAGING]: valid[STAGING]}, new RegExp(`${PRODUCTION} has no pins`)],
    [{...valid, "ascend-f2e4f": {ALPHA: 1, BETA: 1}}, /"ascend-f2e4f" is not a guarded project/],
    [{...valid, [PRODUCTION]: {ALPHA: 3}}, /must pin BETA to a positive integer/],
    [{...valid, [PRODUCTION]: {ALPHA: 3, BETA: 4, GONE: 1}}, /pins GONE, which no function/],
    [{...valid, [PRODUCTION]: {ALPHA: "3", BETA: 4}}, /must pin ALPHA to a positive integer/],
    [{...valid, [PRODUCTION]: {ALPHA: 0, BETA: 4}}, /must pin ALPHA to a positive integer/],
  ];
  for (const [manifest, pattern] of cases) {
    assert.throws(() => parseSecretVersionManifest(JSON.stringify(manifest), declared), pattern);
  }
  assert.throws(() => parseSecretVersionManifest("{", declared), /not valid JSON/);
});

test("the required products are derived from the app's own configuration", () => {
  const production = requiredAllowlistFloor({projectId: PRODUCTION, ...repository});
  assert.equal(production.entitlementId, "app_access");
  assert.deepEqual(
    production.products.map((entry) => entry.productId),
    ["ascend_monthly", "ascend_yearly", PROMO]
  );
  assert.match(
    production.products.find((entry) => entry.productId === PROMO).reasons.join(),
    /comp-access\.mjs grants it \(lifetime comps\)/
  );
  assert.match(
    production.products.find((entry) => entry.productId === "ascend_yearly").reasons.join(),
    /Release build sells it \(ASCEND_REVENUECAT_YEARLY_PRODUCT_ID\)/
  );

  const staging = requiredAllowlistFloor({projectId: STAGING, ...repository});
  assert.deepEqual(
    staging.products.map((entry) => entry.productId),
    ["ascend_staging_monthly", "ascend_staging_yearly"]
  );
});

test("the floor refuses to assert nothing", () => {
  assert.throws(
    () => requiredAllowlistFloor({
      projectId: PRODUCTION,
      pbxproj: repository.pbxproj.replaceAll("ASCEND_REVENUECAT_", "ASCEND_OTHER_"),
      monetizationSource: repository.monetizationSource,
    }),
    /declares no ASCEND_REVENUECAT_\*_PRODUCT_ID/
  );
  assert.throws(
    () => requiredAllowlistFloor({
      projectId: PRODUCTION,
      pbxproj: repository.pbxproj,
      monetizationSource: "struct Nothing {}",
    }),
    /exactly one default revenueCatEntitlementID; found 0/
  );
  assert.throws(
    () => requiredAllowlistFloor({projectId: "ascend-f2e4f", ...repository}),
    /not a project the Functions secret guard covers/
  );
});

// ---------------------------------------------------------------------------
// Key diffs
// ---------------------------------------------------------------------------

test("a changed secret is described by key names and never by values", () => {
  const change = diffSecretPayloadKeys(V2, V3);
  assert.deepEqual(change, {
    kind: "json",
    added: [],
    removed: [],
    changed: ["allowedProductIds"],
  });
  const described = describeKeyChange(change);
  assert.equal(described, "keys changed allowedProductIds");
  assertNoSecretValues(described);
  assert.ok(!described.includes(PROMO));

  const rotated = diffSecretPayloadKeys(
    V4,
    revenueCatConfig(["ascend_lifetime"], {apiKey: "sk_live_rotated", newField: true, appId: undefined})
  );
  assert.deepEqual(rotated, {
    kind: "json",
    added: ["newField"],
    removed: ["appId"],
    changed: ["allowedProductIds", "apiKey"],
  });
  assert.equal(
    describeKeyChange(rotated),
    "keys changed allowedProductIds, apiKey; added newField; removed appId"
  );

  assert.deepEqual(diffSecretPayloadKeys(V4, V4), {kind: "identical"});
  assert.deepEqual(
    diffSecretPayloadKeys('{"a":{"x":1,"y":2}}', '{ "a": {"y":2, "x":1} }'),
    {kind: "json", added: [], removed: [], changed: []}
  );
  assert.equal(
    describeKeyChange(diffSecretPayloadKeys('{"a":1}', '{ "a": 1 }')),
    "no key's value changed (formatting only)"
  );
  assert.deepEqual(diffSecretPayloadKeys("plain-token-one", "plain-token-two"), {kind: "opaque"});
  assert.doesNotMatch(describeKeyChange({kind: "opaque"}), /plain-token/);
});

// ---------------------------------------------------------------------------
// Drift
// ---------------------------------------------------------------------------

const declaredRevenueCat = [REVENUECAT_SECRET];
const incidentBindings = boundSecretVersions(productionFunctions({revenueCat: 2}));

test("the 2026-09-25 rebind is refused, naming the functions, the versions and the changed key", () => {
  const {errors, notices} = evaluateSecretDrift({
    projectId: PRODUCTION,
    declaredSecrets: declaredRevenueCat,
    pins: {[REVENUECAT_SECRET]: "2"},
    latest: {[REVENUECAT_SECRET]: {version: "3", state: "ENABLED"}},
    bound: incidentBindings,
    keyChanges: {[REVENUECAT_SECRET]: {"2": diffSecretPayloadKeys(V2, V3)}},
  });

  assert.deepEqual(notices, []);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /REVENUECAT_SERVER_CONFIG in ascend-prod-9c8f2: version 3 is the latest/);
  assert.match(errors[0], /pins version 2 at this commit, so version 3 was never acknowledged/);
  assert.match(
    errors[0],
    /would move reconcileAppAccess, revenueCatWebhook from version 2 to version 3 \(keys changed allowedProductIds\)/
  );
  assert.match(errors[0], /add a newer version rebuilt from the bound one/);
  assertNoSecretValues(errors[0]);
});

test("an acknowledged version is a notice that still names what changes", () => {
  const {errors, notices} = evaluateSecretDrift({
    projectId: PRODUCTION,
    declaredSecrets: declaredRevenueCat,
    pins: {[REVENUECAT_SECRET]: "4"},
    latest: {[REVENUECAT_SECRET]: {version: "4", state: "ENABLED"}},
    bound: boundSecretVersions(productionFunctions({revenueCat: 3})),
    keyChanges: {[REVENUECAT_SECRET]: {"3": diffSecretPayloadKeys(V3, V4)}},
  });
  assert.deepEqual(errors, []);
  assert.deepEqual(notices, [
    "REVENUECAT_SERVER_CONFIG in ascend-prod-9c8f2: this deploy moves " +
      "reconcileAppAccess, revenueCatWebhook from version 3 to the pinned " +
      "version 4 (keys changed allowedProductIds).",
  ]);
});

test("every other drift shape is refused", () => {
  const base = {
    projectId: PRODUCTION,
    declaredSecrets: declaredRevenueCat,
    bound: boundSecretVersions(productionFunctions({revenueCat: 4})),
  };
  const cases = [
    [
      "a live version the commit never pinned",
      {pins: {[REVENUECAT_SECRET]: "3"}, latest: {[REVENUECAT_SECRET]: {version: "4", state: "ENABLED"}}},
      /already bound to version 4, so this commit's pin no longer describes what is live/,
    ],
    [
      "a pin ahead of Secret Manager",
      {pins: {[REVENUECAT_SECRET]: "5"}, latest: {[REVENUECAT_SECRET]: {version: "4", state: "ENABLED"}}},
      /pins version 5, but the latest version is 4[\s\S]*Version 5 does not exist yet/,
    ],
    [
      "a disabled latest version",
      {pins: {[REVENUECAT_SECRET]: "5"}, latest: {[REVENUECAT_SECRET]: {version: "5", state: "DISABLED"}}},
      /version 5 is the latest in ascend-prod-9c8f2 but is DISABLED[\s\S]*latest alias still resolves to it/,
    ],
    [
      "an unpinned version of a secret nothing binds yet",
      {
        declaredSecrets: ["NEW_CONFIG"],
        pins: {NEW_CONFIG: "1"},
        latest: {NEW_CONFIG: {version: "2", state: "ENABLED"}},
      },
      /version 2 was never acknowledged\. No deployed function binds it yet, so this deploy would bind version 2\./,
    ],
    [
      "a secret with no latest version",
      {pins: {[REVENUECAT_SECRET]: "4"}, latest: {}},
      /has no readable latest version/,
    ],
    [
      "a declared secret the manifest does not pin",
      {pins: {}, latest: {[REVENUECAT_SECRET]: {version: "4", state: "ENABLED"}}},
      /pins no version of it for ascend-prod-9c8f2/,
    ],
  ];
  for (const [name, input, pattern] of cases) {
    const {errors} = evaluateSecretDrift({...base, ...input});
    assert.equal(errors.length, 1, name);
    assert.match(errors[0], pattern, name);
  }
});

test("a secret no function binds yet is allowed at its pinned version", () => {
  const {errors, notices} = evaluateSecretDrift({
    projectId: STAGING,
    declaredSecrets: ["NEW_CONFIG"],
    pins: {NEW_CONFIG: "1"},
    latest: {NEW_CONFIG: {version: "1", state: "ENABLED"}},
    bound: {},
  });
  assert.deepEqual(errors, []);
  assert.match(notices[0], /no deployed function binds it yet/);
});

test("bindings are grouped by secret from the Cloud Functions resources", () => {
  assert.deepEqual(boundSecretVersions(productionFunctions({revenueCat: 3})), {
    [REVENUECAT_SECRET]: [
      {functionId: "reconcileAppAccess", version: "3"},
      {functionId: "revenueCatWebhook", version: "3"},
    ],
    MIXPANEL_SERVER_CONFIG: [{functionId: "processRevenueCatAnalyticsOutbox", version: "2"}],
    TRANSACTIONAL_EMAIL_CONFIG: [{functionId: "processEmailJobs", version: "1"}],
  });
});

test("a deploy that bound anything but the pin is refused afterwards", () => {
  const errors = evaluateDeployedBindings({
    projectId: PRODUCTION,
    declaredSecrets: [REVENUECAT_SECRET, "MIXPANEL_SERVER_CONFIG", "UNBOUND_CONFIG"],
    pins: {[REVENUECAT_SECRET]: "4", MIXPANEL_SERVER_CONFIG: "2", UNBOUND_CONFIG: "1"},
    bound: boundSecretVersions([
      functionResource("revenueCatWebhook", {[REVENUECAT_SECRET]: 5}),
      functionResource("reconcileAppAccess", {[REVENUECAT_SECRET]: 4}),
      functionResource("processRevenueCatAnalyticsOutbox", {MIXPANEL_SERVER_CONFIG: 2}),
    ]),
  });
  assert.equal(errors.length, 2);
  assert.match(errors[0], /revenueCatWebhook in ascend-prod-9c8f2 is bound to REVENUECAT_SERVER_CONFIG version 5, not the pinned version 4/);
  assert.match(errors[1], /UNBOUND_CONFIG: no function deployed/);
});

// ---------------------------------------------------------------------------
// The allowlist invariant
// ---------------------------------------------------------------------------

const productionFloor = requiredAllowlistFloor({projectId: PRODUCTION, ...repository});

test("version 3's allowlist fails the production invariant and version 4's passes", () => {
  const required = requiredProducts(productionFloor, compedGrants, NOW);
  const v3 = evaluateAllowlistInvariant({
    projectId: PRODUCTION,
    version: "3",
    payloadText: V3,
    entitlementId: "app_access",
    required,
  });
  assert.equal(v3.errors.length, 1);
  assert.match(
    v3.errors[0],
    /REVENUECAT_SERVER_CONFIG version 3 in ascend-prod-9c8f2 does not allowlist rc_promo_app_access_lifetime, which scripts\/comp-access\.mjs grants it \(lifetime comps\) and 2 live app_access grants hold it/
  );
  assertNoSecretValues(v3.errors[0]);

  const v4 = evaluateAllowlistInvariant({
    projectId: PRODUCTION,
    version: "4",
    payloadText: V4,
    entitlementId: "app_access",
    required,
  });
  assert.deepEqual(v4.errors, []);
  assert.deepEqual(v4.allowedProductIds, JSON.parse(V4).allowedProductIds);
});

test("the comp product is required in production even when nobody holds a comp", () => {
  const {errors} = evaluateAllowlistInvariant({
    projectId: PRODUCTION,
    version: "3",
    payloadText: V3,
    entitlementId: "app_access",
    required: requiredProducts(productionFloor, [], NOW),
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /does not allowlist rc_promo_app_access_lifetime/);
});

test("every product a live grant holds is required, and an expired grant holds nothing", () => {
  const stagingFloor = requiredAllowlistFloor({projectId: STAGING, ...repository});
  const required = requiredProducts(stagingFloor, [
    {uid: "a", productId: "ascend_staging_lifetime", accessUntil: LIFETIME},
    {uid: "b", productId: "ascend_staging_lifetime", accessUntil: null},
    {uid: "c", productId: "rc_promo_app_access_weekly", accessUntil: "2026-09-01T00:00:00Z"},
  ], NOW);
  assert.deepEqual(required.map((entry) => entry.productId), [
    "ascend_staging_lifetime",
    "ascend_staging_monthly",
    "ascend_staging_yearly",
  ]);
  assert.deepEqual(required[0].reasons, ["2 live app_access grants hold it"]);

  const {errors} = evaluateAllowlistInvariant({
    projectId: STAGING,
    version: "3",
    payloadText: revenueCatConfig(["ascend_staging_monthly", "ascend_staging_yearly"]),
    entitlementId: "app_access",
    required,
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /does not allowlist ascend_staging_lifetime, which 2 live app_access grants hold it/);
});

test("an entitlement or allowlist the functions cannot use is refused without quoting it", () => {
  const required = requiredProducts(productionFloor, [], NOW);
  const wrongEntitlement = evaluateAllowlistInvariant({
    projectId: PRODUCTION,
    version: "5",
    payloadText: revenueCatConfig(JSON.parse(V4).allowedProductIds, {entitlementId: "premium_secret_name"}),
    entitlementId: "app_access",
    required,
  });
  assert.equal(wrongEntitlement.errors.length, 1);
  assert.match(wrongEntitlement.errors[0], /does not name the app's entitlement "app_access"/);
  assert.ok(!wrongEntitlement.errors[0].includes("premium_secret_name"));

  const noAllowlist = evaluateAllowlistInvariant({
    projectId: PRODUCTION,
    version: "5",
    payloadText: revenueCatConfig(undefined),
    entitlementId: "app_access",
    required,
  });
  assert.match(noAllowlist.errors.at(-1), /has no allowedProductIds array of strings/);
  assert.equal(noAllowlist.allowedProductIds, null);

  const notJson = evaluateAllowlistInvariant({
    projectId: PRODUCTION,
    version: "5",
    payloadText: "not json at all",
    entitlementId: "app_access",
    required,
  });
  assert.deepEqual(notJson.errors, [
    "REVENUECAT_SERVER_CONFIG version 5 in ascend-prod-9c8f2 is not a JSON object, so it cannot be checked.",
  ]);
});

// ---------------------------------------------------------------------------
// Grant survival
// ---------------------------------------------------------------------------

function survivalSnapshot(grants = compedGrants, ledger = compLedger) {
  return buildGrantSnapshot({
    projectId: PRODUCTION,
    takenAt: NOW,
    entitlementId: "app_access",
    grants,
    ledger,
  });
}

test("every pre-deploy grant that still exists and is allowlisted survives", () => {
  const result = evaluateGrantSurvival({
    snapshot: survivalSnapshot(),
    currentGrants: compedGrants,
    allowedProductIds: JSON.parse(V4).allowedProductIds,
    now: NOW,
  });
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.warnings, []);
  assert.equal(
    result.summary,
    "2 of 2 pre-deploy grant(s) still held and allowlisted (2 of them comped per comp_grants)."
  );
});

test("a grant the deploy deleted, or will delete on the next reconcile, fails loudly", () => {
  const result = evaluateGrantSurvival({
    snapshot: survivalSnapshot(),
    currentGrants: [compedGrants[1]],
    allowedProductIds: JSON.parse(V3).allowedProductIds,
    statusByUid: {
      captain: {
        isActive: false,
        sourceEventType: "CLIENT_RECONCILIATION",
        verifiedAt: "2026-09-25T21:00:48Z",
      },
    },
    now: NOW,
  });
  assert.equal(result.errors.length, 2);
  assert.match(
    result.errors[0],
    /^LOST: captain \(comped\) held users\/\{uid\}\/entitlements\/app_access \(rc_promo_app_access_lifetime\) before this deploy and no longer does\. Its entitlement_status says isActive false, sourceEventType CLIENT_RECONCILIATION/
  );
  assert.match(
    result.errors[1],
    /^WILL BE LOST: viktor \(comped\) holds users\/\{uid\}\/entitlements\/app_access for rc_promo_app_access_lifetime, which the version the functions are now bound to does not allowlist/
  );
});

test("a grant that expired during the deploy is not a loss, and a pre-existing ledger gap is a warning", () => {
  const snapshot = survivalSnapshot(
    [
      {uid: "captain", productId: PROMO, accessUntil: LIFETIME},
      {uid: "lapsed", productId: "ascend_monthly", accessUntil: "2026-09-25T19:59:00Z"},
    ],
    [
      ...compLedger,
      {uid: "revoked", lastAction: "revoke", productId: PROMO, landing: null},
    ]
  );
  const result = evaluateGrantSurvival({
    snapshot,
    currentGrants: [compedGrants[0]],
    allowedProductIds: JSON.parse(V4).allowedProductIds,
    now: NOW,
  });
  assert.deepEqual(result.errors, []);
  assert.equal(result.warnings.length, 1);
  assert.match(
    result.warnings[0],
    /comp_grants records a comp for viktor \(rc_promo_app_access_lifetime, landing LANDED\), but it held no users\/\{uid\}\/entitlements\/app_access before this deploy either/
  );
  assert.match(result.summary, /1 of 2 pre-deploy grant\(s\) still held and allowlisted \(1 of them comped per comp_grants\); 1 expired during the deploy/);
});

test("a snapshot from another project or another tool is refused", () => {
  const text = JSON.stringify(survivalSnapshot());
  assert.equal(parseGrantSnapshot(text, PRODUCTION).grants.length, 2);
  assert.throws(() => parseGrantSnapshot(text, STAGING), /taken for ascend-prod-9c8f2, not ascend-staging-fa7d5/);
  assert.throws(() => parseGrantSnapshot('{"grants": []}', PRODUCTION), /not one the preflight wrote/);
});

// ---------------------------------------------------------------------------
// The command, end to end against an in-memory project
// ---------------------------------------------------------------------------

test("replaying the incident: the preflight refuses version 3 before anything deploys", async () => {
  const capture = capturingLog();
  const directory = snapshotDirectory();
  const backend = fakeBackend({
    latest: {
      [REVENUECAT_SECRET]: {version: "3", state: "ENABLED"},
      MIXPANEL_SERVER_CONFIG: {version: "2", state: "ENABLED"},
      TRANSACTIONAL_EMAIL_CONFIG: {version: "1", state: "ENABLED"},
    },
    functions: productionFunctions({revenueCat: 2}),
  });

  const exitCode = await runPreflight({
    projectId: PRODUCTION,
    backend,
    repository: {
      ...repository,
      manifestText: manifestWith(PRODUCTION, {[REVENUECAT_SECRET]: 2, TRANSACTIONAL_EMAIL_CONFIG: 1}),
    },
    snapshotPath: join(directory, "snapshot.json"),
    now: () => NOW,
    log: capture.log,
  });

  assert.equal(exitCode, EXIT.unsafe);
  const errors = capture.errors();
  assert.equal(errors.length, 3);
  assert.match(errors[0], /version 3 was never acknowledged[\s\S]*\(keys changed allowedProductIds\)/);
  assert.match(errors[1], /version 3 in ascend-prod-9c8f2 does not allowlist rc_promo_app_access_lifetime/);
  assert.match(errors[2], /must not run: 2 problem\(s\) above\. Nothing has been deployed/);
  assertNoSecretValues(capture.text());
  assert.throws(() => readFileSync(join(directory, "snapshot.json")), /ENOENT/);
});

test("pinning a version does not excuse an allowlist that drops a live product", async () => {
  const capture = capturingLog();
  const exitCode = await runPreflight({
    projectId: PRODUCTION,
    backend: fakeBackend({
      latest: {
        [REVENUECAT_SECRET]: {version: "3", state: "ENABLED"},
        MIXPANEL_SERVER_CONFIG: {version: "2", state: "ENABLED"},
        TRANSACTIONAL_EMAIL_CONFIG: {version: "1", state: "ENABLED"},
      },
      functions: productionFunctions({revenueCat: 2}),
    }),
    repository: {
      ...repository,
      manifestText: manifestWith(PRODUCTION, {[REVENUECAT_SECRET]: 3, TRANSACTIONAL_EMAIL_CONFIG: 1}),
    },
    snapshotPath: null,
    now: () => NOW,
    log: capture.log,
  });

  assert.equal(exitCode, EXIT.unsafe);
  assert.match(capture.text(), /notice: [^\n]*moves reconcileAppAccess, revenueCatWebhook from version 2 to the pinned version 3 \(keys changed allowedProductIds\)/);
  assert.equal(capture.errors().length, 2);
  assert.match(capture.errors()[0], /does not allowlist rc_promo_app_access_lifetime/);
  assertNoSecretValues(capture.text());
});

test("an acknowledged move still deploys when the bound version can no longer be read to compare", async () => {
  const capture = capturingLog();
  const exitCode = await runPreflight({
    projectId: PRODUCTION,
    backend: fakeBackend({
      functions: productionFunctions({revenueCat: 3}),
      payloads: {[`${REVENUECAT_SECRET}@4`]: V4},
    }),
    repository: {
      ...repository,
      manifestText: manifestWith(PRODUCTION, {[REVENUECAT_SECRET]: 4, TRANSACTIONAL_EMAIL_CONFIG: 1}),
    },
    snapshotPath: null,
    now: () => NOW,
    log: capture.log,
  });
  assert.equal(exitCode, EXIT.safe, capture.text());
  assert.match(
    capture.text(),
    /notice: [^\n]*from version 3 to the pinned version 4 \(the versions could not be read to compare \(no REVENUECAT_SERVER_CONFIG@3\)\)/
  );
});

test("a healthy deploy records its grants and the post-deploy check proves they survived", async () => {
  const directory = snapshotDirectory();
  const snapshotPath = join(directory, "snapshot.json");
  const productionRepository = {
    ...repository,
    manifestText: manifestWith(PRODUCTION, {[REVENUECAT_SECRET]: 4, TRANSACTIONAL_EMAIL_CONFIG: 1}),
  };

  const preflight = capturingLog();
  assert.equal(
    await runPreflight({
      projectId: PRODUCTION,
      backend: fakeBackend(),
      repository: productionRepository,
      snapshotPath,
      now: () => NOW,
      log: preflight.log,
    }),
    EXIT.safe,
    preflight.text()
  );
  const snapshot = JSON.parse(readFileSync(snapshotPath, "utf8"));
  assert.deepEqual(snapshot.grants.map((grant) => grant.uid), ["captain", "viktor"]);

  const verify = capturingLog();
  assert.equal(
    await runVerifyDeploy({
      projectId: PRODUCTION,
      backend: fakeBackend(),
      repository: productionRepository,
      snapshotPath,
      now: () => NOW,
      log: verify.log,
    }),
    EXIT.safe,
    verify.text()
  );
  assert.match(verify.text(), /2 of 2 pre-deploy grant\(s\) still held and allowlisted/);

  const lost = capturingLog();
  assert.equal(
    await runVerifyDeploy({
      projectId: PRODUCTION,
      backend: fakeBackend({grants: [compedGrants[1]]}),
      repository: productionRepository,
      snapshotPath,
      now: () => NOW,
      log: lost.log,
    }),
    EXIT.unsafe
  );
  assert.match(lost.errors()[0], /^LOST: captain \(comped\)/);
  assert.match(lost.errors().at(-1), /Stopping before rules, Storage and Hosting/);

  const rebound = capturingLog();
  assert.equal(
    await runVerifyDeploy({
      projectId: PRODUCTION,
      backend: fakeBackend({functions: productionFunctions({revenueCat: 5})}),
      repository: productionRepository,
      snapshotPath,
      now: () => NOW,
      log: rebound.log,
    }),
    EXIT.unsafe
  );
  assert.match(rebound.errors()[0], /bound to REVENUECAT_SERVER_CONFIG version 5, not the pinned version 4/);
  assertNoSecretValues(rebound.text());
});

test("a read that could not run is 'could not verify', never a pass", async () => {
  for (const run of [runPreflight, runVerifyDeploy]) {
    const directory = snapshotDirectory();
    const snapshotPath = join(directory, "snapshot.json");
    writeFileSync(snapshotPath, JSON.stringify(survivalSnapshot()));
    const capture = capturingLog();
    const exitCode = await run({
      projectId: PRODUCTION,
      backend: fakeBackend({
        failWith: new GoogleApiError({message: "HTTP 503", status: 503, transient: true}),
      }),
      repository,
      snapshotPath,
      now: () => NOW,
      log: capture.log,
    });
    assert.equal(exitCode, EXIT.unverified, run.name);
    assert.match(capture.errors()[0], /nothing is verified: HTTP 503/);
  }

  const missingSnapshot = capturingLog();
  assert.equal(
    await runVerifyDeploy({
      projectId: PRODUCTION,
      backend: fakeBackend(),
      repository,
      snapshotPath: join(snapshotDirectory(), "absent.json"),
      now: () => NOW,
      log: missingSnapshot.log,
    }),
    EXIT.unverified
  );
});

// ---------------------------------------------------------------------------
// The REST layer
// ---------------------------------------------------------------------------

function fakeClient(routes) {
  const requests = [];
  return {
    requests,
    async getJson(url) {
      requests.push({method: "GET", url});
      return route(url);
    },
    async postJson(url, body) {
      requests.push({method: "POST", url, body});
      return route(url, body);
    },
  };

  function route(url, body) {
    for (const [pattern, respond] of routes) {
      if (pattern.test(url)) return respond(url, body);
    }
    throw new GoogleApiError({message: `no route for ${url}`, status: 404, transient: false});
  }
}

test("the backend resolves latest the way the deploy does and treats 404 as absent", async () => {
  const backend = createFunctionsSecretBackend({
    projectId: PRODUCTION,
    client: fakeClient([
      [/REVENUECAT_SERVER_CONFIG\/versions\/latest$/, () => ({
        name: "projects/123/secrets/REVENUECAT_SERVER_CONFIG/versions/4",
        state: "ENABLED",
      })],
      [/versions\/4:access$/, () => ({payload: {data: Buffer.from(V4).toString("base64")}})],
    ]),
  });
  assert.deepEqual(await backend.latestSecretVersion(REVENUECAT_SECRET), {version: "4", state: "ENABLED"});
  assert.equal(await backend.latestSecretVersion("ABSENT_CONFIG"), null);
  assert.equal(await backend.accessSecretVersion(REVENUECAT_SECRET, "4"), V4);
});

test("the backend pages functions and refuses an unreachable region", async () => {
  const backend = createFunctionsSecretBackend({
    projectId: PRODUCTION,
    client: fakeClient([
      [/functions\?pageSize=200&pageToken=next$/, () => ({functions: [{name: "b"}]})],
      [/functions\?pageSize=200$/, () => ({functions: [{name: "a"}], nextPageToken: "next"})],
    ]),
  });
  assert.deepEqual(await backend.listFunctions(), [{name: "a"}, {name: "b"}]);

  const unreachable = createFunctionsSecretBackend({
    projectId: PRODUCTION,
    client: fakeClient([[/functions/, () => ({functions: [], unreachable: ["us-east1"]})]]),
  });
  await assert.rejects(unreachable.listFunctions(), /could not reach us-east1/);
});

test("the backend pages every grant by document name and keeps only app_access grants", async () => {
  const documentName = (uid, id = "app_access") =>
    `projects/${PRODUCTION}/databases/(default)/documents/users/${uid}/entitlements/${id}`;
  const firstPage = Array.from({length: 300}, (_, index) => ({
    document: {
      name: documentName(`u${String(index).padStart(3, "0")}`, index === 5 ? "other" : "app_access"),
      fields: {
        productId: {stringValue: PROMO},
        accessUntil: {timestampValue: LIFETIME},
      },
    },
  }));
  const client = fakeClient([
    [/:runQuery$/, (url, body) => body.structuredQuery.startAt ?
      [{document: {name: documentName("zed"), fields: {productId: {nullValue: null}}}}, {readTime: "t"}] :
      [...firstPage, {readTime: "t"}]],
  ]);
  const grants = await createFunctionsSecretBackend({projectId: PRODUCTION, client}).listGrants("app_access");

  assert.equal(grants.length, 300);
  assert.deepEqual(grants.at(-1), {uid: "zed", productId: null, accessUntil: null});
  assert.deepEqual(grants[0], {uid: "u000", productId: PROMO, accessUntil: LIFETIME});
  const queries = client.requests.map((request) => request.body.structuredQuery);
  assert.deepEqual(queries[0].from, [{collectionId: "entitlements", allDescendants: true}]);
  assert.deepEqual(queries[1].startAt, {
    values: [{referenceValue: documentName("u299")}],
    before: false,
  });
});

test("the ledger reader takes the last history entry", async () => {
  const client = fakeClient([
    [/comp_grants\?pageSize=300$/, () => ({
      documents: [{
        name: `projects/${PRODUCTION}/databases/(default)/documents/comp_grants/captain`,
        fields: {
          lastAction: {stringValue: "grant"},
          history: {arrayValue: {values: [
            {mapValue: {fields: {action: {stringValue: "revoke"}, productId: {stringValue: "old"}}}},
            {mapValue: {fields: {
              action: {stringValue: "grant"},
              productId: {stringValue: PROMO},
              landing: {stringValue: "LANDED"},
            }}},
          ]}},
        },
      }],
    })],
  ]);
  assert.deepEqual(
    await createFunctionsSecretBackend({projectId: PRODUCTION, client}).listCompLedger(),
    [{uid: "captain", lastAction: "grant", productId: PROMO, landing: "LANDED"}]
  );
  assert.deepEqual(decodeFirestoreValue({integerValue: "7"}), 7);
  assert.deepEqual(decodeFirestoreValue({booleanValue: false}), false);
});

function fakeFetch(responses) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({url, init});
    const next = responses.shift();
    if (next instanceof Error) throw next;
    return {
      ok: next.status >= 200 && next.status < 300,
      status: next.status,
      text: async () => next.body,
    };
  };
  return {calls, fetchImpl};
}

test("the REST client retries a transient failure and attributes every request to the project", async () => {
  const {calls, fetchImpl} = fakeFetch([
    {status: 503, body: '{"error":{"message":"backend unavailable"}}'},
    new TypeError("socket hang up"),
    {status: 200, body: '{"ok":true}'},
  ]);
  const client = createGoogleRestClient({
    getAccessToken: async () => "access-token",
    quotaProjectId: PRODUCTION,
    fetchImpl,
    sleep: async () => {},
  });
  assert.deepEqual(await client.getJson("https://example.test/a"), {ok: true});
  assert.equal(calls.length, 3);
  assert.equal(calls[0].init.headers.Authorization, "Bearer access-token");
  assert.equal(calls[0].init.headers["x-goog-user-project"], PRODUCTION);
});

test("the REST client returns a refusal at once and never quotes a body", async () => {
  const {calls, fetchImpl} = fakeFetch([
    {status: 403, body: '{"error":{"message":"Permission denied on secret"},"payload":"leak"}'},
  ]);
  const client = createGoogleRestClient({
    getAccessToken: async () => "access-token",
    quotaProjectId: PRODUCTION,
    fetchImpl,
    sleep: async () => {},
  });
  await assert.rejects(client.getJson("https://example.test/secret:access"), (error) => {
    assert.equal(error.status, 403);
    assert.equal(error.transient, false);
    assert.equal(error.message, "GET https://example.test/secret:access failed with HTTP 403: Permission denied on secret");
    return true;
  });
  assert.equal(calls.length, 1);

  const exhausted = createGoogleRestClient({
    getAccessToken: async () => "access-token",
    quotaProjectId: PRODUCTION,
    fetchImpl: fakeFetch([{status: 500, body: ""}, {status: 500, body: ""}, {status: 500, body: ""}]).fetchImpl,
    sleep: async () => {},
  });
  await assert.rejects(exhausted.getJson("https://example.test/b"), /HTTP 500/);
});

// ---------------------------------------------------------------------------
// The deploy credential
// ---------------------------------------------------------------------------

function pinnedAuthStub(accessToken) {
  const directory = mkdtempSync(join(tmpdir(), "ascend-pinned-auth-"));
  mkdirSync(join(directory, "lib"));
  writeFileSync(
    join(directory, "package.json"),
    JSON.stringify({name: "firebase-tools", version: PINNED_FIREBASE_TOOLS_VERSION})
  );
  writeFileSync(
    join(directory, "lib/auth.js"),
    [
      "exports.getGlobalDefaultAccount = () => ({tokens: {refresh_token: \"local-refresh\"}});",
      `exports.getAccessToken = async (refreshToken) => ({access_token: ${JSON.stringify(accessToken)} ?? refreshToken});`,
    ].join("\n")
  );
  return directory;
}

test("access tokens are minted from FIREBASE_TOKEN through the pinned CLI", async () => {
  const getAccessToken = createGoogleAccessTokenSource({
    firebaseToolsRoot: pinnedAuthStub("minted-access"),
    refreshToken: "ci-refresh",
  });
  assert.equal(await getAccessToken(), "minted-access");

  const refused = createGoogleAccessTokenSource({
    firebaseToolsRoot: pinnedAuthStub(null),
    refreshToken: "ci-refresh",
  });
  await assert.rejects(refused(), /Google refused the Firebase refresh token/);

  const unpinned = pinnedAuthStub("x");
  writeFileSync(
    join(unpinned, "package.json"),
    JSON.stringify({name: "firebase-tools", version: "99.0.0"})
  );
  assert.throws(
    () => createGoogleAccessTokenSource({firebaseToolsRoot: unpinned, refreshToken: "t"}),
    /resolved 99\.0\.0/
  );
});

test("the pinned CLI root comes from FIREBASE_TOOLS_ROOT or npm's exec cache", () => {
  assert.equal(
    resolvePinnedFirebaseToolsRoot({env: {FIREBASE_TOOLS_ROOT: "/pinned"}, execFile: () => {
      throw new Error("must not run");
    }}),
    "/pinned"
  );

  const root = mkdtempSync(join(tmpdir(), "ascend-npx-"));
  mkdirSync(join(root, "node_modules/.bin"), {recursive: true});
  mkdirSync(join(root, "node_modules/firebase-tools"));
  let invoked;
  const resolved = resolvePinnedFirebaseToolsRoot({
    env: {},
    execFile: (command, args) => {
      invoked = [command, ...args].join(" ");
      return `${join(root, "node_modules/.bin/firebase")}\n`;
    },
  });
  assert.equal(invoked, `npm exec --yes --package=firebase-tools@${PINNED_FIREBASE_TOOLS_VERSION} -- which firebase`);
  assert.match(resolved, /node_modules\/firebase-tools$/);
});

// ---------------------------------------------------------------------------
// The workflows
// ---------------------------------------------------------------------------

function workflow(name) {
  return readFileSync(join(REPO_ROOT, ".github/workflows", name), "utf8");
}

function stepBlock(contents, name) {
  const start = contents.indexOf(`      - name: ${name}\n`);
  assert.notEqual(start, -1, `missing step: ${name}`);
  const next = contents.indexOf("\n      - name: ", start + 1);
  return contents.slice(start, next === -1 ? undefined : next);
}

for (const [file, project] of [
  ["deploy-production.yml", '"${{ vars.FIREBASE_PROJECT_ID_PRODUCTION }}"'],
  ["deploy-staging.yml", STAGING],
]) {
  test(`${file} checks secrets before any backend change and grants before rules`, () => {
    const contents = workflow(file);
    const preflightName = "Verify Functions secrets before any backend change";
    const verifyName = "Verify the Functions deploy kept every paid-access grant";
    const order = [
      preflightName,
      "Deploy Firestore indexes",
      "Deploy Functions",
      "Verify deployed functions match this ref",
      verifyName,
      "Deploy Firestore rules",
    ].map((name) => contents.indexOf(`      - name: ${name}\n`));
    for (const position of order) assert.notEqual(position, -1);
    assert.deepEqual(order, [...order].sort((a, b) => a - b));

    const firstDeploy = contents.search(/npx -y firebase-tools@[\d.]+ deploy /);
    assert.notEqual(firstDeploy, -1);
    assert.ok(order[0] < firstDeploy, "the preflight must precede every firebase deploy");

    const snapshot = "--snapshot \"$RUNNER_TEMP/functions-secret-snapshot.json\"";
    const preflight = stepBlock(contents, preflightName);
    assert.match(preflight, /FIREBASE_TOKEN: \$\{\{ secrets\.FIREBASE_TOKEN \}\}/);
    assert.ok(
      preflight.includes(`node scripts/verify-functions-secrets.mjs preflight --project ${project} ${snapshot}`),
      preflight
    );
    const verify = stepBlock(contents, verifyName);
    assert.match(verify, /FIREBASE_TOKEN: \$\{\{ secrets\.FIREBASE_TOKEN \}\}/);
    assert.ok(
      verify.includes(`node scripts/verify-functions-secrets.mjs verify-deploy --project ${project} ${snapshot}`),
      verify
    );
    for (const block of [preflight, verify]) {
      assert.doesNotMatch(block, /continue-on-error/);
    }
  });
}

test("a daily read-only check reports a secret drift before the next deploy trips on it", () => {
  const contents = workflow("functions-secret-drift.yml");
  assert.match(contents, /schedule:\n\s+- cron: "[^"]+"/);
  assert.match(contents, /workflow_dispatch:/);
  assert.match(contents, /permissions:\n\s+contents: read/);
  for (const project of Object.keys(GUARDED_PROJECTS)) {
    assert.ok(
      contents.includes(`node scripts/verify-functions-secrets.mjs preflight --project ${project}\n`),
      `the drift check skips ${project}`
    );
  }
  assert.doesNotMatch(contents, /--snapshot|verify-deploy|firebase-tools@[\d.]+ deploy/);
});

test("the manifest lives where every functions path filter already watches", () => {
  assert.equal(SECRET_VERSION_MANIFEST_PATH, "functions/secret-versions.json");
  for (const file of ["deploy-production.yml", "deploy-staging.yml"]) {
    assert.match(workflow(file), /- "functions\/\*\*"/);
  }
});
