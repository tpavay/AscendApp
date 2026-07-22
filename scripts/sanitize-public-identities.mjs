#!/usr/bin/env node

/**
 * Removes account-authored names and photos from Ascend's public projections.
 *
 * The migration is captain-run operations work. It never selects an environment
 * implicitly and requires one explicit mode. Apply is idempotent, ledger-backed,
 * and ordered so Storage token rotation and legacy-object cleanup finish before
 * Firestore stops carrying the URLs needed to resume that work.
 *
 * Usage:
 *   node scripts/sanitize-public-identities.mjs --env dev --dry-run
 *   node scripts/sanitize-public-identities.mjs --env dev --apply
 *   node scripts/sanitize-public-identities.mjs --env dev --audit
 *   node scripts/sanitize-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
 */

import {randomUUID} from "node:crypto";
import {FieldPath, FieldValue} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {
  beginRun,
  initFirestore,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {
  collectPublishedPhotoURLs,
  isTrustedSyntheticFirstAscent,
  isTrustedSyntheticRecord,
  packBatches,
  parseSanitizationArgs,
  planSanitizationPage,
  replacementDownloadURL,
  storageObjectFromDownloadURL,
} from "./lib/public-identity-sanitization.mjs";

const OPERATION_ID = "migration/public-identity-sanitization";
const OPERATION_VERSION = 1;
const LEGACY_PROFILE_PREFIX = "profile_pictures/";

const args = parseSanitizationArgs(process.argv);
if (args.help) printUsageAndExit();

const environment = resolveEnvironment(args.env, {
  allowProduction: true,
  productionConfirmation: args.productionConfirmation,
});
const db = await initFirestore(environment);
const plan = await buildPlan(db, args.batchSize, environment.projectId);
printPlan(plan, environment, args.mode);

if (args.mode === "audit") {
  const violations = firestoreUpdateCount(plan) + plan.storage.legacyFiles.length;
  if (violations > 0) {
    throw new Error(`Public identity audit failed with ${violations} violation(s).`);
  }
  console.log("Audit passed: no real-user public identity or legacy profile-picture objects remain.");
  process.exit(0);
}

if (args.mode === "dry-run") {
  console.log("Dry-run complete. Re-run with --apply to execute this exact migration class.");
  process.exit(0);
}

const run = await beginRun(db, {
  operationId: OPERATION_ID,
  operationVersion: OPERATION_VERSION,
  environment,
  rerun: args.rerun,
});

try {
  const storageCounts = await applyStoragePlan(plan.storage);
  const firestoreCounts = await applyFirestorePlan(db, plan, args.batchSize);
  const verification = await buildPlan(db, args.batchSize, environment.projectId);
  const remaining = firestoreUpdateCount(verification) + verification.storage.legacyFiles.length;
  if (remaining > 0) {
    throw new Error(`Verification found ${remaining} unsanitized public identity record(s).`);
  }

  const counts = {...storageCounts, ...firestoreCounts};
  await run.finish(counts);
  console.log(`Applied and verified public identity sanitization: ${JSON.stringify(counts)}.`);
} catch (error) {
  await run.fail(error);
  throw error;
}

async function buildPlan(firestore, pageSize, projectId) {
  const users = await readPaginated(firestore.collection("users"), pageSize);
  const publicProfiles = (await readPaginated(
    firestore.collectionGroup("public_profile"),
    pageSize
  )).filter((document) => document.ref.id === "current");
  const leaderboardStats = await readPaginated(firestore.collection("leaderboard_stats"), pageSize);
  const replayContexts = await readPaginated(
    firestore.collection("live_replay_leaderboards"),
    pageSize
  );
  const replayEntries = [];
  const replayFinishers = [];

  for (const context of replayContexts) {
    const bucketReferences = await context.ref.collection("splitBuckets").listDocuments();
    for (const bucketReference of bucketReferences) {
      replayEntries.push(...await readPaginated(bucketReference.collection("entries"), pageSize));
    }
    replayFinishers.push(...await readPaginated(context.ref.collection("finishers"), pageSize));
  }

  const records = (documents) => documents.map((document) => ({
    ref: document.ref,
    path: document.ref.path,
    data: document.data,
  }));
  const publicProfileRecords = records(publicProfiles);
  const leaderboardRecords = records(leaderboardStats);
  const contextRecords = records(replayContexts);
  const entryRecords = records(replayEntries);
  const finisherRecords = records(replayFinishers);
  const firstAscentRecords = contextRecords.filter((record) =>
    record.data.firstAscentCompletedAt !== undefined
  );
  const realPhotoRecords = [
    ...publicProfileRecords,
    ...leaderboardRecords,
    ...entryRecords.filter((record) => !isTrustedSyntheticRecord(record.data)),
    ...finisherRecords.filter((record) => !isTrustedSyntheticRecord(record.data)),
    ...firstAscentRecords.filter((record) => !isTrustedSyntheticFirstAscent(record.data)),
  ].map((record) => record.data);

  return {
    users: records(users),
    publicProfiles: planSanitizationPage(publicProfileRecords, "publicProfile"),
    leaderboardStats: planSanitizationPage(leaderboardRecords, "leaderboard"),
    firstAscents: planSanitizationPage(firstAscentRecords, "firstAscent"),
    replayEntries: planSanitizationPage(entryRecords, "replay"),
    replayFinishers: planSanitizationPage(finisherRecords, "replay"),
    storage: await buildStoragePlan(
      records(users),
      collectPublishedPhotoURLs(realPhotoRecords),
      projectId
    ),
    scanned: {
      users: users.length,
      publicProfiles: publicProfiles.length,
      leaderboardStats: leaderboardStats.length,
      replayContexts: replayContexts.length,
      replayEntries: replayEntries.length,
      replayFinishers: replayFinishers.length,
    },
  };
}

async function buildStoragePlan(users, publishedPhotoURLs, projectId) {
  const currentUserPhotosByObject = new Map();
  for (const user of users) {
    const parsed = storageObjectFromDownloadURL(user.data.profilePictureURL);
    if (!parsed) continue;
    const key = `${parsed.bucket}/${parsed.path}`;
    const owners = currentUserPhotosByObject.get(key) ?? [];
    owners.push({ref: user.ref, userId: user.ref.id, parsed});
    currentUserPhotosByObject.set(key, owners);
  }

  const rotationsByObject = new Map();
  const publishedURLsByObject = new Map();
  const unrotatablePublishedURLs = [];
  for (const url of publishedPhotoURLs) {
    const parsed = storageObjectFromDownloadURL(url);
    if (!parsed) {
      unrotatablePublishedURLs.push(url);
      continue;
    }
    const key = `${parsed.bucket}/${parsed.path}`;
    const objectURLs = publishedURLsByObject.get(key) ?? new Set();
    objectURLs.add(url);
    publishedURLsByObject.set(key, objectURLs);

    if (!parsed.path.startsWith("users/") || !parsed.path.includes("/profile_pictures/")) {
      if (!parsed.path.startsWith(LEGACY_PROFILE_PREFIX)) {
        unrotatablePublishedURLs.push(url);
      }
      continue;
    }
    const rotation = rotationsByObject.get(key) ?? {
      bucket: parsed.bucket,
      path: parsed.path,
      oldURLs: new Set(),
      owners: currentUserPhotosByObject.get(key) ?? [],
    };
    rotation.oldURLs.add(url);
    rotationsByObject.set(key, rotation);
  }

  const defaultBucketName = `${projectId}.firebasestorage.app`;
  const defaultBucket = getStorage().bucket(defaultBucketName);
  const [legacyFiles] = await defaultBucket.getFiles({prefix: LEGACY_PROFILE_PREFIX});
  const legacyPlans = legacyFiles
    .filter((file) => file.name !== LEGACY_PROFILE_PREFIX)
    .map((file) => {
      const key = `${defaultBucketName}/${file.name}`;
      return {
        bucket: defaultBucketName,
        path: file.name,
        owners: currentUserPhotosByObject.get(key) ?? [],
        oldURLs: [...(publishedURLsByObject.get(key) ?? [])],
      };
    });

  return {
    rotations: [...rotationsByObject.values()].map((item) => ({
      ...item,
      oldURLs: [...item.oldURLs],
    })),
    legacyFiles: legacyPlans,
    unrotatablePublishedURLs,
  };
}

async function applyStoragePlan(plan) {
  let tokensRotated = 0;
  let legacyFilesMoved = 0;
  let legacyFilesDeleted = 0;
  let ownerDocumentsUpdated = 0;
  const oldURLsToVerify = new Set();

  for (const rotation of plan.rotations) {
    const token = randomUUID();
    const bucket = getStorage().bucket(rotation.bucket);
    const file = bucket.file(rotation.path);
    const [metadata] = await file.getMetadata();
    await file.setMetadata({
      metadata: {
        ...(metadata.metadata ?? {}),
        firebaseStorageDownloadTokens: token,
      },
    });
    const replacementURL = replacementDownloadURL(rotation.bucket, rotation.path, token);
    for (const owner of rotation.owners) {
      await owner.ref.set({profilePictureURL: replacementURL}, {merge: true});
      ownerDocumentsUpdated += 1;
    }
    rotation.oldURLs.forEach((url) => oldURLsToVerify.add(url));
    tokensRotated += 1;
  }

  for (const legacy of plan.legacyFiles) {
    const bucket = getStorage().bucket(legacy.bucket);
    const source = bucket.file(legacy.path);
    for (const owner of legacy.owners) {
      const basename = legacy.path.slice(LEGACY_PROFILE_PREFIX.length);
      const destinationPath = `users/${owner.userId}/profile_pictures/${basename}`;
      const destination = bucket.file(destinationPath);
      await source.copy(destination);
      const token = randomUUID();
      const [metadata] = await destination.getMetadata();
      await destination.setMetadata({
        metadata: {
          ...(metadata.metadata ?? {}),
          firebaseStorageDownloadTokens: token,
        },
      });
      await owner.ref.set({
        profilePictureURL: replacementDownloadURL(legacy.bucket, destinationPath, token),
      }, {merge: true});
      oldURLsToVerify.add(owner.parsed.url);
      ownerDocumentsUpdated += 1;
      legacyFilesMoved += 1;
    }
    await source.delete({ignoreNotFound: true});
    legacy.oldURLs.forEach((url) => oldURLsToVerify.add(url));
    legacyFilesDeleted += 1;
  }

  for (const oldURL of oldURLsToVerify) {
    const response = await fetch(oldURL, {redirect: "manual"});
    if (response.ok) {
      throw new Error(`Old profile-photo download URL still resolves after rotation: ${oldURL}`);
    }
  }

  return {
    tokensRotated,
    legacyFilesMoved,
    legacyFilesDeleted,
    ownerDocumentsUpdated,
    oldURLsVerifiedInvalid: oldURLsToVerify.size,
  };
}

async function applyFirestorePlan(firestore, plan, batchSize) {
  const groups = [
    ["publicProfiles", plan.publicProfiles],
    ["leaderboardStats", plan.leaderboardStats],
    ["firstAscents", plan.firstAscents],
    ["replayEntries", plan.replayEntries],
    ["replayFinishers", plan.replayFinishers],
  ];
  const counts = {};

  for (const [name, items] of groups) {
    counts[name] = items.length;
    for (const batchItems of packBatches(items, batchSize)) {
      const batch = firestore.batch();
      for (const item of batchItems) {
        const update = {...item.update};
        if (name === "publicProfiles" || name === "leaderboardStats") {
          update.lastUpdated = FieldValue.serverTimestamp();
        }
        batch.set(item.ref, update, {merge: true});
      }
      await batch.commit();
    }
  }
  return counts;
}

async function readPaginated(collectionOrQuery, pageSize, orderByDocumentID = true) {
  const documents = [];
  let lastDocument = null;

  while (true) {
    let query = collectionOrQuery;
    if (orderByDocumentID) query = query.orderBy(FieldPath.documentId());
    if (lastDocument) query = query.startAfter(lastDocument);
    const snapshot = await query.limit(pageSize).get();
    if (snapshot.empty) break;
    documents.push(...snapshot.docs.map((document) => ({
      ref: document.ref,
      data: document.data(),
    })));
    lastDocument = snapshot.docs.at(-1);
    if (snapshot.size < pageSize) break;
  }
  return documents;
}

function firestoreUpdateCount(plan) {
  return plan.publicProfiles.length +
    plan.leaderboardStats.length +
    plan.firstAscents.length +
    plan.replayEntries.length +
    plan.replayFinishers.length;
}

function printPlan(plan, environmentValue, mode) {
  console.log([
    `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
    `Environment: ${environmentValue.env} (${environmentValue.projectId})`,
    `Mode: ${mode}`,
    `Users scanned: ${plan.scanned.users}`,
    `Public profiles scanned/to sanitize: ${plan.scanned.publicProfiles}/${plan.publicProfiles.length}`,
    `Leaderboard documents scanned/to sanitize: ${plan.scanned.leaderboardStats}/${plan.leaderboardStats.length}`,
    `Replay contexts scanned/First Ascents to sanitize: ${plan.scanned.replayContexts}/${plan.firstAscents.length}`,
    `Replay entries scanned/to sanitize: ${plan.scanned.replayEntries}/${plan.replayEntries.length}`,
    `Replay finishers scanned/to sanitize: ${plan.scanned.replayFinishers}/${plan.replayFinishers.length}`,
    `User-scoped photo tokens to rotate: ${plan.storage.rotations.length}`,
    `Legacy root profile pictures to move/delete: ${plan.storage.legacyFiles.length}`,
    `Published URLs outside managed user-scoped Storage: ${plan.storage.unrotatablePublishedURLs.length}`,
  ].join("\n"));
}

function printUsageAndExit() {
  console.log(`
Sanitize account-authored public identity.

Usage:
  node scripts/sanitize-public-identities.mjs --env dev --dry-run
  node scripts/sanitize-public-identities.mjs --env staging --apply
  node scripts/sanitize-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
  node scripts/sanitize-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --audit

Options:
  --env <dev|staging|prod>   Required named environment.
  --dry-run                 Plan and count without mutation.
  --apply                   Apply, verify, and record the migration ledger.
  --audit                   Fail if any real-user public identity remains.
  --batch-size <1...450>     Firestore write and scan page size (default 400).
  --rerun                   Re-apply an already successful operation version.
  --confirm-production <id> Required for prod; must equal ascend-prod-9c8f2.
`);
  process.exit(0);
}
