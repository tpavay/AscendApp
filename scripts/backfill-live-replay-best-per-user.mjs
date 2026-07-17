#!/usr/bin/env node

/**
 * Backfills the best-per-user flag on per-climb Live Replay bucket entries.
 *
 * A per-climb race ranks one row per opponent, so exactly one of a user's
 * attempts in a context may carry isBestForUser. New completions get the flag
 * from the Cloud Function; this script covers entries published before it
 * existed. Without it the live race filter matches nothing and the field looks
 * empty.
 *
 * Only live_climb contexts are touched. Every other context races each
 * completed attempt as its own opponent and carries no flag, so collapsing
 * their entries on fastest-wins would pick the wrong attempt.
 *
 * Only each climber's fastest attempt is written. Firestore's equality filter
 * never matches a document missing the field, so slower attempts are already
 * excluded from the live race and are left untouched.
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
 */

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const PROD_PROJECT_ID = "ascend-prod-9c8f2";
const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const SPLIT_BUCKETS_COLLECTION = "splitBuckets";
const ENTRIES_COLLECTION = "entries";
const BUCKET_ZERO_DOC_ID = "0";
const MAX_REPLAY_SPLIT_CHECKPOINTS = 360;
const FIRESTORE_NOT_FOUND_CODE = 5;
const BULK_WRITER_MAX_ATTEMPTS = 3;
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
const result = await backfillBestPerUserFlags(db, args);

console.log(
  [
    `Project: ${projectId}`,
    `Mode: ${args.dryRun ? "dry run" : "write"}`,
    `Contexts scanned (live_climb): ${result.contextsScanned}`,
    `Contexts skipped (races every attempt): ${result.contextsSkipped}`,
    `Attempts scanned: ${result.attemptsScanned}`,
    `Climbers scanned: ${result.climbersScanned}`,
    `Repeat climbers collapsed: ${result.repeatClimbersCollapsed}`,
    `Attempts promoted to best: ${result.attemptsPromoted}`,
    `Attempts demoted: ${result.attemptsDemoted}`,
    `Attempts with unknown bucket span: ${result.attemptsWithUnknownSpan}`,
    `Entry writes expected to land (estimate): ${result.entryWritesExpected}`,
    `Entry writes attempted (upper bound): ${result.entryWritesPlanned}`,
    `Entry writes applied: ${result.entryWritesApplied}`,
    `Entry writes skipped (bucket absent): ${result.entryWritesSkipped}`,
    `Entry writes failed: ${result.entryWritesFailed}`,
    `Attempts unreadable: ${result.attemptsSkipped}`,
  ].join("\n")
);

if (result.entryWritesFailed > 0) {
  // A dropped flag write leaves a climber duplicated in the live field, so the
  // run must not report success just because the rest of the writes landed.
  console.error(
    `\n${result.entryWritesFailed} entry write(s) failed. Re-run the backfill ` +
    `to reconcile the remaining entries.\nFirst error: ${result.firstWriteError}`
  );
  process.exitCode = 1;
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
    (await firestore.collection(LIVE_REPLAY_COLLECTION).get()).docs.map(
      (doc) => doc.ref
    );

  for (const leaderboardRef of leaderboardRefs) {
    const summarySnapshot = await leaderboardRef.get();
    if (!summarySnapshot.exists) {
      continue;
    }

    const summaryData = summarySnapshot.data() ?? {};

    if (!collapsesRepeatFinishers(summaryData, leaderboardRef.id)) {
      counters.contextsSkipped += 1;
      continue;
    }

    counters.contextsScanned += 1;
    await backfillContext(firestore, leaderboardRef, options, counters);
  }

  return counters;
}

/**
 * Whether a context races one row per climber rather than one per attempt.
 *
 * Only per-climb contexts collapse repeats, so only they carry the flag. The
 * summary records its own context type; a summary written before that field
 * existed falls back to the context key, which is prefixed with the type.
 * @param {Record<string, unknown>} summaryData Context summary data.
 * @param {string} contextKey Context document ID.
 * @return {boolean} True when the context collapses repeat finishers.
 */
function collapsesRepeatFinishers(summaryData, contextKey) {
  const contextType = typeof summaryData.contextType === "string" ?
    summaryData.contextType :
    contextKey.split("__")[0];

  return contextType === LIVE_CLIMB_CONTEXT_TYPE;
}

/**
 * Backfills one replay context.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} leaderboardRef Context document.
 * @param {object} options Backfill options.
 * @param {object} counters Mutated counters.
 */
async function backfillContext(firestore, leaderboardRef, options, counters) {
  const entriesSnapshot = await leaderboardRef
    .collection(SPLIT_BUCKETS_COLLECTION)
    .doc(BUCKET_ZERO_DOC_ID)
    .collection(ENTRIES_COLLECTION)
    .get();
  const attemptsByUserId = new Map();

  for (const doc of entriesSnapshot.docs) {
    const attempt = userAttemptEntry(doc.data() ?? {}, doc.id);

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

    updates.push(...bestForUserFlagUpdates(attempts));
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
  for (const update of updates) {
    counters.entryWritesPlanned += update.splitBucketCount;
    counters.entryWritesExpected += update.estimatedEntryCount;

    if (!update.hasKnownBucketSpan) {
      counters.attemptsWithUnknownSpan += 1;
    }
  }

  if (options.dryRun) {
    return;
  }

  // BulkWriter rather than a batch: a batch is atomic, so one entry deleted
  // mid-run would drop every other write with it.
  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => {
    if (error.code === FIRESTORE_NOT_FOUND_CODE) {
      return false;
    }

    return error.failedAttempts < BULK_WRITER_MAX_ATTEMPTS;
  });

  for (const update of updates) {
    for (let index = 0; index < update.splitBucketCount; index += 1) {
      const entryRef = leaderboardRef
        .collection(SPLIT_BUCKETS_COLLECTION)
        .doc(String(index))
        .collection(ENTRIES_COLLECTION)
        .doc(update.workoutId);

      // update() rather than set(): a bucket this attempt never published into
      // must stay absent, not appear as a flag-only row the counts would see.
      writer
        .update(entryRef, {isBestForUser: update.isBestForUser})
        .then(() => {
          counters.entryWritesApplied += 1;
        })
        .catch((error) => {
          if (isNotFoundWriteError(error)) {
            counters.entryWritesSkipped += 1;
            return;
          }

          counters.entryWritesFailed += 1;
          counters.firstWriteError ??= String(error);
        });
    }
  }

  await writer.close();
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
 * Selects the workout owning a user's best (fastest) completion in a context.
 * Equal durations resolve on workout ID so every caller picks the same winner.
 * @param {object[]} attempts Published attempts for one user.
 * @return {string | null} Winning workout ID, or null when there are none.
 */
function bestAttemptWorkoutId(attempts) {
  let best = null;

  for (const attempt of attempts) {
    const isFaster = best === null ||
      attempt.completionDurationSeconds < best.completionDurationSeconds;
    const breaksTie = best !== null &&
      attempt.completionDurationSeconds === best.completionDurationSeconds &&
      attempt.workoutId < best.workoutId;

    if (isFaster || breaksTie) {
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
 * @return {object[]} Attempts whose flag must change.
 */
function bestForUserFlagUpdates(attempts) {
  const winningWorkoutId = bestAttemptWorkoutId(attempts);
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
 * Reads one published attempt from its bucket-zero entry document.
 * @param {Record<string, unknown>} data Bucket-zero entry data.
 * @param {string} documentId Entry document ID.
 * @return {object | null} Parsed attempt, or null when unusable.
 */
function userAttemptEntry(data, documentId) {
  const completionDurationSeconds = nonNegativeNumberValue(
    data.completionDurationSeconds
  );
  const userId = typeof data.userId === "string" ? data.userId : null;

  if (completionDurationSeconds === null || userId === null) {
    return null;
  }

  return {
    workoutId: typeof data.workoutId === "string" ? data.workoutId : documentId,
    userId,
    completionDurationSeconds,
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

/**
 * Skips writes to buckets an attempt never published into.
 * @param {unknown} error Rejected BulkWriter write error.
 * @return {boolean} Whether the write failed because the entry is absent.
 */
function isNotFoundWriteError(error) {
  return typeof error === "object" &&
    error !== null &&
    error.code === FIRESTORE_NOT_FOUND_CODE;
}
