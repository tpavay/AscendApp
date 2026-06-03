#!/usr/bin/env node

/**
 * Ascend Dev Database Tool
 *
 * One command surface for clearing, seeding, resetting, and hydrating dev-like
 * Firebase data. This tool intentionally refuses production.
 *
 * Usage:
 *   node scripts/dev-db.mjs plan
 *   node scripts/dev-db.mjs seed --target profiles --project dev
 *   node scripts/dev-db.mjs clear --target profiles,leaderboard --project dev
 *   node scripts/dev-db.mjs reset --target all --project dev
 *   node scripts/dev-db.mjs wipe --project dev --confirm-dev-wipe
 *   node scripts/dev-db.mjs hydrate-user --project dev --user <uid> --display-name "Tyler P." --age 27 --gender man --weight-lb 178 --country US --region IL
 *   node scripts/dev-db.mjs seed-demo-user --project staging --email person@example.com
 */

import {spawnSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const PRODUCTION_PROJECT_ID = "ascend-prod-9c8f2";
const BATCH_TARGET_ORDER = ["profiles", "leaderboard", "live-replay", "routine-templates"];
const ALLOWED_PROJECT_IDS = new Set([DEV_PROJECT_ID, STAGING_PROJECT_ID]);
const VALID_GENDERS = new Set(["woman", "man", "non_binary", "prefer_not_to_say"]);
const WIPE_COLLECTION_IDS = [
  "users",
  "leaderboard_stats",
  "live_replay_leaderboards",
  "live_climb_community_stats",
  "routine_templates",
  "feedback",
  "userRateLimits",
  "config",
  "email_jobs",
  "email_rate_limits",
  "oauthStates",
  "waitlist",
];

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");

const TARGETS = {
  profiles: {
    label: "Profile users, public profiles, profile stats, achievements, public workout summaries",
    script: "seed-test-users.mjs",
  },
  leaderboard: {
    label: "Global leaderboard_stats test rows",
    script: "seed-leaderboard.mjs",
  },
  "live-replay": {
    label: "Live Replay leaderboard summaries, finishers, split buckets, and entries",
    script: "seed-live-replay-leaderboards.mjs",
  },
  "routine-templates": {
    label: "Remote routine template content",
    script: "seed-routine-templates.mjs",
  },
};

const SERVER_TIMESTAMP_PREVIEW = "<serverTimestamp>";
const LIVE_REPLAY_SEED_FLAGS = new Set([
  "--source-user",
  "--avatar-dir",
  "--seed-pack",
  "--apple-health-step-factor",
  "--skip-clear",
]);
const ROUTINE_TEMPLATE_SEED_FLAGS = new Set([
  "--file",
  "--seed-pack",
  "--skip-clear",
]);

const TARGET_ALIASES = new Map([
  ["all", "all"],
  ["profile", "profiles"],
  ["profiles", "profiles"],
  ["users", "profiles"],
  ["user", "profiles"],
  ["leaderboard", "leaderboard"],
  ["leaderboards", "leaderboard"],
  ["replay", "live-replay"],
  ["live-replay", "live-replay"],
  ["live_replay", "live-replay"],
  ["routine-template", "routine-templates"],
  ["routine-templates", "routine-templates"],
  ["routine_templates", "routine-templates"],
  ["routines", "routine-templates"],
  ["training", "routine-templates"],
]);

function parseArgs(argv) {
  const args = {
    command: argv[2] ?? "help",
    project: "dev",
    targets: ["all"],
    dryRun: false,
    skipClear: false,
    confirmDevWipe: false,
    passthrough: [],
    userId: null,
    displayName: null,
    firstName: null,
    lastName: null,
    email: null,
    photoURL: null,
    age: null,
    gender: null,
    weightKg: null,
    locationCountry: null,
    locationRegion: null,
    joinedAt: null,
    scenario: "full-showcase",
    seedFirstAscent: true,
    firstAscentClimbId: null,
  };

  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--project":
        args.project = requireValue(argv, ++index, value);
        break;
      case "--target":
      case "--targets":
        args.targets = requireValue(argv, ++index, value).split(",").map((target) => target.trim());
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--skip-clear":
        args.skipClear = true;
        args.passthrough.push(value);
        break;
      case "--confirm-dev-wipe":
        args.confirmDevWipe = true;
        break;
      case "--source-user":
      case "--avatar-dir":
      case "--seed-pack":
      case "--file":
      case "--apple-health-step-factor":
        args.passthrough.push(value, requireValue(argv, ++index, value));
        break;
      case "--user":
      case "--uid":
        args.userId = requireValue(argv, ++index, value);
        break;
      case "--display-name":
        args.displayName = requireValue(argv, ++index, value);
        break;
      case "--first-name":
        args.firstName = requireValue(argv, ++index, value);
        break;
      case "--last-name":
        args.lastName = requireValue(argv, ++index, value);
        break;
      case "--email":
        args.email = requireValue(argv, ++index, value);
        break;
      case "--photo-url":
        args.photoURL = requireValue(argv, ++index, value);
        break;
      case "--age":
        args.age = numberValue(requireValue(argv, ++index, value), value);
        break;
      case "--gender":
        args.gender = requireValue(argv, ++index, value);
        break;
      case "--weight-kg":
        args.weightKg = numberValue(requireValue(argv, ++index, value), value);
        break;
      case "--weight-lb":
        args.weightKg = poundsToKg(numberValue(requireValue(argv, ++index, value), value));
        break;
      case "--country":
        args.locationCountry = requireValue(argv, ++index, value).toUpperCase();
        break;
      case "--region":
        args.locationRegion = requireValue(argv, ++index, value).toUpperCase();
        break;
      case "--joined-at":
        args.joinedAt = parseDate(requireValue(argv, ++index, value), value);
        break;
      case "--scenario":
        args.scenario = requireValue(argv, ++index, value);
        break;
      case "--first-ascent-climb":
        args.firstAscentClimbId = requireValue(argv, ++index, value);
        break;
      case "--no-first-ascent":
        args.seedFirstAscent = false;
        break;
      case "--help":
      case "-h":
        args.command = "help";
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  return args;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function numberValue(value, flag) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`${flag} must be a finite number`);
  }
  return parsed;
}

function parseDate(value, flag) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`${flag} must be an ISO date or timestamp`);
  }
  return date;
}

function printHelp() {
  console.log(`
Usage:
  node scripts/dev-db.mjs plan
  node scripts/dev-db.mjs seed --target profiles --project dev
  node scripts/dev-db.mjs clear --target profiles,leaderboard --project dev
  node scripts/dev-db.mjs reset --target all --project dev
  node scripts/dev-db.mjs wipe --project dev --confirm-dev-wipe
  node scripts/dev-db.mjs hydrate-user --project dev --user <uid> --display-name "Tyler P." --age 27 --gender man --weight-lb 178 --country US --region IL
  node scripts/dev-db.mjs seed-demo-user --project staging --email person@example.com

Commands:
  plan          Show available targets and examples.
  seed          Seed one or more targets.
  clear         Clear one or more targets.
  reset         Clear then seed one or more targets.
  wipe          Delete all reviewed top-level Firestore collections in dev only.
  hydrate-user  Merge complete profile identity/demographic fields into one dev/staging user.
  seed-demo-user Seed one real dev/staging Auth user with product-demo data.

Targets:
  profiles      ${TARGETS.profiles.label}
  leaderboard   ${TARGETS.leaderboard.label}
  live-replay   ${TARGETS["live-replay"].label}
  routine-templates ${TARGETS["routine-templates"].label}
  all           profiles, leaderboard, live-replay, routine-templates

Options:
  --project <dev|staging|projectId>  Defaults to dev. Production is refused.
  --target <list>                    Comma-separated target list. Defaults to all.
  --dry-run                          Print plans without writing.
  --skip-clear                       Forwarded to seed targets that support it.
  --confirm-dev-wipe                 Required for wipe without --dry-run.
  --source-user <uid>                Forwarded to live-replay seed.
  --avatar-dir <path>                Forwarded to live-replay seed.
  --seed-pack <id>                   Forwarded to seed targets that support it.
  --file <path>                      Forwarded to routine-templates seed.
  --apple-health-step-factor <n>     Forwarded to live-replay seed.
  --scenario <name>                  Demo user scenario. Defaults to full-showcase.
  --first-ascent-climb <climbId>     Demo First Ascent climb. Defaults in seed script.
  --no-first-ascent                  Demo user seed will not claim a First Ascent.

hydrate-user fields:
  --user <uid> --display-name <name> --age <13-120> --gender <woman|man|non_binary|prefer_not_to_say>
  --weight-kg <kg> or --weight-lb <lb>
  --country <ISO-2> [--region <state/province>] [--joined-at <ISO date>]
  [--email <email>] [--first-name <name>] [--last-name <name>] [--photo-url <url>]
`);
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.command === "help" || args.command === "--help" || args.command === "-h") {
    printHelp();
    return;
  }

  if (args.command === "plan") {
    printPlan();
    return;
  }

  const projectId = resolveProjectId(args.project);
  assertAllowedProject(projectId);

  if (args.command === "wipe") {
    await wipeDevFirestore(projectId, args);
    return;
  }

  if (args.command === "hydrate-user") {
    await hydrateUser(projectId, args);
    return;
  }

  if (args.command === "seed-demo-user") {
    runDemoUserScript(projectId, args);
    return;
  }

  if (!["seed", "clear", "reset"].includes(args.command)) {
    throw new Error("Command must be plan, seed, clear, reset, wipe, hydrate-user, seed-demo-user, or help");
  }

  const targets = resolveTargets(args.targets);
  printExecutionPlan(args.command, projectId, targets, args);

  if (args.command === "clear" || args.command === "reset") {
    for (const target of targets) {
      runTargetScript(target, "clear", projectId, args);
    }
  }

  if (args.command === "seed" || args.command === "reset") {
    for (const target of targets) {
      runTargetScript(target, "seed", projectId, args);
    }
  }
}

function printPlan() {
  console.log("Ascend dev database targets:");
  for (const target of BATCH_TARGET_ORDER) {
    console.log(`  ${target}: ${TARGETS[target].label}`);
  }
  console.log("\nExamples:");
  console.log("  node scripts/dev-db.mjs reset --target all --project dev");
  console.log("  node scripts/dev-db.mjs wipe --project dev --confirm-dev-wipe");
  console.log("  node scripts/dev-db.mjs seed --target profiles,live-replay --project dev --dry-run");
  console.log("  node scripts/dev-db.mjs seed --target routine-templates --project dev");
  console.log("  node scripts/dev-db.mjs clear --target leaderboard --project dev");
  console.log("  node scripts/dev-db.mjs hydrate-user --project dev --user <uid> --display-name \"Tyler P.\" --age 27 --gender man --weight-lb 178 --country US --region IL");
  console.log("  node scripts/dev-db.mjs seed-demo-user --project staging --email person@example.com");
}

function resolveProjectId(projectOrAlias) {
  const rc = JSON.parse(readFileSync(resolve(REPO_ROOT, ".firebaserc"), "utf-8"));
  return rc.projects?.[projectOrAlias] ?? projectOrAlias;
}

function assertAllowedProject(projectId) {
  if (projectId === PRODUCTION_PROJECT_ID || !ALLOWED_PROJECT_IDS.has(projectId)) {
    throw new Error(
      `Refusing to write ${projectId}. Only ${DEV_PROJECT_ID} and ${STAGING_PROJECT_ID} are allowed.`
    );
  }
}

function resolveTargets(rawTargets) {
  const normalized = new Set();
  for (const rawTarget of rawTargets) {
    const target = TARGET_ALIASES.get(rawTarget);
    if (!target) {
      throw new Error(`Unknown target "${rawTarget}". Use profiles, leaderboard, live-replay, routine-templates, or all.`);
    }

    if (target === "all") {
      BATCH_TARGET_ORDER.forEach((item) => normalized.add(item));
    } else {
      normalized.add(target);
    }
  }

  return BATCH_TARGET_ORDER.filter((target) => normalized.has(target));
}

function printExecutionPlan(command, projectId, targets, args) {
  console.log(`Project: ${projectId}`);
  console.log(`Command: ${command}${args.dryRun ? " (dry run)" : ""}`);
  console.log(`Targets: ${targets.join(", ")}`);
}

function runTargetScript(target, command, projectId, args) {
  const targetConfig = TARGETS[target];
  const scriptArgs = [
    resolve(SCRIPT_DIR, targetConfig.script),
    command,
    "--project",
    projectId,
  ];

  if (args.dryRun) {
    scriptArgs.push("--dry-run");
  }

  if (command === "seed") {
    appendSeedPassthroughArgs(target, scriptArgs, args);
  }

  console.log(`\n> node ${targetConfig.script} ${scriptArgs.slice(1).join(" ")}`);
  const result = spawnSync(process.execPath, scriptArgs, {
    cwd: SCRIPT_DIR,
    stdio: "inherit",
  });

  if (result.status !== 0) {
    throw new Error(`${targetConfig.script} ${command} failed with exit code ${result.status}`);
  }
}

function runDemoUserScript(projectId, args) {
  const scriptArgs = [
    resolve(SCRIPT_DIR, "seed-demo-user.mjs"),
    "seed",
    "--project",
    projectId,
  ];

  if (args.dryRun) {
    scriptArgs.push("--dry-run");
  }
  if (args.userId) {
    scriptArgs.push("--user", args.userId);
  }
  if (args.email) {
    scriptArgs.push("--email", args.email);
  }
  if (args.displayName) {
    scriptArgs.push("--display-name", args.displayName);
  }
  if (args.photoURL) {
    scriptArgs.push("--photo-url", args.photoURL);
  }
  if (args.age != null) {
    scriptArgs.push("--age", String(args.age));
  }
  if (args.gender) {
    scriptArgs.push("--gender", args.gender);
  }
  if (args.weightKg != null) {
    scriptArgs.push("--weight-kg", String(args.weightKg));
  }
  if (args.locationCountry) {
    scriptArgs.push("--country", args.locationCountry);
  }
  if (args.locationRegion) {
    scriptArgs.push("--region", args.locationRegion);
  }
  if (args.joinedAt) {
    scriptArgs.push("--joined-at", args.joinedAt.toISOString());
  }
  if (args.scenario) {
    scriptArgs.push("--scenario", args.scenario);
  }
  if (args.firstAscentClimbId) {
    scriptArgs.push("--first-ascent-climb", args.firstAscentClimbId);
  }
  if (!args.seedFirstAscent) {
    scriptArgs.push("--no-first-ascent");
  }

  console.log(`\n> node seed-demo-user.mjs ${scriptArgs.slice(1).join(" ")}`);
  const result = spawnSync(process.execPath, scriptArgs, {
    cwd: SCRIPT_DIR,
    stdio: "inherit",
  });

  if (result.status !== 0) {
    throw new Error(`seed-demo-user.mjs seed failed with exit code ${result.status}`);
  }
}

function appendSeedPassthroughArgs(target, scriptArgs, args) {
  if (target === "live-replay") {
    appendFilteredPassthroughArgs(scriptArgs, args.passthrough, LIVE_REPLAY_SEED_FLAGS);
  } else if (target === "routine-templates") {
    appendFilteredPassthroughArgs(scriptArgs, args.passthrough, ROUTINE_TEMPLATE_SEED_FLAGS);
  } else if (args.skipClear && target === "profiles") {
    // seed-test-users clears before seeding and does not currently support --skip-clear.
    console.warn("profiles target does not support --skip-clear; it will replace its seed pack.");
  } else if (args.skipClear && target === "leaderboard") {
    console.warn("leaderboard target does not support --skip-clear; it will upsert generated rows.");
  }
}

function appendFilteredPassthroughArgs(scriptArgs, passthroughArgs, allowedFlags) {
  for (let index = 0; index < passthroughArgs.length; index += 1) {
    const flag = passthroughArgs[index];
    const isBooleanFlag = flag === "--skip-clear";
    const value = isBooleanFlag ? null : passthroughArgs[index + 1];

    if (allowedFlags.has(flag)) {
      scriptArgs.push(flag);
      if (!isBooleanFlag) {
        scriptArgs.push(value);
      }
    }

    if (!isBooleanFlag) {
      index += 1;
    }
  }
}

async function wipeDevFirestore(projectId, args) {
  if (projectId !== DEV_PROJECT_ID) {
    throw new Error(`wipe is dev-only. Refusing to wipe ${projectId}.`);
  }
  if (!args.dryRun && !args.confirmDevWipe) {
    throw new Error("wipe requires --confirm-dev-wipe unless --dry-run is set");
  }

  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();
  const existingCollections = await db.listCollections();
  const existingIds = existingCollections.map((collection) => collection.id).sort();
  const allowedIds = new Set(WIPE_COLLECTION_IDS);
  const unknownIds = existingIds.filter((collectionId) => !allowedIds.has(collectionId));
  if (unknownIds.length > 0) {
    throw new Error(
      "Refusing wipe because Firestore has unreviewed top-level collection(s): " +
        unknownIds.join(", ")
    );
  }

  const collectionsToDelete = WIPE_COLLECTION_IDS
    .filter((collectionId) => existingIds.includes(collectionId));

  console.log(`Project: ${projectId}`);
  console.log(`Command: wipe${args.dryRun ? " (dry run)" : ""}`);
  console.log(`Collections: ${collectionsToDelete.length > 0 ? collectionsToDelete.join(", ") : "(none)"}`);

  if (args.dryRun) {
    console.log("Dry run only. No Firestore documents were deleted.");
    return;
  }

  for (const collectionId of collectionsToDelete) {
    console.log(`Deleting ${collectionId} recursively...`);
    await db.recursiveDelete(db.collection(collectionId));
  }

  console.log(`Wiped ${collectionsToDelete.length} top-level collection(s) from ${projectId}.`);
}

async function hydrateUser(projectId, args) {
  validateHydrateUserArgs(args);
  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();
  const userRef = db.collection("users").doc(args.userId);
  const existingSnapshot = await userRef.get();
  const existing = existingSnapshot.data() ?? {};
  const displayName = trimmed(args.displayName) ?? trimmed(existing.displayName) ?? "Climber";
  const photoURL = trimmed(args.photoURL) ?? trimmed(existing.profilePictureURL) ?? "";
  const joinedAt = args.joinedAt ?? timestampDate(existing.joined_at) ?? new Date();
  const firstName = trimmed(args.firstName) ?? firstNameFromDisplayName(displayName);
  const lastName = trimmed(args.lastName) ?? lastNameFromDisplayName(displayName);
  const email = trimmed(args.email) ?? trimmed(existing.email) ?? "";
  const serverTimestamp = serverTimestampValue(args.dryRun);

  const privateData = {
    email,
    firstName,
    lastName,
    displayName,
    profilePictureURL: photoURL,
    age: args.age,
    gender: args.gender,
    weight_kg: args.weightKg,
    location_country: args.locationCountry,
    joined_at: Timestamp.fromDate(joinedAt),
    lastUpdated: serverTimestamp,
  };

  if (args.locationRegion) {
    privateData.location_region = args.locationRegion;
  }
  if (!existingSnapshot.exists || !existing.createdAt) {
    privateData.createdAt = serverTimestamp;
  }

  const publicData = {
    userId: args.userId,
    displayName,
    photoURL,
    age: args.age,
    gender: args.gender,
    weight_kg: args.weightKg,
    location_country: args.locationCountry,
    joined_at: Timestamp.fromDate(joinedAt),
    lastUpdated: serverTimestamp,
  };
  if (args.locationRegion) {
    publicData.location_region = args.locationRegion;
  }

  printHydratePlan(projectId, args.userId, privateData, publicData, args.dryRun);
  if (args.dryRun) {
    return;
  }

  const batch = db.batch();
  batch.set(userRef, privateData, {merge: true});
  batch.set(userRef.collection("public_profile").doc("current"), publicData, {merge: true});
  await batch.commit();
  console.log(`Hydrated profile data for ${args.userId}.`);
}

function validateHydrateUserArgs(args) {
  if (!args.userId) {
    throw new Error("hydrate-user requires --user <uid>");
  }
  if (args.age == null || args.age < 13 || args.age > 120 || !Number.isInteger(args.age)) {
    throw new Error("hydrate-user requires integer --age from 13 through 120");
  }
  if (!VALID_GENDERS.has(args.gender)) {
    throw new Error("hydrate-user requires --gender woman|man|non_binary|prefer_not_to_say");
  }
  if (args.weightKg == null || args.weightKg <= 0 || args.weightKg > 400) {
    throw new Error("hydrate-user requires --weight-kg or --weight-lb within a sane range");
  }
  if (!args.locationCountry || !/^[A-Z]{2}$/.test(args.locationCountry)) {
    throw new Error("hydrate-user requires --country as an ISO-2 code, e.g. US");
  }
  if (args.locationRegion && !/^[A-Z0-9-]{1,8}$/.test(args.locationRegion)) {
    throw new Error("--region must be 1-8 uppercase letters, numbers, or hyphens");
  }
}

function printHydratePlan(projectId, userId, privateData, publicData, dryRun) {
  const printablePrivate = printableFirestoreData(privateData);
  const printablePublic = printableFirestoreData(publicData);
  console.log(`Project: ${projectId}`);
  console.log(`Command: hydrate-user${dryRun ? " (dry run)" : ""}`);
  console.log(`User: ${userId}`);
  console.log("users/{uid}:");
  console.log(JSON.stringify(printablePrivate, null, 2));
  console.log("users/{uid}/public_profile/current:");
  console.log(JSON.stringify(printablePublic, null, 2));
}

function printableFirestoreData(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => {
    if (value instanceof Timestamp) {
      return [key, value.toDate().toISOString()];
    }
    if (value === SERVER_TIMESTAMP_PREVIEW) {
      return [key, SERVER_TIMESTAMP_PREVIEW];
    }
    if (value && typeof value === "object" && value.constructor?.name === "FieldValue") {
      return [key, SERVER_TIMESTAMP_PREVIEW];
    }
    return [key, value];
  }));
}

function serverTimestampValue(dryRun) {
  return dryRun ? SERVER_TIMESTAMP_PREVIEW : FieldValue.serverTimestamp();
}

function timestampDate(value) {
  if (value && typeof value.toDate === "function") {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  return null;
}

function trimmed(value) {
  if (typeof value !== "string") {
    return null;
  }
  const result = value.trim();
  return result.length > 0 ? result : null;
}

function firstNameFromDisplayName(displayName) {
  return displayName.split(/\s+/)[0] ?? "";
}

function lastNameFromDisplayName(displayName) {
  return displayName.split(/\s+/).slice(1).join(" ");
}

function poundsToKg(value) {
  return Math.round(value * 0.453592 * 10) / 10;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
