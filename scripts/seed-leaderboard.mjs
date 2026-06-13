#!/usr/bin/env node

/**
 * Leaderboard Seed Script
 *
 * Seeds or clears deterministic leaderboard rows for the profile fixture users.
 * The profile seed target is the base layer; this target exists so standings
 * can be refreshed independently without creating orphan leaderboard users.
 *
 * Usage:
 *   node scripts/seed-leaderboard.mjs seed --project dev
 *   node scripts/seed-leaderboard.mjs clear --project staging
 *   node scripts/seed-leaderboard.mjs seed --project dev --dry-run
 */

import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {
  assertSeedableProject,
  resolveProjectId,
} from "./seed/lib/environments.mjs";
import {
  buildLeaderboardSeedWrites,
  expectedLeaderboardDocIds,
  PROFILE_SEED_PERSONAS,
} from "./seed/fixtures/profile-fixtures.mjs";

const COLLECTION = "leaderboard_stats";
const BATCH_LIMIT = 450;
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const LEGACY_TEST_USER_IDS = Array.from({length: 40}, (_, index) => `test_user_${index + 1}`);
const LEGACY_TIME_FRAMES = ["daily", "weekly", "monthly", "yearly", "all_time"];

function parseArgs(argv) {
  const args = {command: argv[2] ?? "help", project: null, dryRun: false};

  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--dry-run") args.dryRun = true;
    else if (value === "--help" || value === "-h") args.command = "help";
    else throw new Error(`Unknown argument: ${value}`);
  }

  if (!args.project) {
    throw new Error("--project is required (e.g. --project dev)");
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
  node scripts/seed-leaderboard.mjs seed --project dev
  node scripts/seed-leaderboard.mjs clear --project staging
  node scripts/seed-leaderboard.mjs seed --project dev --dry-run
`);
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.command === "help") {
    printHelp();
    return;
  }
  if (!["seed", "clear"].includes(args.command)) {
    throw new Error("Command must be seed, clear, or help");
  }

  const projectId = resolveProjectId(args.project, REPO_ROOT);
  assertSeedableProject(projectId);

  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();

  console.log(`Project: ${projectId}`);
  console.log(`Command: ${args.command}${args.dryRun ? " (dry run)" : ""}`);
  console.log(`Users: ${PROFILE_SEED_PERSONAS.length}`);

  if (args.command === "clear") {
    const refs = await leaderboardRefsToClear(db);
    console.log(`Documents to delete: ${refs.length}`);
    if (args.dryRun) return;
    await commitDeletes(db, refs);
    console.log(`Deleted ${refs.length} leaderboard documents.`);
    return;
  }

  const writes = buildLeaderboardSeedWrites({
    db,
    catalog: loadCatalog(),
    Timestamp,
    FieldValue,
    avatarURLs: await loadSeededProfilePhotoURLs(db),
  });
  console.log(`Prepared ${writes.length} leaderboard documents.`);
  console.log("Note: run the profiles target first when seeding an empty environment.");
  if (args.dryRun) return;

  await commitDeletes(db, await leaderboardRefsToClear(db));
  await commitWrites(db, writes);
  console.log(`Seeded ${writes.length} documents into "${COLLECTION}".`);
}

function loadCatalog() {
  const raw = JSON.parse(readFileSync(resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"), "utf-8"));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

async function loadSeededProfilePhotoURLs(db) {
  const avatarURLs = new Map();
  for (const persona of PROFILE_SEED_PERSONAS) {
    const snapshot = await db
      .collection("users")
      .doc(persona.id)
      .collection("public_profile")
      .doc("current")
      .get();
    const photoURL = snapshot.data()?.photoURL;
    if (typeof photoURL === "string" && photoURL.length > 0) {
      avatarURLs.set(persona.id, photoURL);
    }
  }
  return avatarURLs;
}

async function leaderboardRefsToClear(db) {
  const refs = expectedLeaderboardDocIds().map((docId) => db.collection(COLLECTION).doc(docId));

  for (const userId of LEGACY_TEST_USER_IDS) {
    LEGACY_TIME_FRAMES.forEach((timeFrame) => {
      refs.push(db.collection(COLLECTION).doc(`${userId}_${timeFrame}`));
    });
  }

  const legacySnapshot = await db
    .collection(COLLECTION)
    .where("isTestData", "==", true)
    .where("seedSource", "==", "leaderboard-script")
    .get();
  legacySnapshot.docs.forEach((doc) => refs.push(doc.ref));

  return uniqueRefs(refs);
}

function uniqueRefs(refs) {
  const seen = new Set();
  return refs.filter((ref) => {
    if (seen.has(ref.path)) return false;
    seen.add(ref.path);
    return true;
  });
}

async function commitWrites(db, writes) {
  for (let index = 0; index < writes.length; index += BATCH_LIMIT) {
    const batch = db.batch();
    for (const {ref, data} of writes.slice(index, index + BATCH_LIMIT)) {
      batch.set(ref, data);
    }
    await batch.commit();
  }
}

async function commitDeletes(db, refs) {
  for (let index = 0; index < refs.length; index += BATCH_LIMIT) {
    const batch = db.batch();
    refs.slice(index, index + BATCH_LIMIT).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
