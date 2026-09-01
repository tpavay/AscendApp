#!/usr/bin/env node

/**
 * Backfills immutable Live Replay completion-rank snapshots.
 *
 * New completions get snapshots from the Cloud Function. This script covers
 * existing leaderboard rows by reconstructing attempt completion time from the
 * private workout backup when available.
 *
 * It is also the repair path for snapshots frozen while the numerator counted a
 * climber's own leading row and then subtracted it back out: run it with
 * `--force` over one context to rewrite them.
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

import {realpathSync} from "node:fs";
import {fileURLToPath} from "node:url";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const PROD_PROJECT_ID = "ascend-prod-9c8f2";
const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const JUST_CLIMB_CONTEXT_TYPE = "just_climb";
const ROUTINE_TEMPLATE_CONTEXT_TYPE = "routine_template";
const ROUTINE_CONTEXT_TYPE = "routine";
// Mirrors `LiveReplayLeaderboardContextType`. A type outside this set decides
// nothing here: it is the switch behind the standing rule, the ranking metric,
// the tie policy and the direction of "ahead", all of which get frozen into a
// write-once snapshot.
const KNOWN_CONTEXT_TYPES = new Set([
  LIVE_CLIMB_CONTEXT_TYPE,
  JUST_CLIMB_CONTEXT_TYPE,
  ROUTINE_TEMPLATE_CONTEXT_TYPE,
  ROUTINE_CONTEXT_TYPE,
]);
const CONTEXT_KEY_SEPARATOR = "__";
const DURATION_RANKING_METRIC = "completionDurationSeconds";
const STEPS_RANKING_METRIC = "finalSteps";
const DURATION_TIE_POLICY = "competition_rank_equal_durations_share_rank";
const STEPS_TIE_POLICY = "competition_rank_equal_steps_share_rank";
const SNAPSHOTS_COLLECTION = "completionSnapshots";
const BUCKET_ZERO_DOC_ID = "0";
const MAX_BATCH_WRITES = 450;
const PROJECT_ALIASES = new Map([
  ["dev", DEV_PROJECT_ID],
  ["staging", STAGING_PROJECT_ID],
  ["prod", PROD_PROJECT_ID],
  ["production", PROD_PROJECT_ID],
]);

// Node leaves argv[1] unresolved through symlinks while the ESM loader
// realpaths the module URL, so a plain compare makes this whole tool a silent
// no-op that exits 0 whenever it is invoked through a linked path.
if (isEntrypoint()) {
  await main();
}

/**
 * Resolves whether this module was invoked as the command, not imported.
 * @return {boolean} True when this file is the process entrypoint.
 */
function isEntrypoint() {
  const invoked = process.argv[1];
  if (!invoked) {
    return false;
  }
  try {
    return realpathSync(invoked) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

/**
 * Runs the backfill and prints its report.
 */
async function main() {
  const args = parseArgs(process.argv);
  const projectId = resolveProjectId(args.project);

  if (projectId === PROD_PROJECT_ID && !args.dryRun && !args.confirmProduction) {
    throw new Error("Production backfill requires --confirm-production.");
  }

  initializeApp({
    credential: applicationDefault(),
    projectId,
  });

  const result = await backfillCompletionSnapshots(getFirestore(), args);

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
}

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
    const {entries, skipped} = await completionEntriesForContext(
      firestore,
      leaderboardRef,
      summary
    );
    counters.entriesScanned += entries.length;
    counters.entriesSkipped += skipped;

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
 * @return {Promise<{entries: object[], skipped: number}>} Enriched entries and
 *   the count of rows this pass refused to rank.
 */
async function completionEntriesForContext(firestore, leaderboardRef, summary) {
  const entriesSnapshot = await leaderboardRef
    .collection("splitBuckets")
    .doc(BUCKET_ZERO_DOC_ID)
    .collection("entries")
    .get();
  const entries = [];
  let skipped = 0;

  for (const doc of entriesSnapshot.docs) {
    const data = doc.data();
    const userId = stringValue(data.userId);
    const workoutId = stringValue(data.workoutId) ?? doc.id;
    const completionDurationSeconds = numberValue(
      data.completionDurationSeconds
    );
    const finalSteps = integerValue(data.finalSteps);

    if (!userId || !workoutId || !completionDurationSeconds || !finalSteps) {
      skipped += 1;
      continue;
    }

    const contextType = resolveContextType(
      [stringValue(data.contextType), stringValue(summary.contextType)],
      leaderboardRef.id
    );

    // A guessed context type is worse than no repair. It decides climbers
    // against attempts, the ranking metric, the tie policy and which direction
    // "ahead" runs, and the snapshot it lands in is written once and never
    // moves - so an unresolvable row is left exactly as it stands.
    if (!contextType) {
      skipped += 1;
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
      contextType,
      finalSteps,
      rankedAt: Timestamp.fromMillis(completionMillis),
      targetStepCount: integerValue(summary.targetStepCount) ?? 0,
      userId,
      workoutId,
    });
  }

  return {entries, skipped};
}

/**
 * Resolves a row's context type from its stored values, then from the context
 * key, and refuses anything it cannot recognise.
 *
 * The stored field predates this repair path on some boards, and the key is the
 * one place the type is structurally present: a leaderboard document ID is
 * `<contextType>__<sanitizedId>` (`LiveReplayLeaderboardContext.contextKey`),
 * and the sanitizer never emits a prefix that collides with a different type.
 * @param {Array<string|null>} storedValues Stored context types, best first.
 * @param {string} contextKey Leaderboard document ID.
 * @return {string|null} A known context type, or null.
 */
export function resolveContextType(storedValues, contextKey) {
  for (const candidate of storedValues) {
    if (candidate && KNOWN_CONTEXT_TYPES.has(candidate)) {
      return candidate;
    }
  }

  const separatorIndex = String(contextKey ?? "").indexOf(CONTEXT_KEY_SEPARATOR);
  if (separatorIndex <= 0) {
    return null;
  }

  const derived = String(contextKey).slice(0, separatorIndex);
  return KNOWN_CONTEXT_TYPES.has(derived) ? derived : null;
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
export function buildCompletionSnapshots(entries) {
  const sorted = [...entries].sort((lhs, rhs) => {
    if (lhs.completionMillis !== rhs.completionMillis) {
      return lhs.completionMillis - rhs.completionMillis;
    }
    return lhs.workoutId.localeCompare(rhs.workoutId);
  });

  return sorted.map((entry) => {
    // One population on both halves, the same one the live publish path counts:
    // distinct climbers where the board collapses repeat finishers, attempts
    // everywhere else. Two halves counting different populations is what needed
    // a `Math.min` clamp to stay possible at all, and that clamp is what made a
    // repeat climber's slower run read "1st of 1".
    //
    // Ordered on the metric the publish path ranks that board on, taken from
    // one predicate that mirrors the server: a routine template fixes the clock
    // and ranks on steps, everything else ranks on the clock. A repair that
    // picked either answer on its own would freeze a permanent order the board
    // contradicts.
    const completedSoFar = entries.filter(
      (candidate) => candidate.completionMillis <= entry.completionMillis
    );
    const {completedCount, rank} = collapsesRepeatFinishers(entry.contextType) ?
      climberStanding(completedSoFar, entry) :
      attemptStanding(completedSoFar, entry);

    return {
      completedCount,
      completionDurationSeconds: entry.completionDurationSeconds,
      contextId: entry.contextId,
      contextType: entry.contextType,
      finalSteps: entry.finalSteps,
      rank,
      rankedAt: entry.rankedAt,
      rankingMetric: rankingMetricFor(entry.contextType),
      schemaVersion: 1,
      targetStepCount: entry.targetStepCount,
      tiePolicy: tiePolicyFor(entry.contextType),
      userId: entry.userId,
      workoutId: entry.workoutId,
      backfilledAt: FieldValue.serverTimestamp(),
      backfillSource: "private_workout_completion_time_v1",
    };
  });
}

/**
 * Whether a context races one row per climber rather than one per attempt.
 *
 * Mirrors `collapsesRepeatFinishers` in functions/src/liveReplayLeaderboard.ts,
 * so a repaired snapshot and a freshly frozen one count the same population.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when the context collapses repeat finishers.
 */
export function collapsesRepeatFinishers(contextType) {
  return contextType === LIVE_CLIMB_CONTEXT_TYPE ||
    contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE;
}

/**
 * Whether a context ranks on steps rather than on the clock.
 *
 * Mirrors `ranksOnSteps` in functions/src/liveReplayLeaderboard.ts exactly:
 * `routine_template` and nothing else. A routine template fixes the clock, so
 * its field is ordered by steps and higher wins; every other board - a plain
 * `routine` included - is ordered on the clock by the publish path.
 *
 * This script is the repair path and runs over every board unless
 * `--context-key` scopes it, so disagreeing with the publish path here does not
 * merely fail to fix a board, it reorders a correct one on a metric it does not
 * rank on and freezes that permanently. `scripts/test/` pins the two predicates
 * against each other for exactly that reason.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when the context ranks on steps.
 */
export function ranksOnSteps(contextType) {
  return contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE;
}

/**
 * Whether one ranking value stands strictly ahead of another.
 *
 * The one place this file expresses "ahead", mirroring `beatsOnMetric` on the
 * server, so a repaired snapshot can never be ordered by a metric the board
 * does not rank on.
 * @param {string} contextType Replay context type.
 * @param {number} value Candidate ranking value.
 * @param {number} other Ranking value to beat.
 * @return {boolean} True when value is strictly better than other.
 */
function beatsOnMetric(contextType, value, other) {
  return ranksOnSteps(contextType) ? value > other : value < other;
}

/**
 * The value one completion is ranked on, in its context's own metric.
 * @param {string} contextType Replay context type.
 * @param {object} entry Enriched entry.
 * @return {number} Ranking value.
 */
function rankingValueFor(contextType, entry) {
  return ranksOnSteps(contextType) ?
    entry.finalSteps :
    entry.completionDurationSeconds;
}

/**
 * The field name a context's snapshots record their ordering against.
 *
 * Stamped from the same predicate the ordering used, so the recorded metric can
 * never name a field the rank was not computed on.
 * @param {string} contextType Replay context type.
 * @return {string} Ranking metric field name.
 */
export function rankingMetricFor(contextType) {
  return ranksOnSteps(contextType) ?
    STEPS_RANKING_METRIC :
    DURATION_RANKING_METRIC;
}

/**
 * How a context resolves completions that tie on its ranking metric.
 * @param {string} contextType Replay context type.
 * @return {string} Tie policy identifier.
 */
export function tiePolicyFor(contextType) {
  return ranksOnSteps(contextType) ? STEPS_TIE_POLICY : DURATION_TIE_POLICY;
}

/**
 * Standing on a board that collapses a climber's repeat runs to their best.
 *
 * Both halves count distinct climbers, and the numerator compares against this
 * climber's own best at that moment - which already includes the attempt being
 * stamped - so their own row can never satisfy a strictly-faster filter and
 * nothing has to be subtracted back out.
 * @param {object[]} completedSoFar Attempts completed by this moment.
 * @param {object} entry Attempt being stamped.
 * @return {{completedCount: number, rank: number}} Standing.
 */
export function climberStanding(completedSoFar, entry) {
  const contextType = entry.contextType;
  const bestByUser = new Map();

  for (const candidate of completedSoFar) {
    const value = rankingValueFor(contextType, candidate);
    const best = bestByUser.get(candidate.userId);
    if (best === undefined || beatsOnMetric(contextType, value, best)) {
      bestByUser.set(candidate.userId, value);
    }
  }

  const ownBest = bestByUser.get(entry.userId) ??
    rankingValueFor(contextType, entry);
  const rank = [...bestByUser.values()]
    .filter((best) => beatsOnMetric(contextType, best, ownBest))
    .length + 1;

  return {completedCount: Math.max(bestByUser.size, 1), rank};
}

/**
 * Standing on a board that races every attempt as its own opponent.
 *
 * Strictly faster only, so attempts tied on the clock share a rank. Every row
 * counted here is one of the rows `completedCount` counted, so the pair is
 * coherent by construction and needs no clamp.
 * @param {object[]} completedSoFar Attempts completed by this moment.
 * @param {object} entry Attempt being stamped.
 * @return {{completedCount: number, rank: number}} Standing.
 */
export function attemptStanding(completedSoFar, entry) {
  const contextType = entry.contextType;
  const entryValue = rankingValueFor(contextType, entry);
  const rank = completedSoFar.filter(
    (candidate) => beatsOnMetric(
      contextType,
      rankingValueFor(contextType, candidate),
      entryValue
    )
  ).length + 1;

  return {completedCount: Math.max(completedSoFar.length, 1), rank};
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
