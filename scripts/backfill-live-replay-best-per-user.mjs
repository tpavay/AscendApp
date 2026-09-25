#!/usr/bin/env node

/**
 * Backfills the race-best flags on Live Replay bucket entries: `isBestForUser`
 * on every board, and `bestForGoals` on the global Just Climb board.
 *
 * A live race ranks one row per opponent, so exactly one of a climber's
 * attempts in a context carries `isBestForUser`, and on the global Just Climb
 * board each entry also carries the goal keys its attempt is that climber's
 * best under. New completions get both from the Cloud Function
 * (`reconcileUserBestEntries`); this script covers what was published before
 * the rule the function now applies. The rule itself is The rank model,
 * statement 1, in `ascend-leaderboards` (settled by the captain on
 * 2026-09-22): with no goal a Just Climb's best is the most steps, with a step
 * goal the fastest run to that count, with a duration goal the most steps
 * within it. Before that rule the collapse ran on the board's duration metric
 * and flagged the captain's shortest climb as his best.
 *
 * This is a one-time step of the release that ships the rule, run once per
 * environment after the Cloud Functions deploy and before the iOS build - the
 * captain ruled out a recurring scheduled job on 2026-09-22. It is idempotent:
 * a second run on corrected data writes nothing and says so. It never stops on
 * one climber: a climber whose entries cannot be read or written is logged the
 * moment it fails, the run continues, and every skipped climber is named again
 * at the end. Each board prints a progress line every two seconds.
 *
 * A climber's writes are split into commits by `bestForGoals` elements as well
 * as by count (`scripts/lib/race-goal-commit-budget.mjs`): one commit of 360
 * rows x 65 goal keys was refused as `Transaction too big` on staging, and a
 * production climber carries 117. So a climber is no longer one atomic
 * commit, and what keeps a partial write recoverable is order: every bucket
 * but zero commits first, and bucket zero - the row this script and the
 * trigger both diff against - only once the rest have landed. A climber that
 * fails part-way still reads as unmigrated, and the next run rewrites them
 * whole. A dry run plans the same commits, and names any climber the write
 * run could not keep under the budget instead of promising a clean run.
 *
 * The winner selection is `scripts/lib/live-replay-race-best.mjs`, the same
 * module the seeds use and the mirror of `functions/src/liveReplayRaceBest.ts`,
 * pinned to it by `SharedTestVectors/live-replay-race-best-vector.json` - so
 * this script and the trigger can never flag different attempts.
 *
 * Usage:
 *   node scripts/backfill-live-replay-best-per-user.mjs --env dev --dry-run
 *   node scripts/backfill-live-replay-best-per-user.mjs --env staging
 *   node scripts/backfill-live-replay-best-per-user.mjs --env prod --confirm-production ascend-prod-9c8f2 --dry-run
 *   node scripts/backfill-live-replay-best-per-user.mjs --env prod --confirm-production ascend-prod-9c8f2
 *   node scripts/backfill-live-replay-best-per-user.mjs --env dev --context-key just_climb__global
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login
 *
 * The planning half is exported so scripts/test can run it against fixtures
 * without a Firestore; the run itself starts only when this file is the
 * entrypoint.
 */

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {
  PhaseStalledError,
  createBatchWriter,
  createProgressReporter,
  listDocumentsAcross,
  planCommits,
  withRetry,
} from "./lib/firestore-bulk.mjs";
import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {
  GOAL_KEY_COMMIT_BUDGET,
  MAX_GOAL_KEYS_PER_COMMIT,
} from "./lib/race-goal-commit-budget.mjs";
import {
  contextRacesGoals,
  raceBestOnSteps,
  raceGoalKeysByWorkoutId,
} from "./lib/live-replay-race-best.mjs";

export const PRODUCTION_PROJECT_ID = "ascend-prod-9c8f2";
export const ENVIRONMENTS = Object.freeze({
  dev: "ascend-f2e4f",
  staging: "ascend-staging-fa7d5",
  prod: PRODUCTION_PROJECT_ID,
});

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const SPLIT_BUCKETS_COLLECTION = "splitBuckets";
const ENTRIES_COLLECTION = "entries";
const ATTEMPT_CURVES_COLLECTION = "attemptCurves";
const BUCKET_ZERO_DOC_ID = "0";
export const MAX_REPLAY_SPLIT_CHECKPOINTS = 360;
const DEFAULT_SPLIT_INTERVAL_SECONDS = 10;

if (isEntrypoint(import.meta.url)) {
  await main();
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printUsage();
    return;
  }

  const target = resolveTarget(args);
  initializeApp({credential: applicationDefault(), projectId: target.projectId});

  const report = await backfillRaceBests(getFirestore(), args);
  console.log(renderReport(report, {target, dryRun: args.dryRun}));

  if (report.skippedClimbers.length > 0 || (args.dryRun && report.oversizedClimbers.length > 0)) {
    // A climber left behind is a climber duplicated or missing in the live
    // field, so the run must not read as a success just because every other
    // climber landed - and a dry run that plans a commit over the budget has
    // not shown that the write run will land them.
    process.exitCode = 1;
  }
}

/**
 * Parses command-line arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Parsed arguments.
 */
export function parseArgs(argv) {
  const parsed = {
    env: null,
    confirmProduction: null,
    dryRun: false,
    contextKey: null,
    help: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--env":
        parsed.env = requireValue(argv, ++index, "--env");
        break;
      case "--confirm-production":
        parsed.confirmProduction = requireValue(argv, ++index, "--confirm-production");
        break;
      case "--context-key":
        parsed.contextKey = requireValue(argv, ++index, "--context-key");
        break;
      case "--dry-run":
        parsed.dryRun = true;
        break;
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  return parsed;
}

/**
 * The environment a run targets, with the same refusal shape as the other
 * production scripts: `--env` is required, and production additionally needs
 * `--confirm-production` spelling out its project id - for a dry run too,
 * because a dry run still reads real climbers' data.
 * @param {{env: string | null, confirmProduction: string | null}} args Parsed
 *   arguments.
 * @return {{projectId: string, env: string, label: string}} Resolved target.
 */
export function resolveTarget({env = null, confirmProduction = null} = {}) {
  if (env === null) {
    throw new Error(
      "No target. Pass --env dev, --env staging, or --env prod " +
        `--confirm-production ${PRODUCTION_PROJECT_ID}.`
    );
  }
  if (!Object.hasOwn(ENVIRONMENTS, env)) {
    throw new Error(
      `Unknown environment "${env}". Use one of: ${Object.keys(ENVIRONMENTS).join(", ")}.`
    );
  }

  const projectId = ENVIRONMENTS[env];
  if (projectId === PRODUCTION_PROJECT_ID && confirmProduction !== projectId) {
    throw new Error(
      `Production requires --confirm-production ${PRODUCTION_PROJECT_ID}.`
    );
  }

  return {projectId, env, label: `${projectId} (${env})`};
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

function printUsage() {
  console.log(`
Usage:
  node scripts/backfill-live-replay-best-per-user.mjs --env dev --dry-run
  node scripts/backfill-live-replay-best-per-user.mjs --env staging
  node scripts/backfill-live-replay-best-per-user.mjs --env prod --confirm-production ${PRODUCTION_PROJECT_ID} --dry-run
  node scripts/backfill-live-replay-best-per-user.mjs --env prod --confirm-production ${PRODUCTION_PROJECT_ID}

Options:
  --env dev|staging|prod          Required.
  --confirm-production <id>       Required for prod; must equal ${PRODUCTION_PROJECT_ID}.
  --context-key <key>             One board only, e.g. just_climb__global.
  --dry-run                       Report what would change without writing.
`);
}

/**
 * Backfills race-best flags across every matching replay board.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {{dryRun: boolean, contextKey: string | null}} options Run options.
 * @return {Promise<object>} The run report.
 */
export async function backfillRaceBests(db, options) {
  const report = {
    boards: [],
    boardsSkipped: [],
    skippedClimbers: [],
    oversizedClimbers: [],
  };
  const boardRefs = options.contextKey ?
    [db.collection(LIVE_REPLAY_COLLECTION).doc(options.contextKey)] :
    await listDocumentsAcross([db.collection(LIVE_REPLAY_COLLECTION)]);

  for (const boardRef of boardRefs) {
    const summary = await withRetry(() => boardRef.get(), {
      description: `read of ${boardRef.path}`,
    });
    const contextType = resolvedContextType(summary.data() ?? {}, boardRef.id);
    if (contextType === null) {
      report.boardsSkipped.push({contextKey: boardRef.id, reason: "context type unreadable"});
      continue;
    }

    report.boards.push(await backfillBoard(db, boardRef, contextType, options, report));
  }

  return report;
}

/**
 * The context type a board races under, or null when nothing names one.
 * @param {Record<string, unknown>} summaryData Board summary data.
 * @param {string} contextKey Board document ID.
 * @return {string | null} Context type.
 */
export function resolvedContextType(summaryData, contextKey) {
  const contextType = typeof summaryData.contextType === "string" ?
    summaryData.contextType :
    contextKey.split("__")[0] ?? "";
  return contextType.length > 0 ? contextType : null;
}

/**
 * Backfills one board, climber by climber, recording each climber that could
 * not be brought onto the rule rather than stopping on them.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} boardRef Board document.
 * @param {string} contextType Replay context type.
 * @param {{dryRun: boolean}} options Run options.
 * @param {object} report Run report, mutated.
 * @return {Promise<object>} The board's summary.
 */
async function backfillBoard(db, boardRef, contextType, options, report) {
  const board = {
    contextKey: boardRef.id,
    contextType,
    racesGoals: contextRacesGoals(contextType),
    attemptsScanned: 0,
    attemptsUnreadable: 0,
    climbersScanned: 0,
    climbersChanged: 0,
    climbersSkipped: 0,
    attemptsPromoted: 0,
    attemptsDemoted: 0,
    goalKeyRewrites: 0,
    curvesRebuilt: 0,
    entryWritesPlanned: 0,
    entryWritesApplied: 0,
    bucketsWithoutEntry: 0,
    commitsPlanned: 0,
    largestCommitGoalKeys: 0,
  };
  const entries = await withRetry(
    () => boardRef.collection(SPLIT_BUCKETS_COLLECTION).doc(BUCKET_ZERO_DOC_ID)
      .collection(ENTRIES_COLLECTION).get(),
    {description: `read of ${boardRef.path}/splitBuckets/0/entries`}
  );
  const attemptsByUserId = new Map();

  for (const doc of entries.docs) {
    const attempt = userAttemptEntry(doc.data() ?? {}, doc.id, contextType);
    if (attempt === null) {
      board.attemptsUnreadable += 1;
      continue;
    }
    board.attemptsScanned += 1;
    const attempts = attemptsByUserId.get(attempt.userId) ?? [];
    attempts.push(attempt);
    attemptsByUserId.set(attempt.userId, attempts);
  }
  board.climbersScanned = attemptsByUserId.size;

  const progress = createProgressReporter({
    label: boardRef.id,
    total: attemptsByUserId.size,
    unit: "climbers",
  });
  const noteWrites = () => {
    progress.note(
      (options.dryRun ?
        `${board.entryWritesPlanned.toLocaleString()} entry writes planned` :
        `${board.entryWritesApplied.toLocaleString()}/${board.entryWritesPlanned.toLocaleString()} entry writes applied`) +
      (board.climbersSkipped > 0 ? `, ${board.climbersSkipped} climber(s) skipped` : "")
    );
  };

  let existingEntryIds = null;
  try {
    for (const [userId, attempts] of attemptsByUserId) {
      progress.assertAlive();
      try {
        const curves = board.racesGoals ?
          await attemptCurves(db, boardRef, attempts, options, board, progress) :
          null;
        const {updates} = planClimberUpdates({attempts, contextType, curves});
        if (updates.length > 0) {
          existingEntryIds ??= await existingEntryIdsByBucket(
            boardRef,
            Math.max(...[...attemptsByUserId.values()].flat().map((a) => a.splitBucketCount))
          );
          const plan = entryWritePlan(updates, existingEntryIds);
          const phases = entryUpdatePhases(boardRef, plan.writes);
          const commits = plannedEntryCommits(phases);
          const heaviestCommit = commits.reduce((heaviest, commit) => Math.max(heaviest, commit.weight), 0);
          board.climbersChanged += 1;
          board.bucketsWithoutEntry += plan.skipped;
          board.entryWritesPlanned += plan.writes.length;
          board.commitsPlanned += commits.length;
          board.largestCommitGoalKeys = Math.max(board.largestCommitGoalKeys, heaviestCommit);
          for (const update of updates) {
            if (update.isBestForUser === true) board.attemptsPromoted += 1;
            if (update.isBestForUser === false) board.attemptsDemoted += 1;
            if (update.bestForGoals !== undefined) board.goalKeyRewrites += 1;
          }
          if (heaviestCommit > MAX_GOAL_KEYS_PER_COMMIT) {
            report.oversizedClimbers.push({
              contextKey: boardRef.id,
              userId,
              attempts: attempts.length,
              goalKeys: heaviestCommit,
            });
            console.error(
              `  ${boardRef.id}: climber ${userId} has one row of ${heaviestCommit} goal keys, over the ` +
              `${MAX_GOAL_KEYS_PER_COMMIT} per-commit budget; ` +
              (options.dryRun ? "the write run will commit it alone and Firestore may refuse it." : "committing it alone.")
            );
          }

          if (!options.dryRun) {
            await applyEntryWrites(db, phases, {
              progress,
              onCommitted: (count) => {
                board.entryWritesApplied += count;
                noteWrites();
              },
            });
          }
        }
      } catch (error) {
        if (error instanceof PhaseStalledError) throw error;
        const reason = String(error?.message ?? error);
        board.climbersSkipped += 1;
        report.skippedClimbers.push({
          contextKey: boardRef.id,
          userId,
          attempts: attempts.length,
          reason,
        });
        console.error(`  ${boardRef.id}: skipped climber ${userId} (${attempts.length} attempt(s)): ${reason}`);
      }
      progress.advance(1);
      noteWrites();
    }
  } finally {
    progress.finish(
      `${progress.count()}/${board.climbersScanned} climbers, ` +
      `${(options.dryRun ? board.entryWritesPlanned : board.entryWritesApplied).toLocaleString()} entry writes ` +
      `${options.dryRun ? "planned" : "applied"}`
    );
  }

  return board;
}

/**
 * A climber's entry writes as `createBatchWriter` operations, in the two
 * phases they commit in: every bucket but zero, then bucket zero. The planner
 * diffs against bucket zero, so bucket zero landing last is what lets a
 * climber whose later commits failed be planned again in full.
 * @param {FirebaseFirestore.DocumentReference} boardRef Board document.
 * @param {object[]} writes Entry writes from `entryWritePlan`.
 * @return {object[][]} Non-empty phases, in commit order.
 */
export function entryUpdatePhases(boardRef, writes) {
  const operation = (write) => ({
    kind: "update",
    ref: boardRef.collection(SPLIT_BUCKETS_COLLECTION).doc(String(write.bucketIndex))
      .collection(ENTRIES_COLLECTION).doc(write.workoutId),
    data: write.fields,
  });
  const laterBuckets = writes.filter((write) => write.bucketIndex !== 0).map(operation);
  const bucketZero = writes.filter((write) => write.bucketIndex === 0).map(operation);
  return [laterBuckets, bucketZero].filter((phase) => phase.length > 0);
}

/**
 * The commits `applyEntryWrites` will send for these phases, each with its
 * `bestForGoals` element count as `weight`.
 * @param {object[][]} phases From `entryUpdatePhases`.
 * @return {{operations: object[], weight: number}[]} Commits in order.
 */
export function plannedEntryCommits(phases) {
  return phases.flatMap((phase) => planCommits(phase, GOAL_KEY_COMMIT_BUDGET));
}

/**
 * Writes one climber's entry updates through their own batch queue, so a
 * failure is theirs alone and the next climber still gets their turn. Commits
 * are split under the goal-key budget exactly as `plannedEntryCommits` plans
 * them, and a phase starts only once the one before it has fully landed.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {object[][]} phases From `entryUpdatePhases`.
 * @param {object} [options] Reporting hooks.
 * @param {object} [options.progress] The board's progress reporter; a landed
 *   commit or a retry counts as a sign of life.
 * @param {(count: number) => void} [options.onCommitted] Called with each
 *   commit's write count once it lands.
 * @return {Promise<void>} Resolves once every phase has committed.
 */
export async function applyEntryWrites(db, phases, {progress = null, onCommitted = () => {}} = {}) {
  const writer = createBatchWriter(db, {
    ...GOAL_KEY_COMMIT_BUDGET,
    progress: {
      assertAlive: () => progress?.assertAlive(),
      retried: () => progress?.retried(),
      advance: (count) => {
        progress?.advance(0);
        onCommitted(count);
      },
    },
  });
  for (const phase of phases) {
    for (const operation of phase) {
      writer.update(operation.ref, operation.data);
    }
    await writer.flush();
  }
}

/**
 * The split curves behind a climber's attempts on a goal-racing board, read
 * from `attemptCurves` and rebuilt from the attempt's own bucket entries where
 * the curve was never stored - which is every attempt published before the
 * rule. A rebuilt curve is stored in a write run so the trigger's next
 * reconciliation finds it, the same way the Cloud Function heals one.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {FirebaseFirestore.DocumentReference} boardRef Board document.
 * @param {object[]} attempts The climber's attempts.
 * @param {{dryRun: boolean}} options Run options.
 * @param {object} board Board summary, mutated.
 * @param {object} progress The board's progress reporter.
 * @return {Promise<Map<string, object>>} Curves by workout id.
 */
async function attemptCurves(db, boardRef, attempts, options, board, progress) {
  const refs = attempts.map((attempt) =>
    boardRef.collection(ATTEMPT_CURVES_COLLECTION).doc(attempt.workoutId)
  );
  const snapshots = await withRetry(() => db.getAll(...refs), {
    description: `read of ${attempts.length} curve(s) in ${boardRef.path}`,
    onRetry: () => progress.retried(),
  });
  const curves = new Map();

  for (let index = 0; index < attempts.length; index += 1) {
    const attempt = attempts[index];
    const stored = curveFromData(attempt, snapshots[index].data());
    if (stored !== null) {
      curves.set(attempt.workoutId, stored);
      continue;
    }

    const rebuilt = await rebuildCurve(db, boardRef, attempt, progress);
    board.curvesRebuilt += 1;
    curves.set(attempt.workoutId, rebuilt);
    if (!options.dryRun) {
      await withRetry(() => refs[index].set({
        finalDurationSeconds: rebuilt.finalDurationSeconds,
        finalSteps: rebuilt.finalSteps,
        schemaVersion: 1,
        splitIntervalSeconds: rebuilt.splitIntervalSeconds,
        splitSteps: rebuilt.splitSteps,
        updatedAt: FieldValue.serverTimestamp(),
        userId: attempt.userId,
        workoutId: attempt.workoutId,
      }), {description: `write of ${refs[index].path}`, onRetry: () => progress.retried()});
    }
  }

  return curves;
}

async function rebuildCurve(db, boardRef, attempt, progress) {
  const refs = [];
  for (let index = 0; index < attempt.splitBucketCount; index += 1) {
    refs.push(
      boardRef.collection(SPLIT_BUCKETS_COLLECTION).doc(String(index))
        .collection(ENTRIES_COLLECTION).doc(attempt.workoutId)
    );
  }

  const splitSteps = [];
  for (let start = 0; start < refs.length; start += 100) {
    const chunk = refs.slice(start, start + 100);
    const snapshots = await withRetry(() => db.getAll(...chunk), {
      description: `read of ${attempt.workoutId} buckets ${start}.. in ${boardRef.path}`,
      onRetry: () => progress.retried(),
    });
    let ended = false;
    for (const snapshot of snapshots) {
      const steps = nonNegativeIntegerValue(snapshot.data()?.stepsAtBucket);
      if (steps === null) {
        ended = true;
        break;
      }
      splitSteps.push(steps);
    }
    if (ended) break;
  }

  return {
    workoutId: attempt.workoutId,
    finalSteps: attempt.finalSteps,
    finalDurationSeconds: attempt.completionDurationSeconds,
    splitIntervalSeconds: attempt.splitIntervalSeconds,
    splitSteps,
  };
}

/**
 * A stored curve as the race-best rule reads it, or null when the document is
 * absent or unusable.
 * @param {object} attempt The attempt.
 * @param {Record<string, unknown> | undefined} data Curve document data.
 * @return {object | null} Curve.
 */
export function curveFromData(attempt, data) {
  if (!data || !Array.isArray(data.splitSteps)) {
    return null;
  }
  const splitSteps = data.splitSteps.filter((step) => Number.isInteger(step) && step >= 0);
  if (splitSteps.length !== data.splitSteps.length) {
    return null;
  }
  return {
    workoutId: attempt.workoutId,
    finalSteps: nonNegativeIntegerValue(data.finalSteps) ?? attempt.finalSteps,
    finalDurationSeconds: nonNegativeNumberValue(data.finalDurationSeconds) ??
      attempt.completionDurationSeconds,
    splitIntervalSeconds: positiveIntegerValue(data.splitIntervalSeconds) ??
      attempt.splitIntervalSeconds,
    splitSteps,
  };
}

/**
 * Everything one climber's entries must change to be on the rule: the
 * `isBestForUser` diff on the race metric, and on a goal-racing board the
 * `bestForGoals` diff from their curves. Mirrors the server's
 * `bestForUserFlagUpdates`; an attempt already carrying the right values is
 * omitted, which is what makes a second run write nothing.
 * @param {object} input Planning input.
 * @param {object[]} input.attempts The climber's parsed attempts.
 * @param {string} input.contextType Replay context type.
 * @param {Map<string, object> | null} input.curves Curves by workout id, or
 *   null off a goal-racing board.
 * @return {{winner: string | null, goalKeys: Map<string, string[]> | null,
 *   updates: object[]}} The plan.
 */
export function planClimberUpdates({attempts, contextType, curves = null}) {
  const winner = bestAttemptWorkoutId(attempts, contextType);
  const goalKeys = curves === null ?
    null :
    raceGoalKeysByWorkoutId(attempts.map((attempt) => curves.get(attempt.workoutId)));
  const updates = [];

  // Fail closed rather than demote: a climber whose attempts resolve no
  // winner would have `false` written across them on the strength of a value
  // that could not be read.
  if (winner === null) {
    return {winner, goalKeys, updates};
  }

  for (const attempt of attempts) {
    const update = {
      workoutId: attempt.workoutId,
      splitBucketCount: attempt.splitBucketCount,
    };
    const isBestForUser = attempt.workoutId === winner;
    if (isBestForUser !== attempt.isBestForUser) {
      update.isBestForUser = isBestForUser;
    }
    const keys = goalKeys?.get(attempt.workoutId);
    if (keys !== undefined && !sameKeys(attempt.bestForGoals, keys)) {
      update.bestForGoals = keys;
    }
    if (update.isBestForUser !== undefined || update.bestForGoals !== undefined) {
      updates.push(update);
    }
  }

  return {winner, goalKeys, updates};
}

/**
 * The climber's best on the race metric (`raceBestOnSteps`): the most steps
 * on a Just Climb or a routine template, the fastest time elsewhere. Equal
 * values resolve on workout id, as on the server.
 * @param {object[]} attempts The climber's attempts.
 * @param {string} contextType Replay context type.
 * @return {string | null} Winning workout id.
 */
export function bestAttemptWorkoutId(attempts, contextType) {
  const onSteps = raceBestOnSteps(contextType);
  let best = null;
  for (const attempt of attempts) {
    const beats = best === null ||
      (onSteps ? attempt.raceValue > best.raceValue : attempt.raceValue < best.raceValue);
    const breaksTie = best !== null &&
      attempt.raceValue === best.raceValue &&
      attempt.workoutId < best.workoutId;
    if (beats || breaksTie) {
      best = attempt;
    }
  }
  return best?.workoutId ?? null;
}

/**
 * Resolves attempt updates to the bucket entries that actually exist, so a
 * batch never fails on a bucket an attempt never published into.
 * @param {object[]} updates Attempt updates.
 * @param {Map<number, Set<string>>} existingEntryIds Entry ids by bucket.
 * @return {{writes: object[], skipped: number}} Writes and absent buckets.
 */
export function entryWritePlan(updates, existingEntryIds) {
  const writes = [];
  let skipped = 0;
  for (const update of updates) {
    const fields = {};
    if (update.isBestForUser !== undefined) fields.isBestForUser = update.isBestForUser;
    if (update.bestForGoals !== undefined) fields.bestForGoals = update.bestForGoals;
    for (let index = 0; index < update.splitBucketCount; index += 1) {
      if (existingEntryIds.get(index)?.has(update.workoutId)) {
        writes.push({bucketIndex: index, workoutId: update.workoutId, fields});
      } else {
        skipped += 1;
      }
    }
  }
  return {writes, skipped};
}

async function existingEntryIdsByBucket(boardRef, bucketSpan) {
  const collections = Array.from({length: bucketSpan}, (_unused, index) =>
    boardRef.collection(SPLIT_BUCKETS_COLLECTION).doc(String(index)).collection(ENTRIES_COLLECTION)
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
 * Reads one attempt from its bucket-zero entry, mirroring the server's
 * `userAttemptEntry`: the race value on the race metric, and the stored goal
 * keys sorted so they compare against a derived list.
 * @param {Record<string, unknown>} data Entry data.
 * @param {string} documentId Entry document id.
 * @param {string} contextType Replay context type.
 * @return {object | null} Parsed attempt, or null when unusable.
 */
export function userAttemptEntry(data, documentId, contextType) {
  const finalSteps = nonNegativeIntegerValue(data.finalSteps);
  const completionDurationSeconds = nonNegativeNumberValue(data.completionDurationSeconds);
  const raceValue = raceBestOnSteps(contextType) ? finalSteps : completionDurationSeconds;
  const userId = typeof data.userId === "string" ? data.userId : null;
  if (raceValue === null || userId === null) {
    return null;
  }

  const storedSpan = positiveIntegerValue(data.splitBucketCount);
  return {
    workoutId: typeof data.workoutId === "string" ? data.workoutId : documentId,
    userId,
    raceValue,
    finalSteps: finalSteps ?? 0,
    completionDurationSeconds: completionDurationSeconds ?? 0,
    splitIntervalSeconds: positiveIntegerValue(data.splitIntervalSeconds) ??
      DEFAULT_SPLIT_INTERVAL_SECONDS,
    // Entries written before the span was stored sweep the whole checkpoint
    // range; absent buckets are skipped by the write plan, never written.
    splitBucketCount: Math.min(storedSpan ?? MAX_REPLAY_SPLIT_CHECKPOINTS, MAX_REPLAY_SPLIT_CHECKPOINTS),
    isBestForUser: data.isBestForUser === true,
    bestForGoals: Array.isArray(data.bestForGoals) ?
      data.bestForGoals.filter((key) => typeof key === "string").sort() :
      [],
  };
}

/**
 * The run, rendered board by board with every skipped climber named.
 * @param {object} report Run report.
 * @param {{target: object, dryRun: boolean}} context Run context.
 * @return {string} Report text.
 */
export function renderReport(report, {target, dryRun}) {
  const lines = [
    `Project: ${target.label}`,
    `Mode: ${dryRun ? "dry run" : "write"}`,
    "",
  ];
  let totalPlanned = 0;

  for (const board of report.boards) {
    totalPlanned += board.entryWritesPlanned;
    lines.push(
      `${board.contextKey} (${board.contextType}${board.racesGoals ? ", races goals" : ""})`,
      `  climbers: ${board.climbersScanned} scanned, ${board.climbersChanged} changed, ${board.climbersSkipped} skipped`,
      `  attempts: ${board.attemptsScanned} scanned, ${board.attemptsUnreadable} unreadable, ` +
        `${board.attemptsPromoted} promoted, ${board.attemptsDemoted} demoted, ` +
        `${board.goalKeyRewrites} goal-key rewrites, ${board.curvesRebuilt} curves rebuilt`,
      `  entry writes: ${board.entryWritesPlanned} ${dryRun ? "would be applied" : "planned"}` +
        `${dryRun ? "" : `, ${board.entryWritesApplied} applied`}, ` +
        `${board.bucketsWithoutEntry} buckets skipped (entry absent)`,
      `  commits: ${board.commitsPlanned} ${dryRun ? "would be sent" : "planned"}` +
        (board.racesGoals ?
          `, largest ${board.largestCommitGoalKeys} goal keys (budget ${MAX_GOAL_KEYS_PER_COMMIT})` :
          "")
    );
  }

  for (const skipped of report.boardsSkipped) {
    lines.push(`${skipped.contextKey}: skipped (${skipped.reason})`);
  }

  lines.push("");
  if (report.oversizedClimbers.length > 0) {
    lines.push(
      `Over the goal-key budget (${report.oversizedClimbers.length}) - one row alone carries more than ` +
        `${MAX_GOAL_KEYS_PER_COMMIT} keys, so its commit ${dryRun ? "may be" : "may have been"} refused as too big:`
    );
    for (const climber of report.oversizedClimbers) {
      lines.push(`  ${climber.contextKey} / ${climber.userId} (${climber.attempts} attempt(s)): ${climber.goalKeys} goal keys in one commit`);
    }
  }
  if (report.skippedClimbers.length > 0) {
    lines.push(`Skipped climbers (${report.skippedClimbers.length}) - re-run to reach them:`);
    for (const climber of report.skippedClimbers) {
      lines.push(`  ${climber.contextKey} / ${climber.userId} (${climber.attempts} attempt(s)): ${climber.reason}`);
    }
  } else if (dryRun && report.oversizedClimbers.length > 0) {
    lines.push(`${totalPlanned} entry write(s) would be applied across ${report.boards.length} board(s); the write run is not shown to land every climber.`);
  } else if (totalPlanned === 0) {
    lines.push("Nothing to write: every board is already on the current rule.");
  } else {
    lines.push(`${totalPlanned} entry write(s) ${dryRun ? "would be applied" : "applied"} across ${report.boards.length} board(s); no climber skipped.`);
  }

  return lines.join("\n");
}

function sameKeys(stored, derived) {
  return stored.length === derived.length && stored.every((key, index) => key === derived[index]);
}

function nonNegativeNumberValue(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null;
}

function nonNegativeIntegerValue(value) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

function positiveIntegerValue(value) {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ? value : null;
}
