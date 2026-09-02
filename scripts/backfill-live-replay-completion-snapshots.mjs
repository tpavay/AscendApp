#!/usr/bin/env node

/**
 * Backfills immutable Live Replay completion-rank snapshots.
 *
 * New completions get snapshots from the Cloud Function. This script covers
 * existing leaderboard rows by reconstructing attempt completion time from the
 * private workout backup when available.
 *
 * Usage:
 *   node scripts/backfill-live-replay-completion-snapshots.mjs --project dev --dry-run
 *   node scripts/backfill-live-replay-completion-snapshots.mjs --project staging
 *   node scripts/backfill-live-replay-completion-snapshots.mjs --project prod --confirm-production
 *   node scripts/backfill-live-replay-completion-snapshots.mjs --project dev --context-key live_climb__burj-khalifa
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login
 */

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const PROD_PROJECT_ID = "ascend-prod-9c8f2";
const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const SNAPSHOTS_COLLECTION = "completionSnapshots";
const BUCKET_ZERO_DOC_ID = "0";
const MAX_BATCH_WRITES = 450;
const PROJECT_ALIASES = new Map([
  ["dev", DEV_PROJECT_ID],
  ["staging", STAGING_PROJECT_ID],
  ["prod", PROD_PROJECT_ID],
  ["production", PROD_PROJECT_ID],
]);

const args = parseArgs(process.argv);
const projectId = resolveProjectId(args.project);

if (projectId === PROD_PROJECT_ID && !args.dryRun && !args.confirmProduction) {
  throw new Error("Production backfill requires --confirm-production.");
}

initializeApp({
  credential: applicationDefault(),
  projectId,
});

const db = getFirestore();
const result = await backfillCompletionSnapshots(db, args);

console.log(
  [
    `Project: ${projectId}`,
    `Mode: ${args.dryRun ? "dry run" : "write"}`,
    `Contexts scanned: ${result.contextsScanned}`,
    `Entries scanned: ${result.entriesScanned}`,
    `Snapshots existing: ${result.existingSnapshots}`,
    `Snapshots planned: ${result.snapshotsPlanned}`,
    `Snapshots written: ${result.snapshotsWritten}`,
    `Entries skipped: ${result.entriesSkipped}`,
  ].join("\n")
);

/**
 * Parses command-line arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Parsed arguments.
 */
function parseArgs(argv) {
  const parsed = {
    project: "dev",
    dryRun: false,
    force: false,
    confirmProduction: false,
    contextKey: null,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--project":
        parsed.project = requireValue(argv, ++index, "--project");
        break;
      case "--context-key":
        parsed.contextKey = requireValue(argv, ++index, "--context-key");
        break;
      case "--dry-run":
        parsed.dryRun = true;
        break;
      case "--force":
        parsed.force = true;
        break;
      case "--confirm-production":
        parsed.confirmProduction = true;
        break;
      case "--help":
      case "-h":
        printUsageAndExit();
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  return parsed;
}

/**
 * Resolves a project alias or returns an explicit Firebase project ID.
 * @param {string} value Project alias or ID.
 * @return {string} Firebase project ID.
 */
function resolveProjectId(value) {
  return PROJECT_ALIASES.get(value) ?? value;
}

/**
 * Requires an argv value after a flag.
 * @param {string[]} argv Process argv.
 * @param {number} index Value index.
 * @param {string} flag Flag name.
 * @return {string} Flag value.
 */
function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node scripts/backfill-live-replay-completion-snapshots.mjs --project dev --dry-run
  node scripts/backfill-live-replay-completion-snapshots.mjs --project staging
  node scripts/backfill-live-replay-completion-snapshots.mjs --project prod --confirm-production

Options:
  --project <dev|staging|prod|projectId>
  --context-key <live_replay_context_key>
  --dry-run
  --force
  --confirm-production
`);
  process.exit(0);
}

/**
 * Backfills all matching replay leaderboard contexts.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object} options Backfill options.
 * @return {Promise<object>} Backfill counts.
 */
async function backfillCompletionSnapshots(firestore, options) {
  const counters = {
    contextsScanned: 0,
    entriesScanned: 0,
    existingSnapshots: 0,
    snapshotsPlanned: 0,
    snapshotsWritten: 0,
    entriesSkipped: 0,
  };

  const leaderboardRefs = options.contextKey ?
    [firestore.collection(LIVE_REPLAY_COLLECTION).doc(options.contextKey)] :
    (await firestore.collection(LIVE_REPLAY_COLLECTION).get()).docs.map(
      (doc) => doc.ref
    );

  for (const leaderboardRef of leaderboardRefs) {
    const summarySnapshot = await leaderboardRef.get();
    if (!summarySnapshot.exists) {
      counters.entriesSkipped += 1;
      continue;
    }

    counters.contextsScanned += 1;
    const summary = summarySnapshot.data() ?? {};
    const entries = await completionEntriesForContext(
      firestore,
      leaderboardRef,
      summary
    );
    counters.entriesScanned += entries.length;

    if (entries.length === 0) {
      continue;
    }

    const snapshots = buildCompletionSnapshots(entries);
    const existingSnapshotIds = await existingSnapshotDocumentIds(
      leaderboardRef
    );
    counters.existingSnapshots += existingSnapshotIds.size;

    let batch = firestore.batch();
    let batchWriteCount = 0;

    for (const snapshot of snapshots) {
      if (!options.force && existingSnapshotIds.has(snapshot.workoutId)) {
        continue;
      }

      counters.snapshotsPlanned += 1;

      if (options.dryRun) {
        continue;
      }

      const snapshotRef = leaderboardRef
        .collection(SNAPSHOTS_COLLECTION)
        .doc(snapshot.workoutId);

      batch.set(snapshotRef, snapshot, {merge: false});
      batchWriteCount += 1;

      if (batchWriteCount >= MAX_BATCH_WRITES) {
        await batch.commit();
        counters.snapshotsWritten += batchWriteCount;
        batch = firestore.batch();
        batchWriteCount = 0;
      }
    }

    if (!options.dryRun && batchWriteCount > 0) {
      await batch.commit();
      counters.snapshotsWritten += batchWriteCount;
    }
  }

  return counters;
}

/**
 * Loads bucket-zero completion entries and enriches them with completion time.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} leaderboardRef Context ref.
 * @param {Record<string, unknown>} summary Leaderboard summary data.
 * @return {Promise<object[]>} Enriched completion entries.
 */
async function completionEntriesForContext(firestore, leaderboardRef, summary) {
  const entriesSnapshot = await leaderboardRef
    .collection("splitBuckets")
    .doc(BUCKET_ZERO_DOC_ID)
    .collection("entries")
    .get();
  const entries = [];

  for (const doc of entriesSnapshot.docs) {
    const data = doc.data();
    const userId = stringValue(data.userId);
    const workoutId = stringValue(data.workoutId) ?? doc.id;
    const completionDurationSeconds = numberValue(
      data.completionDurationSeconds
    );
    const finalSteps = integerValue(data.finalSteps);

    if (!userId || !workoutId || !completionDurationSeconds || !finalSteps) {
      continue;
    }

    const completionMillis = await completionMillisForEntry(
      firestore,
      userId,
      workoutId,
      data
    );

    entries.push({
      completionDurationSeconds,
      completionMillis,
      contextId: stringValue(data.contextId) ?? stringValue(summary.contextId) ?? "",
      contextType: stringValue(data.contextType) ?? stringValue(summary.contextType) ?? "",
      finalSteps,
      rankedAt: Timestamp.fromMillis(completionMillis),
      targetStepCount: integerValue(summary.targetStepCount) ?? 0,
      userId,
      workoutId,
    });
  }

  return entries;
}

/**
 * Resolves attempt completion time from the private workout backup.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {string} userId User ID.
 * @param {string} workoutId Workout ID.
 * @param {Record<string, unknown>} entryData Public entry data fallback.
 * @return {Promise<number>} Completion timestamp in milliseconds.
 */
async function completionMillisForEntry(
  firestore,
  userId,
  workoutId,
  entryData
) {
  const workoutSnapshot = await firestore
    .collection("users")
    .doc(userId)
    .collection("workouts")
    .doc(workoutId)
    .get();
  const workout = workoutSnapshot.data() ?? {};
  const startedAtMillis = timestampMillis(workout.startedAt);
  const durationSeconds = numberValue(workout.durationSeconds);

  if (startedAtMillis !== null && durationSeconds !== null) {
    return startedAtMillis + Math.round(durationSeconds * 1000);
  }

  return timestampMillis(entryData.updatedAt) ?? Date.now();
}

/**
 * Builds immutable snapshot documents from enriched completion entries.
 * @param {object[]} entries Enriched entries.
 * @return {object[]} Snapshot write payloads.
 */
function buildCompletionSnapshots(entries) {
  const sorted = [...entries].sort((lhs, rhs) => {
    if (lhs.completionMillis !== rhs.completionMillis) {
      return lhs.completionMillis - rhs.completionMillis;
    }
    return lhs.workoutId.localeCompare(rhs.workoutId);
  });
  const firstCompletionByUser = new Map();

  for (const entry of sorted) {
    const previous = firstCompletionByUser.get(entry.userId);
    if (previous === undefined || entry.completionMillis < previous) {
      firstCompletionByUser.set(entry.userId, entry.completionMillis);
    }
  }

  return sorted.map((entry) => {
    const completedCount = Math.max(
      [...firstCompletionByUser.values()]
        .filter((completedAt) => completedAt <= entry.completionMillis)
        .length,
      1
    );
    const rawRank = entries.filter(
      (candidate) =>
        candidate.completionMillis <= entry.completionMillis &&
        candidate.completionDurationSeconds < entry.completionDurationSeconds
    ).length + 1;

    return {
      completedCount,
      completionDurationSeconds: entry.completionDurationSeconds,
      contextId: entry.contextId,
      contextType: entry.contextType,
      finalSteps: entry.finalSteps,
      // Still clamped on purpose: this backfill ranks entry rows against a
      // distinct-climber count, so its two halves count different populations
      // and only the clamp keeps the pair possible. The live publish path in
      // functions/src/liveReplayLeaderboard.ts counts one population on both
      // halves by construction and therefore dropped its clamp and throws
      // instead; the divergence is deliberate, not an oversight.
      rank: Math.min(rawRank, completedCount),
      rankedAt: entry.rankedAt,
      rankingMetric: "completionDurationSeconds",
      schemaVersion: 1,
      targetStepCount: entry.targetStepCount,
      tiePolicy: "competition_rank_equal_durations_share_rank",
      userId: entry.userId,
      workoutId: entry.workoutId,
      backfilledAt: FieldValue.serverTimestamp(),
      backfillSource: "private_workout_completion_time_v1",
    };
  });
}

/**
 * Reads existing snapshot IDs for one leaderboard context.
 * @param {FirebaseFirestore.DocumentReference} leaderboardRef Context ref.
 * @return {Promise<Set<string>>} Existing snapshot document IDs.
 */
async function existingSnapshotDocumentIds(leaderboardRef) {
  const snapshot = await leaderboardRef.collection(SNAPSHOTS_COLLECTION).get();
  return new Set(snapshot.docs.map((doc) => doc.id));
}

/**
 * Converts common timestamp shapes to epoch milliseconds.
 * @param {unknown} value Timestamp-like value.
 * @return {number | null} Milliseconds, if parseable.
 */
function timestampMillis(value) {
  if (!value) {
    return null;
  }

  if (value instanceof Timestamp) {
    return value.toMillis();
  }

  if (typeof value.toMillis === "function") {
    return value.toMillis();
  }

  if (value instanceof Date) {
    return value.getTime();
  }

  return null;
}

/**
 * Parses a finite number.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed number.
 */
function numberValue(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * Parses a non-negative integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer.
 */
function integerValue(value) {
  return typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 0 ?
    value :
    null;
}

/**
 * Parses a non-empty string.
 * @param {unknown} value Raw value.
 * @return {string | null} Parsed string.
 */
function stringValue(value) {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}
