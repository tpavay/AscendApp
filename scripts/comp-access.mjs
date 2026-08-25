#!/usr/bin/env node

/**
 * Complimentary app access: look somebody up, show what is about to happen,
 * grant it, and prove it landed.
 *
 * Ascend has two access gates. The client paywall reads RevenueCat directly
 * (`AppRootRoute.swift`); every server-guarded read is gated on the Firestore
 * document `users/{uid}/entitlements/app_access`, which the RevenueCat webhook
 * writes only for a product in that environment's `allowedProductIds`. A comp
 * that satisfies one gate and not the other is worse than no comp at all: the
 * person clears the paywall and then every screen fails. That is what a "1
 * year" grant did on 2026-08-25, because RevenueCat publishes a promotional
 * grant as `rc_promo_{entitlement}_{duration}` and only `lifetime` was
 * allowlisted.
 *
 * So this tool reads the LIVE allowlist out of the secret version the deployed
 * webhook is actually bound to, refuses any duration that allowlist would not
 * honor, and then verifies the grant document appeared rather than assuming it.
 *
 * Usage:
 *   node scripts/comp-access.mjs find "Bob Smith" --env prod --confirm-production ascend-prod-9c8f2
 *   node scripts/comp-access.mjs grant bob@gmail.com --env prod --confirm-production ascend-prod-9c8f2 \
 *     --reason "podcast guest"
 *   node scripts/comp-access.mjs grant bob@gmail.com --env prod --confirm-production ascend-prod-9c8f2 \
 *     --reason "podcast guest" --confirm-grant <uid>
 *   node scripts/comp-access.mjs revoke bob@gmail.com --env prod --confirm-production ascend-prod-9c8f2 \
 *     --reason "trial period over" --confirm-revoke <uid>
 *   node scripts/comp-access.mjs list --env prod --confirm-production ascend-prod-9c8f2
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login   (Firestore)
 *   gcloud auth login                       (reading the deployed allowlist)
 *   The `secret` helper on PATH, holding revenuecat-{production,staging}-server-config.
 */

import {spawnSync} from "node:child_process";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {
  ACCESS_STATE,
  COMP_LEDGER_COLLECTION,
  DEFAULT_COMP_DURATION,
  LANDING,
  LOOKUP_OUTCOME,
  REVENUECAT_PROMOTIONAL_DURATIONS,
  buildGrantWarnings,
  buildLedgerEntry,
  classifySubscriberState,
  classifyWebhookLanding,
  evaluateDuration,
  evaluateGrantConfirmation,
  isPromotionalProductId,
  protectedSubjectRefusal,
  resolveCompTarget,
  resolveLookup,
} from "./lib/comp-access-policy.mjs";

const REVENUECAT_API_BASE_URL = "https://api.revenuecat.com/v1";
const REVENUECAT_TIMEOUT_MS = 15_000;
const FUNCTIONS_REGION = "us-central1";
const WEBHOOK_FUNCTION_NAME = "revenueCatWebhook";
const SERVER_CONFIG_SECRET = "REVENUECAT_SERVER_CONFIG";
const KEYCHAIN_SECRETS = Object.freeze({
  prod: "revenuecat-production-server-config",
  staging: "revenuecat-staging-server-config",
});
// The webhook landed in two seconds on 2026-08-25. Ninety seconds is generous
// enough that a timeout means something is actually wrong, and short enough
// that nobody walks away from a half-finished comp.
const LANDING_TIMEOUT_MS = 90_000;
const LANDING_POLL_MS = 3_000;
const DEFAULT_SCAN_LIMIT = 2_000;

const EXIT = Object.freeze({
  ok: 0,
  usage: 2,
  refused: 3,
  needsConfirmation: 4,
  halfDone: 5,
});

const COMMANDS = ["find", "grant", "revoke", "list"];

if (isEntrypoint(import.meta.url)) {
  await main(process.argv);
}

/**
 * Runs one comp command.
 * @param {string[]} argv Process argv.
 * @return {Promise<void>} Resolves once the exit code is assigned.
 */
async function main(argv) {
  let args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    fail(error.message, EXIT.usage);
    return;
  }

  if (args.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  let target;
  try {
    target = resolveCompTarget(args);
  } catch (error) {
    fail(error.message, EXIT.usage);
    return;
  }

  let firestore;
  try {
    firestore = initializeFirestore(target);
  } catch (error) {
    fail(
      `Could not reach Firestore in ${target.projectId}: ${error.message}\n` +
        "Run `gcloud auth application-default login` and try again.",
      EXIT.usage
    );
    return;
  }

  try {
    switch (args.command) {
      case "find":
        await runFind(args, target, firestore);
        break;
      case "grant":
        await runGrant(args, target, firestore);
        break;
      case "revoke":
        await runRevoke(args, target, firestore);
        break;
      case "list":
        await runList(args, target, firestore);
        break;
      default:
        fail(`Unknown command "${args.command}".`, EXIT.usage);
    }
  } catch (error) {
    fail(error.message, EXIT.usage);
  }
}

async function runFind(args, target, firestore) {
  const subject = await resolveSubject(args, target, firestore);
  if (subject === null) return;

  const config = readServerConfig(target);
  const liveState = await readLiveState(subject, config);
  printDossier({subject, target, liveState});

  const refusal = protectedSubjectRefusal(subject);
  if (refusal !== null) {
    process.stdout.write(`\nPROTECTED\n${wrap(refusal, "  ")}\n`);
    process.exitCode = EXIT.refused;
  }
}

async function runGrant(args, target, firestore) {
  const subject = await resolveSubject(args, target, firestore);
  if (subject === null) return;

  const refusal = protectedSubjectRefusal(subject);
  if (refusal !== null) {
    fail(refusal, EXIT.refused);
    return;
  }

  const config = readServerConfig(target);
  const allowlist = readDeployedAllowlist(target);
  const duration = evaluateDuration({
    duration: args.duration,
    entitlementId: config.entitlementId,
    allowedProductIds: allowlist.allowedProductIds,
  });

  const liveState = await readLiveState(subject, config);
  printDossier({subject, target, liveState});
  printAllowlist({target, allowlist, duration, requested: args.duration});

  if (!duration.ok) {
    fail(`\n${duration.reason}`, EXIT.refused);
    return;
  }

  // A missing reason must stop the command before anything is granted, not
  // after, so the ledger entry is built up front and reused on the way out.
  const at = new Date();
  let ledgerEntry;
  try {
    ledgerEntry = buildLedgerEntry({
      action: "grant",
      subject,
      productId: duration.productId,
      duration: args.duration,
      reason: args.reason,
      operator: resolveOperator(),
      at,
    });
  } catch (error) {
    fail(error.message, EXIT.usage);
    return;
  }

  const {requiresBillingAcknowledgement, warnings} = buildGrantWarnings({
    liveState,
    duration: args.duration,
  });

  process.stdout.write("\nPLAN\n");
  process.stdout.write(`  grant       ${duration.productId} (${args.duration})\n`);
  process.stdout.write(`  to          ${describeSubject(subject)}\n`);
  process.stdout.write(`  in          ${target.label}\n`);
  process.stdout.write(`  reason      ${ledgerEntry.reason}\n`);
  process.stdout.write(`  recorded as ${COMP_LEDGER_COLLECTION}/${subject.uid}\n`);

  if (warnings.length > 0) {
    process.stdout.write("\nWARNINGS\n");
    for (const warning of warnings) {
      process.stdout.write(`${wrap(warning, "  ! ")}\n`);
    }
  }

  const confirmation = evaluateGrantConfirmation({
    subject,
    requiresBillingAcknowledgement,
    confirmGrant: args.confirmGrant,
    acknowledgeActiveSubscription: args.acknowledgeActiveSubscription,
  });
  if (!confirmation.ok) {
    process.stdout.write(`\n${wrap(confirmation.reason, "  ")}\n`);
    process.exitCode = EXIT.needsConfirmation;
    return;
  }

  process.stdout.write("\nGRANTING\n");
  await grantPromotionalEntitlement({
    appUserId: subject.uid,
    entitlementId: config.entitlementId,
    duration: args.duration,
    apiKey: config.apiKey,
  });
  process.stdout.write(
    `  RevenueCat accepted the ${args.duration} grant.\n`
  );

  const landed = await waitForLanding({
    firestore,
    uid: subject.uid,
    entitlementId: config.entitlementId,
    expectedProductId: duration.productId,
  });

  ledgerEntry.landing = landed.landing;
  await appendLedgerEntry(firestore, subject, ledgerEntry);
  process.stdout.write(
    `  Recorded in ${COMP_LEDGER_COLLECTION}/${subject.uid}.\n`
  );

  process.stdout.write(`\n${landed.landing}\n${wrap(landed.reason, "  ")}\n`);
  process.exitCode = landed.landing === LANDING.landed ? EXIT.ok : EXIT.halfDone;
}

async function runRevoke(args, target, firestore) {
  const subject = await resolveSubject(args, target, firestore);
  if (subject === null) return;

  const refusal = protectedSubjectRefusal(subject);
  if (refusal !== null) {
    fail(refusal, EXIT.refused);
    return;
  }

  const config = readServerConfig(target);
  const liveState = await readLiveState(subject, config);
  printDossier({subject, target, liveState});

  const at = new Date();
  let ledgerEntry;
  try {
    ledgerEntry = buildLedgerEntry({
      action: "revoke",
      subject,
      productId: liveState.productId,
      reason: args.reason,
      operator: resolveOperator(),
      at,
    });
  } catch (error) {
    fail(error.message, EXIT.usage);
    return;
  }

  process.stdout.write("\nPLAN\n");
  process.stdout.write(
    `  revoke every promotional ${config.entitlementId} grant\n`
  );
  process.stdout.write(`  from        ${describeSubject(subject)}\n`);
  process.stdout.write(`  in          ${target.label}\n`);
  process.stdout.write(`  reason      ${ledgerEntry.reason}\n`);

  if (liveState.storeSubscription !== null) {
    process.stdout.write(
      `${wrap(
        "Revoking the comp does not touch their store subscription " +
          `(${liveState.storeSubscription.productId}); if that is still ` +
          "active they keep access through it.",
        "  ! "
      )}\n`
    );
  }
  if (!liveState.isPromotional) {
    process.stdout.write(
      `${wrap(
        "They do not currently hold a promotional entitlement. Revoking is " +
          "harmless but will change nothing.",
        "  ! "
      )}\n`
    );
  }

  if (args.confirmRevoke !== subject.uid) {
    process.stdout.write(
      `${wrap(
        args.confirmRevoke === null ?
          "Nothing was revoked. Re-run with --confirm-revoke " +
            `${subject.uid} once the captain has said yes.` :
          `--confirm-revoke ${args.confirmRevoke} does not match the account ` +
            `this lookup resolved (${subject.uid}). Refusing.`,
        "  "
      )}\n`
    );
    process.exitCode = EXIT.needsConfirmation;
    return;
  }

  await revokePromotionalEntitlements({
    appUserId: subject.uid,
    entitlementId: config.entitlementId,
    apiKey: config.apiKey,
  });
  process.stdout.write("\nREVOKED\n  RevenueCat accepted the revoke.\n");

  await appendLedgerEntry(firestore, subject, ledgerEntry);
  process.stdout.write(
    `  Recorded in ${COMP_LEDGER_COLLECTION}/${subject.uid}.\n`
  );

  const after = await readGrantDocuments(
    firestore,
    subject.uid,
    config.entitlementId
  );
  process.stdout.write(
    after.grantDoc === null ?
      "  users/{uid}/entitlements/app_access is gone; the server gate is " +
        "closed again.\n" :
      "  users/{uid}/entitlements/app_access still exists. The webhook may " +
        "not have landed yet, or a real store subscription is still granting " +
        "access. Re-check before telling anybody they were removed.\n"
  );
}

async function runList(args, target, firestore) {
  const config = readServerConfig(target);
  process.stdout.write(`LEDGER  ${COMP_LEDGER_COLLECTION} @ ${target.label}\n`);

  const ledger = await firestore.collection(COMP_LEDGER_COLLECTION).get();
  if (ledger.empty) {
    process.stdout.write("  no recorded comps\n");
  }
  for (const doc of ledger.docs) {
    const data = doc.data();
    const history = Array.isArray(data.history) ? data.history : [];
    const last = history[history.length - 1] ?? {};
    process.stdout.write(
      `  ${doc.id}  ${data.displayName ?? "?"} <${data.email ?? "?"}>\n` +
      `    ${last.action ?? "?"} ${last.productId ?? ""} ` +
      `${formatTimestamp(last.at)} by ${last.operator ?? "?"}\n` +
      `    reason: ${last.reason ?? "?"}\n`
    );
  }

  // The ledger only knows about comps this tool made. A grant issued from the
  // RevenueCat dashboard leaves no ledger row, so the live grant documents are
  // scanned too and the two are reported separately rather than merged.
  process.stdout.write(
    `\nLIVE GRANTS  users/*/entitlements/${config.entitlementId} @ ${target.label}\n`
  );
  const live = await firestore
    .collectionGroup("entitlements")
    .limit(args.scanLimit)
    .get();
  const comped = live.docs.filter(
    (doc) => doc.id === config.entitlementId &&
      isPromotionalProductId(doc.get("productId"))
  );

  if (comped.length === 0) {
    process.stdout.write("  no live promotional grants found\n");
  }
  for (const doc of comped) {
    const uid = doc.ref.parent.parent?.id ?? "?";
    process.stdout.write(
      `  ${uid}  ${doc.get("productId")}  ` +
      `verified ${formatTimestamp(doc.get("verifiedAt"))}` +
      `${ledger.docs.some((entry) => entry.id === uid) ? "" : "  [NOT IN LEDGER]"}\n`
    );
  }

  if (live.size === args.scanLimit) {
    process.stdout.write(
      `\n  NOTE: the scan hit its --scan-limit of ${args.scanLimit} documents, ` +
      "so this is not a complete list. Raise it and re-run.\n"
    );
    process.exitCode = EXIT.halfDone;
  }
}

/**
 * Resolves the captain's query to exactly one account, or explains why not.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} firestore Firestore handle.
 * @return {Promise<?object>} The subject, or null when nothing was resolved.
 */
async function resolveSubject(args, target, firestore) {
  const candidates = await readUserCandidates(
    firestore,
    args.query,
    args.scanLimit
  );
  const lookup = resolveLookup({
    query: args.query,
    candidates: candidates.users,
    scanTruncated: candidates.truncated,
  });

  if (lookup.outcome === LOOKUP_OUTCOME.matched) {
    return lookup.subject;
  }

  process.stdout.write(`${lookup.outcome}  @ ${target.label}\n`);
  process.stdout.write(`${wrap(lookup.reason, "  ")}\n`);
  if (lookup.outcome === LOOKUP_OUTCOME.ambiguous) {
    for (const candidate of lookup.matches) {
      process.stdout.write(`    ${describeSubject(candidate)}\n`);
    }
  }
  process.exitCode = EXIT.refused;
  return null;
}

/**
 * Reads the user documents a query could plausibly match.
 *
 * Firestore has no case-insensitive or substring index, and an Apple Hide My
 * Email account's stored address is not the one anybody would type, so the
 * indexed equality lookups are tried first and a bounded scan backs them up.
 * The scan reports when it was truncated rather than silently answering from a
 * partial read.
 * @param {object} firestore Firestore handle.
 * @param {string} query Captain's query.
 * @param {number} scanLimit Maximum documents the fallback scan reads.
 * @return {Promise<{users: object[], truncated: boolean}>} Candidates.
 */
async function readUserCandidates(firestore, query, scanLimit) {
  const users = firestore.collection("users");
  const needle = String(query ?? "").trim();

  const direct = await Promise.all([
    users.where("email", "==", needle).limit(10).get(),
    users.where("email", "==", needle.toLowerCase()).limit(10).get(),
    users.where("displayName", "==", needle).limit(10).get(),
    users.doc(needle).get(),
  ]);

  const found = new Map();
  for (const result of direct.slice(0, 3)) {
    for (const doc of result.docs) found.set(doc.id, toSubject(doc));
  }
  const byId = direct[3];
  if (byId.exists) found.set(byId.id, toSubject(byId));
  if (found.size > 0) {
    return {users: [...found.values()], truncated: false};
  }

  const scan = await users.limit(scanLimit).get();
  return {
    users: scan.docs.map(toSubject),
    truncated: scan.size === scanLimit,
  };
}

function toSubject(doc) {
  const data = doc.data() ?? {};
  return {
    uid: doc.id,
    email: data.email ?? null,
    displayName: data.displayName ?? null,
    firstName: data.firstName ?? null,
    lastName: data.lastName ?? null,
    joinedAt: data.joined_at ?? data.createdAt ?? null,
  };
}

/**
 * Reads live RevenueCat state for one account. Never inferred, never cached.
 * @param {object} subject Resolved subject.
 * @param {object} config Server config with the API key.
 * @return {Promise<object>} Classified live state.
 */
async function readLiveState(subject, config) {
  const response = await fetch(
    `${REVENUECAT_API_BASE_URL}/subscribers/${encodeURIComponent(subject.uid)}`,
    {
      headers: {
        "Accept": "application/json",
        "Authorization": `Bearer ${config.apiKey}`,
      },
      signal: AbortSignal.timeout(REVENUECAT_TIMEOUT_MS),
    }
  );

  if (response.status === 404) {
    return classifySubscriberState({
      subscriber: null,
      entitlementId: config.entitlementId,
    });
  }
  if (!response.ok) {
    throw new Error(
      `RevenueCat refused the subscriber read with HTTP ${response.status}. ` +
        "Nothing has been granted. Live state is unknown, so nothing may be " +
        "decided from it."
    );
  }

  const body = await response.json();
  return classifySubscriberState({
    subscriber: body.subscriber ?? null,
    entitlementId: config.entitlementId,
  });
}

async function grantPromotionalEntitlement({
  appUserId,
  entitlementId,
  duration,
  apiKey,
}) {
  const response = await fetch(
    `${REVENUECAT_API_BASE_URL}/subscribers/${encodeURIComponent(appUserId)}` +
      `/entitlements/${encodeURIComponent(entitlementId)}/promotional`,
    {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({duration}),
      signal: AbortSignal.timeout(REVENUECAT_TIMEOUT_MS),
    }
  );

  if (!response.ok) {
    throw new Error(
      `RevenueCat refused the grant with HTTP ${response.status}: ` +
        `${(await response.text()).slice(0, 400)}`
    );
  }
}

async function revokePromotionalEntitlements({
  appUserId,
  entitlementId,
  apiKey,
}) {
  const response = await fetch(
    `${REVENUECAT_API_BASE_URL}/subscribers/${encodeURIComponent(appUserId)}` +
      `/entitlements/${encodeURIComponent(entitlementId)}/revoke_promotionals`,
    {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(REVENUECAT_TIMEOUT_MS),
    }
  );

  if (!response.ok) {
    throw new Error(
      `RevenueCat refused the revoke with HTTP ${response.status}: ` +
        `${(await response.text()).slice(0, 400)}`
    );
  }
}

/**
 * Waits for the webhook to write the server-owned grant document.
 *
 * The RevenueCat call returning 200 is not success; this document is. Polling
 * stops early on the allowlist rejection signature, because that state never
 * resolves itself no matter how long anybody waits.
 * @param {object} options Poll inputs.
 * @return {Promise<{landing: string, reason: string}>} Landing verdict.
 */
async function waitForLanding({
  firestore,
  uid,
  entitlementId,
  expectedProductId,
}) {
  const deadline = Date.now() + LANDING_TIMEOUT_MS;
  let verdict = null;

  process.stdout.write("  waiting for the webhook to write the grant document");
  while (Date.now() < deadline) {
    const documents = await readGrantDocuments(firestore, uid, entitlementId);
    verdict = classifyWebhookLanding({...documents, expectedProductId});
    if (verdict.landing !== LANDING.pending) break;
    process.stdout.write(".");
    await delay(LANDING_POLL_MS);
  }
  process.stdout.write("\n");

  return verdict ?? classifyWebhookLanding({expectedProductId});
}

async function readGrantDocuments(firestore, uid, entitlementId) {
  const [grant, status] = await firestore.getAll(
    firestore.doc(`users/${uid}/entitlements/${entitlementId}`),
    firestore.doc(`users/${uid}/entitlement_status/${entitlementId}`)
  );
  return {
    grantDoc: grant.exists ? grant.data() : null,
    statusDoc: status.exists ? status.data() : null,
  };
}

/**
 * Appends one entry to the durable comp record.
 *
 * History is appended rather than replaced so a revoke and a later re-grant
 * both survive, and so "who did we comp, when, and why" stays answerable after
 * the access itself has been taken back.
 * @param {object} firestore Firestore handle.
 * @param {object} subject Resolved subject.
 * @param {object} entry Ledger entry.
 * @return {Promise<void>} Resolves once written.
 */
async function appendLedgerEntry(firestore, subject, entry) {
  const ref = firestore.collection(COMP_LEDGER_COLLECTION).doc(subject.uid);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const history = snapshot.exists && Array.isArray(snapshot.get("history")) ?
      snapshot.get("history") : [];
    transaction.set(ref, {
      schemaVersion: 1,
      uid: subject.uid,
      email: subject.email ?? null,
      displayName: subject.displayName ?? null,
      lastAction: entry.action,
      lastActionAt: entry.at,
      history: [...history, entry],
    });
  });
}

/**
 * Reads the allowlist the deployed webhook is actually bound to.
 *
 * Three copies of this config exist and they drift: the local Keychain entry,
 * the latest Secret Manager version, and the version the deployed function
 * pinned at deploy time. Only the last one decides whether a grant document
 * gets written, so only the last one is consulted. On 2026-08-25 the Keychain
 * copy was a full version behind the deployed one.
 * @param {object} target Resolved target.
 * @return {{allowedProductIds: ?string[], version: ?string, source: string}} Allowlist.
 */
function readDeployedAllowlist(target) {
  const version = runCommand("gcloud", [
    "functions", "describe", WEBHOOK_FUNCTION_NAME,
    "--project", target.projectId,
    "--region", FUNCTIONS_REGION,
    "--format",
    "value(serviceConfig.secretEnvironmentVariables[0].version)",
  ]);

  if (version === null) {
    return {
      allowedProductIds: null,
      version: null,
      source:
        `could not read the deployed ${WEBHOOK_FUNCTION_NAME} function in ` +
        `${target.projectId}`,
    };
  }

  const raw = runCommand("gcloud", [
    "secrets", "versions", "access", version.trim(),
    "--secret", SERVER_CONFIG_SECRET,
    "--project", target.projectId,
  ]);

  if (raw === null) {
    return {
      allowedProductIds: null,
      version: version.trim(),
      source:
        `could not read ${SERVER_CONFIG_SECRET} version ${version.trim()} in ` +
        `${target.projectId}`,
    };
  }

  try {
    const parsed = JSON.parse(raw);
    return {
      allowedProductIds: parsed.allowedProductIds ?? null,
      version: version.trim(),
      source:
        `${SERVER_CONFIG_SECRET} version ${version.trim()}, as bound by the ` +
        `deployed ${WEBHOOK_FUNCTION_NAME}`,
    };
  } catch {
    return {
      allowedProductIds: null,
      version: version.trim(),
      source: `${SERVER_CONFIG_SECRET} version ${version.trim()} is not JSON`,
    };
  }
}

/**
 * Reads the RevenueCat API key and entitlement id from the Keychain.
 *
 * The value is piped straight into this process and never printed, written to
 * a file, or passed as a command argument. Only `apiKey` and `entitlementId`
 * are taken from here - the allowlist deliberately comes from the deployed
 * secret instead, because this copy goes stale.
 * @param {object} target Resolved target.
 * @return {{apiKey: string, entitlementId: string}} Server config.
 */
function readServerConfig(target) {
  const name = KEYCHAIN_SECRETS[target.env];
  const raw = runCommand("secret", [name]);
  if (raw === null) {
    throw new Error(
      `Could not read the "${name}" Keychain entry. Check \`secret list\`.`
    );
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`The "${name}" Keychain entry is not valid JSON.`);
  }

  if (typeof parsed.apiKey !== "string" || parsed.apiKey === "") {
    throw new Error(`The "${name}" Keychain entry has no apiKey field.`);
  }

  return {
    apiKey: parsed.apiKey,
    entitlementId: parsed.entitlementId ?? "app_access",
  };
}

function runCommand(command, args) {
  const result = spawnSync(command, args, {encoding: "utf8"});
  if (result.error || result.status !== 0) return null;
  return result.stdout;
}

function initializeFirestore(target) {
  initializeApp({
    credential: applicationDefault(),
    projectId: target.projectId,
  });
  return getFirestore();
}

function printDossier({subject, target, liveState}) {
  process.stdout.write(`SUBJECT  @ ${target.label}\n`);
  process.stdout.write(`  name        ${subject.displayName ?? "(none set)"}\n`);
  process.stdout.write(`  email       ${describeEmail(subject.email)}\n`);
  process.stdout.write(`  uid         ${subject.uid}\n`);
  process.stdout.write(`  joined      ${formatTimestamp(subject.joinedAt)}\n`);
  process.stdout.write(`\nLIVE ACCESS  (read from RevenueCat just now)\n`);
  process.stdout.write(`  state       ${liveState.state}\n`);
  process.stdout.write(`${wrap(liveState.summary, "  ")}\n`);
}

function printAllowlist({target, allowlist, duration, requested}) {
  process.stdout.write(`\nALLOWLIST  ${target.label}\n`);
  process.stdout.write(`  source      ${allowlist.source}\n`);
  process.stdout.write(
    `  allows      ${allowlist.allowedProductIds?.join(", ") ?? "UNREADABLE"}\n`
  );
  process.stdout.write(
    `  grantable   ${duration.grantable.length > 0 ?
      duration.grantable.join(", ") : "NOTHING - no rc_promo_ id is allowlisted"}\n`
  );
  process.stdout.write(
    `  requested   ${requested} -> ${duration.productId ?? "n/a"} ` +
    `${duration.ok ? "OK" : "REFUSED"}\n`
  );
}

function describeSubject(subject) {
  const email = typeof subject.email === "string" && subject.email !== "" ?
    subject.email : "no email";
  return `${subject.displayName ?? "(no name)"} <${email}> ${subject.uid}`;
}

function describeEmail(email) {
  if (typeof email !== "string" || email === "") return "(none)";
  return email.endsWith("@privaterelay.appleid.com") ?
    `${email}  [Apple Hide My Email - not their real address]` : email;
}

function formatTimestamp(value) {
  if (value === null || value === undefined) return "unknown";
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString().slice(0, 19).replace("T", " ");
  }
  if (value instanceof Date) {
    return value.toISOString().slice(0, 19).replace("T", " ");
  }
  return String(value);
}

function resolveOperator() {
  return process.env.USER ?? process.env.LOGNAME ?? "unknown";
}

function wrap(text, prefix, width = 78) {
  const indent = " ".repeat(prefix.length);
  const lines = [];
  let line = prefix;
  let started = false;

  for (const word of String(text).split(/\s+/).filter(Boolean)) {
    if (!started) {
      line += word;
      started = true;
    } else if (line.length + word.length + 1 > width) {
      lines.push(line);
      line = `${indent}${word}`;
    } else {
      line += ` ${word}`;
    }
  }

  lines.push(line);
  return lines.join("\n");
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function fail(message, exitCode) {
  process.stderr.write(`${message}\n`);
  process.exitCode = exitCode;
}

function parseArgs(argv) {
  const parsed = {
    command: null,
    query: null,
    env: null,
    confirmProduction: null,
    confirmGrant: null,
    confirmRevoke: null,
    acknowledgeActiveSubscription: false,
    duration: DEFAULT_COMP_DURATION,
    reason: null,
    scanLimit: DEFAULT_SCAN_LIMIT,
    help: false,
  };

  const rest = argv.slice(2);
  for (let index = 0; index < rest.length; index += 1) {
    const argument = rest[index];
    switch (argument) {
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      case "--env":
        parsed.env = rest[++index] ?? null;
        break;
      case "--confirm-production":
        parsed.confirmProduction = rest[++index] ?? null;
        break;
      case "--confirm-grant":
        parsed.confirmGrant = rest[++index] ?? null;
        break;
      case "--confirm-revoke":
        parsed.confirmRevoke = rest[++index] ?? null;
        break;
      case "--acknowledge-active-subscription":
        parsed.acknowledgeActiveSubscription = true;
        break;
      case "--duration":
        parsed.duration = rest[++index] ?? null;
        break;
      case "--reason":
        parsed.reason = rest[++index] ?? null;
        break;
      case "--scan-limit":
        parsed.scanLimit = Number.parseInt(rest[++index] ?? "", 10);
        break;
      default:
        if (argument.startsWith("-")) {
          throw new Error(`Unknown flag "${argument}".`);
        }
        if (parsed.command === null) {
          parsed.command = argument;
        } else if (parsed.query === null) {
          parsed.query = argument;
        } else {
          throw new Error(`Unexpected argument "${argument}".`);
        }
    }
  }

  if (parsed.help) return parsed;

  if (parsed.command === null || !COMMANDS.includes(parsed.command)) {
    throw new Error(
      `Pass one of: ${COMMANDS.join(", ")}.\n\n${usage()}`
    );
  }
  if (parsed.command !== "list" && parsed.query === null) {
    throw new Error(
      `"${parsed.command}" needs somebody to act on - an email, a display ` +
        "name, or a uid."
    );
  }
  if (!Number.isInteger(parsed.scanLimit) || parsed.scanLimit <= 0) {
    throw new Error("--scan-limit must be a positive integer.");
  }

  return parsed;
}

function usage() {
  return `Complimentary app access for Ascend.

Commands
  find <email|name|uid>     Look somebody up and show their live access state.
  grant <email|name|uid>    Show the plan, then grant once confirmed.
  revoke <email|name|uid>   Take a comp back.
  list                      Every recorded comp, plus every live promo grant.

Flags
  --env staging|prod              Required.
  --confirm-production <id>       Required for prod; must equal ascend-prod-9c8f2.
  --reason "<why>"                Required to grant or revoke; recorded forever.
  --duration <duration>           Default ${DEFAULT_COMP_DURATION}. One of:
                                  ${REVENUECAT_PROMOTIONAL_DURATIONS.join(", ")}.
                                  Refused unless the live allowlist honors it.
  --confirm-grant <uid>           Required to actually grant. Must match the
                                  account the lookup resolved.
  --acknowledge-active-subscription
                                  Additionally required when they are on a live
                                  store subscription a comp will not cancel.
  --confirm-revoke <uid>          Required to actually revoke.
  --scan-limit <n>                Bounded fallback scan size (default ${DEFAULT_SCAN_LIMIT}).

Exit codes
  0 done   2 usage   3 refused   4 needs confirmation   5 half-done, act now

States: ${Object.values(ACCESS_STATE).join(" | ")}`;
}

export {parseArgs, usage};
