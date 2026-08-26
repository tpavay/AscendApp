#!/usr/bin/env node

/**
 * Demo User Seed Script
 *
 * Seeds one real Firebase Auth user in dev/staging with product-demo data:
 * private workout backups, profile summaries, achievements, global standings,
 * and Live Replay leaderboard rows for climbs/routines.
 *
 * The tester must sign in to the target Firebase environment first. This script
 * looks up the existing Auth user by email or uid; it does not create accounts.
 *
 * Usage:
 *   node scripts/seed-demo-user.mjs seed --project staging --email person@example.com
 *   node scripts/seed-demo-user.mjs seed --project dev --user <uid> --display-name "Product Tester"
 *   node scripts/seed-demo-user.mjs seed --project staging --email person@example.com --dry-run
 *   node scripts/seed-demo-user.mjs clear --project staging --email person@example.com
 */

import {createHash, randomUUID} from "node:crypto";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getStorage} from "firebase-admin/storage";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {createBatchWriter, createProgressReporter} from "./lib/firestore-bulk.mjs";
import {
  canonicalWorkoutDocumentId,
  seededReplayCompletedCount,
  staleWorkoutDocumentIds,
} from "./lib/workout-document-id.mjs";
import {currentPeriod, utcDate} from "./lib/leaderboard-period.mjs";
import {
  PUBLIC_IDENTITY_STATE_PUBLISHED,
  clearedFirstAscentFields,
  firstAscentInvariantFailure,
  firstAscentSeedFields,
} from "./seed/lib/live-replay-first-ascent.mjs";
import {buildDemoReplayEntry} from "./seed/lib/demo-replay-entry.mjs";
import {
  REPLAY_SUMMARY_SOURCE_LIVE,
} from "./seed/lib/live-replay-summary-source.mjs";
import {contestedClimbIds} from "./seed/lib/live-replay-climb-tiers.mjs";
import {defaultSeedPackId} from "./seed/lib/environments.mjs";
import {
  reservedAccountAvatar,
  seedAvatarPrefix,
} from "./seed/lib/seed-avatar-allocation.mjs";
import {isAllowedPublicPhotoURL} from "./seed/lib/public-identity-contract.mjs";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const PRODUCTION_PROJECT_ID = "ascend-prod-9c8f2";
const ALLOWED_PROJECT_IDS = new Set([DEV_PROJECT_ID, STAGING_PROJECT_ID]);
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const CATALOG_PATH = resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json");

const BATCH_LIMIT = 400;
const WORKOUT_SCHEMA_VERSION = 1;
const LEADERBOARD_SCHEMA_VERSION = 2;
const REPLAY_SCHEMA_VERSION = 1;
const STEPS_PER_FLOOR = 16;
const SPLIT_INTERVAL_SECONDS = 10;
const DEFAULT_SCENARIO = "full-showcase";

/**
 * The climb this account holds the First Ascent on.
 *
 * It has to be a climb no synthetic competitor has finished. The server claims a
 * slot only for a finisher on a board with no completions, so a holder written
 * onto a contested board claims nothing - it just overwrites the seed pack's
 * holder with an account seated behind dozens of climbers, on the one screen
 * whose entire claim is "first ever".
 *
 * So the holder's climb sits outside `seed-live-replay-leaderboards.mjs`'s
 * contested lists, on a board that pack seeds open. This account is then
 * genuinely the only finisher the board has ever had. `validateArgs` enforces
 * that rather than trusting this comment.
 */
const DEFAULT_FIRST_ASCENT_CLIMB_ID = "875-north-michigan-avenue";

const TIME_FRAMES = ["daily", "weekly", "monthly", "yearly", "all_time"];
const SPM_BY_LEVEL = [
  24, 31, 38, 45, 52,
  59, 66, 73, 80, 86,
  93, 100, 107, 114, 121,
  128, 134, 141, 148, 155,
  162, 169, 176, 183, 190,
];

const ROUTINE_TEMPLATES = [
  {
    id: "tylers-10-min-heater",
    name: "Tyler's 10 Min Heater",
    durationSeconds: 600,
    intervals: [
      {durationSeconds: 150, level: 14},
      {durationSeconds: 60, level: 20},
      {durationSeconds: 90, level: 12},
      {durationSeconds: 60, level: 20},
      {durationSeconds: 90, level: 12},
      {durationSeconds: 60, level: 20},
      {durationSeconds: 90, level: 12},
    ],
    daysAgo: 1,
    stepsOffset: 36,
  },
  {
    id: "challenge_10_8_4",
    name: "Quick Climb",
    durationSeconds: 600,
    intervals: [
      {durationSeconds: 60, level: 7},
      {durationSeconds: 480, level: 8},
      {durationSeconds: 60, level: 7},
    ],
    daysAgo: 3,
    stepsOffset: 22,
  },
  {
    id: "social-pyramid-20",
    name: "Social Pyramid 20",
    durationSeconds: 1200,
    intervals: [
      {durationSeconds: 120, level: 6},
      {durationSeconds: 120, level: 8},
      {durationSeconds: 120, level: 10},
      {durationSeconds: 120, level: 12},
      {durationSeconds: 120, level: 14},
      {durationSeconds: 120, level: 16},
      {durationSeconds: 120, level: 14},
      {durationSeconds: 120, level: 12},
      {durationSeconds: 120, level: 10},
      {durationSeconds: 120, level: 8},
    ],
    daysAgo: 6,
    stepsOffset: 74,
  },
];

const LIVE_CLIMB_SPECS = [
  {climbId: "empire-state-building", daysAgo: 0, spm: 94, finisherOrder: 1},
  {climbId: DEFAULT_FIRST_ASCENT_CLIMB_ID, daysAgo: 2, spm: 92, finisherOrder: 1},
  {climbId: "taipei-101", daysAgo: 4, spm: 89, finisherOrder: 7},
  {climbId: "burj-khalifa", daysAgo: 9, spm: 101, finisherOrder: 18},
  {climbId: "eiffel-tower", daysAgo: 14, spm: 84, finisherOrder: 12},
  {climbId: "space-needle", daysAgo: 19, spm: 96, finisherOrder: 3},
  {climbId: "statue-of-liberty", daysAgo: 27, spm: 88, finisherOrder: 1},
];

// Non-climb sessions, here so Best Efforts and history have depth behind the
// landmark races. Both are `headphone_motion`: #437 deleted manual entry and
// Apple Health workout import on 2026-08-08, so seeding a `manual` or
// `apple_health` row would put a workout in the demo account that the app can
// no longer produce.
const EXTRA_WORKOUT_SPECS = [
  {
    key: "record-20-min",
    name: "20 Minute Stair Push",
    daysAgo: 35,
    durationSeconds: 1200,
    steps: 1927,
    source: "headphone_motion",
    integrityLevel: "verified",
    notes: "Demo session for best-effort depth.",
  },
  {
    key: "long-climb",
    name: "Long Stair Climb",
    daysAgo: 42,
    durationSeconds: 4820,
    steps: 6120,
    source: "headphone_motion",
    integrityLevel: "verified",
    notes: "Demo session for history depth.",
  },
];

function parseArgs(argv) {
  const args = {
    command: argv[2] ?? "help",
    project: "dev",
    dryRun: false,
    userId: null,
    email: null,
    displayName: null,
    photoURL: null,
    age: 32,
    gender: "prefer_not_to_say",
    weightKg: 81.6,
    heightCm: 178,
    locationCountry: "US",
    locationRegion: null,
    joinedAt: null,
    scenario: DEFAULT_SCENARIO,
    seedFirstAscent: true,
    firstAscentClimbId: DEFAULT_FIRST_ASCENT_CLIMB_ID,
  };

  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--project":
        args.project = requireValue(argv, ++index, value);
        break;
      case "--user":
      case "--uid":
        args.userId = requireValue(argv, ++index, value);
        break;
      case "--email":
        args.email = requireValue(argv, ++index, value);
        break;
      case "--display-name":
        args.displayName = requireValue(argv, ++index, value);
        break;
      case "--photo-url":
        args.photoURL = requireValue(argv, ++index, value);
        break;
      case "--age":
        args.age = integerValue(requireValue(argv, ++index, value), value);
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
      case "--dry-run":
        args.dryRun = true;
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

function printHelp() {
  console.log(`
Usage:
  node scripts/seed-demo-user.mjs seed --project staging --email person@example.com
  node scripts/seed-demo-user.mjs seed --project dev --user <uid> --display-name "Product Tester"
  node scripts/seed-demo-user.mjs seed --project staging --email person@example.com --dry-run
  node scripts/seed-demo-user.mjs clear --project staging --email person@example.com

Commands:
  seed   Write this scenario's data onto one existing dev/staging account.
  clear  Take the same documents back out. Account identity and any climb
         performed in the app are left alone; delete those in the app, which is
         the only thing that also removes the device's local copy.

Options:
  --project <dev|staging|projectId>  Defaults to dev. Production is refused.
  --email <email>                    Existing Firebase Auth email to seed.
  --user <uid>                       Existing Firebase Auth uid to seed.
  --display-name <name>              Overrides Auth display name/email fallback.
  --photo-url <url>                  Optional profile photo URL.
  --age <13-120>                     Defaults to 32.
  --gender <value>                   woman|man|non_binary|prefer_not_to_say.
  --weight-kg <kg> or --weight-lb <lb>
  --height-cm <cm> or --height-in <in>
  --country <ISO-2> [--region <code>]
  --joined-at <ISO date>
  --scenario <full-showcase>         Currently only full-showcase is supported.
  --first-ascent-climb <climbId>     Defaults to ${DEFAULT_FIRST_ASCENT_CLIMB_ID}.
  --no-first-ascent                  Do not assign a First Ascent in replay summaries.
  --dry-run                          Print the write plan without writing.
`);
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.command === "help" || args.command === "--help" || args.command === "-h") {
    printHelp();
    return;
  }

  if (!["seed", "clear"].includes(args.command)) {
    throw new Error("Command must be seed, clear, or help");
  }

  validateArgs(args);

  const projectId = resolveProjectId(args.project);
  assertAllowedProject(projectId);

  initializeApp({
    credential: applicationDefault(),
    projectId,
    storageBucket: `${projectId}.firebasestorage.app`,
  });
  const auth = getAuth();
  const db = getFirestore();
  const authUser = await resolveAuthUser(auth, args);
  const catalog = loadCatalog();

  if (args.command === "clear") {
    await runClear(db, catalog, authUser, args, projectId);
    return;
  }

  const accountPhotoURL = args.dryRun ?
    null :
    await ensureAccountPhoto(authUser, args, projectId);
  const seedPlan = await buildSeedPlan(db, catalog, authUser, {
    ...args,
    photoURL: args.photoURL ?? accountPhotoURL,
  });

  printPlan(projectId, seedPlan, args);

  if (args.dryRun) {
    console.log("Dry run only. No Firestore writes were made.");
    return;
  }

  await commitDeletes(db, seedPlan.deletes);
  await commitWrites(db, seedPlan.writes);
  console.log(
    `Seeded demo account ${seedPlan.user.uid} with ` +
      `${seedPlan.workouts.length} workouts, ` +
      `${seedPlan.liveContexts.length} replay context(s), and ` +
      `${seedPlan.leaderboardRowCount} leaderboard stat rows.`
  );
}

function validateArgs(args) {
  if (!args.email && !args.userId) {
    throw new Error("seed-demo-user requires --email <email> or --user <uid>");
  }
  if (args.scenario !== DEFAULT_SCENARIO) {
    throw new Error(`Unsupported scenario "${args.scenario}". Use ${DEFAULT_SCENARIO}.`);
  }
  if (args.age < 13 || args.age > 120) {
    throw new Error("--age must be from 13 through 120");
  }
  if (!["woman", "man", "non_binary", "prefer_not_to_say"].includes(args.gender)) {
    throw new Error("--gender must be woman|man|non_binary|prefer_not_to_say");
  }
  if (!Number.isFinite(args.weightKg) || args.weightKg <= 0 || args.weightKg > 400) {
    throw new Error("--weight-kg/--weight-lb must be within a sane range");
  }
  if (!Number.isFinite(args.heightCm) || args.heightCm < 90 || args.heightCm > 240) {
    throw new Error("--height-cm/--height-in must be within a sane range");
  }
  if (!/^[A-Z]{2}$/.test(args.locationCountry)) {
    throw new Error("--country must be an ISO-2 code, e.g. US");
  }
  if (args.locationRegion && !/^[A-Z0-9-]{1,8}$/.test(args.locationRegion)) {
    throw new Error("--region must be 1-8 uppercase letters, numbers, or hyphens");
  }
  if (args.seedFirstAscent && !LIVE_CLIMB_SPECS.some((spec) => spec.climbId === args.firstAscentClimbId)) {
    throw new Error(
      `--first-ascent-climb must be one of the seeded climb IDs: ${LIVE_CLIMB_SPECS.map((spec) => spec.climbId).join(", ")}`
    );
  }
  // The live replay pack fills these boards with finishers, and the server lets
  // only an unheld slot on an empty board be claimed. Writing a holder onto one
  // anyway claims nothing and renders as first-ever beside a full field.
  if (args.seedFirstAscent && contestedClimbIds().has(args.firstAscentClimbId)) {
    throw new Error(
      `--first-ascent-climb ${args.firstAscentClimbId} is contested by the live ` +
      "replay seed pack, so its First Ascent is already spent. Pick a climb the " +
      "pack leaves open, or pass --no-first-ascent."
    );
  }
}

async function resolveAuthUser(auth, args) {
  try {
    if (args.userId) {
      return await auth.getUser(args.userId);
    }
    return await auth.getUserByEmail(args.email);
  } catch (error) {
    const lookup = args.userId ? `uid ${args.userId}` : `email ${args.email}`;
    throw new Error(
      `No Firebase Auth user found for ${lookup}. Have the tester sign into this environment once, then rerun.`
    );
  }
}

async function buildSeedPlan(db, catalog, authUser, args) {
  const now = new Date();
  const user = userSnapshot(authUser, args);
  const joinedAt = args.joinedAt ?? new Date(now.getTime() - 46 * 24 * 60 * 60 * 1000);
  const writes = [];
  const deletes = [];
  const liveContexts = [];
  const workouts = [];
  const userRef = db.collection("users").doc(user.uid);
  const existingUserSnapshot = await userRef.get();
  const existingUser = existingUserSnapshot.data() ?? {};

  const privateProfile = privateProfileData(user, args, joinedAt, Boolean(existingUser.createdAt));
  const publicProfile = publicProfileData(user, args, joinedAt);
  writes.push([userRef, privateProfile]);
  writes.push([userRef.collection("public_profile").doc("current"), publicProfile]);

  const fixture = fixtureSessions(user, catalog, now);
  workouts.push(...fixture.workouts);
  liveContexts.push(...fixture.liveContexts);

  const stats = statsFor(workouts, args.seedFirstAscent ? 1 : 0);
  writes.push([
    db.collection("users").doc(user.uid).collection("profile_stats").doc("current"),
    profileStatsData(stats),
  ]);

  for (const workout of workouts) {
    const profileWorkoutsRef = db.collection("users").doc(user.uid).collection("profile_workouts");
    writes.push([profileWorkoutsRef.doc(workout.id), profileWorkoutData(workout)]);
    for (const staleId of staleWorkoutDocumentIds(workout.id)) {
      deletes.push(profileWorkoutsRef.doc(staleId));
    }
  }

  const firstAscentClaim = args.seedFirstAscent ?
    firstAscentClaimFor(args.firstAscentClimbId, liveContexts) :
    null;
  for (const achievement of achievementRecords(user.uid, now, firstAscentClaim)) {
    writes.push([
      db.collection("users").doc(user.uid).collection("achievements").doc(achievement.id),
      achievement,
    ]);
  }

  let leaderboardRowCount = 0;
  for (const timeFrame of TIME_FRAMES) {
    const totals = leaderboardTotals(workouts, timeFrame);
    const period = currentPeriod(timeFrame, now);
    const statsRef = db
      .collection("leaderboard_stats")
      .doc(leaderboardDocId(user.uid, timeFrame, period.key));
    // The server derivation publishes no row for a period with no eligible
    // workouts and removes any it finds, so seeding one here would be undone on
    // the next trigger.
    if (totals.totalWorkouts === 0) {
      deletes.push(statsRef);
      continue;
    }
    writes.push([statsRef, leaderboardStatsData(user, timeFrame, period, totals)]);
    leaderboardRowCount += 1;
  }

  await addReplayWrites(db, writes, deletes, user, liveContexts, args);
  await addCommunityStatsWrites(db, writes, user, liveContexts);

  for (const workout of workouts) {
    const workoutsRef = db.collection("users").doc(user.uid).collection("workouts");
    writes.push([workoutsRef.doc(workout.id), workout.document]);
    for (const staleId of staleWorkoutDocumentIds(workout.id)) {
      deletes.push(workoutsRef.doc(staleId));
    }
  }

  return {
    user,
    writes,
    deletes,
    workouts,
    liveContexts,
    stats,
    leaderboardRowCount,
  };
}

/**
 * Makes sure the account has a real profile photograph, and returns its URL.
 *
 * This account is the one every screenshot is centered on, so an empty photo is a
 * grey circle in the middle of the shot. It is also the one row on a seeded
 * board that a person actually owns, so its picture has to live under its own
 * `users/{uid}/profile_pictures/` prefix rather than pointing at the shared
 * avatar tree - user media never lives on a shared root path.
 *
 * An account that already has a *publishable* photo keeps it: a real climber's
 * own picture is not the fixture's to replace. Otherwise the seed copies the
 * avatar reserved for it out of this pack's set, so the face is real, belongs to
 * no competitor on the same leaderboard, and stays the same across re-seeds.
 *
 * "Publishable" is load-bearing and is why this used to fail. A Google or Apple
 * sign-in leaves a provider avatar on the Auth record - `lh3.googleusercontent.com`
 * for the account this was run against - and the identity contract only accepts a
 * Firebase Storage download URL. Handing that one straight through published a
 * photo the projection then dropped, so the one account every screenshot centers
 * on rendered as a grey circle while the seed reported success. A URL the server
 * will not project is the same as no photo, so it takes the reserved avatar
 * instead.
 * @param {object} authUser Resolved Firebase Auth user.
 * @param {object} args Parsed CLI arguments.
 * @param {string} projectId Target Firebase project.
 * @return {Promise<string | null>} Published photo URL, or null when none exists.
 */
async function ensureAccountPhoto(authUser, args, projectId) {
  const requested = trimmed(args.photoURL);
  if (requested) {
    if (!isAllowedPublicPhotoURL(requested)) {
      throw new Error(
        `--photo-url ${requested} is not a Firebase Storage download URL, so the ` +
        "identity projection would drop it and the account would render as an " +
        "empty circle."
      );
    }
    return requested;
  }

  const existing = trimmed(authUser.photoURL);
  if (existing && isAllowedPublicPhotoURL(existing)) {
    return existing;
  }
  if (existing) {
    console.log(
      `Ignoring the provider photo on this Auth record (${new URL(existing).host}): ` +
      "the identity contract only publishes Firebase Storage download URLs. " +
      "Using this pack's reserved avatar instead."
    );
  }

  const bucket = getStorage().bucket();
  const seedPackId = defaultSeedPackId("live-replay", projectId);
  const prefix = seedAvatarPrefix(seedPackId);
  const [files] = await bucket.getFiles({prefix});
  const source = reservedAccountAvatar(
    files.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name))
  );

  if (!source) {
    console.warn(
      `No avatar images under ${prefix}, so this account will publish no photo ` +
      "and render as a grey circle. Pass --photo-url, or seed the live replay " +
      "pack with --avatar-dir once."
    );
    return null;
  }

  const destination = `users/${authUser.uid}/profile_pictures/${seedPackId}.jpg`;
  const token = randomUUID();
  await source.copy(bucket.file(destination), {
    metadata: {
      cacheControl: "public,max-age=31536000,immutable",
      contentType: "image/jpeg",
      metadata: {firebaseStorageDownloadTokens: token},
    },
  });

  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
    `${encodeURIComponent(destination)}?alt=media&token=${token}`;
}

/**
 * Every session this scenario seeds, and the replay contexts they land on.
 *
 * Seeding and clearing have to name the identical set of documents, so both
 * derive it here rather than each listing the fixture themselves. Every id is a
 * hash of the account and the fixture entity, never of the run, so a clear
 * addresses exactly what an earlier seed wrote.
 * @param {object} user Resolved demo account snapshot.
 * @param {Map<string, object>} catalog Climb catalog by id.
 * @param {Date} now Run clock, which dates the sessions but not their ids.
 * @return {object} Seeded workouts and their replay contexts.
 */
function fixtureSessions(user, catalog, now) {
  const workouts = [];
  const liveContexts = [];

  for (const spec of LIVE_CLIMB_SPECS) {
    const climb = requiredClimb(catalog, spec.climbId);
    const workout = liveClimbWorkout(user, climb, spec, now);
    workouts.push(workout);
    liveContexts.push(liveContextForWorkout(workout));
  }

  for (const template of ROUTINE_TEMPLATES) {
    const workout = routineTemplateWorkout(user, template, now);
    workouts.push(workout);
    liveContexts.push(liveContextForWorkout(workout));
  }

  for (const spec of EXTRA_WORKOUT_SPECS) {
    workouts.push(extraWorkout(user, spec, now));
  }

  return {workouts, liveContexts};
}

/**
 * Takes this scenario's documents back out of one account.
 * @param {object} db Firestore instance.
 * @param {Map<string, object>} catalog Climb catalog by id.
 * @param {object} authUser Resolved Firebase Auth user.
 * @param {object} args Parsed CLI arguments.
 * @param {string} projectId Target Firebase project.
 */
async function runClear(db, catalog, authUser, args, projectId) {
  const clearPlan = await buildClearPlan(db, catalog, authUser, args);
  printClearPlan(projectId, clearPlan, args);

  if (args.dryRun) {
    console.log("Dry run only. No Firestore writes were made.");
    return;
  }

  await commitDeletes(db, clearPlan.deletes);
  await commitWrites(db, clearPlan.writes);
  console.log(
    `Cleared demo data for ${clearPlan.user.uid}: ` +
      `${clearPlan.deletes.length} documents deleted, ` +
      `${clearPlan.writes.length} shared summaries repaired.`
  );
}

/**
 * Builds the deletes that undo this scenario, plus the repairs the documents it
 * shares with other climbers need afterwards.
 *
 * Only what the seed wrote. The account's identity stays, because it belongs to
 * the person signed in rather than to the fixture. A climb performed in the app
 * stays too: the device holds its own SwiftData copy, so only the app's own
 * delete removes both, and a server-side delete would strand the local one.
 * @param {object} db Firestore instance.
 * @param {Map<string, object>} catalog Climb catalog by id.
 * @param {object} authUser Resolved Firebase Auth user.
 * @param {object} args Parsed CLI arguments.
 * @return {Promise<object>} Clear plan.
 */
async function buildClearPlan(db, catalog, authUser, args) {
  const user = userSnapshot(authUser, args);
  const userRef = db.collection("users").doc(user.uid);
  const {workouts, liveContexts} = fixtureSessions(user, catalog, new Date());
  const deletes = [];
  const writes = [];

  for (const workout of workouts) {
    // `liveClimbPublishStatuses` is written by the publish trigger rather than
    // by the seed, but it is keyed by the same workout id and describes a climb
    // that is about to stop existing.
    for (const collection of [
      "workouts",
      "profile_workouts",
      "liveClimbPublishStatuses",
    ]) {
      const ref = userRef.collection(collection);
      deletes.push(ref.doc(workout.id));
      for (const staleId of staleWorkoutDocumentIds(workout.id)) {
        deletes.push(ref.doc(staleId));
      }
    }
  }

  deletes.push(userRef.collection("profile_stats").doc("current"));

  for (const achievement of achievementRecords(
    user.uid,
    new Date(),
    firstAscentClaimFor(args.firstAscentClimbId, liveContexts)
  )) {
    deletes.push(userRef.collection("achievements").doc(achievement.id));
  }

  // Queried rather than derived: a standing's id carries the period it was
  // seeded for, so a clear run in a later week cannot name the rows an earlier
  // run wrote. The server derivation would drop them once the workouts are gone,
  // but a reset has to leave a known state immediately.
  const standings = await db
    .collection("leaderboard_stats")
    .where("userId", "==", user.uid)
    .get();
  for (const standing of standings.docs) {
    deletes.push(standing.ref);
  }

  const repairedContexts = await addReplayClearWrites(
    db,
    writes,
    deletes,
    user,
    liveContexts
  );

  // Deliberately untouched: `live_climb_community_stats`. The
  // `onWorkoutReplaySplitsWritten` trigger reconciles that counter
  // transactionally against whether the account still has a completed climb, and
  // deleting the workouts above is the signal it reads. Subtracting here as well
  // would race the trigger for the same decrement.
  return {user, workouts, liveContexts, repairedContexts, deletes, writes};
}

/**
 * Removes this account from every replay board the scenario put it on.
 *
 * A summary is shared with the synthetic competitors, so it is repaired rather
 * than deleted: `completedCount` drops back to the climbers still standing on
 * the board. Where this account holds the First Ascent, the holder fields go
 * with its completion - a slot with a holder and no completions is one of the
 * two states the app can never produce or leave.
 * @param {object} db Firestore instance.
 * @param {Array} writes Accumulated writes.
 * @param {Array} deletes Accumulated deletes.
 * @param {object} user Resolved demo account snapshot.
 * @param {object[]} liveContexts Seeded replay contexts.
 * @return {Promise<object[]>} Per-context repair descriptions.
 */
async function addReplayClearWrites(db, writes, deletes, user, liveContexts) {
  const repaired = [];

  for (const context of liveContexts) {
    const contextKey = replayContextKey(context.contextType, context.contextId);
    const leaderboardRef = db.collection("live_replay_leaderboards").doc(contextKey);
    const [summarySnapshot, bucketZeroSnapshot] = await Promise.all([
      leaderboardRef.get(),
      leaderboardRef.collection("splitBuckets").doc("0").collection("entries").get(),
    ]);

    const removedIds = new Set([
      context.workoutId,
      ...staleWorkoutDocumentIds(context.workoutId),
    ]);
    const remainingCount = bucketZeroSnapshot.docs
      .filter((document) => !removedIds.has(document.id)).length;
    const holdsFirstAscent =
      summarySnapshot.data()?.firstAscentUserId === user.uid;

    // Releasing the holder is only safe when this account's completion was the
    // board's last one. The shared module already defines what an unreachable
    // First Ascent state is, so the clear asks it rather than restating it.
    const releaseFailure = holdsFirstAscent ?
      firstAscentInvariantFailure({
        climbId: contextKey,
        completedCount: remainingCount,
        hasFirstAscent: false,
      }) :
      null;
    if (releaseFailure) {
      throw new Error(
        `${releaseFailure} Re-seed the live replay pack for this climb instead, ` +
        "which gives the board a holder again."
      );
    }

    deletes.push(leaderboardRef.collection("finishers").doc(user.uid));
    deletes.push(leaderboardRef.collection("userBestAttempts").doc(user.uid));
    deletes.push(
      leaderboardRef.collection("completionSnapshots").doc(context.workoutId)
    );
    for (let index = 0; index < context.splitSteps.length; index += 1) {
      const entriesRef = leaderboardRef
        .collection("splitBuckets").doc(String(index)).collection("entries");
      for (const entryId of removedIds) {
        deletes.push(entriesRef.doc(entryId));
      }
    }

    const summaryWrite = {
      completedCount: remainingCount,
      totalClimbers: remainingCount,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (holdsFirstAscent) {
      Object.assign(summaryWrite, clearedFirstAscentFields(FieldValue.delete()));
    }

    writes.push([leaderboardRef, summaryWrite]);
    repaired.push({
      contextKey,
      completedCount: remainingCount,
      firstAscentReleased: holdsFirstAscent,
    });
  }

  return repaired;
}

/**
 * Document ids an earlier seed run wrote for the same fixture entity before ids were
 * canonicalized to uppercase. Re-seeding must remove them or every consumer keyed by
 * document id keeps a ghost row alongside the canonical one.
 * @param {string} canonicalId Uppercase canonical UUID document id.
 * @return {string[]} Stale ids to delete, empty when none can exist.
 */
function staleDocumentIds(canonicalId) {
  return [canonicalId.toLowerCase()].filter((id) => id !== canonicalId);
}

/**
 * A believable human name for an account that has not supplied one.
 *
 * This name is published to public leaderboards, so it is what a screenshot
 * shows. "Product Tester" was the old fallback and no climber is called that.
 * Deliberately outside `SEEDED_DISPLAY_NAMES` so the account never collides with
 * a synthetic competitor on the same board.
 */
const FALLBACK_DEMO_DISPLAY_NAME = "Morgan Hale";

function userSnapshot(authUser, args) {
  // No email-derived name. An address local part is an identifier, not a name -
  // deriving one published "Content Capture" and "Qa G4 Noname" onto leaderboards
  // that exist to be photographed. Synthetic rows are told apart by isSynthetic,
  // source and seedPackId, so nothing needs the display name to carry a marker.
  const displayName =
    trimmed(args.displayName) ??
    trimmed(authUser.displayName) ??
    FALLBACK_DEMO_DISPLAY_NAME;

  if (!trimmed(args.displayName) && !trimmed(authUser.displayName)) {
    console.warn(
      `This account has no display name, so it will be published as ` +
      `"${FALLBACK_DEMO_DISPLAY_NAME}". Pass --display-name to choose one.`
    );
  }

  // Same rule as `ensureAccountPhoto`: a provider URL the projection would drop
  // is not a photo. `args.photoURL` is the resolved one by this point.
  const resolved = trimmed(args.photoURL) ?? trimmed(authUser.photoURL) ?? "";
  const photoURL = isAllowedPublicPhotoURL(resolved) ? resolved : "";

  return {
    uid: authUser.uid,
    email: authUser.email ?? args.email ?? "",
    displayName,
    photoURL,
    avatarToken: avatarToken(displayName),
  };
}

function privateProfileData(user, args, joinedAt, hasExistingCreatedAt) {
  const displayParts = user.displayName.split(/\s+/);
  const data = {
    email: user.email,
    firstName: displayParts[0] ?? "",
    lastName: displayParts.slice(1).join(" "),
    displayName: user.displayName,
    profilePictureURL: user.photoURL,
    age: args.age,
    gender: args.gender,
    weight_kg: roundTo(args.weightKg, 1),
    height_cm: roundTo(args.heightCm, 1),
    location_country: args.locationCountry,
    joined_at: Timestamp.fromDate(joinedAt),
    lastUpdated: FieldValue.serverTimestamp(),
  };

  if (args.locationRegion) {
    data.location_region = args.locationRegion;
  }

  if (!hasExistingCreatedAt) {
    data.createdAt = FieldValue.serverTimestamp();
  }
  return data;
}

function publicProfileData(user, args, joinedAt) {
  const data = {
    userId: user.uid,
    displayName: user.displayName,
    photoURL: user.photoURL,
    identityPolicyVersion: 1,
    identityChangedAt: FieldValue.serverTimestamp(),
    age: args.age,
    gender: args.gender,
    weight_kg: roundTo(args.weightKg, 1),
    height_cm: roundTo(args.heightCm, 1),
    location_country: args.locationCountry,
    joined_at: Timestamp.fromDate(joinedAt),
    lastUpdated: FieldValue.serverTimestamp(),
  };

  if (args.locationRegion) {
    data.location_region = args.locationRegion;
  }

  return data;
}

function liveClimbWorkout(user, climb, spec, now) {
  const steps = climbSteps(climb);
  const durationSeconds = Math.max(300, Math.round((steps / spec.spm) * 60));
  const startedAt = daysAgo(now, spec.daysAgo);
  const id = deterministicUUID(`${user.uid}:${DEFAULT_SCENARIO}:climb:${climb.id}`);
  const attemptId = deterministicUUID(`${user.uid}:${DEFAULT_SCENARIO}:attempt:${climb.id}`);
  const splitSteps = splitCurve(steps, durationSeconds, `${id}:curve`);
  const sourceMetadata = JSON.stringify({
    algorithmVersion: 1,
    climbId: climb.id,
    climbTargetStepCount: steps,
    sampleCount: Math.round(durationSeconds * 50),
    sampleRateAssumptionHz: 50,
    source: "headphone_motion",
    splitIntervalSeconds: SPLIT_INTERVAL_SECONDS,
    splitSteps,
    stopReason: "target_reached",
    targetStepCount: steps,
    trackingMode: "live_climb",
  });

  return workoutRecord({
    user,
    id,
    name: `${climb.name} Live Climb`,
    startedAt,
    durationSeconds,
    steps,
    source: "headphone_motion",
    integrityLevel: "verified",
    notes: "Demo Live Climb completion.",
    sourceMetadata,
    climb,
    replay: {
      contextType: "live_climb",
      contextId: climb.id,
      targetSteps: steps,
      splitSteps,
      finisherOrder: spec.finisherOrder,
    },
    participations: [
      participationRecord({
        user,
        workoutId: id,
        participationId: deterministicUUID(`${id}:participation:climb`),
        contextType: "climb_attempt",
        contextId: attemptId,
        leaderboardEligible: true,
        verificationTier: "sensor_verified",
        startedAt,
        durationSeconds,
        steps,
      }),
    ],
  });
}

function routineTemplateWorkout(user, template, now) {
  const targetSteps = routineTargetSteps(template);
  const steps = targetSteps + template.stepsOffset;
  const durationSeconds = template.durationSeconds;
  const startedAt = daysAgo(now, template.daysAgo);
  const id = deterministicUUID(`${user.uid}:${DEFAULT_SCENARIO}:routine:${template.id}`);
  const splitSteps = splitCurve(steps, durationSeconds, `${id}:curve`);
  const sourceMetadata = JSON.stringify({
    algorithmVersion: 1,
    climbId: null,
    climbTargetStepCount: null,
    sampleCount: Math.round(durationSeconds * 50),
    sampleRateAssumptionHz: 50,
    source: "headphone_motion",
    splitIntervalSeconds: SPLIT_INTERVAL_SECONDS,
    splitSteps,
    stopReason: "target_reached",
    targetStepCount: targetSteps,
    trackingMode: "just_climb",
  });

  return workoutRecord({
    user,
    id,
    name: `${template.name} Routine`,
    startedAt,
    durationSeconds,
    steps,
    source: "headphone_motion",
    integrityLevel: "verified",
    notes: "Demo routine completion.",
    sourceMetadata,
    replay: {
      contextType: "routine_template",
      contextId: template.id,
      targetSteps,
      splitSteps,
      finisherOrder: template.id === "tylers-10-min-heater" ? 2 : 5,
    },
    participations: [
      participationRecord({
        user,
        workoutId: id,
        participationId: deterministicUUID(`${id}:participation:routine-template`),
        contextType: "routine_template",
        contextId: template.id,
        leaderboardEligible: true,
        verificationTier: "sensor_verified",
        startedAt,
        durationSeconds,
        steps,
      }),
    ],
  });
}

function extraWorkout(user, spec, now) {
  const id = deterministicUUID(`${user.uid}:${DEFAULT_SCENARIO}:extra:${spec.key}`);
  const startedAt = daysAgo(now, spec.daysAgo);

  return workoutRecord({
    user,
    id,
    name: spec.name,
    startedAt,
    durationSeconds: spec.durationSeconds,
    steps: spec.steps,
    source: spec.source,
    integrityLevel: spec.integrityLevel,
    notes: spec.notes,
    sourceMetadata: null,
    participations: [],
  });
}

function workoutRecord(input) {
  const floors = Math.max(1, Math.round(input.steps / STEPS_PER_FLOOR));
  const updatedAt = new Date(input.startedAt.getTime() + Math.min(input.durationSeconds * 1000, 45 * 60 * 1000));
  const document = {
    userId: input.user.uid,
    schemaVersion: WORKOUT_SCHEMA_VERSION,
    name: input.name,
    startedAt: Timestamp.fromDate(input.startedAt),
    durationSeconds: input.durationSeconds,
    steps: input.steps,
    floors,
    stepsPerFloor: STEPS_PER_FLOOR,
    notes: input.notes,
    source: input.source,
    integrityLevel: input.integrityLevel,
    createdAt: Timestamp.fromDate(input.startedAt),
    updatedAt: Timestamp.fromDate(updatedAt),
    avgHeartRateBpm: averageHeartRate(input.steps, input.durationSeconds),
    maxHeartRateBpm: averageHeartRate(input.steps, input.durationSeconds) + 24,
    caloriesBurned: Math.round(input.durationSeconds / 60 * 8.4),
    effortRating: 4.5,
    averageMETs: 8.2,
    deviceModel: "Ascend Demo Seed",
    participations: input.participations,
  };

  if (input.sourceMetadata) {
    document.sourceMetadata = input.sourceMetadata;
  }

  return {
    id: input.id,
    name: input.name,
    startedAt: input.startedAt,
    durationSeconds: input.durationSeconds,
    steps: input.steps,
    floors,
    source: input.source,
    climb: input.climb ?? null,
    replay: input.replay ?? null,
    document,
  };
}

function participationRecord(input) {
  const floors = Math.max(1, Math.round(input.steps / STEPS_PER_FLOOR));
  const spm = stepsPerMinute(input.steps, input.durationSeconds);
  return {
    id: input.participationId,
    workoutId: input.workoutId,
    userId: input.user.uid,
    contextType: input.contextType,
    contextId: input.contextId,
    contextVersion: 1,
    rulesVersion: 1,
    role: "primary",
    leaderboardEligible: input.leaderboardEligible,
    verificationTier: input.verificationTier,
    metricsSnapshot: {
      startedAt: Timestamp.fromDate(input.startedAt),
      durationSeconds: input.durationSeconds,
      steps: input.steps,
      floors,
      stepsPerMinute: spm,
    },
    createdAt: Timestamp.fromDate(input.startedAt),
  };
}

async function addReplayWrites(db, writes, deletes, user, liveContexts, args) {
  for (const context of liveContexts) {
    const contextKey = replayContextKey(context.contextType, context.contextId);
    const leaderboardRef = db.collection("live_replay_leaderboards").doc(contextKey);
    const finisherRef = leaderboardRef.collection("finishers").doc(user.uid);
    const bucketZeroEntriesRef = leaderboardRef.collection("splitBuckets").doc("0").collection("entries");
    const [finisherSnapshot, bucketZeroSnapshot] = await Promise.all([
      finisherRef.get(),
      bucketZeroEntriesRef.get(),
    ]);
    const staleEntryIds = staleWorkoutDocumentIds(context.workoutId);
    const completedCount = seededReplayCompletedCount(
      bucketZeroSnapshot.docs.map((document) => document.id),
      context.workoutId
    );
    const existingFinisher = finisherSnapshot.exists;
    const existingFinisherOrder = nonNegativeInteger(
      finisherSnapshot.data()?.globalCompletionOrder
    );
    const finisherOrder = existingFinisher && existingFinisherOrder && existingFinisherOrder <= completedCount ?
      existingFinisherOrder :
      completedCount;
    const forceFirstAscent = args.seedFirstAscent &&
      context.contextType === "live_climb" &&
      context.contextId === args.firstAscentClimbId;

    const summaryData = {
      bucketIntervalSeconds: SPLIT_INTERVAL_SECONDS,
      completedCount,
      contextId: context.contextId,
      contextType: context.contextType,
      schemaVersion: REPLAY_SCHEMA_VERSION,
      // A real signed-in account, so this board has stopped being purely seeded
      // whatever synthetic rows still sit on it. `replaySummaryWrite` in the
      // Cloud Function stamps the same value on every publish.
      source: REPLAY_SUMMARY_SOURCE_LIVE,
      targetStepCount: context.targetSteps,
      totalClimbers: completedCount,
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (forceFirstAscent) {
      Object.assign(summaryData, firstAscentSeedFields(
        {
          avatarToken: user.avatarToken,
          displayName: user.displayName,
          id: context.workoutId,
          photoURL: user.photoURL,
          userId: user.uid,
        },
        Timestamp.fromDate(context.completedAt),
        {isSynthetic: false}
      ));
    }

    writes.push([leaderboardRef, summaryData]);
    writes.push([
      finisherRef,
      {
        avatarToken: user.avatarToken,
        bestCompletionDurationSeconds: context.durationSeconds,
        bestWorkoutId: context.workoutId,
        displayName: user.displayName,
        firstCompletedAt: Timestamp.fromDate(context.completedAt),
        firstWorkoutId: context.workoutId,
        globalCompletionOrder: finisherOrder,
        identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
        isSynthetic: false,
        photoURL: user.photoURL,
        schemaVersion: REPLAY_SCHEMA_VERSION,
        updatedAt: FieldValue.serverTimestamp(),
        userId: user.uid,
      },
    ]);
    writes.push([
      leaderboardRef.collection("userBestAttempts").doc(user.uid),
      {
        completedAt: Timestamp.fromDate(context.completedAt),
        completionDurationSeconds: context.durationSeconds,
        schemaVersion: REPLAY_SCHEMA_VERSION,
        updatedAt: FieldValue.serverTimestamp(),
        workoutId: context.workoutId,
      },
    ]);

    for (let index = 0; index < context.splitSteps.length; index += 1) {
      const entriesRef = leaderboardRef.collection("splitBuckets").doc(String(index)).collection("entries");
      for (const staleEntryId of staleEntryIds) {
        deletes.push(entriesRef.doc(staleEntryId));
      }
      writes.push([
        entriesRef.doc(context.workoutId),
        buildDemoReplayEntry({
          context,
          identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
          schemaVersion: REPLAY_SCHEMA_VERSION,
          splitIndex: index,
          splitIntervalSeconds: SPLIT_INTERVAL_SECONDS,
          updatedAt: FieldValue.serverTimestamp(),
          user,
        }),
      ]);
    }
  }
}

async function addCommunityStatsWrites(db, writes, user, liveContexts) {
  const hasLiveClimb = liveContexts.some((context) => context.contextType === "live_climb");
  if (!hasLiveClimb) {
    return;
  }

  const statsRef = db.collection("live_climb_community_stats").doc("global");
  const completedUserRef = statsRef.collection("completedUsers").doc(user.uid);
  const completedUserSnapshot = await completedUserRef.get();
  writes.push([
    completedUserRef,
    {
      ...(completedUserSnapshot.exists ? {} : {firstCompletedAt: FieldValue.serverTimestamp()}),
      schemaVersion: REPLAY_SCHEMA_VERSION,
      updatedAt: FieldValue.serverTimestamp(),
      userId: user.uid,
    },
  ]);
  const statsData = {
    schemaVersion: REPLAY_SCHEMA_VERSION,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!completedUserSnapshot.exists) {
    statsData.uniqueCompletedUserCount = FieldValue.increment(1);
  }
  writes.push([statsRef, statsData]);
}

function liveContextForWorkout(workout) {
  return {
    contextType: workout.replay.contextType,
    contextId: workout.replay.contextId,
    targetSteps: workout.replay.targetSteps,
    splitSteps: workout.replay.splitSteps,
    finisherOrder: workout.replay.finisherOrder,
    finalSteps: workout.steps,
    durationSeconds: workout.durationSeconds,
    startedAt: workout.startedAt,
    completedAt: new Date(workout.startedAt.getTime() + workout.durationSeconds * 1000),
    workoutId: workout.id,
  };
}

function profileWorkoutData(workout) {
  const data = {
    name: workout.name,
    startedAt: Timestamp.fromDate(workout.startedAt),
    durationSeconds: workout.durationSeconds,
    steps: workout.steps,
    source: workout.source,
    lastUpdated: FieldValue.serverTimestamp(),
  };

  if (workout.climb) {
    data.climbId = workout.climb.id;
    data.climbTier = workout.climb.tier ?? "common";
    data.climbCompletionStatus = "completed";
    data.climbCompletionDurationSeconds = Math.round(workout.durationSeconds);
  }

  return data;
}

function statsFor(workouts, firstAscentCount) {
  const climbWorkouts = workouts.filter((workout) => workout.climb);
  const maxSteps = Math.max(0, ...workouts.map((workout) => workout.steps));
  const maxDuration = Math.max(0, ...workouts.map((workout) => workout.durationSeconds));
  const maxSPM = Math.max(0, ...workouts.map((workout) => stepsPerMinute(workout.steps, workout.durationSeconds)));
  const lifetimeTotalSteps = workouts.reduce((sum, workout) => sum + workout.steps, 0);
  const lifetimeDurationSeconds = Math.round(workouts.reduce((sum, workout) => sum + workout.durationSeconds, 0));

  return {
    totalClimbsCompleted: climbWorkouts.length,
    totalFirstAscents: firstAscentCount,
    lifetimeTotalSteps,
    lifetimeDurationSeconds,
    totalClimbs: workouts.length,
    averageStepsPerMinute: lifetimeDurationSeconds > 0 ? lifetimeTotalSteps / (lifetimeDurationSeconds / 60) : 0,
    top1: 2,
    top3: 4,
    top10: 7,
    top100: 12,
    mostCompletedClimbId: climbWorkouts[0]?.climb?.id ?? "",
    currentStreakWeeks: 4,
    bestStreakWeeks: 7,
    prMostSteps: maxSteps,
    prLongestClimbSeconds: Math.round(maxDuration),
    prHighestSPM: maxSPM,
  };
}

function profileStatsData(stats) {
  return {
    total_climbs_completed: stats.totalClimbsCompleted,
    total_first_ascents: stats.totalFirstAscents,
    lifetime_total_steps: stats.lifetimeTotalSteps,
    lifetime_duration_seconds: stats.lifetimeDurationSeconds,
    total_climbs: stats.totalClimbs,
    average_steps_per_minute: stats.averageStepsPerMinute,
    top_1_finishes: stats.top1,
    top_3_finishes: stats.top3,
    top_10_finishes: stats.top10,
    top_100_finishes: stats.top100,
    most_completed_climb_id: stats.mostCompletedClimbId,
    current_streak_weeks: stats.currentStreakWeeks,
    best_streak_weeks: stats.bestStreakWeeks,
    pr_most_steps: stats.prMostSteps,
    pr_longest_climb_seconds: stats.prLongestClimbSeconds,
    pr_highest_spm: stats.prHighestSPM,
    lastUpdated: FieldValue.serverTimestamp(),
  };
}

/**
 * The seeded completion that claims the First Ascent, or null when none does.
 *
 * The achievement has to be dated from the climb that earned it. Stamping it
 * "today" while the climb it names was seeded days ago put two dates on one
 * event, on the profile surface whose whole job is to be a record.
 * @param {string} firstAscentClimbId Climb this account claims.
 * @param {object[]} liveContexts Seeded replay contexts.
 * @return {object | null} Claim climb id and completion date.
 */
function firstAscentClaimFor(firstAscentClimbId, liveContexts) {
  const context = liveContexts.find(
    (candidate) => candidate.contextType === "live_climb" &&
      candidate.contextId === firstAscentClimbId
  );

  return context ?
    {climbId: firstAscentClimbId, completedAt: context.completedAt} :
    null;
}

function achievementRecords(uid, now, firstAscentClaim) {
  const records = [
    achievement(uid, "weekly_top_1", "2026-W22", 1, daysAgo(now, 2)),
    achievement(uid, "weekly_top_1", "2026-W21", 1, daysAgo(now, 9)),
    achievement(uid, "monthly_top_3", "2026-M05", 2, daysAgo(now, 13)),
    achievement(uid, "weekly_top_3", "2026-W20", 3, daysAgo(now, 16)),
    achievement(uid, "weekly_top_10", "2026-W19", 7, daysAgo(now, 24)),
    achievement(uid, "monthly_top_10", "2026-M04", 8, daysAgo(now, 32)),
    achievement(uid, "yearly_top_100", "2026", 38, daysAgo(now, 40)),
  ];

  if (firstAscentClaim) {
    records.unshift({
      id: deterministicId(`${uid}:achievement:first_ascent:${firstAscentClaim.climbId}`),
      type: "first_ascent",
      scope: "climb",
      climbId: firstAscentClaim.climbId,
      earnedAt: Timestamp.fromDate(firstAscentClaim.completedAt),
      rank: 1,
    });
  }

  return records;
}

function achievement(uid, type, periodKey, rank, earnedAt) {
  const period = achievementPeriod(type, periodKey, earnedAt);
  return {
    id: deterministicId(`${uid}:achievement:${type}:${periodKey}`),
    type,
    scope: "global",
    metric: "steps",
    value: Math.max(1200, 54000 - rank * 950),
    valueUnit: "steps",
    periodKey,
    periodStartAt: Timestamp.fromDate(period.startAt),
    periodEndAt: Timestamp.fromDate(period.endAt),
    earnedAt: Timestamp.fromDate(earnedAt),
    rank,
  };
}

function achievementPeriod(type, periodKey, earnedAt) {
  if (type.startsWith("monthly_")) {
    const [year, month] = periodKey.split("-M").map((value) => Number(value));
    return {
      startAt: utcDate(year, month - 1, 1),
      endAt: utcDate(year, month, 1),
    };
  }

  if (type.startsWith("yearly_")) {
    const year = Number(periodKey);
    return {
      startAt: utcDate(year, 0, 1),
      endAt: utcDate(year + 1, 0, 1),
    };
  }

  return {
    startAt: daysAgo(earnedAt, 7),
    endAt: earnedAt,
  };
}

// Mirrors aggregateForPeriod in functions/src/leaderboardStats.ts. The demo user
// has real seeded workouts, so the server derivation owns this row and rebuilds
// it from them on the next trigger. Any total this seed asserts that those
// workouts do not support - the step floors this used to apply - survives only
// until then, and a seeded standing its own evidence contradicts is exactly the
// shape issue #307 exists to stop.
function leaderboardTotals(workouts, timeFrame) {
  const now = new Date();
  const period = currentPeriod(timeFrame, now);
  const included = timeFrame === "all_time"
    ? workouts
    : workouts.filter((workout) => workout.startedAt >= period.startAt);

  const totalSteps = included.reduce((sum, workout) => sum + workout.steps, 0);
  const totalFloors = included.reduce((sum, workout) => sum + workout.floors, 0);
  const totalWorkouts = included.length;
  const totalDuration = included.reduce((sum, workout) => sum + workout.durationSeconds, 0);
  const minutes = totalDuration / 60;

  return {
    totalSteps,
    totalFloors,
    totalWorkouts,
    totalDuration,
    stepsPerMinute: minutes > 0 ? totalSteps / minutes : 0,
  };
}

function leaderboardStatsData(user, timeFrame, period, totals) {
  return {
    userId: user.uid,
    displayName: user.displayName,
    photoURL: user.photoURL,
    identityPolicyVersion: 1,
    identityChangedAt: FieldValue.serverTimestamp(),
    identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
    timeFrame,
    schemaVersion: LEADERBOARD_SCHEMA_VERSION,
    periodKey: period.key,
    periodStartAt: Timestamp.fromDate(period.startAt),
    totalSteps: totals.totalSteps,
    totalFloors: totals.totalFloors,
    totalWorkouts: totals.totalWorkouts,
    totalDuration: totals.totalDuration,
    stepsPerMinute: totals.stepsPerMinute,
    lastUpdated: FieldValue.serverTimestamp(),
  };
}

function leaderboardDocId(userId, timeFrame, periodKey) {
  return `${timeFrame}_${periodKey}_${userId}`;
}

function loadCatalog() {
  const raw = JSON.parse(readFileSync(CATALOG_PATH, "utf-8"));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

function requiredClimb(catalog, climbId) {
  const climb = catalog.get(climbId);
  if (!climb) {
    throw new Error(`Missing climb "${climbId}" in ${CATALOG_PATH}`);
  }
  return climb;
}

function climbSteps(climb) {
  return climb.realStairCount ?? climb.totalSteps ?? climb.referenceStepCount ?? 1000;
}

function routineTargetSteps(template) {
  return Math.max(
    1,
    Math.round(
      template.intervals.reduce((sum, interval) => {
        return sum + spmForLevel(interval.level) * (interval.durationSeconds / 60);
      }, 0)
    )
  );
}

function splitCurve(finalSteps, durationSeconds, seed) {
  const finalBucketIndex = Math.max(Math.ceil(durationSeconds / SPLIT_INTERVAL_SECONDS), 1);
  const seedValue = parseInt(createHash("sha256").update(seed).digest("hex").slice(0, 8), 16);
  const steps = [];
  let last = 0;

  for (let index = 0; index <= finalBucketIndex; index += 1) {
    const elapsedSeconds = Math.min(index * SPLIT_INTERVAL_SECONDS, durationSeconds);
    const progress = Math.min(Math.max(elapsedSeconds / durationSeconds, 0), 1);
    const wave = Math.sin(index * 0.7 + seedValue) * 0.025;
    const eased = Math.pow(progress, 0.985) + wave * progress * (1 - progress);
    const value = index === finalBucketIndex
      ? finalSteps
      : Math.round(finalSteps * Math.min(Math.max(eased, 0), 1));
    last = Math.max(last, value);
    steps.push(Math.min(last, finalSteps));
  }

  steps[0] = 0;
  steps[steps.length - 1] = finalSteps;
  return steps;
}

function replayContextKey(contextType, contextId) {
  return `${contextType}__${String(contextId).replace(/[^A-Za-z0-9_-]/g, "_")}`;
}

function spmForLevel(level) {
  return SPM_BY_LEVEL[Math.min(Math.max(level, 1), SPM_BY_LEVEL.length) - 1];
}

function averageHeartRate(steps, durationSeconds) {
  const spm = stepsPerMinute(steps, durationSeconds);
  return Math.round(Math.min(Math.max(118 + (spm - 80) * 0.55, 112), 168));
}

function stepsPerMinute(steps, durationSeconds) {
  if (durationSeconds <= 0) {
    return 0;
  }
  return roundTo(steps / (durationSeconds / 60), 1);
}

function daysAgo(now, count) {
  return new Date(now.getTime() - count * 24 * 60 * 60 * 1000);
}

function avatarToken(displayName) {
  const initials = displayName
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
  return initials || "A";
}

function deterministicUUID(input) {
  const hex = createHash("sha256").update(input).digest("hex");
  const variant = ((parseInt(hex.slice(16, 18), 16) & 0x3f) | 0x80).toString(16).padStart(2, "0");
  return canonicalWorkoutDocumentId([
    hex.slice(0, 8),
    hex.slice(8, 12),
    `4${hex.slice(13, 16)}`,
    `${variant}${hex.slice(18, 20)}`,
    hex.slice(20, 32),
  ].join("-"));
}

function deterministicId(input) {
  return createHash("sha256").update(input).digest("hex").slice(0, 24);
}

async function commitDeletes(db, deletes) {
  const progress = createProgressReporter({label: "Account (clear)", total: deletes.length});
  const writer = createBatchWriter(db, {progress});
  for (const ref of deletes) {
    writer.delete(ref);
  }
  await writer.drain();
  progress.finish();
}

async function commitWrites(db, writes) {
  const progress = createProgressReporter({label: "Account", total: writes.length});
  const writer = createBatchWriter(db, {progress});
  for (const [ref, data] of writes) {
    writer.set(ref, data, {merge: true});
  }
  await writer.drain();
  progress.finish();
}

function printPlan(projectId, seedPlan, args) {
  const preview = {
    project: projectId,
    command: `seed-demo-user${args.dryRun ? " (dry run)" : ""}`,
    user: {
      uid: seedPlan.user.uid,
      email: seedPlan.user.email,
      displayName: seedPlan.user.displayName,
    },
    scenario: args.scenario,
    workouts: seedPlan.workouts.length,
    liveReplayContexts: seedPlan.liveContexts.length,
    writes: seedPlan.writes.length,
    staleCaseVariantDeletes: seedPlan.deletes.length,
    firstAscentClimb: args.seedFirstAscent ? args.firstAscentClimbId : null,
    totalClimbsCompleted: seedPlan.stats.totalClimbsCompleted,
  };
  console.log(JSON.stringify(preview, null, 2));
}

function printClearPlan(projectId, clearPlan, args) {
  console.log(JSON.stringify({
    project: projectId,
    command: `seed-demo-user clear${args.dryRun ? " (dry run)" : ""}`,
    user: {
      uid: clearPlan.user.uid,
      email: clearPlan.user.email,
      displayName: clearPlan.user.displayName,
    },
    workouts: clearPlan.workouts.length,
    documentDeletes: clearPlan.deletes.length,
    repairedContexts: clearPlan.repairedContexts,
    preserved: [
      "users/{uid} identity and demographics",
      "users/{uid}/public_profile/current",
      "climbs performed in the app (delete those in the app)",
      "live_climb_community_stats (the publish trigger reconciles it)",
    ],
  }, null, 2));
}

function resolveProjectId(projectOrAlias) {
  const rc = JSON.parse(readFileSync(resolve(REPO_ROOT, ".firebaserc"), "utf-8"));
  return rc.projects?.[projectOrAlias] ?? projectOrAlias;
}

function assertAllowedProject(projectId) {
  if (projectId === PRODUCTION_PROJECT_ID || !ALLOWED_PROJECT_IDS.has(projectId)) {
    throw new Error(
      `Refusing to seed ${projectId}. This script only writes ${DEV_PROJECT_ID} or ${STAGING_PROJECT_ID}.`
    );
  }
}

function nonNegativeInteger(value) {
  if (Number.isInteger(value) && value >= 0) {
    return value;
  }
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
    return Math.floor(value);
  }
  return null;
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

function integerValue(value, flag) {
  const parsed = numberValue(value, flag);
  if (!Number.isInteger(parsed)) {
    throw new Error(`${flag} must be an integer`);
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

function trimmed(value) {
  if (typeof value !== "string") {
    return null;
  }
  const result = value.trim();
  return result.length > 0 ? result : null;
}

function poundsToKg(value) {
  return roundTo(value * 0.453592, 1);
}

function inchesToCm(value) {
  return roundTo(value * 2.54, 1);
}

function roundTo(value, places) {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
