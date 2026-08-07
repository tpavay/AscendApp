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
 *   node scripts/dev-db.mjs audit --target all --project staging
 *   node scripts/dev-db.mjs clear --target profiles,leaderboard --project dev
 *   node scripts/dev-db.mjs reset --target all --project dev
 *   node scripts/dev-db.mjs wipe --project dev --confirm-dev-wipe
 *   node scripts/dev-db.mjs wipe --project staging --confirm-staging-wipe
 *   node scripts/dev-db.mjs create-auth-user --project staging --email qa@example.com --display-name "QA Tester"
 *   node scripts/dev-db.mjs hydrate-user --project dev --user <uid> --display-name "Tyler P." --age 27 --gender man --height-in 70 --weight-lb 178 --country US --region IL
 *   node scripts/dev-db.mjs seed-demo-user --project staging --email person@example.com
 */

import {spawnSync} from "node:child_process";
import {randomBytes} from "node:crypto";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {
  DEV_PROJECT_ID,
  STAGING_PROJECT_ID,
  assertSeedableProject,
  resolveProjectId as resolveFirebaseProjectId,
} from "./seed/lib/environments.mjs";
import {
  classifyWipeCollections,
  reviewedWipeCollectionIds,
} from "./lib/firestore-wipe-policy.mjs";
import {
  assertPublishablePublicIdentity,
} from "./seed/lib/public-identity-contract.mjs";

const BATCH_TARGET_ORDER = ["profiles", "leaderboard", "live-replay", "routine-templates"];
const VALID_GENDERS = new Set(["woman", "man", "non_binary", "prefer_not_to_say"]);
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");

const TARGETS = {
  profiles: {
    label: "Profile users, public profiles, profile stats, achievements, public workout summaries",
    script: "seed-test-users.mjs",
  },
  leaderboard: {
    label: "Global leaderboard_stats rows for seeded profile users",
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
let initializedProjectId = null;
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
    confirmStagingWipe: false,
    passthrough: [],
    userId: null,
    password: null,
    passwordEnv: null,
    generatePassword: false,
    useExistingAuthUser: false,
    emailVerified: true,
    hydrateProfile: false,
    seedDemoData: false,
    displayName: null,
    firstName: null,
    lastName: null,
    email: null,
    photoURL: null,
    age: null,
    gender: null,
    weightKg: null,
    heightCm: null,
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
      case "--confirm-staging-wipe":
        args.confirmStagingWipe = true;
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
      case "--password":
        args.password = requireValue(argv, ++index, value);
        break;
      case "--password-env":
        args.passwordEnv = requireValue(argv, ++index, value);
        break;
      case "--generate-password":
      case "--random-password":
        args.generatePassword = true;
        break;
      case "--use-existing":
        args.useExistingAuthUser = true;
        break;
      case "--unverified":
        args.emailVerified = false;
        break;
      case "--email-verified":
        args.emailVerified = true;
        break;
      case "--hydrate-profile":
        args.hydrateProfile = true;
        break;
      case "--seed-demo-data":
        args.seedDemoData = true;
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
        args.photoURL = allowEmptyValue(argv, ++index, value);
        break;
      case "--clear-photo":
        args.photoURL = "";
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
      case "--height-cm":
        args.heightCm = numberValue(requireValue(argv, ++index, value), value);
        break;
      case "--height-in":
        args.heightCm = inchesToCm(numberValue(requireValue(argv, ++index, value), value));
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

// An empty string is a meaningful value for --photo-url: it is how an operator
// publishes no photo, so it has to survive argument parsing.
function allowEmptyValue(argv, index, flag) {
  const value = argv[index];
  if (value === undefined || value.startsWith("--")) {
    throw new Error(`${flag} requires a value, or "" to publish no photo`);
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
  node scripts/dev-db.mjs audit --target all --project staging
  node scripts/dev-db.mjs clear --target profiles,leaderboard --project dev
  node scripts/dev-db.mjs reset --target all --project dev
  node scripts/dev-db.mjs wipe --project dev --confirm-dev-wipe
  node scripts/dev-db.mjs wipe --project staging --confirm-staging-wipe
  node scripts/dev-db.mjs create-auth-user --project staging --email qa@example.com --display-name "QA Tester"
  node scripts/dev-db.mjs hydrate-user --project dev --user <uid> --display-name "Tyler P." --age 27 --gender man --height-in 70 --weight-lb 178 --country US --region IL
  node scripts/dev-db.mjs seed-demo-user --project staging --email person@example.com

Commands:
  plan          Show available targets and examples.
  seed          Seed one or more targets.
  audit         Read-only validation for one or more seeded targets.
  clear         Clear one or more targets.
  reset         Clear then seed one or more targets.
  wipe          Delete reviewed top-level Firestore collections in dev/staging.
  create-auth-user Create one Firebase Auth email/password user in dev/staging.
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
  --confirm-dev-wipe                 Required for a dev wipe without --dry-run.
  --confirm-staging-wipe             Required for a staging wipe without --dry-run.
  --source-user <uid>                Forwarded to live-replay seed.
  --avatar-dir <path>                Forwarded to live-replay seed.
  --seed-pack <id>                   Forwarded to seed targets that support it.
  --file <path>                      Forwarded to routine-templates seed.
  --apple-health-step-factor <n>     Forwarded to live-replay seed.
  --scenario <name>                  Demo user scenario. Defaults to full-showcase.
  --first-ascent-climb <climbId>     Demo First Ascent climb. Defaults in seed script.
  --no-first-ascent                  Demo user seed will not claim a First Ascent.

create-auth-user fields:
  --email <email> [--display-name <name>] [--uid <uid>]
  [--photo-url <url> | --photo-url "" | --clear-photo]
  [--password <password> | --password-env <ENV_NAME> | --generate-password]
  [--use-existing] [--unverified]
  [--hydrate-profile (requires --display-name for a new user) | --seed-demo-data]
  If no password flag is provided, a random password is generated and printed once.

hydrate-user fields:
  --user <uid> --display-name <name> --age <13-120> --gender <woman|man|non_binary|prefer_not_to_say>
  --height-cm <cm> or --height-in <in>
  --weight-kg <kg> or --weight-lb <lb>
  --country <ISO-2> [--region <state/province>] [--joined-at <ISO date>]
  [--email <email>] [--first-name <name>] [--last-name <name>]
  [--photo-url <url> | --photo-url "" | --clear-photo]
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

  if (args.command === "audit") {
    runAuditScript(projectId, args);
    return;
  }

  if (args.command === "wipe") {
    await wipeFirestore(projectId, args);
    return;
  }

  if (args.command === "create-auth-user") {
    await createAuthUser(projectId, args);
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
    throw new Error("Command must be plan, seed, audit, clear, reset, wipe, create-auth-user, hydrate-user, seed-demo-user, or help");
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
  console.log("  node scripts/dev-db.mjs audit --target all --project staging");
  console.log("  node scripts/dev-db.mjs wipe --project dev --confirm-dev-wipe");
  console.log("  node scripts/dev-db.mjs wipe --project staging --confirm-staging-wipe");
  console.log("  node scripts/dev-db.mjs seed --target profiles,live-replay --project dev --dry-run");
  console.log("  node scripts/dev-db.mjs seed --target routine-templates --project dev");
  console.log("  node scripts/dev-db.mjs clear --target leaderboard --project dev");
  console.log("  node scripts/dev-db.mjs create-auth-user --project staging --email qa@example.com --display-name \"QA Tester\"");
  console.log("  node scripts/dev-db.mjs hydrate-user --project dev --user <uid> --display-name \"Tyler P.\" --age 27 --gender man --height-in 70 --weight-lb 178 --country US --region IL");
  console.log("  node scripts/dev-db.mjs seed-demo-user --project staging --email person@example.com");
}

function resolveProjectId(projectOrAlias) {
  return resolveFirebaseProjectId(projectOrAlias, REPO_ROOT);
}

function assertAllowedProject(projectId) {
  assertSeedableProject(projectId);
}

function initializeFirebaseAdmin(projectId) {
  if (initializedProjectId) {
    if (initializedProjectId !== projectId) {
      throw new Error(`Firebase Admin already initialized for ${initializedProjectId}; refusing to reuse it for ${projectId}.`);
    }
    return;
  }

  initializeApp({credential: applicationDefault(), projectId});
  initializedProjectId = projectId;
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
  if (isExplicitPhotoClear(args.photoURL)) {
    scriptArgs.push("--clear-photo");
  } else if (args.photoURL) {
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
  if (args.heightCm != null) {
    scriptArgs.push("--height-cm", String(args.heightCm));
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

function runAuditScript(projectId, args) {
  const scriptArgs = [
    resolve(SCRIPT_DIR, "audit-seed-data.mjs"),
    "--project",
    projectId,
    "--target",
    args.targets.join(","),
  ];

  console.log(`\n> node audit-seed-data.mjs ${scriptArgs.slice(1).join(" ")}`);
  const result = spawnSync(process.execPath, scriptArgs, {
    cwd: SCRIPT_DIR,
    stdio: "inherit",
  });

  if (result.status !== 0) {
    throw new Error(`audit-seed-data.mjs failed with exit code ${result.status}`);
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

async function createAuthUser(projectId, args) {
  validateCreateAuthUserArgs(args);
  const password = resolveCreateAuthPassword(args);

  printCreateAuthUserPlan(projectId, args, password);
  if (args.dryRun) {
    console.log("Dry run only. No Firebase Auth user or Firestore documents were written.");
    return;
  }

  initializeFirebaseAdmin(projectId);
  const auth = getAuth();
  const createRequest = {
    email: args.email,
    password: password.value,
    emailVerified: args.emailVerified,
    disabled: false,
  };
  if (args.userId) {
    createRequest.uid = args.userId;
  }
  if (args.displayName) {
    createRequest.displayName = args.displayName;
  }
  if (args.photoURL) {
    createRequest.photoURL = args.photoURL;
  }

  let userRecord;
  let created = false;
  try {
    userRecord = await auth.createUser(createRequest);
    created = true;
  } catch (error) {
    if (!args.useExistingAuthUser || !isExistingAuthUserError(error)) {
      throw new Error(`Failed to create Firebase Auth user: ${firebaseAuthErrorMessage(error)}`);
    }

    userRecord = await resolveExistingAuthUserForCreate(auth, args, error);
  }

  const action = created ? "Created" : "Using existing";
  console.log(`${action} Firebase Auth user ${userRecord.uid} (${userRecord.email ?? args.email}) in ${projectId}.`);
  if (created && password.generated) {
    console.log(`Generated password: ${password.value}`);
  }

  const childArgs = {
    ...args,
    userId: userRecord.uid,
    email: userRecord.email ?? args.email,
    displayName: args.displayName ?? userRecord.displayName ?? null,
    photoURL: isExplicitPhotoClear(args.photoURL)
      ? ""
      : args.photoURL ?? userRecord.photoURL ?? null,
  };

  if (args.hydrateProfile) {
    await hydrateUser(projectId, childArgs);
  }

  if (args.seedDemoData) {
    runDemoUserScript(projectId, childArgs);
  }
}

function validateCreateAuthUserArgs(args) {
  args.email = trimmed(args.email);
  args.displayName = trimmed(args.displayName);
  args.photoURL = isExplicitPhotoClear(args.photoURL)
    ? ""
    : trimmed(args.photoURL);
  args.password = trimmed(args.password);
  args.passwordEnv = trimmed(args.passwordEnv);

  if (!args.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(args.email)) {
    throw new Error("create-auth-user requires --email <email>");
  }

  const passwordSources = [args.password != null, args.passwordEnv != null, args.generatePassword]
    .filter(Boolean).length;
  if (passwordSources > 1) {
    throw new Error("Use only one password source: --password, --password-env, or --generate-password");
  }

  if (args.password && args.password.length < 6) {
    throw new Error("--password must be at least 6 characters for Firebase Auth");
  }

  if (args.hydrateProfile && args.seedDemoData) {
    throw new Error("Use either --hydrate-profile or --seed-demo-data. Demo seeding already writes profile data.");
  }

  if (args.hydrateProfile) {
    // hydrate-user refuses to invent a public display name, and it runs only after
    // auth.createUser has already succeeded. A brand-new account has no stored
    // displayName to inherit, so without this pre-flight the command leaves an orphaned
    // Auth record with no Firestore user document behind.
    if (!args.displayName && !args.useExistingAuthUser) {
      throw new Error(
        "create-auth-user --hydrate-profile requires --display-name for a new Auth user; " +
        "there is no stored display name to inherit."
      );
    }
    validateHydrateUserArgs({...args, userId: args.userId ?? "new-auth-user"});
  }
}

function resolveCreateAuthPassword(args) {
  if (args.password) {
    return {value: args.password, generated: false, source: "provided via --password"};
  }

  if (args.passwordEnv) {
    const value = trimmed(process.env[args.passwordEnv]);
    if (!value) {
      throw new Error(`--password-env ${args.passwordEnv} is not set or is empty`);
    }
    if (value.length < 6) {
      throw new Error(`--password-env ${args.passwordEnv} must contain at least 6 characters`);
    }
    return {value, generated: false, source: `provided via ${args.passwordEnv}`};
  }

  return {value: randomAuthPassword(), generated: true, source: "generated random password"};
}

function randomAuthPassword() {
  return `${randomBytes(18).toString("base64url")}Aa1!`;
}

function printCreateAuthUserPlan(projectId, args, password) {
  console.log(`Project: ${projectId}`);
  console.log(`Command: create-auth-user${args.dryRun ? " (dry run)" : ""}`);
  console.log(`Email: ${args.email}`);
  console.log(`UID: ${args.userId ?? "(Firebase generated)"}`);
  console.log(`Display name: ${args.displayName ?? "(none)"}`);
  console.log(`Email verified: ${args.emailVerified ? "yes" : "no"}`);
  console.log(`Password: ${password.source}${password.generated ? " (printed only if a new user is created)" : " (not printed)"}`);
  console.log(`Existing user behavior: ${args.useExistingAuthUser ? "reuse matching existing user" : "fail if the email or uid already exists"}`);
  if (args.hydrateProfile) {
    console.log("After create: hydrate profile documents");
  }
  if (args.seedDemoData) {
    console.log("After create: seed product-demo account data");
  }
}

function isExistingAuthUserError(error) {
  return error?.code === "auth/email-already-exists" || error?.code === "auth/uid-already-exists";
}

async function resolveExistingAuthUserForCreate(auth, args, createError) {
  if (createError?.code === "auth/email-already-exists") {
    const existing = await auth.getUserByEmail(args.email);
    if (args.userId && existing.uid !== args.userId) {
      throw new Error(`Firebase Auth email ${args.email} already belongs to uid ${existing.uid}, not requested uid ${args.userId}.`);
    }
    return existing;
  }

  if (createError?.code === "auth/uid-already-exists") {
    const existing = await auth.getUser(args.userId);
    if (existing.email !== args.email) {
      throw new Error(`Firebase Auth uid ${args.userId} already belongs to ${existing.email ?? "(no email)"}, not ${args.email}.`);
    }
    return existing;
  }

  throw createError;
}

function firebaseAuthErrorMessage(error) {
  const code = error?.code ? `${error.code}: ` : "";
  return `${code}${error?.message ?? String(error)}`;
}

async function wipeFirestore(projectId, args) {
  assertWipeConfirmation(projectId, args);

  initializeFirebaseAdmin(projectId);
  const db = getFirestore();
  const existingCollections = await db.listCollections();
  const existingIds = existingCollections.map((collection) => collection.id).sort();
  const plan = classifyWipeCollections(
    existingIds,
    reviewedWipeCollectionIds(REPO_ROOT)
  );
  if (plan.unknownCollections.length > 0) {
    throw new Error(
      "Refusing wipe because Firestore has unreviewed top-level collection(s): " +
        plan.unknownCollections.join(", ")
    );
  }

  console.log(`Project: ${projectId}`);
  console.log(`Command: wipe${args.dryRun ? " (dry run)" : ""}`);
  console.log(
    `Protected: ${plan.protectedCollections.length > 0 ? plan.protectedCollections.join(", ") : "(none)"}`
  );
  console.log(
    `Collections: ${plan.collectionsToDelete.length > 0 ? plan.collectionsToDelete.join(", ") : "(none)"}`
  );

  if (args.dryRun) {
    console.log("Dry run only. No Firestore documents were deleted.");
    return;
  }

  for (const collectionId of plan.collectionsToDelete) {
    console.log(`Deleting ${collectionId} recursively...`);
    await db.recursiveDelete(db.collection(collectionId));
  }

  console.log(`Wiped ${plan.collectionsToDelete.length} top-level collection(s) from ${projectId}.`);
}

function assertWipeConfirmation(projectId, args) {
  assertSeedableProject(projectId, "wipe");
  if (args.confirmDevWipe && args.confirmStagingWipe) {
    throw new Error("wipe accepts exactly one environment-specific confirmation");
  }
  if (args.confirmDevWipe && projectId !== DEV_PROJECT_ID) {
    throw new Error(`--confirm-dev-wipe cannot authorize a wipe of ${projectId}`);
  }
  if (args.confirmStagingWipe && projectId !== STAGING_PROJECT_ID) {
    throw new Error(`--confirm-staging-wipe cannot authorize a wipe of ${projectId}`);
  }
  if (args.dryRun) {
    return;
  }
  if (projectId === DEV_PROJECT_ID && !args.confirmDevWipe) {
    throw new Error("dev wipe requires --confirm-dev-wipe");
  }
  if (projectId === STAGING_PROJECT_ID && !args.confirmStagingWipe) {
    throw new Error("staging wipe requires --confirm-staging-wipe");
  }
}

async function hydrateUser(projectId, args) {
  validateHydrateUserArgs(args);
  initializeFirebaseAdmin(projectId);
  const db = getFirestore();
  const userRef = db.collection("users").doc(args.userId);
  const existingSnapshot = await userRef.get();
  const existing = existingSnapshot.data() ?? {};
  // Never invent a public display name. The app's own fallback for a nameless account is
  // PublicClimberIdentity.systemHandle, a per-uid handle ("Climber A3F9MQ"); a bare
  // "Climber" published here collides across every hydrated account and is indistinguishable
  // from a real name once it reaches a podium. Make the operator supply one instead.
  const displayName = trimmed(args.displayName) ?? trimmed(existing.displayName);
  if (!displayName) {
    throw new Error(
      `hydrate-user: ${args.userId} has no display name to publish. Pass --display-name.`
    );
  }
  const photoURL = resolveHydratePhotoURL(args.photoURL, existing.profilePictureURL);
  assertPublishablePublicIdentity({displayName, photoURL}, "hydrate-user");
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
    height_cm: args.heightCm,
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
    identityPolicyVersion: 1,
    identityChangedAt: serverTimestamp,
    age: args.age,
    gender: args.gender,
    weight_kg: args.weightKg,
    height_cm: args.heightCm,
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
  if (args.heightCm == null || args.heightCm < 90 || args.heightCm > 240) {
    throw new Error("hydrate-user requires --height-cm or --height-in within a sane range");
  }
  if (!args.locationCountry || !/^[A-Z]{2}$/.test(args.locationCountry)) {
    throw new Error("hydrate-user requires --country as an ISO-2 code, e.g. US");
  }
  if (args.locationRegion && !/^[A-Z0-9-]{1,8}$/.test(args.locationRegion)) {
    throw new Error("--region must be 1-8 uppercase letters, numbers, or hyphens");
  }
  assertPublishablePublicIdentity(
    {
      displayName: trimmed(args.displayName),
      photoURL: isExplicitPhotoClear(args.photoURL)
        ? ""
        : trimmed(args.photoURL),
    },
    "hydrate-user"
  );
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

export function isExplicitPhotoClear(value) {
  return typeof value === "string" && value.trim().length === 0;
}

// An explicit --photo-url "" (or --clear-photo) publishes no photo. Anything
// else falls back to the stored value, then to no photo.
export function resolveHydratePhotoURL(argumentValue, storedValue) {
  if (isExplicitPhotoClear(argumentValue)) {
    return "";
  }
  return trimmed(argumentValue) ?? trimmed(storedValue) ?? "";
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

function inchesToCm(value) {
  return Math.round(value * 2.54 * 10) / 10;
}

if (resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
