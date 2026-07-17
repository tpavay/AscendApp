#!/usr/bin/env node

/**
 * Live Replay Leaderboard Seed Script
 *
 * Seeds or clears dev/staging replay leaderboard data for Live Climbs using the
 * Firebase Admin SDK. The script writes the read-only public replay indexes:
 *
 * live_replay_leaderboards/{contextKey}/splitBuckets/{bucketIndex}/entries/{entryId}
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

const ACTIVE_CLIMBS = [
  {id: "mount-everest", totalClimbers: 247, replayEntries: 96, completionRate: 0.36},
  {id: "empire-state-building", totalClimbers: 198, replayEntries: 88, completionRate: 0.42},
  {id: "burj-khalifa", totalClimbers: 173, replayEntries: 84, completionRate: 0.34},
  {id: "gateway-arch", totalClimbers: 166, replayEntries: 72, completionRate: 0.48},
  {id: "eiffel-tower", totalClimbers: 156, replayEntries: 72, completionRate: 0.44},
  {id: "petronas-towers", totalClimbers: 142, replayEntries: 68, completionRate: 0.38},
  {id: "cn-tower", totalClimbers: 137, replayEntries: 64, completionRate: 0.36},
  {id: "statue-of-liberty", totalClimbers: 128, replayEntries: 60, completionRate: 0.54},
  {id: "tokyo-skytree", totalClimbers: 118, replayEntries: 56, completionRate: 0.35},
  {id: "marina-bay-sands", totalClimbers: 104, replayEntries: 52, completionRate: 0.46},
];

const WARM_CLIMBS = [
  {id: "space-needle", totalClimbers: 62, replayEntries: 30, completionRate: 0.44},
  {id: "washington-monument", totalClimbers: 58, replayEntries: 28, completionRate: 0.48},
  {id: "willis-tower", totalClimbers: 54, replayEntries: 28, completionRate: 0.36},
  {id: "one-world-trade-center", totalClimbers: 49, replayEntries: 26, completionRate: 0.34},
  {id: "chrysler-building", totalClimbers: 46, replayEntries: 24, completionRate: 0.40},
  {id: "the-shard", totalClimbers: 42, replayEntries: 24, completionRate: 0.40},
  {id: "sagrada-familia", totalClimbers: 39, replayEntries: 22, completionRate: 0.46},
  {id: "acropolis-of-athens", totalClimbers: 36, replayEntries: 20, completionRate: 0.58},
  {id: "elizabeth-tower", totalClimbers: 34, replayEntries: 20, completionRate: 0.58},
  {id: "tokyo-tower", totalClimbers: 32, replayEntries: 20, completionRate: 0.40},
  {id: "shanghai-tower", totalClimbers: 29, replayEntries: 18, completionRate: 0.34},
  {id: "canton-tower", totalClimbers: 27, replayEntries: 18, completionRate: 0.34},
  {id: "leaning-tower-of-pisa", totalClimbers: 24, replayEntries: 16, completionRate: 0.56},
  {id: "cairo-tower", totalClimbers: 23, replayEntries: 16, completionRate: 0.44},
  {id: "sydney-tower", totalClimbers: 21, replayEntries: 16, completionRate: 0.56},
];

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
      avatarFiles.length > 0 &&
      !args.dryRun
    ? await uploadSeedAvatars(avatarFiles, args)
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

function buildSeedPlan(climbsById, paceSamples, args, avatarURLs) {
  const configs = [
    ...ACTIVE_CLIMBS.map((config) => ({...config, activityTier: "active"})),
    ...WARM_CLIMBS.map((config) => ({...config, activityTier: "warm"})),
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
    const maxBucketIndex = bucketLimitForAttempts(attempts);
    const clearAttemptIds = Array.from(
      {length: Math.max(config.replayEntries, completedCount)},
      (_, index) => seedAttemptId(args.seedPackId, climb.id, index)
    );

    return [{
      config,
      climb,
      attempts,
      completedCount,
      clearAttemptIds,
      maxBucketIndex,
      entryDocumentCount: attempts.length * (maxBucketIndex + 1),
    }];
  });

  if (climbPlans.length === 0) {
    throw new Error("No configured seed climbs matched the catalog.");
  }

  const justClimbAttempts = climbPlans.flatMap((plan) => plan.attempts);
  const justClimbClearAttemptIds = climbPlans.flatMap(
    (plan) => plan.clearAttemptIds
  );
  const justClimbMaxBucketIndex = MAX_BUCKET_INDEX;
  const justClimbPlan = {
    attempts: justClimbAttempts,
    clearAttemptIds: justClimbClearAttemptIds,
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
      userId: `seeded:${seedPackId}:${sanitizeContextId(climb.id)}:${index}`,
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
  let deleted = clearSeedEntriesFromPlan(db, writer, seedPlan);
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

    writer.delete(document.ref);
    deleted += 1;
  }

  return deleted;
}

function clearSeedEntriesFromPlan(db, writer, seedPlan) {
  let deleted = 0;

  for (const plan of seedPlan.climbPlans) {
    for (let bucketIndex = 0; bucketIndex <= MAX_BUCKET_INDEX; bucketIndex += 1) {
      for (const attemptId of plan.clearAttemptIds) {
        writer.delete(entriesCollection(db, plan.climb.id, bucketIndex).doc(attemptId));
        deleted += 1;
      }
    }
  }

  for (let bucketIndex = 0; bucketIndex <= MAX_BUCKET_INDEX; bucketIndex += 1) {
    for (const attemptId of seedPlan.justClimbPlan.clearAttemptIds) {
      writer.delete(justClimbEntriesCollection(db, bucketIndex).doc(attemptId));
      deleted += 1;
    }
  }

  return deleted;
}

async function writeSeedPlan(db, seedPlan, args) {
  const writer = bulkWriter(db);
  const now = FieldValue.serverTimestamp();
  let writes = 0;

  for (const plan of seedPlan.climbPlans) {
    const targetSteps = referenceStepCount(plan.climb);
    const summaryRef = leaderboardRef(db, plan.climb.id);
    writer.set(summaryRef, {
      activityTier: plan.config.activityTier,
      bucketIntervalSeconds: BUCKET_INTERVAL_SECONDS,
      completedCount: plan.completedCount,
      contextId: plan.climb.id,
      contextType: LIVE_CLIMB_CONTEXT_TYPE,
      replayEntryCount: plan.attempts.length,
      schemaVersion: 1,
      seedPackId: args.seedPackId,
      seededAttemptCount: plan.attempts.length,
      source: "seeded",
      targetStepCount: targetSteps,
      totalClimbers: plan.attempts.length,
      updatedAt: now,
    }, {merge: true});
    writes += 1;

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
    completedCount: seedPlan.justClimbPlan.attempts.length,
    contextId: JUST_CLIMB_GLOBAL_CONTEXT_ID,
    contextType: JUST_CLIMB_CONTEXT_TYPE,
    replayEntryCount: seedPlan.justClimbPlan.attempts.length,
    schemaVersion: 1,
    seedPackId: args.seedPackId,
    seededAttemptCount: seedPlan.justClimbPlan.attempts.length,
    source: "seeded",
    targetStepCount: null,
    totalClimbers: seedPlan.justClimbPlan.attempts.length,
    updatedAt: now,
  }, {merge: true});
  writes += 1;

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
        // Every synthetic attempt is its own climber, so each is its own best.
        isBestForUser: true,
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

function hashString(value) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function mulberry32(seed) {
  return function random() {
    let value = seed += 0x6D2B79F5;
    value = Math.imul(value ^ value >>> 15, value | 1);
    value ^= value + Math.imul(value ^ value >>> 7, value | 61);
    return ((value ^ value >>> 14) >>> 0) / 4294967296;
  };
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
