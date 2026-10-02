#!/usr/bin/env node

/**
 * Sends a drop announcement email (`drop_announcement`), one per opted-in
 * climber, through the ordinary email queue.
 *
 * Nothing here talks to Resend. Every mode that sends writes `email_jobs`
 * through `enqueueLifecycleEmailIfAllowed` - the consent-gated, dedupe-checked
 * enqueue every lifecycle email uses - and the deployed `processEmailJobs`
 * worker delivers them, re-reading consent at send time and adding the signed
 * unsubscribe link and one-click headers. The drop's content and renderer are
 * the compiled `functions/src/email/drops.ts` and `dropTemplate.ts`, so the
 * preview, the test and the real send are byte-for-byte the same template.
 *
 * Modes, one per run:
 *   (none)          Dry run. Prints the audience count and every preflight
 *                   check. Writes nothing.
 *   --preview FILE  Writes the rendered HTML (and FILE.txt, the plain-text
 *                   part) for a browser look. Writes nothing to Firestore.
 *   --test-to EMAIL Queues one test email to the account with that address in
 *                   the target project, under a test-only dedupe key, so the
 *                   account's real send is untouched. The account must have
 *                   opted in, exactly as for the real send.
 *   --send          Queues the drop for the whole audience. Idempotent: the
 *                   dedupe key is `drop:{dropId}:{uid}`, so a rerun queues only
 *                   climbers not already queued.
 *   --status        Counts this drop's real jobs by status.
 *
 * --send refuses unless every preflight passes:
 *   - every image the email draws answers 200 from the asset site;
 *   - every item, requirement and event in the email matches the unlock
 *     catalogue that project's app reads (`/unlocks/catalog.json`), and the
 *     catalogue has no live item for the event that the email leaves out;
 *   - in production, the App Store reports at least the drop's
 *     `minimumAppStoreVersion` live, because the email must not land before
 *     the update that contains what it promises.
 * --test-to runs the same checks but only warns on the catalogue and the App
 * Store, so a test can go out before either is live.
 *
 * Usage:
 *   node scripts/send-drop-email.mjs --env staging --drop halloween-2026
 *   node scripts/send-drop-email.mjs --env staging --drop halloween-2026 --preview /tmp/drop.html
 *   node scripts/send-drop-email.mjs --env staging --drop halloween-2026 --test-to you@example.com
 *   node scripts/send-drop-email.mjs --env prod --confirm-production ascend-prod-9c8f2 --drop halloween-2026
 *   node scripts/send-drop-email.mjs --env prod --confirm-production ascend-prod-9c8f2 --drop halloween-2026 --send
 *   node scripts/send-drop-email.mjs --env prod --confirm-production ascend-prod-9c8f2 --drop halloween-2026 --status
 *
 * Prerequisites:
 *   cd functions && npm ci && npm run build
 *   gcloud auth application-default login
 *   The target project's processEmailJobs deployed from a build that knows
 *   `drop_announcement`, bound to a TRANSACTIONAL_EMAIL_CONFIG that carries an
 *   unsubscribeSigningKey - without it the worker delivers nothing at all.
 */

import {createRequire} from "node:module";
import {existsSync, writeFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {isEntrypoint} from "./lib/is-entrypoint.mjs";

export const PRODUCTION_PROJECT_ID = "ascend-prod-9c8f2";
export const ENVIRONMENTS = Object.freeze({
  dev: "ascend-f2e4f",
  staging: "ascend-staging-fa7d5",
  prod: PRODUCTION_PROJECT_ID,
});
export const PRODUCTION_SITE_URL = "https://ascendstepper.com";
export const APP_STORE_APP_ID = "6757202987";
const MODES = ["preview", "testTo", "send", "status"];

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const FUNCTIONS_DIR = resolve(SCRIPT_DIR, "..", "functions");
const DROP_EMAILS_MODULE = resolve(FUNCTIONS_DIR, "lib/src/dropEmails.js");
const DROPS_MODULE = resolve(FUNCTIONS_DIR, "lib/src/email/drops.js");
const TEMPLATE_MODULE = resolve(FUNCTIONS_DIR, "lib/src/email/dropTemplate.js");

if (isEntrypoint(import.meta.url)) {
  try {
    await main();
  } catch (error) {
    console.error(error?.message ?? error);
    process.exitCode = 1;
  }
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printUsage();
    return;
  }
  const target = resolveTarget(args);
  if (!args.drop) {
    throw new Error("--drop is required, e.g. --drop halloween-2026.");
  }
  const {admin, dropEmails, drops, template} = loadFunctionsModules();
  const definition = drops.DROP_EMAILS[args.drop];
  if (!definition) {
    throw new Error(`Unknown drop "${args.drop}". Known: ` +
      `${Object.keys(drops.DROP_EMAILS).join(", ")}.`);
  }
  const assetBaseUrl = args.assetBaseUrl ?? defaultAssetBaseUrl(target.projectId);
  const payload = dropEmails.validateDropEmailPayload(
    drops.buildDropEmailPayload(args.drop, assetBaseUrl)
  );

  console.log(`Target: ${target.label}`);
  console.log(`Drop: ${payload.dropId} ("${payload.subject}")`);
  console.log(`Mode: ${modeLabel(args)}`);

  if (args.preview) {
    writePreview(template, payload, args.preview);
    return;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: target.projectId,
  });
  const db = admin.firestore();

  if (args.status) {
    const counts = await dropEmails.readDropJobStatus(db, payload.dropId);
    const total = Object.values(counts).reduce((sum, count) => sum + count, 0);
    console.log(`Jobs for ${payload.dropId}: ${total}`);
    for (const [status, count] of Object.entries(counts).sort()) {
      console.log(`  ${status}: ${count}`);
    }
    return;
  }

  const strict = Boolean(args.send);
  const checks = await runPreflight({
    dropEmails,
    template,
    payload,
    definition,
    target,
  });
  printChecks(checks, {strict});

  if (args.testTo) {
    if (checks.some((check) => check.name === "images" && !check.ok)) {
      throw new Error("Refusing the test send: an image is missing, so the " +
        "test would not show what climbers will get.");
    }
    await sendTest({admin, db, dropEmails, payload, email: args.testTo});
    return;
  }

  const audience = await dropEmails.readDropAudience(db);
  console.log("");
  console.log(`Audience: ${audience.recipients.length} opted-in climber(s) ` +
    "with an email address");
  console.log(`  opted in, no address on profile: ${audience.skippedNoEmail}`);
  console.log(`  not opted in: ${audience.notOptedIn}`);

  if (!args.send) {
    console.log("");
    console.log("Dry run: nothing was queued. Pass --send to queue the drop.");
    return;
  }

  const failed = checks.filter((check) => !check.ok);
  if (failed.length > 0) {
    throw new Error(`Refusing to send: ${failed.length} preflight check(s) ` +
      `failed (${failed.map((check) => check.name).join(", ")}).`);
  }

  const summary = await dropEmails.enqueueDropEmails(
    db,
    payload,
    audience.recipients
  );
  console.log("");
  console.log(`Queued: ${summary.queued}`);
  console.log(`Already queued by an earlier run: ${summary.alreadyQueued}`);
  console.log(`Opted out since the audience was read: ${summary.preferencesDisabled}`);
  console.log(`Failed to queue: ${summary.failed.length}`);
  for (const failure of summary.failed) {
    console.log(`  ${failure.uid}: ${failure.error}`);
  }
  console.log("");
  console.log("processEmailJobs delivers 25 a minute. Watch it with --status.");
  if (summary.failed.length > 0) {
    process.exitCode = 1;
  }
}

/**
 * Parses command-line arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Parsed arguments.
 */
export function parseArgs(argv) {
  const parsed = {
    assetBaseUrl: null,
    confirmProduction: null,
    drop: null,
    env: null,
    help: false,
    preview: null,
    send: false,
    status: false,
    testTo: null,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--env":
        parsed.env = requireValue(argv, ++index, value);
        break;
      case "--confirm-production":
        parsed.confirmProduction = requireValue(argv, ++index, value);
        break;
      case "--drop":
        parsed.drop = requireValue(argv, ++index, value);
        break;
      case "--asset-base-url":
        parsed.assetBaseUrl = parseHttpsUrl(requireValue(argv, ++index, value));
        break;
      case "--preview":
        parsed.preview = requireValue(argv, ++index, value);
        break;
      case "--test-to":
        parsed.testTo = requireValue(argv, ++index, value).trim();
        break;
      case "--send":
        parsed.send = true;
        break;
      case "--status":
        parsed.status = true;
        break;
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  const modes = MODES.filter((mode) => Boolean(parsed[mode]));
  if (modes.length > 1) {
    throw new Error("Pick one of --preview, --test-to, --send, --status.");
  }
  if (parsed.testTo !== null && !parsed.testTo.includes("@")) {
    throw new Error("--test-to needs an email address.");
  }
  if (parsed.send && parsed.assetBaseUrl !== null) {
    // The real send serves images from the environment's own site, the one
    // the drop's images were deployed to with the release; an override is
    // for previewing images that are not deployed yet.
    throw new Error("--asset-base-url is for --preview and --test-to only.");
  }
  return parsed;
}

/**
 * The environment a run targets. `--env` is required, and production also
 * needs `--confirm-production` spelling out its project id - for a dry run
 * too, because a dry run still reads real climbers' preferences.
 * @param {{env: string | null, confirmProduction: string | null}} args Args.
 * @return {{projectId: string, env: string, label: string}} Resolved target.
 */
export function resolveTarget({env = null, confirmProduction = null} = {}) {
  if (env === null) {
    throw new Error(
      "No target. Pass --env dev, --env staging, or --env prod " +
        `--confirm-production ${PRODUCTION_PROJECT_ID}.`
    );
  }
  if (!Object.hasOwn(ENVIRONMENTS, env)) {
    throw new Error(
      `Unknown environment "${env}". Use one of: ${Object.keys(ENVIRONMENTS).join(", ")}.`
    );
  }
  const projectId = ENVIRONMENTS[env];
  if (projectId === PRODUCTION_PROJECT_ID && confirmProduction !== projectId) {
    throw new Error(
      `Production requires --confirm-production ${PRODUCTION_PROJECT_ID}.`
    );
  }
  return {projectId, env, label: `${projectId} (${env})`};
}

/**
 * Where a project's drop images are served: production's public domain, and
 * every other project's own Firebase Hosting site.
 * @param {string} projectId Firebase project id.
 * @return {string} https base URL.
 */
export function defaultAssetBaseUrl(projectId) {
  return projectId === PRODUCTION_PROJECT_ID ?
    PRODUCTION_SITE_URL :
    `https://${projectId}.web.app`;
}

/**
 * The unlock catalogue the project's app reads (`UnlockCatalogRepository`).
 * @param {string} projectId Firebase project id.
 * @return {string} Catalogue URL.
 */
export function catalogueUrl(projectId) {
  return `https://${projectId}.web.app/unlocks/catalog.json`;
}

/**
 * Compares dotted marketing versions numerically ("1.10" > "1.9").
 * @param {string} lhs Version.
 * @param {string} rhs Version.
 * @return {number} Negative, zero or positive.
 */
export function compareVersions(lhs, rhs) {
  const left = lhs.split(".").map(Number);
  const right = rhs.split(".").map(Number);
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) {
      return difference;
    }
  }
  return 0;
}

/**
 * Runs every preflight check and returns each outcome; never throws for a
 * failed check, so the operator sees all of them at once.
 * @param {object} context Modules, payload, drop definition and target.
 * @return {Promise<Array<{name: string, ok: boolean, detail: string[], gate: string}>>}
 *   Outcomes. `gate` is "always" for a check that blocks a test too.
 */
async function runPreflight({dropEmails, template, payload, definition, target}) {
  const checks = [];

  const imagePaths = template.dropEmailImagePaths(payload);
  const missing = [];
  await Promise.all(imagePaths.map(async (path) => {
    const url = `${payload.assetBaseUrl}/${path}`;
    const problem = await checkImage(url);
    if (problem) {
      missing.push(`${url}: ${problem}`);
    }
  }));
  checks.push({
    name: "images",
    gate: "always",
    ok: missing.length === 0,
    detail: missing.length === 0 ?
      [`${imagePaths.length} image(s) answer 200 from ${payload.assetBaseUrl}`] :
      missing.sort(),
  });

  const url = catalogueUrl(target.projectId);
  let catalogueDetail;
  try {
    const response = await fetch(url, {cache: "no-store"});
    if (!response.ok) {
      catalogueDetail = [`${url} answered HTTP ${response.status}`];
    } else {
      const mismatches = dropEmails.dropCatalogueMismatches(
        payload,
        await response.json()
      );
      catalogueDetail = mismatches.length === 0 ? [] : mismatches;
    }
  } catch (error) {
    catalogueDetail = [`${url}: ${error.message}`];
  }
  checks.push({
    name: "catalogue",
    gate: "send",
    ok: catalogueDetail.length === 0,
    detail: catalogueDetail.length === 0 ?
      [`every item matches ${url}`] :
      catalogueDetail,
  });

  if (target.projectId === PRODUCTION_PROJECT_ID) {
    checks.push(await checkAppStoreVersion(definition.minimumAppStoreVersion));
  }
  return checks;
}

/**
 * Why an image URL would not render, or null when it would.
 * @param {string} url Image URL.
 * @return {Promise<string | null>} Problem, or null.
 */
async function checkImage(url) {
  try {
    const response = await fetch(url, {method: "HEAD", cache: "no-store"});
    if (!response.ok) {
      return `HTTP ${response.status}`;
    }
    const type = response.headers.get("content-type") ?? "";
    return type.startsWith("image/") ? null : `content-type ${type || "none"}`;
  } catch (error) {
    return error.message;
  }
}

/**
 * Whether the App Store already sells a version at least `minimum`.
 * @param {string} minimum Minimum marketing version.
 * @return {Promise<object>} Check outcome.
 */
async function checkAppStoreVersion(minimum) {
  const url = `https://itunes.apple.com/lookup?id=${APP_STORE_APP_ID}&country=us`;
  try {
    const response = await fetch(url, {cache: "no-store"});
    const body = await response.json();
    const live = body?.results?.[0]?.version;
    if (typeof live !== "string") {
      return {name: "app-store", gate: "send", ok: false,
        detail: [`${url} returned no version`]};
    }
    const ok = compareVersions(live, minimum) >= 0;
    return {
      name: "app-store",
      gate: "send",
      ok,
      detail: [`App Store live version ${live}; this drop needs ${minimum} or later`],
    };
  } catch (error) {
    return {name: "app-store", gate: "send", ok: false,
      detail: [`${url}: ${error.message}`]};
  }
}

function printChecks(checks, {strict}) {
  console.log("");
  console.log("Preflight:");
  for (const check of checks) {
    const verdict = check.ok ? "PASS" :
      strict || check.gate === "always" ? "FAIL" : "WARN";
    console.log(`  ${verdict} ${check.name}`);
    for (const line of check.detail) {
      console.log(`       ${line}`);
    }
  }
}

/**
 * Queues one test email to the account holding `email` in the target.
 * @param {object} context Admin SDK, Firestore, modules, payload, address.
 */
async function sendTest({admin, db, dropEmails, payload, email}) {
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (error) {
    throw new Error(`No account with ${email} in this project ` +
      `(${error.code ?? error.message}).`);
  }
  const runId = new Date().toISOString().replace(/[^0-9]/g, "");
  const outcome = await dropEmails.enqueueDropTestEmail(
    db,
    payload,
    {email, uid: user.uid},
    runId
  );
  console.log("");
  if (outcome === "preferences_disabled") {
    throw new Error(`${email} (uid ${user.uid}) has not opted in to email, ` +
      "so the real send would skip them too. Turn on Settings -> Email in " +
      "the app for this environment, then run the test again.");
  }
  console.log(`Test ${outcome} for ${email} (uid ${user.uid}), ` +
    `dedupe key ${dropEmails.buildDropTestDedupeKey(payload.dropId, user.uid, runId)}.`);
  console.log("processEmailJobs picks it up within a minute.");
}

function writePreview(template, payload, file) {
  const rendered = template.renderDropEmail(payload, {
    unsubscribeUrl: `${PRODUCTION_SITE_URL}/api/unsubscribe?token=preview`,
  });
  writeFileSync(file, rendered.html);
  writeFileSync(`${file}.txt`, rendered.text);
  console.log(`Wrote ${file} and ${file}.txt (subject: "${rendered.subject}").`);
}

function modeLabel(args) {
  if (args.preview) return `preview -> ${args.preview}`;
  if (args.testTo) return `test send to ${args.testTo}`;
  if (args.send) return "SEND to the whole audience";
  if (args.status) return "status";
  return "dry run (pass --send to queue)";
}

function parseHttpsUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`Not a URL: ${value}`);
  }
  if (url.protocol !== "https:") {
    throw new Error(`Not an https URL: ${value}`);
  }
  return url.toString().replace(/\/+$/, "");
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

/**
 * Loads the compiled functions modules and the firebase-admin instance they
 * call. The bundle resolves firebase-admin inside functions/, so the app is
 * initialized on that instance or the first read fails.
 * @return {object} Modules.
 */
function loadFunctionsModules() {
  if (!existsSync(DROP_EMAILS_MODULE)) {
    throw new Error("functions/lib is not built. Run: cd functions && npm run build");
  }
  const requireFromFunctions = createRequire(resolve(FUNCTIONS_DIR, "package.json"));
  return {
    admin: requireFromFunctions("firebase-admin"),
    dropEmails: requireFromFunctions(DROP_EMAILS_MODULE),
    drops: requireFromFunctions(DROPS_MODULE),
    template: requireFromFunctions(TEMPLATE_MODULE),
  };
}

function printUsage() {
  console.log(`
Usage:
  node scripts/send-drop-email.mjs --env <dev|staging|prod> --drop <id> [mode]

Modes (one at most; none is a dry run that writes nothing):
  --preview <file>          Write the rendered HTML and <file>.txt.
  --test-to <email>         Queue one test to that account (must have opted in).
  --send                    Queue the drop for every opted-in climber.
  --status                  Count this drop's jobs by status.

Flags:
  --confirm-production <id> Required with --env prod, dry run included.
  --asset-base-url <url>    Serve images from another https site
                            (--preview and --test-to only).

--send refuses unless every image answers 200, every item matches the
project's hosted unlock catalogue, and (production) the App Store reports the
drop's minimum app version live. Build first: cd functions && npm run build.
`);
}
