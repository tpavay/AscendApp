#!/usr/bin/env node
/**
 * Who may connect Strava, per project. See docs/strava-integration.md.
 *
 * Usage:
 *   node scripts/strava-access.mjs show   --env dev
 *   node scripts/strava-access.mjs enable --env dev --apply
 *   node scripts/strava-access.mjs allow  --env dev --email climber@example.com --apply
 *   node scripts/strava-access.mjs allow  --env dev --uid <uid> --apply
 *   node scripts/strava-access.mjs remove --env dev --uid <uid> --apply
 *   node scripts/strava-access.mjs disable --env prod --confirm-production --apply
 *
 * Without --apply every change is a dry run that prints the plan. `show` also
 * lists who is connected right now. Strava counts every connection against
 * the app's athlete capacity, so `allow` counts allowed and connected climbers
 * together.
 *
 * Prerequisites: cd scripts && npm install; gcloud auth application-default login
 */

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {ENVIRONMENTS, PRODUCTION_PROJECT_ID} from "./lib/firestore-read-outcome.mjs";
import {
  normalizeStravaAccess,
  planStravaAccessChange,
  STRAVA_ACCESS_PATH,
} from "./lib/strava-access-policy.mjs";

const COMMANDS = new Set(["show", "enable", "disable", "allow", "remove"]);

if (isEntrypoint(import.meta.url)) {
  try {
    await main(process.argv.slice(2));
  } catch (error) {
    console.error(`error: ${error instanceof Error ? error.message : error}`);
    process.exitCode = 1;
  }
}

/**
 * @param {string[]} args CLI arguments.
 * @return {Promise<void>} Resolves when done.
 */
async function main(args) {
  const options = parseArgs(args);
  const projectId = ENVIRONMENTS[options.env];
  if (!projectId) {
    throw new Error(`Pass --env ${Object.keys(ENVIRONMENTS).join("|")}.`);
  }
  if (projectId === PRODUCTION_PROJECT_ID && !options.confirmProduction) {
    throw new Error("Production requires --confirm-production.");
  }
  const app = initializeApp({credential: applicationDefault(), projectId});
  const firestore = getFirestore(app);
  const reference = firestore
    .collection(STRAVA_ACCESS_PATH.collection)
    .doc(STRAVA_ACCESS_PATH.document);
  const current = normalizeStravaAccess((await reference.get()).data());

  const connectedUserIds = (await firestore.collection("_strava_connections").get())
    .docs.map((document) => document.id);

  console.log(`project: ${projectId} (${options.env})`);
  if (options.command === "show") {
    console.log(`enabled: ${current.enabled}`);
    console.log(`allowed (${current.allowedUserIds.length}): ${current.allowedUserIds.join(", ") || "none"}`);
    console.log(`connected (${connectedUserIds.length}): ${connectedUserIds.join(", ") || "none"}`);
    return;
  }

  const userId = options.email ?
    (await getAuth(app).getUserByEmail(options.email)).uid :
    options.uid;
  const plan = planStravaAccessChange(current, {
    command: options.command,
    userId,
    capacity: options.capacity,
    connectedUserIds,
  });
  console.log(plan.summary);
  if (!plan.changed) {
    return;
  }
  if (!options.apply) {
    console.log("Dry run. Re-run with --apply to write it.");
    return;
  }
  await reference.set({
    enabled: plan.next.enabled,
    allowedUserIds: plan.next.allowedUserIds,
    updatedAt: new Date(),
  });
  console.log("Written.");
}

/**
 * @param {string[]} args CLI arguments.
 * @return {object} Parsed options.
 */
function parseArgs(args) {
  const [command, ...rest] = args;
  if (!COMMANDS.has(command)) {
    throw new Error(`First argument must be one of: ${[...COMMANDS].join(", ")}.`);
  }
  const options = {command, env: null, uid: null, email: null, capacity: undefined, apply: false, confirmProduction: false};
  for (let index = 0; index < rest.length; index += 1) {
    const flag = rest[index];
    const value = () => {
      const next = rest[index + 1];
      if (next === undefined || next.startsWith("--")) {
        throw new Error(`${flag} needs a value.`);
      }
      index += 1;
      return next;
    };
    switch (flag) {
    case "--env": options.env = value(); break;
    case "--uid": options.uid = value(); break;
    case "--email": options.email = value(); break;
    case "--capacity": options.capacity = Number(value()); break;
    case "--apply": options.apply = true; break;
    case "--confirm-production": options.confirmProduction = true; break;
    default: throw new Error(`Unknown flag ${flag}.`);
    }
  }
  return options;
}
