#!/usr/bin/env node

/**
 * Backfills the best-per-user flag on Live Replay bucket entries.
 *
 * A live race ranks one row per opponent, so exactly one of a user's
 * attempts in a context may carry isBestForUser. New completions get the flag
 * from the Cloud Function; this script covers entries published before it
 * existed. Without it the live race filter matches nothing and the field looks
 * empty.
 *
 * Every context type is touched. Settled by the captain on 2026-09-02: all
 * three board types race off one mechanism, so the server writes the flag on
 * every board and this backfill has to reach the rows written before it did -
 * a client that filters on a flag the rows do not carry renders an empty board.
 * Run it after the Cloud Functions deploy and before the iOS build ships.
 *
 * Only each climber's best attempt is flagged, on the board's own ranking
 * metric - the most steps on a `routine_template` board, the fastest
 * completion everywhere else (`ranksOnSteps`). Attempts already carrying the
 * right flag are left untouched, so a second run writes nothing.
 *
 * The static completion leaderboard reads these same entries unfiltered and
 * still shows every completion. This script never adds or removes an entry.
 *
 * Usage:
 *   node scripts/backfill-live-replay-best-per-user.mjs --project dev --dry-run
 *   node scripts/backfill-live-replay-best-per-user.mjs --project staging
 *   node scripts/backfill-live-replay-best-per-user.mjs --project prod --confirm-production
 *   node scripts/backfill-live-replay-best-per-user.mjs --project dev --context-key live_climb__burj-khalifa
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login
 *
 * The winner selection is exported so scripts/test can run it against fixtures
 * without a Firestore; the run itself starts only when this file is the
 * entrypoint.
 */

import {realpathSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {
  createBatchWriter,
  createProgressReporter,
  listDocumentsAcross,
  withRetry,
} from "./lib/firestore-bulk.mjs";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const PROD_PROJECT_ID = "ascend-prod-9c8f2";
const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const ROUTINE_TEMPLATE_CONTEXT_TYPE = "routine_template";

/**
 * Mirrors `ranksOnSteps` in functions/src/liveReplayLeaderboard.ts. A repair
 * that picked a winner on the metric a board does not rank on would freeze the
 * wrong row permanently, so this must not drift from the server.
 * @param {string} contextType Replay context type.
 * @return {boolean} True when the context ranks on steps.
 */
export function ranksOnSteps(contextType) {
  return contextType === ROUTINE_TEMPLATE_CONTEXT_TYPE;
}
const SPLIT_BUCKETS_COLLECTION = "splitBuckets";
const ENTRIES_COLLECTION = "entries";
const BUCKET_ZERO_DOC_ID = "0";
export const MAX_REPLAY_SPLIT_CHECKPOINTS = 360;
const PROJECT_ALIASES = new Map([
  ["dev", DEV_PROJECT_ID],
  ["staging", STAGING_PROJECT_ID],
  ["prod", PROD_PROJECT_ID],
  ["production", PROD_PROJECT_ID],
]);

if (isEntrypoint()) {
  await main();
}

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

  const db = getFirestore();
  const result = await backfillBestPerUserFlags(db, args);

  console.log(
    [
      `Project: ${projectId}`,
      `Mode: ${args.dryRun ? "dry run" : "write"}`,
      `Contexts scanned: ${result.contextsScanned}`,
      `Contexts skipped (context type unreadable): ${result.contextsSkipped}`,
      `Attempts scanned: ${result.attemptsScanned}`,
      `Climbers scanned: ${result.climbersScanned}`,
      `Repeat climbers collapsed: ${result.repeatClimbersCollapsed}`,
      `Attempts promoted to best: ${result.attemptsPromoted}`,
      `Attempts demoted: ${result.attemptsDemoted}`,
      `Attempts with unknown bucket span: ${result.attemptsWithUnknownSpan}`,
      `Entry writes expected to land (estimate): ${result.entryWritesExpected}`,
      `Buckets swept (upper bound): ${result.entryWritesPlanned}`,
      `${args.dryRun ? "Entry writes that would be applied" : "Entry writes applied"}: ${result.entryWritesApplied}`,
      `Buckets skipped (entry absent): ${result.entryWritesSkipped}`,
      `Entry writes failed: ${result.entryWritesFailed}`,
      `Attempts unreadable: ${result.attemptsSkipped}`,
    ].join("\n")
  );

  if (result.entryWritesFailed > 0) {
    // A dropped flag write leaves a climber duplicated in the live field, so
    // the run must not report success just because the rest of the writes
    // landed.
    console.error(
      `\n${result.entryWritesFailed} entry write(s) failed. Re-run the backfill ` +
      `to reconcile the remaining entries. The applied and failed counts above ` +
      `are approximate: sibling commits may still have been in flight when the ` +
      `first failure was reported.\nFirst error: ${result.firstWriteError}`
    );
    process.exitCode = 1;
  }
}

/**
 * Whether this file was invoked directly rather than imported.
 *
 * Node leaves argv[1] unresolved through symlinks while the ESM loader
 * realpaths the module URL, so a plain compare would make a linked invocation
 * a silent no-op that exits 0.
 * @return {boolean} True when this module is the process entrypoint.
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
 * Parses command-line arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Parsed arguments.
 */
function parseArgs(argv) {
  const parsed = {
    project: "dev",
    dryRun: false,
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
  node scripts/backfill-live-replay-best-per-user.mjs --project dev --dry-run
  node scripts/backfill-live-replay-best-per-user.mjs --project staging
  node scripts/backfill-live-replay-best-per-user.mjs --project prod --confirm-production

Options:
  --project <dev|staging|prod|projectId>
  --context-key <live_replay_context_key>
  --dry-run
  --confirm-production
`);
  process.exit(0);
}

/**
 * Backfills best-per-user flags across every matching replay context.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {object} options Backfill options.
 * @return {Promise<object>} Backfill counts.
 */
async function backfillBestPerUserFlags(firestore, options) {
  const counters = {
    contextsScanned: 0,
    contextsSkipped: 0,
    attemptsScanned: 0,
    climbersScanned: 0,
    repeatClimbersCollapsed: 0,
    attemptsPromoted: 0,
    attemptsDemoted: 0,
    attemptsWithUnknownSpan: 0,
    entryWritesPlanned: 0,
    entryWritesExpected: 0,
    entryWritesApplied: 0,
    entryWritesSkipped: 0,
    entryWritesFailed: 0,
    firstWriteError: null,
    attemptsSkipped: 0,
  };

  const leaderboardRefs = options.contextKey ?
    [firestore.collection(LIVE_REPLAY_COLLECTION).doc(options.contextKey)] :
    await listDocumentsAcross([firestore.collection(LIVE_REPLAY_COLLECTION)]);

  for (const leaderboardRef of leaderboardRefs) {
    const summarySnapshot = await withRetry(() => leaderboardRef.get(), {
      description: `read of ${leaderboardRef.path}`,
    });
    if (!summarySnapshot.exists) {
      continue;
    }

    const summaryData = summarySnapshot.data() ?? {};

    const contextType = resolvedContextType(summaryData, leaderboardRef.id);

    if (contextType === null) {
      counters.contextsSkipped += 1;
      continue;
    }

    counters.contextsScanned += 1;
    await backfillContext(
      firestore,
      leaderboardRef,
      options,
      counters,
      contextType
    );
  }

  return counters;
}

/**
 * The context type a board ranks under, or null when nothing names one.
 *
 * The summary records its own context type; a summary written before that field
 * existed falls back to the context key, which is prefixed with the type.
 * @param {Record<string, unknown>} summaryData Context summary data.
 * @param {string} contextKey Context document ID.
 * @return {string | null} Context type, or null when it cannot be resolved.
 */
function resolvedContextType(summaryData, contextKey) {
  const contextType = typeof summaryData.contextType === "string" ?
    summaryData.contextType :
    contextKey.split("__")[0] ?? "";

  // Every context type carries the flag now, so a board is skipped only when
  // nothing names its type. Guessing one would pick a winner on a metric the
  // board does not rank on and freeze that permanently.
  return contextType.length > 0 ? contextType : null;
}

/**
 * Backfills one replay context.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} leaderboardRef Context document.
 * @param {object} options Backfill options.
 * @param {object} counters Mutated counters.
 */
async function backfillContext(
  firestore,
  leaderboardRef,
  options,
  counters,
  contextType
) {
  const bucketZeroEntries = leaderboardRef
    .collection(SPLIT_BUCKETS_COLLECTION)
    .doc(BUCKET_ZERO_DOC_ID)
    .collection(ENTRIES_COLLECTION);
  const entriesSnapshot = await withRetry(() => bucketZeroEntries.get(), {
    description: `read of ${bucketZeroEntries.path}`,
  });
  const attemptsByUserId = new Map();

  for (const doc of entriesSnapshot.docs) {
    const attempt = userAttemptEntry(doc.data() ?? {}, doc.id, contextType);

    if (attempt === null) {
      counters.attemptsSkipped += 1;
      continue;
    }

    counters.attemptsScanned += 1;
    const attempts = attemptsByUserId.get(attempt.userId) ?? [];
    attempts.push(attempt);
    attemptsByUserId.set(attempt.userId, attempts);
  }

  counters.climbersScanned += attemptsByUserId.size;
  const updates = [];

  for (const attempts of attemptsByUserId.values()) {
    if (attempts.length > 1) {
      counters.repeatClimbersCollapsed += 1;
    }

    updates.push(...bestForUserFlagUpdates(attempts, contextType));
  }

  for (const update of updates) {
    if (update.isBestForUser) {
      counters.attemptsPromoted += 1;
    } else {
      counters.attemptsDemoted += 1;
    }
  }

  await applyEntryUpdates(firestore, leaderboardRef, updates, options, counters);
}

/**
 * Writes flag updates across every bucket each attempt published into.
 *
 * The buckets an attempt actually occupies are listed first and only those are
 * written, because the writes go through `db.batch()` commits and a batch is
 * atomic: one `update()` against a bucket the attempt never published into
 * would fail the whole commit with NOT_FOUND and drop every sibling write.
 * Listing keeps absent buckets absent - never a flag-only row the counts would
 * see - and makes a dry run report exactly what a write run will touch.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} leaderboardRef Context document.
 * @param {object[]} updates Attempt flag updates.
 * @param {object} options Backfill options.
 * @param {object} counters Mutated counters.
 */
async function applyEntryUpdates(
  firestore,
  leaderboardRef,
  updates,
  options,
  counters
) {
  let bucketSpan = 0;

  for (const update of updates) {
    counters.entryWritesPlanned += update.splitBucketCount;
    counters.entryWritesExpected += update.estimatedEntryCount;
    bucketSpan = Math.max(bucketSpan, update.splitBucketCount);

    if (!update.hasKnownBucketSpan) {
      counters.attemptsWithUnknownSpan += 1;
    }
  }

  if (updates.length === 0) {
    return;
  }

  const existingEntryIds = await existingEntryIdsByBucket(
    leaderboardRef,
    bucketSpan
  );
  const plan = entryWritePlan(updates, existingEntryIds);
  counters.entryWritesSkipped += plan.skipped;

  if (options.dryRun) {
    counters.entryWritesApplied += plan.writes.length;
    return;
  }

  const progress = createProgressReporter({
    label: `flags ${leaderboardRef.id}`,
    total: plan.writes.length,
    unit: "entries",
  });
  const writer = createBatchWriter(firestore, {progress});

  for (const write of plan.writes) {
    writer.update(
      leaderboardRef
        .collection(SPLIT_BUCKETS_COLLECTION)
        .doc(String(write.bucketIndex))
        .collection(ENTRIES_COLLECTION)
        .doc(write.workoutId),
      {isBestForUser: write.isBestForUser}
    );
  }

  try {
    await writer.drain();
  } catch (error) {
    counters.entryWritesFailed += plan.writes.length - progress.count();
    counters.firstWriteError ??= String(error);
  } finally {
    counters.entryWritesApplied += progress.finish();
  }
}

/**
 * The entry document IDs present in each split bucket of one context.
 * @param {FirebaseFirestore.DocumentReference} leaderboardRef Context document.
 * @param {number} bucketSpan Buckets to list, from zero.
 * @return {Promise<Map<number, Set<string>>>} Entry IDs keyed by bucket index.
 */
async function existingEntryIdsByBucket(leaderboardRef, bucketSpan) {
  const collections = Array.from({length: bucketSpan}, (_unused, index) =>
    leaderboardRef
      .collection(SPLIT_BUCKETS_COLLECTION)
      .doc(String(index))
      .collection(ENTRIES_COLLECTION)
  );
  const existing = new Map();

  for (const entryRef of await listDocumentsAcross(collections)) {
    const bucketIndex = Number(entryRef.parent.parent.id);
    const ids = existing.get(bucketIndex) ?? new Set();
    ids.add(entryRef.id);
    existing.set(bucketIndex, ids);
  }

  return existing;
}

/**
 * Resolves attempt flag updates to the bucket entries that actually exist.
 * @param {object[]} updates Attempt flag updates.
 * @param {Map<number, Set<string>>} existingEntryIds Entry IDs keyed by bucket index.
 * @return {{writes: object[], skipped: number}} Entry writes to commit, and
 *   the swept buckets holding no entry for the attempt.
 */
export function entryWritePlan(updates, existingEntryIds) {
  const writes = [];
  let skipped = 0;

  for (const update of updates) {
    for (let index = 0; index < update.splitBucketCount; index += 1) {
      if (existingEntryIds.get(index)?.has(update.workoutId)) {
        writes.push({
          bucketIndex: index,
          workoutId: update.workoutId,
          isBestForUser: update.isBestForUser,
        });
      } else {
        skipped += 1;
      }
    }
  }

  return {writes, skipped};
}

/*
 * functions/src/liveReplayLeaderboard.ts owns the best-per-user rule; the
 * helpers below are a deliberate port of it, because scripts/ and functions/
 * are separate npm packages and importing that module would register its
 * Firestore triggers. Both must pick the same winner or the backfill and the
 * trigger will flag different attempts, so keep them in lockstep. The
 * estimatedEntryCount / hasKnownBucketSpan fields are script-local dry-run
 * reporting and have no bearing on which attempt wins.
 */

/**
 * Selects the workout owning a user's best completion in a context, on that
 * context's own ranking metric: the most steps where it ranks on steps, the
 * fastest time otherwise. Equal values resolve on workout ID so every caller
 * picks the same winner.
 * @param {object[]} attempts Published attempts for one user.
 * @param {string} contextType Replay context type.
 * @return {string | null} Winning workout ID, or null when there are none.
 */
export function bestAttemptWorkoutId(attempts, contextType) {
  const onSteps = ranksOnSteps(contextType);
  let best = null;

  for (const attempt of attempts) {
    const beats = best === null ||
      (onSteps ?
        attempt.rankingValue > best.rankingValue :
        attempt.rankingValue < best.rankingValue);
    const breaksTie = best !== null &&
      attempt.rankingValue === best.rankingValue &&
      attempt.workoutId < best.workoutId;

    if (beats || breaksTie) {
      best = attempt;
    }
  }

  return best?.workoutId ?? null;
}

/**
 * Diffs a user's published attempts against the best-per-user rule.
 * Attempts already carrying the right flag are omitted, so a second run of the
 * backfill writes nothing.
 * @param {object[]} attempts Published attempts for one user.
 * @param {string} contextType Replay context type.
 * @return {object[]} Attempts whose flag must change.
 */
export function bestForUserFlagUpdates(attempts, contextType) {
  const winningWorkoutId = bestAttemptWorkoutId(attempts, contextType);

  // Fail closed rather than demote. A climber whose attempts all read as
  // unusable resolves no winner, and writing `false` across them would strip
  // them out of the live race on the strength of a value that could not be
  // read.
  if (winningWorkoutId === null) {
    return [];
  }

  const updates = [];

  for (const attempt of attempts) {
    const isBestForUser = attempt.workoutId === winningWorkoutId;

    if (isBestForUser === attempt.isBestForUser) {
      continue;
    }

    updates.push({
      workoutId: attempt.workoutId,
      splitBucketCount: attempt.splitBucketCount,
      estimatedEntryCount: attempt.estimatedEntryCount,
      hasKnownBucketSpan: attempt.hasKnownBucketSpan,
      isBestForUser,
    });
  }

  return updates;
}

/**
 * Reads one published attempt from its bucket-zero entry document, taking its
 * ranking value from whichever number the context's metric ranks on.
 *
 * Mirrors the server's `userAttemptEntry`: an attempt carrying no usable value
 * for the board's own metric is rejected here rather than admitted and then
 * skipped by the winner selection, so it can never reach the flag diff as a
 * row to demote out of the live race.
 * @param {Record<string, unknown>} data Bucket-zero entry data.
 * @param {string} documentId Entry document ID.
 * @param {string} contextType Replay context type.
 * @return {object | null} Parsed attempt, or null when unusable.
 */
export function userAttemptEntry(data, documentId, contextType) {
  const rankingValue = ranksOnSteps(contextType) ?
    nonNegativeIntegerValue(data.finalSteps) :
    nonNegativeNumberValue(data.completionDurationSeconds);
  const userId = typeof data.userId === "string" ? data.userId : null;

  if (rankingValue === null || userId === null) {
    return null;
  }

  return {
    workoutId: typeof data.workoutId === "string" ? data.workoutId : documentId,
    userId,
    rankingValue,
    splitBucketCount: attemptSplitBucketCount(data),
    estimatedEntryCount: estimatedPublishedBucketCount(data),
    hasKnownBucketSpan: hasStoredBucketSpan(data),
    isBestForUser: data.isBestForUser === true,
  };
}

/**
 * Bucket span to sweep when re-flagging a published attempt.
 * Entries written before best-per-user collapse carry no stored span, and the
 * curve length the Cloud Function sized the attempt with cannot be recovered
 * from the entry, so legacy attempts sweep the whole checkpoint range. Flags
 * are written with update(), so buckets an attempt never published into fail
 * NOT_FOUND and are skipped, whereas undercounting would strand the final
 * bucket of a promoted climber.
 * @param {Record<string, unknown>} data Bucket-zero entry data.
 * @return {number} Number of buckets to sweep for the attempt.
 */
function attemptSplitBucketCount(data) {
  const storedCount = positiveIntegerValue(data.splitBucketCount);

  if (storedCount === null) {
    return MAX_REPLAY_SPLIT_CHECKPOINTS;
  }

  return Math.min(storedCount, MAX_REPLAY_SPLIT_CHECKPOINTS);
}

/**
 * Whether an entry records the bucket span it actually published into.
 * @param {Record<string, unknown>} data Bucket-zero entry data.
 * @return {boolean} True when the span is known rather than speculative.
 */
function hasStoredBucketSpan(data) {
  return positiveIntegerValue(data.splitBucketCount) !== null;
}

/**
 * Best estimate of how many buckets an attempt really published into.
 *
 * Reporting only: never drive writes from this. attemptSplitBucketCount errs
 * high on purpose so a promoted climber's final bucket always gets flagged, but
 * a dry run that credited the whole sweep would overstate a production run
 * several times over. A stored span is exact; a legacy entry can only be
 * estimated from the interval math the publisher used at the time.
 * @param {Record<string, unknown>} data Bucket-zero entry data.
 * @return {number} Estimated number of buckets holding this attempt.
 */
function estimatedPublishedBucketCount(data) {
  const storedCount = positiveIntegerValue(data.splitBucketCount);

  if (storedCount !== null) {
    return Math.min(storedCount, MAX_REPLAY_SPLIT_CHECKPOINTS);
  }

  const durationSeconds = nonNegativeNumberValue(
    data.completionDurationSeconds
  ) ?? 0;
  const intervalSeconds = positiveIntegerValue(data.splitIntervalSeconds) ?? 1;

  return Math.min(
    Math.floor(durationSeconds / intervalSeconds) + 1,
    MAX_REPLAY_SPLIT_CHECKPOINTS
  );
}

/**
 * Returns a non-negative finite number.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed number, if valid.
 */
function nonNegativeNumberValue(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return null;
  }

  return value;
}

/**
 * Returns a non-negative integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer, if valid.
 */
function nonNegativeIntegerValue(value) {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    return null;
  }

  return value;
}

/**
 * Returns a positive integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer, if valid.
 */
function positiveIntegerValue(value) {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    return null;
  }

  return value;
}
