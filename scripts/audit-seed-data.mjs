#!/usr/bin/env node

/**
 * Read-only seed audit for dev/staging Firebase data.
 *
 * Usage:
 *   node scripts/audit-seed-data.mjs --project staging --target all
 *   node scripts/dev-db.mjs audit --project staging --target profiles,leaderboard
 */

import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import {
  assertSeedableProject,
  defaultSeedPackId,
  resolveProjectId,
} from "./seed/lib/environments.mjs";
import {
  buildLeaderboardSeedWrites,
  currentPeriod,
  expectedLeaderboardDocIds,
  expectedProfileUserIds,
  PROFILE_SEED_PERSONAS,
  statsFromWorkoutDocuments,
  validateDocumentKeys,
} from "./seed/fixtures/profile-fixtures.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const TARGET_ORDER = ["profiles", "leaderboard", "live-replay", "routine-templates"];
const TARGET_ALIASES = new Map([
  ["all", "all"],
  ["profile", "profiles"],
  ["profiles", "profiles"],
  ["users", "profiles"],
  ["leaderboard", "leaderboard"],
  ["leaderboards", "leaderboard"],
  ["replay", "live-replay"],
  ["live-replay", "live-replay"],
  ["live_replay", "live-replay"],
  ["routine-template", "routine-templates"],
  ["routine-templates", "routine-templates"],
  ["routine_templates", "routine-templates"],
  ["routines", "routine-templates"],
]);

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LEGACY_LEADERBOARD_USER_IDS = Array.from({length: 40}, (_, index) => `test_user_${index + 1}`);
const LEGACY_TIME_FRAMES = ["daily", "weekly", "monthly", "yearly", "all_time"];

function parseArgs(argv) {
  const args = {project: "dev", targets: ["all"]};
  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--target" || value === "--targets") {
      args.targets = requireValue(argv, ++index, value).split(",").map((target) => target.trim());
    } else if (value === "--help" || value === "-h") {
      args.help = true;
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }
  return args;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value`);
  return value;
}

function printHelp() {
  console.log(`
Usage:
  node scripts/audit-seed-data.mjs --project staging --target all
  node scripts/audit-seed-data.mjs --project dev --target profiles,leaderboard
`);
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    return;
  }

  const projectId = resolveProjectId(args.project, REPO_ROOT);
  assertSeedableProject(projectId, "audit");
  const targets = resolveTargets(args.targets);

  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();
  const catalog = loadCatalog();
  const failures = [];
  const summaries = [];

  console.log(`Project: ${projectId}`);
  console.log(`Audit targets: ${targets.join(", ")}`);

  if (targets.includes("profiles")) {
    summaries.push(await auditProfiles(db, failures));
  }
  if (targets.includes("leaderboard")) {
    summaries.push(await auditLeaderboard(db, catalog, failures));
  }
  if (targets.includes("live-replay")) {
    summaries.push(await auditLiveReplay(db, projectId, failures));
  }
  if (targets.includes("routine-templates")) {
    summaries.push(await auditRoutineTemplates(db, projectId, failures));
  }

  console.log("\nAudit summary:");
  summaries.forEach((summary) => console.log(`  ${summary}`));

  if (failures.length > 0) {
    console.error("\nSeed audit failed:");
    failures.slice(0, 80).forEach((failure) => console.error(`  - ${failure}`));
    if (failures.length > 80) {
      console.error(`  ...and ${failures.length - 80} more`);
    }
    process.exit(1);
  }

  console.log("\nSeed audit passed.");
}

function resolveTargets(rawTargets) {
  const selected = new Set();
  for (const rawTarget of rawTargets) {
    const target = TARGET_ALIASES.get(rawTarget);
    if (!target) {
      throw new Error(`Unknown target "${rawTarget}". Use profiles, leaderboard, live-replay, routine-templates, or all.`);
    }
    if (target === "all") {
      TARGET_ORDER.forEach((item) => selected.add(item));
    } else {
      selected.add(target);
    }
  }
  return TARGET_ORDER.filter((target) => selected.has(target));
}

function loadCatalog() {
  const raw = JSON.parse(readFileSync(resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"), "utf-8"));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

async function auditProfiles(db, failures) {
  let documentsChecked = 0;

  for (const userId of expectedProfileUserIds()) {
    const userRef = db.collection("users").doc(userId);
    const userSnapshot = await userRef.get();
    const publicSnapshot = await userRef.collection("public_profile").doc("current").get();
    const statsSnapshot = await userRef.collection("profile_stats").doc("current").get();
    const workoutsSnapshot = await userRef.collection("profile_workouts").get();

    documentsChecked += 3 + workoutsSnapshot.size;

    const user = expectDocument(userSnapshot, `users/${userId}`, failures);
    const publicProfile = expectDocument(publicSnapshot, `users/${userId}/public_profile/current`, failures);
    const stats = expectDocument(statsSnapshot, `users/${userId}/profile_stats/current`, failures);

    if (user) {
      validateDocumentKeys(`users/${userId}`, user, "user", failures);
      requirePresent(user, "height_cm", `users/${userId}`, failures);
      requirePresent(user, "weight_kg", `users/${userId}`, failures);
    }
    if (publicProfile) {
      validateDocumentKeys(`users/${userId}/public_profile/current`, publicProfile, "publicProfile", failures);
      requirePresent(publicProfile, "height_cm", `users/${userId}/public_profile/current`, failures);
      requirePresent(publicProfile, "weight_kg", `users/${userId}/public_profile/current`, failures);
    }
    if (stats) {
      validateDocumentKeys(`users/${userId}/profile_stats/current`, stats, "profileStats", failures);
    }

    const workouts = workoutsSnapshot.docs.map((doc) => {
      const data = doc.data();
      const path = `users/${userId}/profile_workouts/${doc.id}`;
      validateDocumentKeys(path, data, "profileWorkout", failures);
      if (data.climbId === "") failures.push(`${path} has empty climbId`);
      if (data.climbCompletionStatus === "completed") {
        requirePresent(data, "climbId", path, failures);
        if (!positiveNumber(data.climbCompletionDurationSeconds)) {
          failures.push(`${path} completed climb is missing positive climbCompletionDurationSeconds`);
        }
      }
      return data;
    });

    if (stats) {
      compareDerivedStats(userId, stats, statsFromWorkoutDocuments(workouts), failures);
    }
  }

  return `profiles: ${PROFILE_SEED_PERSONAS.length} users, ${documentsChecked} profile documents checked`;
}

async function auditLeaderboard(db, catalog, failures) {
  const expectedWrites = buildLeaderboardSeedWrites({
    db,
    catalog,
    Timestamp,
    FieldValue,
  });
  const expectedIds = new Set(expectedWrites.map((item) => item.ref.id));
  let checked = 0;

  for (const writeItem of expectedWrites) {
    const snapshot = await writeItem.ref.get();
    const path = `leaderboard_stats/${writeItem.ref.id}`;
    const data = expectDocument(snapshot, path, failures);
    if (!data) continue;
    checked += 1;

    validateDocumentKeys(path, data, "leaderboardStats", failures);
    if (data.userId && !expectedProfileUserIds().includes(data.userId)) {
      failures.push(`${path} points at non-profile fixture user ${data.userId}`);
    }
    if (data.userId && writeItem.ref.id !== `${data.userId}_${data.timeFrame}`) {
      failures.push(`${path} id does not match userId/timeFrame`);
    }
    if (data.schemaVersion !== 2) {
      failures.push(`${path} schemaVersion must be 2`);
    }
    if (data.timeFrame) {
      const period = currentPeriod(data.timeFrame);
      if (data.periodKey !== period.key) {
        failures.push(`${path} has stale periodKey ${data.periodKey}; expected ${period.key}`);
      }
    }
    if (data.userId) {
      const publicSnapshot = await db
        .collection("users")
        .doc(data.userId)
        .collection("public_profile")
        .doc("current")
        .get();
      if (!publicSnapshot.exists) {
        failures.push(`${path} userId ${data.userId} has no public profile`);
      }
    }
  }

  for (const docId of expectedLeaderboardDocIds()) {
    if (expectedIds.has(docId)) continue;
    const snapshot = await db.collection("leaderboard_stats").doc(docId).get();
    if (snapshot.exists) {
      failures.push(`leaderboard_stats/${docId} should not exist for a zero-step seeded user`);
    }
  }

  for (const userId of LEGACY_LEADERBOARD_USER_IDS) {
    for (const timeFrame of LEGACY_TIME_FRAMES) {
      const docId = `${userId}_${timeFrame}`;
      const snapshot = await db.collection("leaderboard_stats").doc(docId).get();
      if (snapshot.exists) {
        failures.push(`leaderboard_stats/${docId} is legacy orphan leaderboard data; clear/reseed leaderboard`);
      }
    }
  }

  return `leaderboard: ${checked} current persona rows checked`;
}

async function auditLiveReplay(db, projectId, failures) {
  const seedPackId = defaultSeedPackId("live-replay", projectId);
  const snapshot = await db
    .collection(LIVE_REPLAY_COLLECTION)
    .where("seedPackId", "==", seedPackId)
    .get();

  if (snapshot.empty) {
    failures.push(`live replay seed pack ${seedPackId} has no summaries`);
    return "live-replay: 0 summaries checked";
  }

  let bucketZeroEntries = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const path = `${LIVE_REPLAY_COLLECTION}/${doc.id}`;
    requirePresent(data, "contextType", path, failures);
    requirePresent(data, "contextId", path, failures);
    requirePresent(data, "completedCount", path, failures);
    requirePresent(data, "totalClimbers", path, failures);
    requirePresent(data, "replayEntryCount", path, failures);
    requirePresent(data, "bucketIntervalSeconds", path, failures);

    if (!positiveNumber(data.completedCount)) failures.push(`${path} completedCount must be positive`);
    if (!positiveNumber(data.totalClimbers)) failures.push(`${path} totalClimbers must be positive`);
    if (!positiveNumber(data.replayEntryCount)) failures.push(`${path} replayEntryCount must be positive`);

    const bucketZero = await doc.ref.collection("splitBuckets").doc("0").collection("entries").get();
    bucketZeroEntries += bucketZero.size;
    if (bucketZero.empty) {
      failures.push(`${path}/splitBuckets/0 has no entries`);
      continue;
    }

    for (const entry of bucketZero.docs) {
      const entryData = entry.data();
      const entryPath = `${path}/splitBuckets/0/entries/${entry.id}`;
      ["completionDurationSeconds", "contextId", "contextType", "displayName", "finalSteps", "schemaVersion", "splitIntervalSeconds", "stepsAtBucket", "userId", "workoutId"].forEach((field) => {
        requirePresent(entryData, field, entryPath, failures);
      });
      if (entryData.stepsAtBucket !== 0) failures.push(`${entryPath} bucket 0 stepsAtBucket must be 0`);
      if (!positiveNumber(entryData.completionDurationSeconds)) failures.push(`${entryPath} completionDurationSeconds must be positive`);
      if (!positiveNumber(entryData.finalSteps)) failures.push(`${entryPath} finalSteps must be positive`);
    }
  }

  return `live-replay: ${snapshot.size} summaries, ${bucketZeroEntries} bucket-zero entries checked`;
}

async function auditRoutineTemplates(db, projectId, failures) {
  const seedPackId = defaultSeedPackId("routine-templates", projectId);
  const snapshot = await db
    .collection("routine_templates")
    .where("seedPackId", "==", seedPackId)
    .get();

  if (snapshot.empty) {
    failures.push(`routine template seed pack ${seedPackId} has no templates`);
  }

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const path = `routine_templates/${doc.id}`;
    ["templateId", "name", "status", "version", "intervals", "seedPackId", "updatedAt"].forEach((field) => {
      requirePresent(data, field, path, failures);
    });
    if (data.templateId !== doc.id) {
      failures.push(`${path} templateId does not match document ID`);
    }
    if (!Array.isArray(data.intervals) || data.intervals.length === 0) {
      failures.push(`${path} has no routine intervals`);
    }
  }

  return `routine-templates: ${snapshot.size} templates checked`;
}

function expectDocument(snapshot, path, failures) {
  if (!snapshot.exists) {
    failures.push(`${path} is missing`);
    return null;
  }
  return snapshot.data();
}

function requirePresent(data, field, path, failures) {
  if (data[field] === undefined || data[field] === null || data[field] === "") {
    failures.push(`${path} missing ${field}`);
  }
}

function compareDerivedStats(userId, actual, expected, failures) {
  const path = `users/${userId}/profile_stats/current`;
  [
    "total_climbs_completed",
    "lifetime_total_steps",
    "lifetime_duration_seconds",
    "total_climbs",
    "pr_most_steps",
    "pr_longest_climb_seconds",
  ].forEach((field) => {
    if (integerValue(actual[field]) !== integerValue(expected[field])) {
      failures.push(`${path} ${field}=${actual[field]} does not match workouts (${expected[field]})`);
    }
  });

  [
    "average_steps_per_minute",
    "pr_highest_spm",
  ].forEach((field) => {
    if (!nearlyEqual(numberValue(actual[field]), numberValue(expected[field]), 0.01)) {
      failures.push(`${path} ${field}=${actual[field]} does not match workouts (${expected[field]})`);
    }
  });
}

function positiveNumber(value) {
  return Number.isFinite(Number(value)) && Number(value) > 0;
}

function integerValue(value) {
  return Number.isFinite(Number(value)) ? Math.trunc(Number(value)) : 0;
}

function numberValue(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function nearlyEqual(lhs, rhs, tolerance) {
  return Math.abs(lhs - rhs) <= tolerance;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
