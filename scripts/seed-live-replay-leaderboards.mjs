#!/usr/bin/env node

/**
 * Live Replay Leaderboard Seed Script
 *
 * Seeds or clears dev/staging replay leaderboard data for Live Climbs using the
 * Firebase Admin SDK. The script writes the read-only public replay indexes:
 *
 * live_replay_leaderboards/{contextKey}/splitBuckets/{bucketIndex}/entries/{entryId}
 * live_replay_leaderboards/{contextKey}/finishers/{userId}
 *
 * The seed pack writes per-climb Live Climb contexts and the open-ended global
 * Just Climb context used by live tracked sessions without a climb target.
 *
 * Usage:
 *   ASCEND_SEED_SOURCE_USER_ID=<uid> node scripts/seed-live-replay-leaderboards.mjs seed --project dev
 *   ASCEND_SEED_SOURCE_USER_ID=<uid> npm --prefix scripts run seed:live-replay
 *   node scripts/seed-live-replay-leaderboards.mjs seed --project dev --dry-run
 *   node scripts/seed-live-replay-leaderboards.mjs seed --project staging --dry-run
 *   node scripts/seed-live-replay-leaderboards.mjs backfill-avatars --project dev --avatar-dir ~/Downloads/avatars
 *   node scripts/seed-live-replay-leaderboards.mjs clear --project dev
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login
 */

import {createHash, randomUUID} from "node:crypto";
import {readFileSync, readdirSync, statSync} from "node:fs";
import {dirname, extname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {
  appendAll,
  createBatchWriter,
  createProgressReporter,
  listDocumentsAcross,
  runPool,
  withRetry,
} from "./lib/firestore-bulk.mjs";
import {hashString, mulberry32} from "./seed/lib/deterministic.mjs";
import {
  FIRST_ASCENT_OPEN_ACTIVITY_TIER,
  PUBLIC_IDENTITY_STATE_PUBLISHED,
  assertFirstAscentInvariant,
  clearedFirstAscentFields,
  firstAscentClaimedAt,
  firstAscentSeedFields,
  isOpenFirstAscentSummary,
} from "./seed/lib/live-replay-first-ascent.mjs";
import {
  syntheticFinisherWrite,
} from "./seed/lib/live-replay-finisher.mjs";
import {
  isSyntheticUserId,
  seededSummarySource,
} from "./seed/lib/live-replay-summary-source.mjs";
import {
  competitorAvatars,
  seedAvatarPrefix,
} from "./seed/lib/seed-avatar-allocation.mjs";
import {
  ACTIVE_CLIMBS,
  WARM_CLIMBS,
  contestedClimbIds,
  firstAscentOpenConfigs,
} from "./seed/lib/live-replay-climb-tiers.mjs";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const JUST_CLIMB_CONTEXT_TYPE = "just_climb";
const ROUTINE_TEMPLATE_CONTEXT_TYPE = "routine_template";
const JUST_CLIMB_GLOBAL_CONTEXT_ID = "global";
const DEFAULT_DEV_SEED_PACK_ID = "live-replay-v1-dev";
const DEFAULT_STAGING_SEED_PACK_ID = "live-replay-v1-staging";
const DEFAULT_APPLE_HEALTH_STEP_FACTOR = 0.78;
const BUCKET_INTERVAL_SECONDS = 10;
const MAX_BUCKET_INDEX = 360;
const ALLOWED_SEED_PROJECTS = new Map([
  [DEV_PROJECT_ID, {defaultSeedPackId: DEFAULT_DEV_SEED_PACK_ID}],
  [STAGING_PROJECT_ID, {defaultSeedPackId: DEFAULT_STAGING_SEED_PACK_ID}],
]);

/**
 * The hash of the rows a board holds, and how many buckets they span.
 *
 * Written on the summary after the rows land, so the next run can tell a board
 * that already holds exactly what it would write from one that does not, and
 * skip it. This is what makes a repeat seed seconds rather than minutes.
 */
const SEED_FINGERPRINT_FIELD = "seedRowFingerprint";
const SEED_BUCKET_COUNT_FIELD = "seedBucketCount";

/**
 * Bumped by hand when the *shape* of a seeded document changes in a way the
 * fingerprint's inputs do not already cover - a new field, a renamed one, a
 * changed constant. The step values are hashed directly, so the maths behind
 * them needs no bump.
 */
const SEED_WRITE_REVISION = 3;

/** Replay contexts enumerated at once. Each fans out again over its own buckets. */
const CONTEXT_CONCURRENCY = 12;
/** Parallel listings within one context. */
const READ_CONCURRENCY = 64;
/** Coprime-ish stride that scatters one climber's buckets away from the next climber's. */
const BUCKET_STRIPE_STEP = 137;

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");

/**
 * The synthetic climbers' names, one per hosted avatar image.
 *
 * Length is load-bearing twice over. `displayNameForAttempt` falls back to
 * "Climber 061" past the end of this list, so a board with more finishers than
 * there are names puts a machine-readable placeholder on a leaderboard somebody
 * is about to photograph - Empire State Building carried 23 of them. And
 * `avatarURLForDisplayName` indexes the avatar set by a name's position here, so
 * a name past the last uploaded image gets no photo and renders as initials.
 *
 * So this stays the same length as the competitor avatar pool - every uploaded
 * image except the one reserved for the account being seeded - and no climb
 * seeds more finishers than that. `assertSeededIdentitySupply` enforces both,
 * because the failure is invisible until it is on a screenshot.
 *
 * Full names, not "Sarah K.", and that is what the product actually publishes.
 * `SuppliedNameAdoption` takes whatever Sign in with Apple or Google hands over,
 * which is a given name and a family name, so every real leaderboard row carries
 * a full name. Abbreviated fixtures read as fixtures next to one - which is what
 * a podium showed when "Tyler R." stood beside the account's own "Tyler Pavay".
 * Order is load-bearing: a climber's face is resolved by position in this list,
 * so names may be rewritten in place but not reordered.
 */
const SEEDED_DISPLAY_NAMES = [
  "Sarah Keller", "Marcus Tate", "Jenny Whitfield", "Alex Mercado", "Priya Sundaram", "Jordan Leclair",
  "Nina Rasmussen", "Owen Brannigan", "Maya Castellanos", "Eli Pruitt", "Sam Doherty", "Taylor Hargrove",
  "Ari Nakamura", "Chris Valdez", "Riley Faulkner", "Noah Gallagher", "Ava Montrose", "Leo Sandoval",
  "Mia Larkin", "Ben Castillo", "Ivy Redmond", "Theo Janssen", "Lena Petrova", "Kai Whitlock",
  "Nora Bergstrom", "Cole Ashford", "Zara Thibault", "Miles Kowalski", "Eva Delgado", "Jules Renaud",
  "Drew Sorensen", "Iris Mendoza", "Cal Nakashima", "Tessa Vandenberg", "Remy Pichon", "Sage Lindqvist",
  "Quinn Ellery", "Omar Haddad", "Gia Ferraro", "Finn Rourke", "Ana Cabrera", "Max Weatherby",
  "Ruby Nightingale", "Jace Mullins", "Elle Kavanagh", "Sean Prescott", "Vera Lindholm", "Hugo Trevino",
  "Luca Sartori", "Mila Brennan", "Nate Ridgeway", "Lia Pastore", "Ezra Kaufman", "June Vasquez",
  "Rae Cormier", "Ty Donnelly", "Skye Marchetti", "Amir Nazari", "Hope Jamison", "Kira Wallace",
  "Dana Okonkwo", "Pablo Guerrero", "Yuki Tanabe", "Marta Lindgren", "Isaac Barlow", "Freya Nilsen",
  "Andre Perrault", "Sofia Ricci", "Ravi Menon", "Clara Vogel", "Emeka Obiora", "Anya Dragomir",
  "Tobias Hoffmann", "Nadia Farouk", "Liam Callahan", "Rosa Escobar", "Kenji Arakawa", "Greta Sundberg",
  "Malik Johannsen", "Ines Batista", "Oscar Wexler", "Talia Kirkland",
];

function parseArgs(argv) {
  const args = {
    command: argv[2] ?? "help",
    project: "dev",
    dryRun: false,
    // A full clear before the write is now opt-in: the write replaces rows in
    // place under derived ids, so clearing first only costs a second pass.
    // `--skip-clear` is still accepted, and now describes the default.
    clearFirst: false,
    force: false,
    seedPackId: null,
    sourceUserId: process.env.ASCEND_SEED_SOURCE_USER_ID ?? null,
    avatarDir: null,
    appleHealthStepFactor: DEFAULT_APPLE_HEALTH_STEP_FACTOR,
  };

  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--project":
        args.project = requireValue(argv, ++index, "--project");
        break;
      case "--source-user":
        args.sourceUserId = requireValue(argv, ++index, "--source-user");
        break;
      case "--avatar-dir":
        args.avatarDir = resolve(requireValue(argv, ++index, "--avatar-dir"));
        break;
      case "--seed-pack":
        args.seedPackId = requireValue(argv, ++index, "--seed-pack");
        break;
      case "--apple-health-step-factor":
        args.appleHealthStepFactor = Number(requireValue(argv, ++index, value));
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--skip-clear":
        break;
      case "--clear-first":
        args.clearFirst = true;
        break;
      case "--force":
        args.force = true;
        break;
      case "--help":
      case "-h":
        args.command = "help";
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  if (!Number.isFinite(args.appleHealthStepFactor) ||
      args.appleHealthStepFactor <= 0 ||
      args.appleHealthStepFactor > 1.2) {
    throw new Error("--apple-health-step-factor must be a number between 0 and 1.2");
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

function printHelp() {
  console.log(`
Usage:
  ASCEND_SEED_SOURCE_USER_ID=<uid> node scripts/seed-live-replay-leaderboards.mjs seed --project dev
  ASCEND_SEED_SOURCE_USER_ID=<uid> npm --prefix scripts run seed:live-replay
  node scripts/seed-live-replay-leaderboards.mjs seed --project dev --dry-run
  node scripts/seed-live-replay-leaderboards.mjs seed --project staging --dry-run
  node scripts/seed-live-replay-leaderboards.mjs backfill-avatars --project dev --avatar-dir ~/Downloads/avatars
  node scripts/seed-live-replay-leaderboards.mjs clear --project dev

Options:
  --project <alias|projectId>           Firebase project alias or ID. Must resolve to ${DEV_PROJECT_ID} or ${STAGING_PROJECT_ID}.
  --source-user <uid>                   User whose workout backups provide pace calibration.
  --avatar-dir <path>                   Optional curated avatar images to upload and assign to seeded names.
  --seed-pack <id>                      Seed pack marker. Defaults by project: ${DEFAULT_DEV_SEED_PACK_ID}, ${DEFAULT_STAGING_SEED_PACK_ID}.
  --apple-health-step-factor <number>   Calibration for Apple Health steps. Default: ${DEFAULT_APPLE_HEALTH_STEP_FACTOR}.
  --dry-run                             Print the plan without writing.
  --clear-first                         Delete every row this pack owns before writing. Rarely needed:
                                        the write replaces rows in place and deletes what it has retired.
  --skip-clear                          Accepted and ignored. Describes the default.
  --force                               Rewrite every board even when it already holds this pack's rows.
`);
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.command === "help") {
    printHelp();
    return;
  }

  if (!["seed", "clear", "backfill-avatars"].includes(args.command)) {
    throw new Error("Command must be seed, clear, backfill-avatars, or help");
  }

  const projectId = resolveProjectId(args.project);
  const projectConfig = ALLOWED_SEED_PROJECTS.get(projectId);
  if (!projectConfig) {
    throw new Error(
      `Refusing to seed ${projectId}. This script only writes ${DEV_PROJECT_ID} or ${STAGING_PROJECT_ID}.`
    );
  }
  args.seedPackId = args.seedPackId ?? projectConfig.defaultSeedPackId;

  initializeApp({
    credential: applicationDefault(),
    projectId,
    storageBucket: `${projectId}.firebasestorage.app`,
  });

  const db = getFirestore();
  const avatarFiles = args.avatarDir ? loadAvatarFiles(args.avatarDir) : [];
  const avatarURLs = ["seed", "backfill-avatars"].includes(args.command) &&
      !args.dryRun
    ? await resolveSeedAvatarURLs(avatarFiles, args)
    : [];

  if (args.command === "backfill-avatars") {
    if (!args.avatarDir) {
      throw new Error("backfill-avatars requires --avatar-dir");
    }

    console.log(`Project: ${projectId}`);
    console.log(`Seed pack: ${args.seedPackId}`);
    console.log(`Avatars: ${avatarFiles.length} files${args.dryRun ? "" : `, ${avatarURLs.length} uploaded`}`);
    console.log(`Mode: backfill-avatars${args.dryRun ? " (dry run)" : ""}`);

    if (args.dryRun) {
      console.log("Dry run only. No Storage uploads or Firestore writes were made.");
      return;
    }

    const result = await backfillSeedAvatarURLs(db, args, avatarURLs);
    console.log(
      `Backfilled ${result.updated.toLocaleString()} of ` +
        `${result.scanned.toLocaleString()} seeded replay entry documents.`
    );
    return;
  }

  const climbs = loadClimbCatalog();
  const paceSamples = args.command === "seed"
    ? await loadPaceSamples(db, args)
    : [];
  const seedPlan = buildSeedPlan(climbs, paceSamples, args, avatarURLs);

  printPlan(seedPlan, args, avatarFiles.length, avatarURLs.length);

  if (args.dryRun) {
    console.log("Dry run only. No Firestore writes were made.");
    return;
  }

  const startedAt = Date.now();

  // Resolved once, before anything is deleted, and honored by both the clear
  // and the write.
  const claimedOpen = await claimedOpenClimbIds(db, seedPlan);
  if (claimedOpen.size > 0) {
    console.log(
      `Leaving ${claimedOpen.size} open climb(s) untouched - a real climber has ` +
      `finished them: ${[...claimedOpen].join(", ")}`
    );
  }

  if (args.command === "clear") {
    const deleted = await clearSeedPack(db, seedPlan, args, claimedOpen);
    console.log(
      `Cleared ${deleted.toLocaleString()} seeded replay documents in ` +
      `${elapsedSeconds(startedAt)}s.`
    );
    return;
  }

  // The write replaces every row it still plans in place - the ids are derived,
  // so a `set` overwrites rather than duplicates - and deletes only what the
  // plan has retired. A blanket clear beforehand is a second full pass over the
  // same half a million documents that leaves staging empty in between, so it is
  // opt-in rather than the default.
  if (args.clearFirst) {
    const deleted = await clearSeedPack(db, seedPlan, args, claimedOpen);
    console.log(`Cleared ${deleted.toLocaleString()} existing seeded replay documents.`);
  }

  const written = await writeSeedPlan(db, seedPlan, args, claimedOpen);
  console.log(
    `Seeded ${written.toLocaleString()} Firestore documents into ${projectId} in ` +
    `${elapsedSeconds(startedAt)}s.`
  );
}

/**
 * @param {number} startedAt Epoch milliseconds.
 * @return {string} Seconds since then, to one decimal.
 */
function elapsedSeconds(startedAt) {
  return ((Date.now() - startedAt) / 1000).toFixed(1);
}

function resolveProjectId(projectOrAlias) {
  const firebaseRc = JSON.parse(readFileSync(resolve(REPO_ROOT, ".firebaserc"), "utf8"));
  return firebaseRc.projects?.[projectOrAlias] ?? projectOrAlias;
}

function loadClimbCatalog() {
  const catalogPath = resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json");
  const climbs = JSON.parse(readFileSync(catalogPath, "utf8"));
  if (!Array.isArray(climbs) || climbs.length === 0) {
    throw new Error(`No climbs found in ${catalogPath}`);
  }

  return new Map(climbs.map((climb) => [climb.id, climb]));
}

async function loadPaceSamples(db, args) {
  if (!args.sourceUserId) {
    console.warn(
      "No --source-user or ASCEND_SEED_SOURCE_USER_ID provided. Using fallback pace samples."
    );
    return fallbackPaceSamples();
  }

  const snapshot = await db
    .collection("users")
    .doc(args.sourceUserId)
    .collection("workouts")
    .get();

  const samples = [];
  let appleHealthCount = 0;
  let rejectedCount = 0;

  for (const document of snapshot.docs) {
    const data = document.data();
    const sample = paceSampleFromWorkout(data, args.appleHealthStepFactor);
    if (!sample) {
      rejectedCount += 1;
      continue;
    }

    if (sample.isAppleHealth) {
      appleHealthCount += 1;
    }
    samples.push(sample);
  }

  if (samples.length < 12) {
    console.warn(
      `Only ${samples.length} usable source workouts found. Blending fallback pace samples.`
    );
    samples.push(...fallbackPaceSamples());
  }

  samples.sort((lhs, rhs) => lhs.stepsPerMinute - rhs.stepsPerMinute);
  const stats = paceStats(samples);
  console.log(
    [
      `Loaded ${snapshot.size} source workouts`,
      `${samples.length} usable pace samples`,
      `${appleHealthCount} Apple Health calibrated`,
      `${rejectedCount} rejected`,
      `median ${stats.median.toFixed(1)} SPM`,
      `p90 ${stats.p90.toFixed(1)} SPM`,
    ].join(" | ")
  );

  return samples;
}

function paceSampleFromWorkout(data, appleHealthStepFactor) {
  const durationSeconds = positiveNumber(data.durationSeconds ?? data.duration);
  const steps = positiveInteger(data.steps);
  if (!durationSeconds || !steps || durationSeconds < 120 || durationSeconds > 7200) {
    return null;
  }

  const source = stringValue(data.source) ?? "";
  const isAppleHealth = source === "apple_health" ||
    Boolean(stringValue(data.healthKitUUID)) ||
    stringValue(data.deviceModel)?.toLowerCase().includes("apple watch") === true;
  const calibratedSteps = Math.round(steps * (isAppleHealth ? appleHealthStepFactor : 1));
  const stepsPerMinute = calibratedSteps / (durationSeconds / 60);

  if (!Number.isFinite(stepsPerMinute) ||
      stepsPerMinute < 25 ||
      stepsPerMinute > 180) {
    return null;
  }

  return {
    durationSeconds,
    rawSteps: steps,
    calibratedSteps,
    stepsPerMinute,
    isAppleHealth,
    source,
  };
}

function fallbackPaceSamples() {
  return [42, 50, 58, 66, 74, 82, 90, 98, 106, 114, 122, 132].map((spm) => ({
    durationSeconds: 1200,
    rawSteps: spm * 20,
    calibratedSteps: spm * 20,
    stepsPerMinute: spm,
    isAppleHealth: false,
    source: "fallback",
  }));
}

function paceStats(samples) {
  return {
    median: percentile(samples.map((sample) => sample.stepsPerMinute), 0.5),
    p90: percentile(samples.map((sample) => sample.stepsPerMinute), 0.9),
  };
}

function percentile(values, percentileValue) {
  if (values.length === 0) {
    return 0;
  }

  const sorted = [...values].sort((lhs, rhs) => lhs - rhs);
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.floor((sorted.length - 1) * percentileValue))
  );
  return sorted[index];
}

function loadAvatarFiles(avatarDir) {
  const validExtensions = new Set([".jpg", ".jpeg", ".png", ".webp"]);
  const files = readdirSync(avatarDir)
    .map((fileName) => resolve(avatarDir, fileName))
    .filter((filePath) => {
      try {
        return statSync(filePath).isFile() &&
          validExtensions.has(extname(filePath).toLowerCase());
      } catch {
        return false;
      }
    })
    .sort((lhs, rhs) => lhs.localeCompare(rhs));

  if (files.length === 0) {
    throw new Error(`No supported avatar images found in ${avatarDir}`);
  }

  return files;
}

/**
 * The avatar URLs this run should publish on its synthetic climbers.
 *
 * Uploading needs a local image folder, which nobody has to hand months later -
 * so a run without `--avatar-dir` used to publish no photo at all, and every
 * seeded leaderboard row rendered as a lettered circle while 83 real avatar
 * images sat unused in Storage.
 *
 * They are reusable without the originals: each object was uploaded with its own
 * `firebaseStorageDownloadTokens`, which is the only part of a download URL that
 * cannot be derived from the path. So a run with no folder reads the objects
 * back and rebuilds the identical URLs, which also keeps a climber's face stable
 * across re-seeds instead of minting a new token every time.
 * @param {string[]} avatarFiles Local avatar images, empty when none were given.
 * @param {object} args Parsed CLI arguments.
 * @return {Promise<string[]>} Download URLs, ordered by object name.
 */
async function resolveSeedAvatarURLs(avatarFiles, args) {
  if (avatarFiles.length > 0) {
    return competitorAvatars(await uploadSeedAvatars(avatarFiles, args));
  }

  const urls = await hostedSeedAvatarURLs(args);
  if (urls.length === 0) {
    console.warn(
      `No avatar images found locally or under live-replay-avatars/` +
      `${sanitizeContextId(args.seedPackId)}/. Seeded climbers will render as ` +
      "initials. Pass --avatar-dir <path> once to upload a set."
    );
  }

  return urls;
}

/**
 * Rebuilds download URLs for the avatars this seed pack already uploaded.
 * @param {object} args Parsed CLI arguments.
 * @return {Promise<string[]>} Download URLs, ordered by object name.
 */
async function hostedSeedAvatarURLs(args) {
  const bucket = getStorage().bucket();
  const prefix = seedAvatarPrefix(sanitizeContextId(args.seedPackId));
  const [files] = await bucket.getFiles({prefix});

  const urls = files
    .filter((file) => file.metadata.metadata?.firebaseStorageDownloadTokens)
    .sort((lhs, rhs) => lhs.name.localeCompare(rhs.name))
    .map((file) => downloadURL(
      bucket.name,
      file.name,
      String(file.metadata.metadata.firebaseStorageDownloadTokens).split(",")[0]
    ));

  // The last one belongs to the account being seeded, which stands on these same
  // boards; handing it to a competitor too would put one face on two rows.
  return competitorAvatars(urls);
}

async function uploadSeedAvatars(avatarFiles, args) {
  const bucket = getStorage().bucket();
  const seedPackPath = sanitizeContextId(args.seedPackId);
  const urls = [];

  for (let index = 0; index < avatarFiles.length; index += 1) {
    const sourcePath = avatarFiles[index];
    const extension = normalizedImageExtension(sourcePath);
    const destination = [
      "live-replay-avatars",
      seedPackPath,
      `avatar-${String(index + 1).padStart(3, "0")}${extension}`,
    ].join("/");
    const token = randomUUID();

    await bucket.upload(sourcePath, {
      destination,
      metadata: {
        cacheControl: "public,max-age=31536000,immutable",
        contentType: contentTypeForImage(sourcePath),
        metadata: {
          firebaseStorageDownloadTokens: token,
          seedPackId: args.seedPackId,
        },
      },
    });

    urls.push(downloadURL(bucket.name, destination, token));
  }

  return urls;
}

function normalizedImageExtension(filePath) {
  const extension = extname(filePath).toLowerCase();
  return extension === ".jpeg" ? ".jpg" : extension;
}

function contentTypeForImage(filePath) {
  switch (extname(filePath).toLowerCase()) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".png":
      return "image/png";
    case ".webp":
      return "image/webp";
    default:
      return "application/octet-stream";
  }
}

function downloadURL(bucketName, objectPath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
}

/**
 * Fails a plan that would put more finishers on a board than the pack can give
 * distinct identities.
 *
 * Both halves of a synthetic climber's identity are indexed by position:
 * `displayNameForAttempt` falls back to "Climber 061" past the end of the name
 * list, and `avatarURLForDisplayName` returns nothing for a name past the last
 * uploaded image. Neither failure is visible in the seed's own output - it shows
 * up as placeholder names and lettered circles on a leaderboard, which is
 * usually discovered by looking at a screenshot.
 *
 * The name shortfall is a config error and fails the run. The avatar shortfall
 * only warns: an environment that has never been given an avatar set still has a
 * usable board, just an uglier one.
 * @param {object[]} climbPlans Built per-climb plans.
 * @param {string[]} avatarURLs Avatar URLs available to this run.
 */
function assertSeededIdentitySupply(climbPlans, avatarURLs) {
  const overNamed = climbPlans
    .filter((plan) => plan.completedCount > SEEDED_DISPLAY_NAMES.length)
    .map((plan) => `${plan.climb.id} (${plan.completedCount})`);

  if (overNamed.length > 0) {
    throw new Error(
      `${overNamed.join(", ")} would seed more finishers than the ` +
      `${SEEDED_DISPLAY_NAMES.length} distinct names available, so the ` +
      "overflow would render as \"Climber 061\" on a leaderboard. Lower the " +
      "completion rate or add names and avatars together."
    );
  }

  const widest = Math.max(...climbPlans.map((plan) => plan.completedCount));
  if (avatarURLs.length > 0 && avatarURLs.length < widest) {
    console.warn(
      `Only ${avatarURLs.length} avatar image(s) available for a board of ` +
      `${widest} finishers, so ${widest - avatarURLs.length} row(s) will ` +
      "render as initials."
    );
  }
}

function buildSeedPlan(climbsById, paceSamples, args, avatarURLs) {
  const contestedIds = contestedClimbIds();
  const configs = [
    ...ACTIVE_CLIMBS.map((config) => ({...config, activityTier: "active"})),
    ...WARM_CLIMBS.map((config) => ({...config, activityTier: "warm"})),
    ...firstAscentOpenConfigs(climbsById, contestedIds).map((config) => ({
      ...config,
      activityTier: FIRST_ASCENT_OPEN_ACTIVITY_TIER,
    })),
  ];

  const missingConfigs = configs.filter((config) => !climbsById.has(config.id));
  if (missingConfigs.length > 0) {
    console.warn(
      `Skipping ${missingConfigs.length} seed climb(s) missing from catalog: ` +
        missingConfigs.map((config) => config.id).join(", ")
    );
  }

  const climbPlans = configs.flatMap((config) => {
    const climb = climbsById.get(config.id);
    if (!climb) {
      return [];
    }

    const completedCount = Math.round(config.totalClimbers * config.completionRate);
    const attempts = generateAttempts(
      climb,
      config,
      completedCount,
      paceSamples,
      args.seedPackId,
      avatarURLs
    );
    // A climb with no completions has no buckets to publish, and the bucket
    // limit is undefined over an empty duration set.
    const maxBucketIndex = attempts.length > 0 ?
      bucketLimitForAttempts(attempts) :
      -1;
    const clearAttemptIds = Array.from(
      {length: Math.max(config.replayEntries, completedCount)},
      (_, index) => seedAttemptId(args.seedPackId, climb.id, index)
    );
    const clearUserIds = Array.from(
      {length: Math.max(config.replayEntries, completedCount)},
      (_, index) => seedUserId(args.seedPackId, climb.id, index)
    );

    // Attempts carry a completion duration but no wall-clock completion time, so
    // none of them is the earliest. The holder is an arbitrary but deterministic
    // pick, which is all a fixture needs; `firstAscentClaimedAt` dates the claim.
    const firstAscentAttempt = attempts[0] ?? null;

    // Checked at plan time so a bad fixture fails the dry run, before any writes.
    assertFirstAscentInvariant({
      climbId: climb.id,
      completedCount,
      hasFirstAscent: firstAscentAttempt !== null,
    });

    return [{
      config,
      climb,
      attempts,
      completedCount,
      clearAttemptIds,
      clearUserIds,
      maxBucketIndex,
      firstAscentAttempt,
      entryDocumentCount: attempts.length * (maxBucketIndex + 1),
    }];
  });

  if (climbPlans.length === 0) {
    throw new Error("No configured seed climbs matched the catalog.");
  }

  assertSeededIdentitySupply(climbPlans, avatarURLs);

  const justClimbAttempts = climbPlans.flatMap((plan) => plan.attempts);
  const justClimbMaxBucketIndex = MAX_BUCKET_INDEX;
  // No clear id lists: this context is cleared by seed-pack query, because its
  // rows outlive the climb list that produced them.
  const justClimbPlan = {
    attempts: justClimbAttempts,
    maxBucketIndex: justClimbMaxBucketIndex,
    entryDocumentCount: justClimbAttempts.length * (justClimbMaxBucketIndex + 1),
  };

  return {
    climbPlans,
    justClimbPlan,
    totalEntryDocuments: climbPlans.reduce(
      (sum, plan) => sum + plan.entryDocumentCount,
      justClimbPlan.entryDocumentCount
    ),
    totalSummaryDocuments: climbPlans.length + 1,
  };
}

function generateAttempts(climb, config, completedCount, paceSamples, seedPackId, avatarURLs) {
  const targetSteps = referenceStepCount(climb);
  const attempts = [];
  const usedProfileKeys = new Set();

  for (let index = 0; index < completedCount; index += 1) {
    const rng = mulberry32(hashString(`${seedPackId}:${climb.id}:${index}`));
    const paceSample = paceSamples[Math.floor(rng() * paceSamples.length)] ??
      fallbackPaceSamples()[index % fallbackPaceSamples().length];
    const adjustedPace = adjustedPaceForClimb(paceSample.stepsPerMinute, targetSteps, rng);
    const idealCompletionSeconds = (targetSteps / adjustedPace) * 60;
    const durationSeconds = clamp(
      idealCompletionSeconds * randomInRange(rng, 0.94, 1.08),
      90,
      7200
    );
    const finalSteps = targetSteps;
    const displayName = displayNameForAttempt(climb.id, index);
    const photoURL = avatarURLForDisplayName(displayName, avatarURLs);
    const profileKey = syntheticProfileKey(displayName, photoURL);
    if (usedProfileKeys.has(profileKey)) {
      throw new Error(
        `Duplicate synthetic replay profile for ${climb.id}: ${displayName}`
      );
    }
    usedProfileKeys.add(profileKey);

    attempts.push({
      id: seedAttemptId(seedPackId, climb.id, index),
      userId: seedUserId(seedPackId, climb.id, index),
      displayName,
      avatarToken: avatarToken(displayName),
      photoURL,
      finalSteps,
      durationSeconds,
      completionDurationSeconds: durationSeconds,
      paceStepsPerMinute: adjustedPace,
      curveExponent: randomInRange(rng, 0.88, 1.14),
      wobblePhase: randomInRange(rng, 0, Math.PI * 2),
    });
  }

  return attempts;
}

function adjustedPaceForClimb(sourcePace, targetSteps, rng) {
  const targetFatigue = targetSteps <= 600
    ? 1.08
    : targetSteps <= 1200
      ? 1.02
      : targetSteps <= 2500
        ? 0.96
        : targetSteps <= 4000
          ? 0.90
          : 0.84;
  const roll = rng();
  const performanceMultiplier = roll < 0.08
    ? randomInRange(rng, 1.26, 1.48)
    : roll < 0.28
      ? randomInRange(rng, 1.07, 1.24)
      : roll < 0.84
        ? randomInRange(rng, 0.82, 1.08)
        : randomInRange(rng, 0.58, 0.82);

  return clamp(sourcePace * targetFatigue * performanceMultiplier, 32, 165);
}

function bucketLimitForAttempts(attempts) {
  const durations = attempts.map((attempt) => attempt.durationSeconds).sort((lhs, rhs) => lhs - rhs);
  const p95Duration = percentile(durations, 0.95);
  return Math.min(
    MAX_BUCKET_INDEX,
    Math.max(12, Math.ceil(p95Duration / BUCKET_INTERVAL_SECONDS) + 6)
  );
}

function printPlan(seedPlan, args, avatarFileCount, avatarURLCount) {
  console.log(`Project: ${resolveProjectId(args.project)}`);
  console.log(`Seed pack: ${args.seedPackId}`);
  console.log(`Apple Health step factor: ${args.appleHealthStepFactor}`);
  if (avatarFileCount > 0) {
    const suffix = args.dryRun
      ? "found, not uploaded during dry run"
      : `${avatarURLCount} uploaded`;
    console.log(`Avatars: ${avatarFileCount} files ${suffix}`);
  }
  console.log(`Mode: ${args.command}${args.dryRun ? " (dry run)" : ""}`);
  console.log(
    `Planned docs: ${seedPlan.totalSummaryDocuments.toLocaleString()} summaries, ` +
      `${seedPlan.totalEntryDocuments.toLocaleString()} replay entries`
  );

  for (const plan of seedPlan.climbPlans) {
    console.log(
      [
        plan.config.activityTier.toUpperCase().padEnd(6),
        plan.climb.id.padEnd(25),
        `${plan.completedCount} completed`,
        `${plan.attempts.length} replay rows`,
        `${plan.maxBucketIndex + 1} buckets`,
        plan.firstAscentAttempt ?
          `FA held by ${plan.firstAscentAttempt.displayName}` :
          "FA open",
      ].join(" | ")
    );
  }

  console.log(
    [
      "GLOBAL".padEnd(6),
      "just-climb-global".padEnd(25),
      `${seedPlan.justClimbPlan.attempts.length} completed`,
      `${seedPlan.justClimbPlan.attempts.length} replay rows`,
      `${seedPlan.justClimbPlan.maxBucketIndex + 1} buckets`,
    ].join(" | ")
  );
}

/**
 * Open-slot climbs a real climber has already finished.
 *
 * An open board is cleared wholesale - every finisher and every replay row,
 * whoever wrote them - which is only safe while the fixture's promise that the
 * climb has no completions actually holds. It held while four hand-picked
 * un-raced climbs carried the open slot. It does not hold now that every
 * raceable climb the pack does not contest is seeded open: on staging those are
 * climbs TestFlight testers can and do race, and a First Ascent is permanent, so
 * wiping one destroys something the product promises can never be taken.
 *
 * A board a real climber has finished is therefore left entirely alone - not
 * cleared, not rewritten. Its slot is legitimately spent, which is the same
 * answer the server gives.
 * @param {object} db Firestore instance.
 * @param {object} seedPlan Built seed plan.
 * @return {Promise<Set<string>>} Climb ids to leave untouched.
 */
async function claimedOpenClimbIds(db, seedPlan) {
  const openPlans = seedPlan.climbPlans.filter((plan) => isOpenFirstAscentSummary({
    completedCount: plan.completedCount,
    hasFirstAscent: plan.firstAscentAttempt !== null,
  }));
  const claimed = new Set();

  await runPool(openPlans, READ_CONCURRENCY, async (plan) => {
    const finishers = await withRetry(
      () => finishersCollection(db, plan.climb.id).listDocuments(),
      {description: `listDocuments(finishers/${plan.climb.id})`}
    );
    if (finishers.some((document) => !isSyntheticUserId(document.id))) {
      claimed.add(plan.climb.id);
    }
  });

  return claimed;
}

/**
 * Takes this pack's rows back out.
 *
 * Enumerate-then-delete, in that order and both in parallel. The version this
 * replaced deleted by derived id across every bucket index the schema allows,
 * which queued 769,652 deletes for a pack that had written 520,784 rows - most
 * of them for documents that were never there. Reading what exists is one
 * `listDocuments` per bucket, and 64 of those run at once.
 * @param {object} db Firestore instance.
 * @param {object} seedPlan Built seed plan.
 * @param {object} args Parsed CLI arguments.
 * @param {Set<string>} claimedOpen Climb ids a real climber has finished.
 * @return {Promise<number>} Count of documents deleted.
 */
async function clearSeedPack(db, seedPlan, args, claimedOpen = new Set()) {
  const contexts = clearableContexts(db, seedPlan, claimedOpen);
  const enumeration = createProgressReporter({
    label: "Clear (reading what exists)",
    total: contexts.length,
    unit: "boards",
  });
  const doomed = [];

  await runPool(contexts, CONTEXT_CONCURRENCY, async (context) => {
    appendAll(doomed, await seededDocumentsUnder(db, context.ref, args.seedPackId, enumeration, {
      clearsEveryRow: context.clearsEveryRow,
    }));
    enumeration.advance(1);
  });

  const stale = await staleSeedContextDocuments(
    db,
    args.seedPackId,
    contextKeysForPlan(seedPlan),
    enumeration
  );
  appendAll(doomed, stale);
  enumeration.finish(`${doomed.length.toLocaleString()} documents to delete`);

  const deletion = createProgressReporter({
    label: "Clear (deleting)",
    total: doomed.length,
    unit: "docs",
  });
  const writer = createBatchWriter(db, {progress: deletion});
  for (const ref of doomed) {
    writer.delete(ref);
  }
  await writer.flush();

  // Zeroing the summaries is the last thing, so an interrupted clear leaves
  // boards whose counts still describe rows that are really gone rather than
  // boards that claim to be empty while their rows survive.
  const now = FieldValue.serverTimestamp();
  for (const plan of seedPlan.climbPlans) {
    if (claimedOpen.has(plan.climb.id)) {
      continue;
    }

    writer.set(leaderboardRef(db, plan.climb.id), {
      completedCount: 0,
      replayEntryCount: 0,
      seedPackId: args.seedPackId,
      seededAttemptCount: 0,
      totalClimbers: 0,
      updatedAt: now,
      [SEED_FINGERPRINT_FIELD]: FieldValue.delete(),
      [SEED_BUCKET_COUNT_FIELD]: 0,
      // Zeroing completions without dropping the holder would leave the slot
      // readable as open while the server still refuses to claim it.
      ...clearedFirstAscentFields(FieldValue.delete()),
    }, {merge: true});
  }

  writer.set(justClimbLeaderboardRef(db), {
    completedCount: 0,
    replayEntryCount: 0,
    seedPackId: args.seedPackId,
    seededAttemptCount: 0,
    totalClimbers: 0,
    updatedAt: now,
    [SEED_FINGERPRINT_FIELD]: FieldValue.delete(),
    [SEED_BUCKET_COUNT_FIELD]: 0,
  }, {merge: true});

  await writer.drain();
  deletion.finish(`${doomed.length.toLocaleString()} documents deleted`);
  return doomed.length;
}

/**
 * The context documents a clear is allowed to empty.
 * @param {object} db Firestore instance.
 * @param {object} seedPlan Built seed plan.
 * @param {Set<string>} claimedOpen Climb ids a real climber has finished.
 * @return {object[]} Context descriptors.
 */
function clearableContexts(db, seedPlan, claimedOpen) {
  const contexts = seedPlan.climbPlans
    .filter((plan) => !claimedOpen.has(plan.climb.id))
    .map((plan) => ({
      key: plan.climb.id,
      ref: leaderboardRef(db, plan.climb.id),
      clearsEveryRow: isOpenFirstAscentSummary({
        completedCount: plan.completedCount,
        hasFirstAscent: plan.firstAscentAttempt !== null,
      }),
    }));
  contexts.push({
    key: JUST_CLIMB_GLOBAL_CONTEXT_ID,
    ref: justClimbLeaderboardRef(db),
    clearsEveryRow: false,
  });
  return contexts;
}

/**
 * Finds every document this pack owns under one replay context.
 *
 * Split bucket entries are found by listing rather than by query, because a
 * `where("seedPackId", ...)` per bucket is one round trip per bucket that also
 * needs an index; the ids the pack writes are derived, so membership is decided
 * locally. Finishers are found by listing for the same reason, and filtered by
 * `isSyntheticUserId` so a real climber's document is never in the set.
 * @param {object} db Firestore instance.
 * @param {object} contextRef Replay context document reference.
 * @param {string} seedPackId Pack being cleared.
 * @param {object} progress Reporter kept alive during enumeration.
 * @return {Promise<object[]>} Document references to delete.
 */
async function seededDocumentsUnder(db, contextRef, seedPackId, progress, {
  clearsEveryRow = false,
} = {}) {
  const bucketRefs = await withRetry(
    () => contextRef.collection("splitBuckets").listDocuments(),
    {description: `listDocuments(${contextRef.path}/splitBuckets)`, onRetry: () => progress.retried()}
  );
  const entryCollections = bucketRefs.map((bucketRef) => bucketRef.collection("entries"));
  const [entries, finishers] = await Promise.all([
    listDocumentsAcross(entryCollections, {progress}),
    withRetry(() => contextRef.collection("finishers").listDocuments(), {
      description: `listDocuments(${contextRef.path}/finishers)`,
      onRetry: () => progress.retried(),
    }),
  ]);

  // A contested board carries real climbers' rows beside the pack's, under ids
  // only they know, and those are not the fixture's to delete. A board seeded
  // with an open First Ascent is the documented exception: it promises zero
  // completions, and `claimedOpenClimbIds` has already taken any board a real
  // climber genuinely finished out of this set, so whatever is left there is
  // the pack's own residue whether the ids say so or not.
  const doomedEntries = clearsEveryRow ?
    entries :
    entries.filter((document) => isSeededAttemptId(document.id, seedPackId));
  const doomedFinishers = clearsEveryRow ?
    finishers :
    finishers.filter((document) => isSyntheticUserId(document.id));

  // Bucket parents only go when nothing under them survives; a bucket document
  // holds no fields of its own, so deleting one that still has entries orphans
  // them behind a parent the console renders as missing.
  const doomed = appendAll([], doomedEntries);
  appendAll(doomed, doomedFinishers);
  if (doomedEntries.length === entries.length) {
    appendAll(doomed, bucketRefs);
  }

  return doomed;
}

function contextKeysForPlan(seedPlan) {
  const keys = new Set(
    seedPlan.climbPlans.map((plan) =>
      contextKey(LIVE_CLIMB_CONTEXT_TYPE, plan.climb.id)
    )
  );
  keys.add(contextKey(JUST_CLIMB_CONTEXT_TYPE, JUST_CLIMB_GLOBAL_CONTEXT_ID));
  return keys;
}

/**
 * Finds the rows of retired contexts - boards this pack once wrote and no longer
 * plans.
 * @param {object} db Firestore instance.
 * @param {string} seedPackId Pack being cleared.
 * @param {Set<string>} activeContextKeys Contexts the current plan still owns.
 * @param {object} progress Reporter kept alive during enumeration.
 * @return {Promise<object[]>} Document references to delete.
 */
async function staleSeedContextDocuments(db, seedPackId, activeContextKeys, progress) {
  const snapshot = await withRetry(
    () => db.collection(LIVE_REPLAY_COLLECTION).where("seedPackId", "==", seedPackId).get(),
    {description: `query(${LIVE_REPLAY_COLLECTION} by seedPackId)`, onRetry: () => progress.retried()}
  );
  const stale = snapshot.docs.filter((document) => !activeContextKeys.has(document.id));
  const doomed = [];

  await runPool(stale, CONTEXT_CONCURRENCY, async (document) => {
    // The whole board is being retired, so nothing under it is worth keeping.
    appendAll(doomed, await seededDocumentsUnder(db, document.ref, seedPackId, progress, {
      clearsEveryRow: true,
    }));
    doomed.push(document.ref);
  });

  return doomed;
}

/**
 * Resolves the completion count each seeded summary may claim.
 *
 * The permanent rank a finished climb keeps counts the finisher documents on
 * its board and measures that rank against the summary's `completedCount`, and
 * it refuses a rank standing outside its own population rather than clamping
 * it. So a summary claiming fewer completions than the board has finishers is
 * not a cosmetic drift: the next climber to finish in the bottom places wedges
 * their publish, and every retry recomputes the same impossible pair.
 *
 * The clear only takes out this pack's own finishers - `seed-demo-user` writes
 * one under a real uid, and an earlier pack's survive under a different
 * `seedPackId` - so the count comes from every finisher that will stand on the
 * board once this pack lands, whatever wrote it.
 * @param {object} db Firestore instance.
 * @param {object} seedPlan Built seed plan.
 * @param {Set<string>} claimedOpen Climb ids a real climber has finished.
 * @return {Promise<object>} Per-climb board states and the Just Climb state.
 */
async function resolveSeededCompletedCounts(db, seedPlan, claimedOpen = new Set()) {
  const plans = seedPlan.climbPlans.filter((plan) => !claimedOpen.has(plan.climb.id));
  const climbBoards = new Map();

  await runPool(plans, CONTEXT_CONCURRENCY, async (plan) => {
    const board = await boardFinisherState(
      finishersCollection(db, plan.climb.id),
      plan.attempts.map((attempt) => attempt.userId),
      plan.completedCount
    );

    // A summary carrying completions with no holder is the dead First Ascent
    // state, so a stranded finisher fails the run before anything is written.
    assertFirstAscentInvariant({
      climbId: plan.climb.id,
      completedCount: board.population,
      hasFirstAscent: plan.firstAscentAttempt !== null,
    });
    climbBoards.set(plan.climb.id, board);
  });

  return {
    climbBoards,
    justClimbBoard: await boardFinisherState(
      justClimbFinishersCollection(db),
      seedPlan.justClimbPlan.attempts.map((attempt) => attempt.userId),
      seedPlan.justClimbPlan.attempts.length
    ),
  };
}

/**
 * Resolves who will hold a finisher document on one board after this run.
 *
 * Both the population and the identities matter. The population is the
 * denominator a finished climb freezes its rank against. The identities decide
 * the summary's `source`: this pack clears only its own finishers, so a real
 * climber can survive the clear, and a board carrying one is not seeded however
 * many synthetic rows sit beside them.
 * @param {object} finishersRef `finishers` collection reference.
 * @param {string[]} seededUserIds Climbers this pack is about to write.
 * @param {number} plannedCount Completions the plan intended to seed.
 * @return {Promise<object>} Population and surviving finisher ids.
 */
async function boardFinisherState(finishersRef, seededUserIds, plannedCount) {
  const surviving = await withRetry(() => finishersRef.listDocuments(), {
    description: `listDocuments(${finishersRef.path})`,
  });
  const userIds = new Set(surviving.map((document) => document.id));
  for (const userId of seededUserIds) {
    userIds.add(userId);
  }

  return {
    population: Math.max(plannedCount, userIds.size),
    survivingFinisherIds: Array.from(userIds),
  };
}

/**
 * The step series one attempt publishes, one value per bucket index.
 *
 * Materialized once and used twice - to fingerprint the context and to write it -
 * so the fingerprint is over the numbers that actually land rather than over the
 * parameters they were derived from. A change to `stepsAtBucketIndex` therefore
 * invalidates the fingerprint without anyone having to remember to say so.
 * @param {object} attempt Generated attempt.
 * @param {number} maxBucketIndex Highest bucket index this context publishes.
 * @return {number[]} Steps at each bucket index.
 */
function stepSeries(attempt, maxBucketIndex) {
  const series = new Array(maxBucketIndex + 1);
  for (let bucketIndex = 0; bucketIndex <= maxBucketIndex; bucketIndex += 1) {
    series[bucketIndex] = stepsAtBucketIndex(attempt, bucketIndex);
  }
  return series;
}

/**
 * What one context's rows will contain, as a hash.
 *
 * This is what makes a re-run seconds instead of minutes. Every id and every
 * value the seed writes is derived from the plan, so a context whose plan has
 * not changed already holds exactly the documents this run would write. The hash
 * is stamped on the summary only after the rows land, so an interrupted run
 * leaves no fingerprint and the next run rewrites the context in full.
 * @param {object} context Prepared context.
 * @param {string} seedPackId Pack being written.
 * @return {string} Hex digest.
 */
function contextFingerprint(context, seedPackId) {
  const hash = createHash("sha256");
  hash.update(`${SEED_WRITE_REVISION}|${seedPackId}|${context.contextType}|`);
  hash.update(`${context.contextId}|${context.maxBucketIndex}|${BUCKET_INTERVAL_SECONDS}\n`);

  for (const {attempt, series} of context.rows) {
    hash.update([
      attempt.id,
      attempt.userId,
      attempt.displayName,
      attempt.avatarToken,
      attempt.photoURL ?? "",
      attempt.finalSteps,
      attempt.completionDurationSeconds.toFixed(4),
      series.join(","),
    ].join("|"));
    hash.update("\n");
  }

  return hash.digest("hex");
}

/**
 * Flattens the plan into the two contexts the writer works over.
 * @param {object} seedPlan Built seed plan.
 * @param {Set<string>} claimedOpen Climb ids a real climber has finished.
 * @param {object} db Firestore instance.
 * @return {object[]} Prepared contexts, each carrying its materialized rows.
 */
function prepareContexts(seedPlan, claimedOpen, db) {
  const withBestAttemptIds = (context) => ({
    ...context,
    bestAttemptIds: bestAttemptIds(context.rows, context.contextType),
  });
  const contexts = seedPlan.climbPlans
    .filter((plan) => !claimedOpen.has(plan.climb.id))
    .map((plan) => ({
      plan,
      contextType: LIVE_CLIMB_CONTEXT_TYPE,
      contextId: plan.climb.id,
      label: plan.climb.id,
      summaryRef: leaderboardRef(db, plan.climb.id),
      finishersRef: finishersCollection(db, plan.climb.id),
      entriesCollection: (bucketIndex) => entriesCollection(db, plan.climb.id, bucketIndex),
      splitBucketsRef: splitBucketsCollection(db, plan.climb.id),
      attempts: plan.attempts,
      maxBucketIndex: plan.maxBucketIndex,
      rows: plan.attempts.map((attempt) => ({
        attempt,
        series: stepSeries(attempt, plan.maxBucketIndex),
      })),
    }))
    .map(withBestAttemptIds);

  const justClimb = seedPlan.justClimbPlan;
  contexts.push(withBestAttemptIds({
    plan: justClimb,
    contextType: JUST_CLIMB_CONTEXT_TYPE,
    contextId: JUST_CLIMB_GLOBAL_CONTEXT_ID,
    label: "just-climb-global",
    summaryRef: justClimbLeaderboardRef(db),
    finishersRef: justClimbFinishersCollection(db),
    entriesCollection: (bucketIndex) => justClimbEntriesCollection(db, bucketIndex),
    splitBucketsRef: justClimbLeaderboardRef(db).collection("splitBuckets"),
    attempts: justClimb.attempts,
    maxBucketIndex: justClimb.maxBucketIndex,
    rows: justClimb.attempts.map((attempt) => ({
      attempt,
      series: stepSeries(attempt, justClimb.maxBucketIndex),
    })),
  }));

  return contexts;
}

async function writeSeedPlan(db, seedPlan, args, claimedOpen = new Set()) {
  const now = FieldValue.serverTimestamp();
  const contexts = prepareContexts(seedPlan, claimedOpen, db);
  const {climbBoards, justClimbBoard} = await resolveSeededCompletedCounts(
    db,
    seedPlan,
    claimedOpen
  );

  const summaries = await withRetry(
    () => db.getAll(...contexts.map((context) => context.summaryRef)),
    {description: `getAll(${contexts.length} replay summaries)`}
  );
  const stored = new Map(summaries.map((snapshot) => [snapshot.ref.path, snapshot.data() ?? {}]));

  const changed = [];
  let skippedEntries = 0;
  for (const context of contexts) {
    context.fingerprint = contextFingerprint(context, args.seedPackId);
    const previous = stored.get(context.summaryRef.path) ?? {};
    context.previousBucketCount = Number.isInteger(previous[SEED_BUCKET_COUNT_FIELD]) ?
      previous[SEED_BUCKET_COUNT_FIELD] :
      null;
    context.entryCount = context.rows.length * (context.maxBucketIndex + 1);

    if (!args.force && previous[SEED_FINGERPRINT_FIELD] === context.fingerprint) {
      skippedEntries += context.entryCount;
      continue;
    }
    changed.push(context);
  }

  if (skippedEntries > 0) {
    console.log(
      `Unchanged: ${(contexts.length - changed.length)} of ${contexts.length} boards ` +
      `already hold this pack's ${skippedEntries.toLocaleString()} rows. Skipping them.`
    );
  }

  const plannedEntries = changed.reduce((sum, context) => sum + context.entryCount, 0);
  const plannedFinishers = changed.reduce((sum, context) => sum + context.rows.length, 0);
  const progress = createProgressReporter({
    label: "Seed",
    total: plannedEntries + plannedFinishers + contexts.length,
    unit: "docs",
  });
  const writer = createBatchWriter(db, {progress});
  let writes = 0;

  // Summaries first and fingerprints last, both deliberate. The summary a board
  // renders from is written before its rows so a run interrupted mid-context
  // leaves a board that under-reports rather than one that promises rows it does
  // not have; the fingerprint is only stamped once the rows are in.
  for (const context of contexts) {
    writer.set(
      context.summaryRef,
      summaryWrite(context, {args, now, climbBoards, justClimbBoard, seedPlan}),
      {merge: true}
    );
    writes += 1;
  }
  await writer.flush();

  for (const context of changed) {
    progress.note(context.label);
    const doomed = await retiredRowRefs(context, args.seedPackId, progress);
    for (const ref of doomed) {
      writer.delete(ref);
    }

    for (const [index, {attempt}] of context.rows.entries()) {
      writer.set(
        context.finishersRef.doc(attempt.userId),
        syntheticFinisherWrite(attempt, {
          contextType: context.contextType,
          globalCompletionOrder: index + 1,
          identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
          schemaVersion: 1,
          seedPackId: args.seedPackId,
          updatedAt: now,
        })
      );
      writes += 1;
    }

    // Climber-major, not bucket-major, and this ordering is worth 9x.
    //
    // Every entry in one split bucket lives in the same `entries` collection, so
    // a 500-write batch filled bucket-first is 500 writes into one collection
    // and 500 index updates over the same `stepsAtBucket` range. Firestore
    // answers that with contention: filled bucket-first this measured 2,327
    // docs/s and retried, filled climber-first the same batch touches 500
    // different bucket collections and measured over 20,000 docs/s.
    const bucketCount = context.maxBucketIndex + 1;
    for (const [row, {attempt, series}] of context.rows.entries()) {
      const entry = entryWrite(context, attempt, 0, {seedPackId: args.seedPackId, now});
      // Each climber starts at a different bucket and wraps, so the batches in
      // flight at any moment are spread over the bucket range instead of all
      // crowding its first few hundred collections at once.
      const offset = (row * BUCKET_STRIPE_STEP) % bucketCount;
      for (let step = 0; step < bucketCount; step += 1) {
        const bucketIndex = (offset + step) % bucketCount;
        writer.set(
          context.entriesCollection(bucketIndex).doc(attempt.id),
          {...entry, stepsAtBucket: series[bucketIndex]}
        );
        writes += 1;
      }
    }

    await writer.flush();
    writer.set(context.summaryRef, {
      [SEED_FINGERPRINT_FIELD]: context.fingerprint,
      [SEED_BUCKET_COUNT_FIELD]: context.maxBucketIndex + 1,
    }, {merge: true});
    await writer.flush();
  }

  await writer.drain();
  progress.finish(`${writes.toLocaleString()} documents written`);
  return writes;
}

/**
 * Rows a previous run left behind that this one no longer plans.
 *
 * Two ways a row is orphaned: its bucket index is past the range this plan
 * publishes, or its attempt index is past the field this plan seeds. Both are
 * read back rather than derived, because a summary written before this field
 * existed cannot say how far the previous run reached.
 * @param {object} context Prepared context.
 * @param {string} seedPackId Pack being written.
 * @param {object} progress Reporter kept alive during enumeration.
 * @return {Promise<object[]>} Document references to delete.
 */
async function retiredRowRefs(context, seedPackId, progress) {
  const plannedIds = new Set(context.rows.map(({attempt}) => attempt.id));
  const bucketRefs = await withRetry(() => context.splitBucketsRef.listDocuments(), {
    description: `listDocuments(${context.splitBucketsRef.path})`,
    onRetry: () => progress.retried(),
  });
  const retiredBuckets = bucketRefs.filter((bucketRef) => {
    const index = Number.parseInt(bucketRef.id, 10);
    return !Number.isInteger(index) || index > context.maxBucketIndex;
  });
  const survivingBuckets = bucketRefs.filter((bucketRef) => !retiredBuckets.includes(bucketRef));

  const [retiredEntries, survivingEntries] = await Promise.all([
    listDocumentsAcross(retiredBuckets.map((ref) => ref.collection("entries")), {progress: null}),
    listDocumentsAcross(survivingBuckets.map((ref) => ref.collection("entries")), {progress: null}),
  ]);
  const finishers = await withRetry(() => context.finishersRef.listDocuments(), {
    description: `listDocuments(${context.finishersRef.path})`,
    onRetry: () => progress.retried(),
  });

  const plannedUserIds = new Set(context.rows.map(({attempt}) => attempt.userId));
  const retired = appendAll([], retiredEntries);
  appendAll(retired, retiredBuckets);
  appendAll(retired, survivingEntries.filter((ref) =>
    !plannedIds.has(ref.id) && isSeededAttemptId(ref.id, seedPackId)));
  appendAll(retired, finishers.filter((ref) =>
    isSyntheticUserId(ref.id) && !plannedUserIds.has(ref.id)));

  return retired;
}

/**
 * Whether one entry document id belongs to this seed pack.
 *
 * Prefix-matched against exactly what `seedAttemptId` builds. A real climber's
 * entry id is their `workoutId`, which never takes this shape, so this is what
 * keeps a clear off rows the seed did not write.
 * @param {string} attemptId Entry document id.
 * @param {string} seedPackId Pack being written.
 * @return {boolean} Whether this pack owns the row.
 */
function isSeededAttemptId(attemptId, seedPackId) {
  return typeof attemptId === "string" &&
    attemptId.startsWith(`seed_${sanitizeContextId(seedPackId)}_`);
}

/**
 * The summary document one context publishes.
 * @param {object} context Prepared context.
 * @param {object} state Shared write state.
 * @return {object} Summary fields.
 */
function summaryWrite(context, {args, now, climbBoards, justClimbBoard, seedPlan}) {
  if (context.contextType === JUST_CLIMB_CONTEXT_TYPE) {
    return {
      bucketIntervalSeconds: BUCKET_INTERVAL_SECONDS,
      completedCount: justClimbBoard.population,
      contextId: JUST_CLIMB_GLOBAL_CONTEXT_ID,
      contextType: JUST_CLIMB_CONTEXT_TYPE,
      replayEntryCount: seedPlan.justClimbPlan.attempts.length,
      schemaVersion: 1,
      seedPackId: args.seedPackId,
      seededAttemptCount: seedPlan.justClimbPlan.attempts.length,
      source: seededSummarySource(justClimbBoard),
      targetStepCount: null,
      totalClimbers: justClimbBoard.population,
      updatedAt: now,
    };
  }

  const plan = context.plan;
  const board = climbBoards.get(plan.climb.id);
  const summary = {
    activityTier: plan.config.activityTier,
    bucketIntervalSeconds: BUCKET_INTERVAL_SECONDS,
    completedCount: board.population,
    contextId: plan.climb.id,
    contextType: LIVE_CLIMB_CONTEXT_TYPE,
    replayEntryCount: plan.attempts.length,
    schemaVersion: 1,
    seedPackId: args.seedPackId,
    seededAttemptCount: plan.attempts.length,
    source: seededSummarySource(board),
    targetStepCount: referenceStepCount(plan.climb),
    // The board population, not the synthetic row count. `replaySummaryWrite`
    // in the Cloud Function writes `totalClimbers = completedCount`, so a seed
    // stamping the attempt count here left the two numbers describing
    // different populations on the same document the moment a real climber
    // finished. `seededAttemptCount` and `replayEntryCount` are where the
    // synthetic row count lives.
    totalClimbers: board.population,
    updatedAt: now,
  };

  return Object.assign(summary, plan.firstAscentAttempt ?
    firstAscentSeedFields(
      plan.firstAscentAttempt,
      firstAscentClaimedAt(args.seedPackId, plan.climb.id)
    ) :
    // An earlier seed may have left a holder here; an open slot has to be
    // genuinely empty for the next finisher to claim it.
    clearedFirstAscentFields(FieldValue.delete()));
}

/**
 * Mirrors `ranksOnSteps` in functions/src/liveReplayLeaderboard.ts.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when higher steps rank better.
 */
function ranksOnSteps(contextType) {
  return contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE;
}

/**
 * The attempt ids one flagged `isBestForUser` row per climber belongs to.
 *
 * The live race filters on that flag on every context type, and Firestore
 * equality never matches a missing field, so a seeded board whose rows omit it
 * renders an empty field however many entries it holds. Mirrors the server's
 * best-per-user rule, including its metric: the most steps where the board
 * ranks on steps, the fastest completion otherwise, ties resolved on the
 * attempt id so every writer picks the same winner.
 * @param {object[]} rows Prepared rows, each carrying its attempt.
 * @param {string} contextType Replay context type.
 * @return {Set<string>} Attempt ids to flag.
 */
function bestAttemptIds(rows, contextType) {
  const onSteps = ranksOnSteps(contextType);
  const valueOf = (attempt) => (onSteps ?
    attempt.finalSteps :
    attempt.completionDurationSeconds);
  const bestByUserId = new Map();

  for (const {attempt} of rows) {
    const best = bestByUserId.get(attempt.userId);
    const beats = best === undefined ||
      (onSteps ?
        valueOf(attempt) > valueOf(best) :
        valueOf(attempt) < valueOf(best));
    const breaksTie = best !== undefined &&
      valueOf(attempt) === valueOf(best) &&
      attempt.id < best.id;

    if (beats || breaksTie) {
      bestByUserId.set(attempt.userId, attempt);
    }
  }

  return new Set([...bestByUserId.values()].map((attempt) => attempt.id));
}

/**
 * One split bucket entry.
 * @param {object} context Prepared context.
 * @param {object} attempt Generated attempt.
 * @param {number} stepsAtBucket Steps this attempt had reached at this bucket.
 * @param {object} state Shared write state.
 * @return {object} Entry fields.
 */
function entryWrite(context, attempt, stepsAtBucket, {seedPackId, now}) {
  const entry = {
    avatarToken: attempt.avatarToken,
    completionDurationSeconds: attempt.completionDurationSeconds,
    contextId: context.contextId,
    contextType: context.contextType,
    displayName: attempt.displayName,
    finalSteps: attempt.finalSteps,
    identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
    isBestForUser: context.bestAttemptIds.has(attempt.id),
    isSynthetic: true,
    photoURL: attempt.photoURL ?? "",
    schemaVersion: 1,
    seedPackId,
    source: "synthetic",
    splitBucketCount: context.maxBucketIndex + 1,
    splitIntervalSeconds: BUCKET_INTERVAL_SECONDS,
    stepsAtBucket,
    updatedAt: now,
    userId: attempt.userId,
    workoutId: attempt.id,
  };

  return entry;
}

async function backfillSeedAvatarURLs(db, args, avatarURLs) {
  const contexts = [
    ...[...ACTIVE_CLIMBS, ...WARM_CLIMBS].map((config) => ({
      label: config.id,
      ref: leaderboardRef(db, config.id),
    })),
    {label: "just-climb-global", ref: justClimbLeaderboardRef(db)},
  ];
  const progress = createProgressReporter({label: "Backfill avatars", unit: "entries"});
  const writer = createBatchWriter(db, {progress});
  let scanned = 0;
  let updated = 0;

  for (const context of contexts) {
    progress.note(context.label);
    const splitBucketRefs = await withRetry(
      () => context.ref.collection("splitBuckets").listDocuments(),
      {description: `listDocuments(${context.ref.path}/splitBuckets)`}
    );

    await runPool(splitBucketRefs, READ_CONCURRENCY, async (splitBucketRef) => {
      const snapshot = await withRetry(
        () => splitBucketRef.collection("entries").where("seedPackId", "==", args.seedPackId).get(),
        {description: `query(${splitBucketRef.path}/entries)`, onRetry: () => progress.retried()}
      );

      for (const document of snapshot.docs) {
        scanned += 1;
        const displayName = document.data().displayName;
        const photoURL = avatarURLForDisplayName(displayName, avatarURLs);
        if (!photoURL || document.data().photoURL === photoURL) {
          continue;
        }

        writer.update(document.ref, {photoURL});
        updated += 1;
      }
    });

    await writer.flush();
  }

  await writer.drain();
  progress.finish(`${updated.toLocaleString()} of ${scanned.toLocaleString()} entries updated`);
  return {scanned, updated};
}

function leaderboardRef(db, climbId) {
  return contextLeaderboardRef(db, LIVE_CLIMB_CONTEXT_TYPE, climbId);
}

function justClimbLeaderboardRef(db) {
  return contextLeaderboardRef(
    db,
    JUST_CLIMB_CONTEXT_TYPE,
    JUST_CLIMB_GLOBAL_CONTEXT_ID
  );
}

function contextLeaderboardRef(db, contextType, contextId) {
  return db
    .collection(LIVE_REPLAY_COLLECTION)
    .doc(contextKey(contextType, contextId));
}

function splitBucketsCollection(db, climbId) {
  return leaderboardRef(db, climbId).collection("splitBuckets");
}

function entriesCollection(db, climbId, bucketIndex) {
  return entriesCollectionForContext(
    db,
    LIVE_CLIMB_CONTEXT_TYPE,
    climbId,
    bucketIndex
  );
}

function justClimbEntriesCollection(db, bucketIndex) {
  return entriesCollectionForContext(
    db,
    JUST_CLIMB_CONTEXT_TYPE,
    JUST_CLIMB_GLOBAL_CONTEXT_ID,
    bucketIndex
  );
}

function finishersCollection(db, climbId) {
  return leaderboardRef(db, climbId).collection("finishers");
}

function justClimbFinishersCollection(db) {
  return justClimbLeaderboardRef(db).collection("finishers");
}

function entriesCollectionForContext(db, contextType, contextId, bucketIndex) {
  return contextLeaderboardRef(db, contextType, contextId)
    .collection("splitBuckets")
    .doc(String(bucketIndex))
    .collection("entries");
}

function stepsAtBucketIndex(attempt, bucketIndex) {
  if (bucketIndex === 0) {
    return 0;
  }

  const elapsedSeconds = bucketIndex * BUCKET_INTERVAL_SECONDS;
  if (elapsedSeconds >= attempt.durationSeconds) {
    return attempt.finalSteps;
  }

  const progress = clamp(elapsedSeconds / attempt.durationSeconds, 0, 1);
  const curvedProgress = Math.pow(progress, attempt.curveExponent);
  const wobble = Math.sin(progress * Math.PI * 3 + attempt.wobblePhase) * 0.018;
  return Math.max(
    0,
    Math.min(attempt.finalSteps, Math.round(attempt.finalSteps * (curvedProgress + wobble)))
  );
}

function referenceStepCount(climb) {
  return positiveInteger(climb.realStairCount) ?? positiveInteger(climb.totalSteps) ?? 1;
}

function displayNameForAttempt(climbId, index) {
  const offset = hashString(climbId) % SEEDED_DISPLAY_NAMES.length;
  if (index < SEEDED_DISPLAY_NAMES.length) {
    return SEEDED_DISPLAY_NAMES[(index + offset) % SEEDED_DISPLAY_NAMES.length];
  }

  return `Climber ${String(index + 1).padStart(3, "0")}`;
}

function avatarURLForDisplayName(displayName, avatarURLs) {
  const index = SEEDED_DISPLAY_NAMES.indexOf(displayName);
  if (index >= 0 && index < avatarURLs.length) {
    return avatarURLs[index];
  }

  return null;
}

function syntheticProfileKey(displayName, photoURL) {
  if (photoURL) {
    return `photo:${photoURL}`;
  }

  return `name:${displayName.trim().toLowerCase()}`;
}

function seedUserId(seedPackId, climbId, index) {
  return `seeded:${seedPackId}:${sanitizeContextId(climbId)}:${index}`;
}

function seedAttemptId(seedPackId, climbId, index) {
  return [
    "seed",
    sanitizeContextId(seedPackId),
    sanitizeContextId(climbId),
    String(index).padStart(4, "0"),
  ].join("_");
}

function contextKey(contextType, contextId) {
  return `${contextType}__${sanitizeContextId(contextId)}`;
}

function sanitizeContextId(value) {
  return String(value).replace(/[^A-Za-z0-9_-]/g, "_");
}

function avatarToken(displayName) {
  const token = displayName
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();

  return token || "A";
}

function randomInRange(rng, min, max) {
  return rng() * (max - min) + min;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function positiveNumber(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  return value;
}

function positiveInteger(value) {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    return null;
  }
  return value;
}

function stringValue(value) {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
