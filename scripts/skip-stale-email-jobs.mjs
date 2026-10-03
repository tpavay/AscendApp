#!/usr/bin/env node

/**
 * Marks stale queued email jobs `skipped` so they never deliver.
 *
 * Until 2026-10-02 no environment's TRANSACTIONAL_EMAIL_CONFIG carried an
 * unsubscribeSigningKey, so `processEmailJobs` refused every run and every job
 * it was handed stayed `queued` - recaps for periods long closed, a rating
 * follow-up from August. The moment a key lands, the worker would deliver that
 * whole backlog within a minute, as if it were news. Run this first, in the
 * same environment, before the key is deployed.
 *
 * `skipped` is the worker's own terminal "deliberately not delivered" status:
 * nothing to retry and no error recorded. Each job is re-read in a transaction
 * and only changed while it is still `queued`.
 *
 * Dry run is the default and lists the jobs (id, type, created) without any
 * address. `--commit` skips exactly the jobs the same cutoff lists.
 *
 * Usage:
 *   node scripts/skip-stale-email-jobs.mjs --env staging --before 2026-10-02T12:00:00Z
 *   node scripts/skip-stale-email-jobs.mjs --env staging --before 2026-10-02T12:00:00Z --commit
 *   node scripts/skip-stale-email-jobs.mjs --env prod --confirm-production ascend-prod-9c8f2 --before <ISO>
 *
 * Prerequisites:
 *   cd functions && npm ci && npm run build
 *   gcloud auth application-default login
 */

import {createRequire} from "node:module";
import {existsSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {resolveTarget} from "./send-drop-email.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const FUNCTIONS_DIR = resolve(SCRIPT_DIR, "..", "functions");
const DROP_EMAILS_MODULE = resolve(FUNCTIONS_DIR, "lib/src/dropEmails.js");

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
    console.log("Usage: node scripts/skip-stale-email-jobs.mjs --env <dev|staging|prod> " +
      "[--confirm-production <id>] --before <ISO time> [--commit]");
    return;
  }
  const target = resolveTarget(args);
  if (!existsSync(DROP_EMAILS_MODULE)) {
    throw new Error("functions/lib is not built. Run: cd functions && npm run build");
  }
  const requireFromFunctions = createRequire(resolve(FUNCTIONS_DIR, "package.json"));
  const admin = requireFromFunctions("firebase-admin");
  const dropEmails = requireFromFunctions(DROP_EMAILS_MODULE);
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: target.projectId,
  });
  const db = admin.firestore();

  console.log(`Target: ${target.label}`);
  console.log(`Cutoff: queued jobs created before ${args.before.toISOString()}`);
  console.log(`Mode: ${args.commit ? "COMMIT" : "dry run (pass --commit to skip them)"}`);

  const stale = await dropEmails.readStaleQueuedEmailJobs(db, args.before);
  console.log("");
  console.log(`Stale queued jobs: ${stale.length}`);
  for (const job of stale) {
    console.log(`  ${job.createdAt}  ${job.type.padEnd(36)} ${job.id}`);
  }
  if (!args.commit || stale.length === 0) {
    return;
  }

  const result = await dropEmails.skipStaleQueuedEmailJobs(
    db,
    stale.map((job) => job.id)
  );
  console.log("");
  console.log(`Skipped: ${result.skipped}`);
  console.log(`No longer queued, left alone: ${result.unchanged}`);
}

/**
 * Parses command-line arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Parsed arguments.
 */
export function parseArgs(argv) {
  const parsed = {
    before: null,
    commit: false,
    confirmProduction: null,
    env: null,
    help: false,
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
      case "--before": {
        const raw = requireValue(argv, ++index, value);
        // An explicit offset only: a bare local time would mean a different
        // cutoff on every operator's machine.
        if (!/(Z|[+-]\d{2}:\d{2})$/.test(raw) || Number.isNaN(Date.parse(raw))) {
          throw new Error("--before needs an ISO time with a zone, e.g. 2026-10-02T12:00:00Z");
        }
        parsed.before = new Date(raw);
        break;
      }
      case "--commit":
        parsed.commit = true;
        break;
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }
  if (!parsed.help && parsed.before === null) {
    throw new Error("--before is required: nothing is stale without a cutoff.");
  }
  return parsed;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}
