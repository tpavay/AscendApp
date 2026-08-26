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
import {createBatchWriter, createProgressReporter, withRetry} from "./lib/firestore-bulk.mjs";
import {
  assertSeedableProject,
  resolveProjectId,
} from "./seed/lib/environments.mjs";
import {
  buildLeaderboardSeedWrites,
  expectedLeaderboardDocIds,
  legacyLeaderboardDocIds,
  PROFILE_SEED_PERSONAS,
  publicIdentityMismatchFields,
  publishedPublicIdentity,
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

  const publicIdentities = await readPublicIdentities(db);
  const writes = buildLeaderboardSeedWrites({
    db,
    catalog: loadCatalog(),
    Timestamp,
    FieldValue,
    publicIdentities,
  });
  console.log(`Prepared ${writes.length} leaderboard documents.`);
  console.log("Note: run the profiles target first when seeding an empty environment.");
  if (args.dryRun) return;

  await commitWrites(db, writes);
  const writtenPaths = new Set(writes.map((writeItem) => writeItem.ref.path));
  const obsoleteRefs = (await leaderboardRefsToClear(db))
    .filter((reference) => !writtenPaths.has(reference.path));
  await commitDeletes(db, obsoleteRefs);
  console.log(`Seeded ${writes.length} documents into "${COLLECTION}".`);
}

async function readPublicIdentities(db) {
  const snapshots = await Promise.all(
    PROFILE_SEED_PERSONAS.map((persona) =>
      db
        .collection("users")
        .doc(persona.id)
        .collection("public_profile")
        .doc("current")
        .get()
    )
  );

  return new Map(snapshots.map((snapshot, index) => {
    const userId = PROFILE_SEED_PERSONAS[index].id;
    if (!snapshot.exists) {
      throw new Error(
        `users/${userId}/public_profile/current must exist before leaderboard seeding`
      );
    }
    return [userId, publishedPublicIdentity(userId, snapshot.data())];
  }));
}

function loadCatalog() {
  const raw = JSON.parse(readFileSync(resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"), "utf-8"));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

async function leaderboardRefsToClear(db) {
  const refs = expectedLeaderboardDocIds().map((docId) => db.collection(COLLECTION).doc(docId));
  legacyLeaderboardDocIds().forEach((docId) => {
    refs.push(db.collection(COLLECTION).doc(docId));
  });

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
  const progress = createProgressReporter({label: "Leaderboard", total: writes.length});
  for (let index = 0; index < writes.length; index += BATCH_LIMIT) {
    const page = writes.slice(index, index + BATCH_LIMIT);
    // Kept a transaction: it re-reads each climber's published identity and
    // refuses a row that went stale mid-seed. Wrapped in a deadline so a
    // transaction the backend never answers fails this command instead of
    // parking it.
    await withRetry(() => db.runTransaction(async (transaction) => {
      const userIds = [...new Set(page.map((writeItem) =>
        writeItem.data.userId
      ))];
      const profileReferences = userIds.map((userId) =>
        db
          .collection("users")
          .doc(userId)
          .collection("public_profile")
          .doc("current")
      );
      const profileSnapshots = await Promise.all(
        profileReferences.map((reference) => transaction.get(reference))
      );
      const currentIdentities = new Map(
        profileSnapshots.map((snapshot, profileIndex) => {
          const userId = userIds[profileIndex];
          if (!snapshot.exists) {
            throw new Error(
              `users/${userId}/public_profile/current disappeared during seeding`
            );
          }
          return [
            userId,
            publishedPublicIdentity(userId, snapshot.data()),
          ];
        })
      );

      for (const {ref, data} of page) {
        const mismatches = publicIdentityMismatchFields(
          data,
          currentIdentities.get(data.userId)
        );
        if (mismatches.length > 0) {
          throw new Error(
            `${ref.path} identity became stale during seeding: ` +
            mismatches.join(", ")
          );
        }
        transaction.set(ref, data);
      }
    }), {
      description: `leaderboard identity transaction for ${page.length} row(s)`,
      onRetry: () => progress.retried(),
    });
    progress.advance(page.length);
  }

  progress.finish();
}

async function commitDeletes(db, refs) {
  const progress = createProgressReporter({label: "Leaderboard (clear)", total: refs.length});
  const writer = createBatchWriter(db, {progress});
  for (const ref of refs) {
    writer.delete(ref);
  }
  await writer.drain();
  progress.finish();
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
