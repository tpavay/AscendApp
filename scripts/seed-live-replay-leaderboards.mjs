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

import {randomUUID} from "node:crypto";
import {readFileSync, readdirSync, statSync} from "node:fs";
import {dirname, extname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {hashString, mulberry32} from "./seed/lib/deterministic.mjs";
import {
  FIRST_ASCENT_OPEN_ACTIVITY_TIER,
  PUBLIC_IDENTITY_STATE_PUBLISHED,
  assertFirstAscentInvariant,
  clearOpenFirstAscentEntries,
  clearOpenFirstAscentFinishers,
  clearedFirstAscentFields,
  firstAscentClaimedAt,
  firstAscentSeedFields,
  isOpenFirstAscentSummary,
} from "./seed/lib/live-replay-first-ascent.mjs";
import {
  syntheticFinisherWrite,
} from "./seed/lib/live-replay-finisher.mjs";
import {
  seededSummarySource,
} from "./seed/lib/live-replay-summary-source.mjs";
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
 * So this stays the same length as the uploaded avatar set (83), and no climb
 * seeds more finishers than that - `assertSeededIdentitySupply` enforces both,
 * because the failure is invisible until it is on a screenshot.
 */
const SEEDED_DISPLAY_NAMES = [
  "Sarah K.", "Marcus T.", "Jenny W.", "Alex M.", "Priya S.", "Jordan L.",
  "Nina R.", "Owen B.", "Maya C.", "Eli P.", "Sam D.", "Taylor H.",
  "Ari N.", "Chris V.", "Riley F.", "Noah G.", "Ava M.", "Leo S.",
  "Mia L.", "Ben C.", "Ivy R.", "Theo J.", "Lena P.", "Kai W.",
  "Nora B.", "Cole A.", "Zara T.", "Miles K.", "Eva D.", "Jules R.",
  "Drew S.", "Iris M.", "Cal N.", "Tessa V.", "Remy P.", "Sage L.",
  "Quinn E.", "Omar H.", "Gia F.", "Finn R.", "Ana C.", "Max W.",
  "Ruby N.", "Jace M.", "Elle K.", "Sean P.", "Vera L.", "Hugo T.",
  "Luca S.", "Mila B.", "Nate R.", "Lia P.", "Ezra K.", "June V.",
  "Rae C.", "Ty D.", "Skye M.", "Amir N.", "Hope J.", "Kira W.",
  "Dana O.", "Pablo G.", "Yuki T.", "Marta L.", "Isaac B.", "Freya N.",
  "Andre P.", "Sofia R.", "Ravi M.", "Clara V.", "Emeka O.", "Anya D.",
  "Tobias H.", "Nadia F.", "Liam C.", "Rosa E.", "Kenji A.", "Greta S.",
  "Malik J.", "Ines B.", "Oscar W.", "Talia K.", "Devon R.",
];

function parseArgs(argv) {
  const args = {
    command: argv[2] ?? "help",
    project: "dev",
    dryRun: false,
    skipClear: false,
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
        args.skipClear = true;
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
  --skip-clear                          Do not clear existing entries for the seed pack before seeding.
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

  if (args.command === "clear") {
    const deleted = await clearSeedPack(db, seedPlan, args);
    console.log(`Cleared ${deleted.toLocaleString()} seeded replay entries.`);
    return;
  }

  if (!args.skipClear) {
    const deleted = await clearSeedPack(db, seedPlan, args);
    console.log(`Cleared ${deleted.toLocaleString()} existing seeded replay entries.`);
  }

  const written = await writeSeedPlan(db, seedPlan, args);
  console.log(`Seeded ${written.toLocaleString()} Firestore documents into ${projectId}.`);
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
    return uploadSeedAvatars(avatarFiles, args);
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
  const prefix = `live-replay-avatars/${sanitizeContextId(args.seedPackId)}/`;
  const [files] = await bucket.getFiles({prefix});

  return files
    .filter((file) => file.metadata.metadata?.firebaseStorageDownloadTokens)
    .sort((lhs, rhs) => lhs.name.localeCompare(rhs.name))
    .map((file) => downloadURL(
      bucket.name,
      file.name,
      String(file.metadata.metadata.firebaseStorageDownloadTokens).split(",")[0]
    ));
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

async function clearSeedPack(db, seedPlan, args) {
  const writer = bulkWriter(db);
  let deleted = await clearSeedEntriesFromPlan(
    db,
    writer,
    seedPlan,
    args.seedPackId
  );
  const activeContextKeys = contextKeysForPlan(seedPlan);
  deleted += await clearStaleSeedContexts(
    db,
    writer,
    args.seedPackId,
    activeContextKeys
  );

  const now = FieldValue.serverTimestamp();
  for (const plan of seedPlan.climbPlans) {
    const ref = leaderboardRef(db, plan.climb.id);
    writer.set(ref, {
      completedCount: 0,
      replayEntryCount: 0,
      seedPackId: args.seedPackId,
      seededAttemptCount: 0,
      totalClimbers: 0,
      updatedAt: now,
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
  }, {merge: true});

  await writer.close();
  return deleted;
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

async function clearStaleSeedContexts(db, writer, seedPackId, activeContextKeys) {
  const snapshot = await db
    .collection(LIVE_REPLAY_COLLECTION)
    .where("seedPackId", "==", seedPackId)
    .get();
  let deleted = 0;

  for (const document of snapshot.docs) {
    if (activeContextKeys.has(document.id)) {
      continue;
    }

    const splitBucketRefs = await document.ref.collection("splitBuckets").listDocuments();
    for (const splitBucketRef of splitBucketRefs) {
      const entries = await splitBucketRef
        .collection("entries")
        .where("seedPackId", "==", seedPackId)
        .get();
      for (const entry of entries.docs) {
        writer.delete(entry.ref);
        deleted += 1;
      }
    }

    const finishers = await document.ref
      .collection("finishers")
      .where("seedPackId", "==", seedPackId)
      .get();
    for (const finisher of finishers.docs) {
      writer.delete(finisher.ref);
      deleted += 1;
    }

    writer.delete(document.ref);
    deleted += 1;
  }

  return deleted;
}

/**
 * Deletes every row this pack has ever put in the global Just Climb context.
 *
 * Found by query rather than by derived id, unlike the per-climb boards. The
 * global context carries one row per attempt on *every* seeded climb, so its
 * contents outlive the climb list: retiring a climb takes its own board away
 * with `clearStaleSeedContexts`, but its attempts stay here, under ids the
 * current plan can no longer name. Staging accumulated 424 of them from eight
 * retired climbs, which is what failed the audit - `replayEntryCount` said 903
 * while 1,327 rows carried this pack's id.
 *
 * The clear runs before the write, so taking out everything with this pack's id
 * is safe: the seed puts the current rows straight back, and a real climber's
 * rows carry no `seedPackId` at all.
 * @param {object} db Firestore instance.
 * @param {object} writer BulkWriter that performs the deletes.
 * @param {object} seedPlan Built seed plan.
 * @return {Promise<number>} Count of entry documents deleted.
 */
async function clearJustClimbSeedRows(db, writer, seedPlan, seedPackId) {
  let deleted = 0;

  for (
    let bucketIndex = 0;
    bucketIndex <= seedPlan.justClimbPlan.maxBucketIndex;
    bucketIndex += 1
  ) {
    const entries = await justClimbEntriesCollection(db, bucketIndex)
      .where("seedPackId", "==", seedPackId)
      .get();
    for (const entry of entries.docs) {
      writer.delete(entry.ref);
      deleted += 1;
    }
  }

  const finishers = await justClimbFinishersCollection(db)
    .where("seedPackId", "==", seedPackId)
    .get();
  for (const finisher of finishers.docs) {
    writer.delete(finisher.ref);
    deleted += 1;
  }

  return deleted;
}

async function clearSeedEntriesFromPlan(db, writer, seedPlan, seedPackId) {
  let deleted = 0;

  for (const plan of seedPlan.climbPlans) {
    if (isOpenFirstAscentSummary({
      completedCount: plan.completedCount,
      hasFirstAscent: plan.firstAscentAttempt !== null,
    })) {
      deleted += await clearOpenFirstAscentEntries(
        splitBucketsCollection(db, plan.climb.id),
        writer
      );
      deleted += await clearOpenFirstAscentFinishers(
        finishersCollection(db, plan.climb.id),
        writer
      );
      continue;
    }

    for (let bucketIndex = 0; bucketIndex <= MAX_BUCKET_INDEX; bucketIndex += 1) {
      for (const attemptId of plan.clearAttemptIds) {
        writer.delete(entriesCollection(db, plan.climb.id, bucketIndex).doc(attemptId));
        deleted += 1;
      }
    }

    for (const userId of plan.clearUserIds) {
      writer.delete(finishersCollection(db, plan.climb.id).doc(userId));
      deleted += 1;
    }
  }

  deleted += await clearJustClimbSeedRows(db, writer, seedPlan, seedPackId);

  return deleted;
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
 * @return {Promise<object>} Per-climb board states and the Just Climb state.
 */
async function resolveSeededCompletedCounts(db, seedPlan) {
  const climbBoards = new Map();

  for (const plan of seedPlan.climbPlans) {
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
  }

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
  const surviving = await finishersRef.listDocuments();
  const userIds = new Set(surviving.map((document) => document.id));
  for (const userId of seededUserIds) {
    userIds.add(userId);
  }

  return {
    population: Math.max(plannedCount, userIds.size),
    survivingFinisherIds: Array.from(userIds),
  };
}

async function writeSeedPlan(db, seedPlan, args) {
  const writer = bulkWriter(db);
  const now = FieldValue.serverTimestamp();
  const {climbBoards, justClimbBoard} = await resolveSeededCompletedCounts(
    db,
    seedPlan
  );
  let writes = 0;

  for (const plan of seedPlan.climbPlans) {
    const targetSteps = referenceStepCount(plan.climb);
    const summaryRef = leaderboardRef(db, plan.climb.id);
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
      targetStepCount: targetSteps,
      // The board population, not the synthetic row count. `replaySummaryWrite`
      // in the Cloud Function writes `totalClimbers = completedCount`, so a seed
      // stamping the attempt count here left the two numbers describing
      // different populations on the same document the moment a real climber
      // finished. `seededAttemptCount` and `replayEntryCount` are where the
      // synthetic row count lives.
      totalClimbers: board.population,
      updatedAt: now,
    };

    Object.assign(summary, plan.firstAscentAttempt ?
      firstAscentSeedFields(
        plan.firstAscentAttempt,
        firstAscentClaimedAt(args.seedPackId, plan.climb.id)
      ) :
      // An earlier seed may have left a holder here; an open slot has to be
      // genuinely empty for the next finisher to claim it.
      clearedFirstAscentFields(FieldValue.delete()));

    writer.set(summaryRef, summary, {merge: true});
    writes += 1;

    // A publish writes a finisher document in the same transaction as the row,
    // and the rank frozen on a finished climb counts those documents. A seeded
    // board carrying entries but no finishers reads as an empty field, so it
    // would freeze a mid-field climber at "1st of 84".
    for (const [index, attempt] of plan.attempts.entries()) {
      writer.set(
        finishersCollection(db, plan.climb.id).doc(attempt.userId),
        syntheticFinisherWrite(attempt, {
          contextType: LIVE_CLIMB_CONTEXT_TYPE,
          globalCompletionOrder: index + 1,
          identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
          schemaVersion: 1,
          seedPackId: args.seedPackId,
          updatedAt: now,
        })
      );
      writes += 1;
    }

    for (let bucketIndex = 0; bucketIndex <= plan.maxBucketIndex; bucketIndex += 1) {
      for (const attempt of plan.attempts) {
        const entryRef = entriesCollection(db, plan.climb.id, bucketIndex).doc(attempt.id);
        const stepsAtBucket = stepsAtBucketIndex(attempt, bucketIndex);
        writer.set(entryRef, {
          avatarToken: attempt.avatarToken,
          completionDurationSeconds: attempt.completionDurationSeconds,
          contextId: plan.climb.id,
          contextType: LIVE_CLIMB_CONTEXT_TYPE,
          displayName: attempt.displayName,
          finalSteps: attempt.finalSteps,
          // Every synthetic attempt is its own climber, so each is its own best.
          identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
          isBestForUser: true,
          isSynthetic: true,
          photoURL: attempt.photoURL ?? "",
          schemaVersion: 1,
          seedPackId: args.seedPackId,
          source: "synthetic",
          splitBucketCount: plan.maxBucketIndex + 1,
          splitIntervalSeconds: BUCKET_INTERVAL_SECONDS,
          stepsAtBucket,
          updatedAt: now,
          userId: attempt.userId,
          workoutId: attempt.id,
        });
        writes += 1;
      }
    }
  }

  writer.set(justClimbLeaderboardRef(db), {
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
  }, {merge: true});
  writes += 1;

  // The open race ranks attempts, not climbers, so its finishers are not in the
  // frozen rank's numerator. They still stand for the same climbers the summary
  // counts, and a real publish writes one, so the fixture writes one too.
  for (const [index, attempt] of seedPlan.justClimbPlan.attempts.entries()) {
    writer.set(
      justClimbFinishersCollection(db).doc(attempt.userId),
      syntheticFinisherWrite(attempt, {
        contextType: JUST_CLIMB_CONTEXT_TYPE,
        globalCompletionOrder: index + 1,
        identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
        schemaVersion: 1,
        seedPackId: args.seedPackId,
        updatedAt: now,
      })
    );
    writes += 1;
  }

  for (
    let bucketIndex = 0;
    bucketIndex <= seedPlan.justClimbPlan.maxBucketIndex;
    bucketIndex += 1
  ) {
    for (const attempt of seedPlan.justClimbPlan.attempts) {
      const entryRef = justClimbEntriesCollection(db, bucketIndex)
        .doc(attempt.id);
      const stepsAtBucket = stepsAtBucketIndex(attempt, bucketIndex);
      writer.set(entryRef, {
        avatarToken: attempt.avatarToken,
        completionDurationSeconds: attempt.completionDurationSeconds,
        contextId: JUST_CLIMB_GLOBAL_CONTEXT_ID,
        contextType: JUST_CLIMB_CONTEXT_TYPE,
        displayName: attempt.displayName,
        finalSteps: attempt.finalSteps,
        // No isBestForUser: the open Just Climb race has no step target, so it
        // races every completed attempt as its own opponent rather than
        // collapsing a climber's repeats onto a "fastest" one.
        identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
        isSynthetic: true,
        photoURL: attempt.photoURL ?? "",
        schemaVersion: 1,
        seedPackId: args.seedPackId,
        source: "synthetic",
        splitBucketCount: seedPlan.justClimbPlan.maxBucketIndex + 1,
        splitIntervalSeconds: BUCKET_INTERVAL_SECONDS,
        stepsAtBucket,
        updatedAt: now,
        userId: attempt.userId,
        workoutId: attempt.id,
      });
      writes += 1;
    }
  }

  await writer.close();
  return writes;
}

async function backfillSeedAvatarURLs(db, args, avatarURLs) {
  const writer = bulkWriter(db);
  const contexts = [
    ...[...ACTIVE_CLIMBS, ...WARM_CLIMBS].map((config) => ({
      label: config.id,
      ref: leaderboardRef(db, config.id),
    })),
    {
      label: "just-climb-global",
      ref: justClimbLeaderboardRef(db),
    },
  ];
  let scanned = 0;
  let updated = 0;

  for (const context of contexts) {
    const contextScannedStart = scanned;
    const contextUpdatedStart = updated;
    const splitBucketRefs = await context.ref
      .collection("splitBuckets")
      .listDocuments();
    console.log(`Scanning ${context.label} (${splitBucketRefs.length} buckets)`);

    for (const splitBucketRef of splitBucketRefs) {
      const snapshot = await splitBucketRef
        .collection("entries")
        .where("seedPackId", "==", args.seedPackId)
        .get();

      for (const document of snapshot.docs) {
        scanned += 1;
        const data = document.data();
        const displayName = stringValue(data.displayName);
        const photoURL = displayName
          ? avatarURLForDisplayName(displayName, avatarURLs)
          : null;

        if (photoURL && stringValue(data.photoURL) !== photoURL) {
          writer.update(document.ref, {
            photoURL,
            updatedAt: FieldValue.serverTimestamp(),
          });
          updated += 1;
        }
      }
    }

    console.log(
      `  ${context.label}: ` +
        `${(updated - contextUpdatedStart).toLocaleString()} updated, ` +
        `${(scanned - contextScannedStart).toLocaleString()} scanned`
    );
  }

  await writer.close();
  return {scanned, updated};
}

function bulkWriter(db) {
  const writer = db.bulkWriter();
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) {
      return true;
    }
    console.error(`Bulk write failed after ${error.failedAttempts} attempts: ${error.message}`);
    return false;
  });
  return writer;
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
