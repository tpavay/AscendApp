#!/usr/bin/env node

/**
 * Profile Test User Seeder
 *
 * Seeds or clears public profile data for dev/staging QA. This is the base
 * fixture layer: seeded leaderboard rows and comparison data should point at
 * these users instead of orphan user IDs.
 *
 * Usage:
 *   node scripts/seed-test-users.mjs seed --project dev
 *   node scripts/seed-test-users.mjs clear --project staging
 *   node scripts/seed-test-users.mjs seed --project dev --dry-run
 */

import {existsSync, readFileSync} from "node:fs";
import {randomUUID} from "node:crypto";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import {
  assertSeedableProject,
  resolveProjectId,
} from "./seed/lib/environments.mjs";
import {
  buildProfileSeedWrites,
  expectedLeaderboardDocIds,
  expectedProfileUserIds,
  legacyLeaderboardDocIds,
  PROFILE_SEED_PACK_ID,
  PROFILE_SEED_PERSONAS,
} from "./seed/fixtures/profile-fixtures.mjs";

const BATCH_LIMIT = 450;
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
// Curated 512x512 JPEGs live in the repo rather than behind a --avatar-dir flag
// so anyone can reproduce the seed without a local image folder. One distinct
// image per persona.
const ASSET_ROOT = resolve(REPO_ROOT, "scripts/seed/assets/profile-avatars");
const AVATAR_CONTENT_TYPE = "image/jpeg";

function parseArgs(argv) {
  const args = {command: argv[2] ?? "help", project: "dev", dryRun: false};
  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--dry-run") args.dryRun = true;
    else if (value === "--help" || value === "-h") args.command = "help";
    else throw new Error(`Unknown argument: ${value}`);
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
  node scripts/seed-test-users.mjs seed --project dev
  node scripts/seed-test-users.mjs clear --project staging
  node scripts/seed-test-users.mjs seed --project dev --dry-run
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

  initializeApp({
    credential: applicationDefault(),
    projectId,
    storageBucket: `${projectId}.firebasestorage.app`,
  });
  const db = getFirestore();
  const catalog = loadCatalog();

  console.log(`Project: ${projectId}`);
  console.log(`Seed pack: ${PROFILE_SEED_PACK_ID}`);
  console.log(`Command: ${args.command}${args.dryRun ? " (dry run)" : ""}`);
  console.log(`Personas: ${PROFILE_SEED_PERSONAS.length}`);

  if (args.command === "clear") {
    const refs = await seedDocumentRefs(db);
    printClearPlan(refs);
    if (args.dryRun) return;
    await commitDeletes(db, refs);
    console.log(`Deleted ${refs.length} seeded documents.`);
    return;
  }

  const avatarURLs = args.dryRun
    ? plannedAvatarURLs(projectId)
    : await uploadProfileAvatars(projectId);

  const writes = buildProfileSeedWrites({
    db,
    catalog,
    Timestamp,
    FieldValue,
    avatarURLs,
  });

  printSeedPlan(writes, avatarURLs);
  if (args.dryRun) return;

  await commitDeletes(
    db,
    await seedDocumentRefs(db, {includeUserDocuments: false})
  );
  await commitWrites(db, writes);
  console.log(`Wrote ${writes.length} seeded documents.`);
}

function loadCatalog() {
  const raw = JSON.parse(readFileSync(resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"), "utf-8"));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

// User media lives only under users/{uid}/... prefixes, never a shared root
// path, so seeded avatars land where storage.rules already scopes them to their
// owner. The object name is deterministic, so re-seeding overwrites in place
// instead of accumulating orphans.
function avatarObjectPath(userId) {
  return `users/${userId}/profile_pictures/${PROFILE_SEED_PACK_ID}.jpg`;
}

function avatarSourcePath(userId) {
  return resolve(ASSET_ROOT, `${userId}.jpg`);
}

async function uploadProfileAvatars(projectId) {
  const {getStorage} = await import("firebase-admin/storage");
  const bucket = getStorage().bucket();
  const avatarURLs = new Map();

  for (const userId of expectedProfileUserIds()) {
    const sourcePath = avatarSourcePath(userId);
    if (!existsSync(sourcePath)) {
      throw new Error(`Missing seed avatar for ${userId} at ${sourcePath}`);
    }

    const token = randomUUID();
    const destination = avatarObjectPath(userId);

    await bucket.upload(sourcePath, {
      destination,
      metadata: {
        cacheControl: "public,max-age=31536000,immutable",
        contentType: AVATAR_CONTENT_TYPE,
        metadata: {
          firebaseStorageDownloadTokens: token,
          seedPackId: PROFILE_SEED_PACK_ID,
          seedUserId: userId,
        },
      },
    });

    avatarURLs.set(userId, downloadURL(bucket.name, destination, token));
  }

  return avatarURLs;
}

function plannedAvatarURLs(projectId) {
  const bucketName = `${projectId}.firebasestorage.app`;
  return new Map(expectedProfileUserIds().map((userId) => [
    userId,
    downloadURL(bucketName, avatarObjectPath(userId), "dry-run"),
  ]));
}

function downloadURL(bucketName, objectPath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
}

/**
 * Documents a clear or a re-seed removes.
 *
 * `includeUserDocuments` is the difference between the two, and it is not
 * cosmetic. Deleting `users/{uid}` fires `cleanupDeletedUserData`, which sweeps
 * every subcollection under that user - so a *seed* that deletes the persona
 * root first is racing an account-deletion sweep against its own writes. On
 * 2026-08-24 the sweep won: the seed wrote 376 documents at 00:30:35 UTC and the
 * trigger deleted `public_profile`, `profile_stats`, `achievements` and
 * `profile_workouts` for all twelve personas at 00:30:40, leaving root documents
 * with nothing under them and failing the audit.
 *
 * A seed does not need the delete anyway: every persona document is rewritten
 * with a whole-document `set`, so no stale field survives. A clear does want it,
 * because there the sweep is the point.
 * @param {object} db Firestore instance.
 * @param {object} [options] Selection options.
 * @param {boolean} [options.includeUserDocuments=true] Delete persona root docs.
 * @return {Promise<object[]>} Document references to delete.
 */
async function seedDocumentRefs(db, {includeUserDocuments = true} = {}) {
  const refs = [];
  for (const userId of expectedProfileUserIds()) {
    const userRef = db.collection("users").doc(userId);
    refs.push(userRef.collection("public_profile").doc("current"));
    refs.push(userRef.collection("profile_stats").doc("current"));

    const workouts = await userRef.collection("profile_workouts").get();
    const achievements = await userRef.collection("achievements").get();
    workouts.docs.forEach((doc) => refs.push(doc.ref));
    achievements.docs.forEach((doc) => refs.push(doc.ref));
    if (includeUserDocuments) {
      refs.push(userRef);
    }
  }

  expectedLeaderboardDocIds().forEach((docId) => {
    refs.push(db.collection("leaderboard_stats").doc(docId));
  });
  legacyLeaderboardDocIds().forEach((docId) => {
    refs.push(db.collection("leaderboard_stats").doc(docId));
  });

  return refs;
}

function printSeedPlan(writes, avatarURLs) {
  const counts = writes.reduce((result, item) => {
    result[item.shape] = (result[item.shape] ?? 0) + 1;
    return result;
  }, {});
  console.log("Seed plan:");
  Object.entries(counts)
    .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
    .forEach(([shape, count]) => {
      console.log(`  ${shape}: ${count}`);
    });
  console.log(`  hostedProfileAvatars: ${avatarURLs.size}`);
}

function printClearPlan(refs) {
  console.log(`Documents to delete: ${refs.length}`);
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
  console.error(error);
  process.exit(1);
});
