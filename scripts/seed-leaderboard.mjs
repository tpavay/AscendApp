#!/usr/bin/env node

/**
 * Leaderboard Seed Script
 *
 * Seeds or clears multi-user leaderboard test data using the Firebase Admin SDK
 * (bypasses Firestore security rules).
 *
 * This script must match the app's current leaderboard schema:
 * - one current-period doc per user per timeframe
 * - Monday-based weekly periods
 * - UTC period windowing
 * - canonical steps-based pace field (`stepsPerMinute`)
 *
 * Usage:
 *   node scripts/seed-leaderboard.mjs seed --project dev
 *   node scripts/seed-leaderboard.mjs clear --project dev
 *   node scripts/seed-leaderboard.mjs seed --project dev --dry-run
 *
 * Prerequisites:
 *   cd scripts && npm install
 *   gcloud auth application-default login
 */

import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const COLLECTION = "leaderboard_stats";
const BATCH_LIMIT = 500; // Firestore batch write limit
const SCHEMA_VERSION = 2;

const TEST_USERS = [
  { id: "test_user_1", name: "Sarah Johnson" },
  { id: "test_user_2", name: "Mike Chen" },
  { id: "test_user_3", name: "Emma Davis" },
  { id: "test_user_4", name: "James Wilson" },
  { id: "test_user_5", name: "Olivia Martinez" },
  { id: "test_user_6", name: "Noah Brown" },
  { id: "test_user_7", name: "Ava Garcia" },
  { id: "test_user_8", name: "Liam Anderson" },
  { id: "test_user_9", name: "Sophia Taylor" },
  { id: "test_user_10", name: "Ethan Moore" },
  { id: "test_user_11", name: "Isabella Thomas" },
  { id: "test_user_12", name: "Mason Jackson" },
  { id: "test_user_13", name: "Mia White" },
  { id: "test_user_14", name: "Lucas Harris" },
  { id: "test_user_15", name: "Charlotte Clark" },
  { id: "test_user_16", name: "Logan Ramirez" },
  { id: "test_user_17", name: "Grace Nguyen" },
  { id: "test_user_18", name: "Benjamin Rivera" },
  { id: "test_user_19", name: "Harper Bennett" },
  { id: "test_user_20", name: "Elijah Bell" },
  { id: "test_user_21", name: "Amelia Foster" },
  { id: "test_user_22", name: "Henry Powell" },
  { id: "test_user_23", name: "Chloe Hughes" },
  { id: "test_user_24", name: "Sebastian Cox" },
  { id: "test_user_25", name: "Victoria Baker" },
  { id: "test_user_26", name: "Caleb Ross" },
  { id: "test_user_27", name: "Penelope Ortiz" },
  { id: "test_user_28", name: "Wyatt Peterson" },
  { id: "test_user_29", name: "Luna Ramirez" },
  { id: "test_user_30", name: "Ezra Murphy" },
  { id: "test_user_31", name: "Aria Lopez" },
  { id: "test_user_32", name: "Hudson Kelly" },
  { id: "test_user_33", name: "Layla Cooper" },
  { id: "test_user_34", name: "Jack Phillips" },
  { id: "test_user_35", name: "Ellie Ward" },
  { id: "test_user_36", name: "Daniel Brooks" },
  { id: "test_user_37", name: "Nora Gray" },
  { id: "test_user_38", name: "Levi Jenkins" },
  { id: "test_user_39", name: "Zoe Russell" },
  { id: "test_user_40", name: "Gabriel Perry" },
];

const TIME_FRAMES = [
  { key: "weekly", multiplier: 1 },
  { key: "monthly", multiplier: 4 },
  { key: "yearly", multiplier: 48 },
  { key: "all_time", multiplier: 100 },
];

const AVATAR_BACKGROUNDS = [
  "1D4ED8", // blue
  "0F766E", // teal
  "B45309", // amber
  "7C3AED", // violet
  "BE123C", // rose
  "166534", // green
  "0E7490", // cyan
  "4338CA", // indigo
];

// ---------------------------------------------------------------------------
// Period logic — matches LeaderboardTimeFrame.swift
// ---------------------------------------------------------------------------

function utcDate(year, month, day) {
  return new Date(Date.UTC(year, month, day));
}

/**
 * Normalizes a date to 00:00:00 UTC.
 */
function startOfUTCDay(date) {
  return utcDate(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

/**
 * Monday-based week start, matching WeekConfiguration.calendar(timeZone: .gmt)
 * with firstWeekday = 2 and minimumDaysInFirstWeek = 1.
 */
function startOfWeekUTC(date) {
  const start = startOfUTCDay(date);
  const daysSinceMonday = (start.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - daysSinceMonday);
  return start;
}

function weekInfoUTC(date) {
  const normalizedDate = startOfUTCDay(date);
  const weekStart = startOfWeekUTC(normalizedDate);
  const calendarYear = normalizedDate.getUTCFullYear();

  const firstWeekStart = startOfWeekUTC(utcDate(calendarYear, 0, 1));
  if (weekStart < firstWeekStart) {
    return weekInfoUTC(utcDate(calendarYear - 1, 11, 31));
  }

  const nextYearFirstWeekStart = startOfWeekUTC(utcDate(calendarYear + 1, 0, 1));
  if (weekStart >= nextYearFirstWeekStart) {
    return {
      year: calendarYear + 1,
      week: 1,
      startAt: weekStart,
    };
  }

  const diffMs = weekStart.getTime() - firstWeekStart.getTime();
  const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));
  return {
    year: calendarYear,
    week: Math.floor(diffDays / 7) + 1,
    startAt: weekStart,
  };
}

function currentPeriod(timeFrameKey, date = new Date()) {
  switch (timeFrameKey) {
    case "weekly": {
      const { year, week, startAt } = weekInfoUTC(date);
      return {
        key: `${year}-W${String(week).padStart(2, "0")}`,
        startAt,
      };
    }
    case "monthly": {
      const year = date.getUTCFullYear();
      const month = date.getUTCMonth() + 1;
      return {
        key: `${year}-M${String(month).padStart(2, "0")}`,
        startAt: utcDate(year, month - 1, 1),
      };
    }
    case "yearly": {
      const year = date.getUTCFullYear();
      return {
        key: `${year}`,
        startAt: utcDate(year, 0, 1),
      };
    }
    case "all_time":
      return {
        key: "all",
        startAt: new Date(0),
      };
    default:
      throw new Error(`Unknown time frame: ${timeFrameKey}`);
  }
}

// ---------------------------------------------------------------------------
// Random stats generation — matches Swift logic
// ---------------------------------------------------------------------------

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomDouble(min, max) {
  return Math.random() * (max - min) + min;
}

function hashString(value) {
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    hash = (hash * 31 + value.charCodeAt(i)) >>> 0;
  }
  return hash;
}

function avatarURL(name) {
  const index = hashString(name) % AVATAR_BACKGROUNDS.length;
  const background = AVATAR_BACKGROUNDS[index];
  const params = new URLSearchParams({
    name,
    size: "200",
    background,
    color: "fff",
    bold: "true",
    format: "png",
  });

  return `https://ui-avatars.com/api/?${params.toString()}`;
}

function generateStats(multiplier) {
  const baseWorkouts = randomInt(3, 7);
  const baseStepsPerWorkout = randomInt(800, 2500);
  const baseFloorsPerWorkout = randomInt(10, 60);
  const baseDurationPerWorkout = randomDouble(15, 45) * 60; // seconds

  const totalWorkouts = Math.floor(baseWorkouts * multiplier);
  const totalSteps = Math.floor(baseStepsPerWorkout * baseWorkouts * multiplier);
  const totalFloors = Math.floor(baseFloorsPerWorkout * baseWorkouts * multiplier);
  const totalDuration = baseDurationPerWorkout * baseWorkouts * multiplier;

  const totalMinutes = totalDuration / 60;
  const stepsPerMinute = totalMinutes > 0 ? totalSteps / totalMinutes : 0;

  return {
    totalSteps,
    totalFloors,
    totalWorkouts,
    totalDuration,
    stepsPerMinute,
  };
}

// ---------------------------------------------------------------------------
// Resolve project ID from .firebaserc
// ---------------------------------------------------------------------------

function resolveProjectId(alias) {
  const __dirname = dirname(fileURLToPath(import.meta.url));
  const rcPath = resolve(__dirname, "..", ".firebaserc");
  let rc;
  try {
    rc = JSON.parse(readFileSync(rcPath, "utf-8"));
  } catch {
    console.error(`Error: Could not read .firebaserc at ${rcPath}`);
    process.exit(1);
  }
  const projectId = rc.projects?.[alias];
  if (!projectId) {
    console.error(`Error: No project alias "${alias}" found in .firebaserc`);
    process.exit(1);
  }
  return projectId;
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

function parseArgs() {
  const args = process.argv.slice(2);
  const command = args[0];
  let project = null;
  let dryRun = false;

  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--project" && args[i + 1]) {
      project = args[i + 1];
      i++;
    } else if (args[i] === "--dry-run") {
      dryRun = true;
    }
  }

  if (!command || !["seed", "clear"].includes(command)) {
    console.error("Usage: node scripts/seed-leaderboard.mjs <seed|clear> --project dev [--dry-run]");
    process.exit(1);
  }

  if (!project) {
    console.error("Error: --project is required (e.g., --project dev)");
    process.exit(1);
  }

  // Safety: only allow dev
  if (project !== "dev") {
    console.error(`Error: Only --project dev is allowed. "${project}" is blocked to prevent accidental writes to shared environments.`);
    process.exit(1);
  }

  return { command, project, dryRun };
}

// ---------------------------------------------------------------------------
// Seed
// ---------------------------------------------------------------------------

async function seed(db, dryRun) {
  const now = new Date();
  const docs = [];

  for (const user of TEST_USERS) {
    for (const tf of TIME_FRAMES) {
      const period = currentPeriod(tf.key, now);
      const stats = generateStats(tf.multiplier);
      const docId = `${user.id}_${tf.key}`;

      docs.push({
        docId,
        data: {
          userId: user.id,
          displayName: user.name,
          photoURL: avatarURL(user.name),
          timeFrame: tf.key,
          schemaVersion: SCHEMA_VERSION,
          periodKey: period.key,
          periodStartAt: period.startAt,
          totalSteps: stats.totalSteps,
          totalFloors: stats.totalFloors,
          totalWorkouts: stats.totalWorkouts,
          totalDuration: stats.totalDuration,
          stepsPerMinute: stats.stepsPerMinute,
          lastUpdated: FieldValue.serverTimestamp(),
          isTestData: true,
          seedSource: "leaderboard-script",
          seededAt: FieldValue.serverTimestamp(),
        },
      });
    }
  }

  console.log(`\nPrepared ${docs.length} documents (${TEST_USERS.length} users x ${TIME_FRAMES.length} time frames)`);

  if (dryRun) {
    console.log("\n[DRY RUN] Would write the following documents:\n");
    for (const doc of docs) {
      const preview = { ...doc.data };
      // Replace FieldValue objects with readable placeholders
      preview.lastUpdated = "<serverTimestamp>";
      preview.seededAt = "<serverTimestamp>";
      preview.periodStartAt = preview.periodStartAt.toISOString();
      console.log(`  ${doc.docId}`);
      console.log(`    ${JSON.stringify(preview, null, 2).split("\n").join("\n    ")}\n`);
    }
    return;
  }

  // Write in batches of BATCH_LIMIT
  let written = 0;
  for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    const slice = docs.slice(i, i + BATCH_LIMIT);

    for (const doc of slice) {
      const ref = db.collection(COLLECTION).doc(doc.docId);
      batch.set(ref, doc.data, { merge: true });
    }

    await batch.commit();
    written += slice.length;
    console.log(`  Wrote batch ${Math.floor(i / BATCH_LIMIT) + 1} (${written}/${docs.length} docs)`);
  }

  console.log(`\nDone! Seeded ${written} documents into "${COLLECTION}".`);
}

// ---------------------------------------------------------------------------
// Clear
// ---------------------------------------------------------------------------

async function clear(db, dryRun) {
  // Primary: query by metadata fields
  console.log("\nQuerying for documents with isTestData=true and seedSource='leaderboard-script'...");
  const metaQuery = db
    .collection(COLLECTION)
    .where("isTestData", "==", true)
    .where("seedSource", "==", "leaderboard-script");

  const metaSnapshot = await metaQuery.get();
  const metaDocIds = new Set(metaSnapshot.docs.map((d) => d.id));
  console.log(`  Found ${metaDocIds.size} documents via metadata query.`);

  // Fallback: also find docs matching known test user ID patterns
  // (catches legacy docs seeded before metadata fields existed)
  console.log("Checking for legacy test user documents...");
  const legacyDocIds = new Set();

  for (const user of TEST_USERS) {
    const userQuery = db.collection(COLLECTION).where("userId", "==", user.id);
    const userSnapshot = await userQuery.get();
    for (const doc of userSnapshot.docs) {
      if (!metaDocIds.has(doc.id)) {
        legacyDocIds.add(doc.id);
      }
    }
  }

  if (legacyDocIds.size > 0) {
    console.log(`  Found ${legacyDocIds.size} additional legacy documents.`);
  }

  const allDocIds = [...metaDocIds, ...legacyDocIds];

  if (allDocIds.length === 0) {
    console.log("\nNo test data found to clear.");
    return;
  }

  console.log(`\nTotal documents to delete: ${allDocIds.length}`);

  if (dryRun) {
    console.log("\n[DRY RUN] Would delete the following documents:\n");
    for (const docId of allDocIds) {
      console.log(`  ${docId}`);
    }
    return;
  }

  // Delete in batches
  let deleted = 0;
  for (let i = 0; i < allDocIds.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    const slice = allDocIds.slice(i, i + BATCH_LIMIT);

    for (const docId of slice) {
      batch.delete(db.collection(COLLECTION).doc(docId));
    }

    await batch.commit();
    deleted += slice.length;
    console.log(`  Deleted batch ${Math.floor(i / BATCH_LIMIT) + 1} (${deleted}/${allDocIds.length} docs)`);
  }

  console.log(`\nDone! Deleted ${deleted} test documents from "${COLLECTION}".`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const { command, project, dryRun } = parseArgs();
  const projectId = resolveProjectId(project);

  console.log(`Project: ${project} -> ${projectId}`);
  console.log(`Command: ${command}${dryRun ? " (dry run)" : ""}`);

  initializeApp({
    credential: applicationDefault(),
    projectId,
  });

  const db = getFirestore();

  if (command === "seed") {
    await seed(db, dryRun);
  } else if (command === "clear") {
    await clear(db, dryRun);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
