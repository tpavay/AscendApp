#!/usr/bin/env node

/**
 * Republishes Live Replay attempts that ran past the hour before the split
 * fix, so a live race shows those rivals where they really were after 60:00.
 *
 * The pre-fix iOS sampler (1.0 through 1.1) clamped every sample after 59:50
 * into bucket 359, and the publish stopped at 360 buckets. So every such
 * attempt on a board today has 360 entries whose last one holds its final
 * steps, a `splitBucketCount` of 360 that tells the live race it is home from
 * 60:00, and - on the global Just Climb board - a stored attempt curve that
 * reaches the finish at 60:00. In the captain's 2026-09-26 race a rival's row
 * jumped to 16,645 steps at the hour although the climb ran 2:30:02.
 *
 * The fixed Cloud Function publishes a long attempt on the board's 10-second
 * grid through its finish, drawing a clamped curve's unrecorded tail straight
 * from the last trusted bucket to the finish - the total and the clock are the
 * only evidence left about it. This script writes exactly that for attempts
 * published before the fix, re-deriving each curve from the attempt's own
 * private workout backup through `scripts/lib/live-replay-split-normalization.mjs`,
 * the mirror of the function's normalizer pinned by the shared vector. The
 * private workout itself is never touched: every reader repairs a clamped
 * curve when it reads one, and a server write onto a climber's own backup
 * would fight their device's next sync.
 *
 * What it writes, per attempt that needs it, and in this order:
 *   1. every bucket past zero: the entries after 60:00 (created from the
 *      attempt's bucket-zero row, so identity and flags match) and the
 *      existing ones (the corrected `stepsAtBucket` and the full span);
 *   2. the attempt curve, on a board that races goals;
 *   3. bucket zero, last. Bucket zero states the attempt's span and is what
 *      this script diffs against, so a run that fails part-way leaves the
 *      attempt reading as unrepaired and the next run redoes it whole.
 *
 * Goal keys (`bestForGoals`) are copied onto the new entries as bucket zero
 * holds them, and those were derived from the bent curve. Run
 * `backfill-live-replay-best-per-user.mjs` against the same environment
 * straight after this one: it re-derives every key from the repaired curves
 * and writes them across each attempt's whole span.
 *
 * Seeded rows (`isSynthetic`) have no workout behind them and are skipped. A
 * session longer than the 24-hour plausibility envelope is skipped too: the
 * function no longer publishes one at all.
 *
 * Migration discipline (`scripts/lib/migration-discipline.mjs`): dry-run by
 * default, `--apply` to write, production only with its project id spelled
 * out, a `_migrations` ledger entry per apply, and idempotent - a second run
 * plans nothing. AUTHOR-ONLY in its pull request: running it is captain-gated
 * ops, per environment, after the Cloud Functions deploy that ships the fix.
 *
 * Usage:
 *   node scripts/backfill-live-replay-long-attempts.mjs --env dev
 *   node scripts/backfill-live-replay-long-attempts.mjs --env staging --apply
 *   node scripts/backfill-live-replay-long-attempts.mjs --env prod --confirm-production ascend-prod-9c8f2
 *   node scripts/backfill-live-replay-long-attempts.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
 *   node scripts/backfill-live-replay-long-attempts.mjs --env dev --context-key just_climb__global
 *
 * Prerequisites: Node 20+, `cd scripts && npm install`, `gcloud auth application-default login`.
 *
 * The planning half is exported so scripts/test can run it against fixtures
 * without a Firestore; the run itself starts only when this file is the
 * entrypoint.
 */

import {FieldValue} from "firebase-admin/firestore";
import {
  beginRun,
  initFirestore,
  parseCommonArgs,
  resolveEnvironment,
} from "./lib/migration-discipline.mjs";
import {createBatchWriter, withRetry} from "./lib/firestore-bulk.mjs";
import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {GOAL_KEY_COMMIT_BUDGET} from "./lib/race-goal-commit-budget.mjs";
import {contextRacesGoals} from "./lib/live-replay-race-best.mjs";
import {
  PRE_FIX_SAMPLER_CHECKPOINTS,
  REPLAY_BOARD_INTERVAL_SECONDS,
  replayBoardSplitSteps,
} from "./lib/live-replay-split-normalization.mjs";

export const OPERATION_ID = "migration/live-replay-long-attempts";
export const OPERATION_VERSION = 1;

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const SPLIT_BUCKETS_COLLECTION = "splitBuckets";
const ENTRIES_COLLECTION = "entries";
const ATTEMPT_CURVES_COLLECTION = "attemptCurves";
const HEADPHONE_MOTION_SOURCE = "headphone_motion";

/**
 * The shortest attempt the pre-fix publish could have cut short: 360 buckets
 * of 10 seconds. Anything shorter published its whole curve.
 */
export const FIRST_CLAMPED_DURATION_SECONDS =
  PRE_FIX_SAMPLER_CHECKPOINTS * REPLAY_BOARD_INTERVAL_SECONDS;

/**
 * The session envelope the Cloud Function publishes under
 * (`MAX_WORKOUT_DURATION_SECONDS` in `functions/src/leaderboardStats.ts`).
 */
export const MAX_WORKOUT_DURATION_SECONDS = 24 * 60 * 60;

/**
 * Entries per commit. Each entry fans out into every index over `entries`,
 * and 360 is the size every publish committed before this fix. Commits are
 * also split by `bestForGoals` elements, which is what makes a row heavy.
 */
const ENTRY_COMMIT_SIZE = 360;

if (isEntrypoint(import.meta.url)) {
  await main();
}

async function main() {
  const args = parseCommonArgs(process.argv);
  if (args.rest.has("help")) {
    printUsage();
    return;
  }

  const environment = resolveEnvironment(args.env, {
    allowProduction: true,
    productionConfirmation: args.rest.get("confirm-production") ?? null,
  });
  const db = await initFirestore(environment);
  const report = await planBackfill(db, {contextKey: args.contextKey});

  console.log(renderReport(report, {environment, apply: args.apply}));

  if (!args.apply) {
    if (report.unrepairable.length > 0) process.exitCode = 1;
    console.log("\nDry-run only. Re-run with --apply to write these documents.");
    return;
  }

  const run = await beginRun(db, {
    operationId: OPERATION_ID,
    operationVersion: OPERATION_VERSION,
    environment,
    rerun: args.rerun,
  });

  try {
    const written = await applyRepublishes(db, report.republishes);
    await run.finish({
      attemptsRepublished: report.republishes.length,
      entryWrites: written,
      unrepairable: report.unrepairable.length,
    });
    console.log(`\nApplied: ${report.republishes.length} attempt(s), ${written} write(s).`);
    if (report.republishes.length > 0) {
      console.log(
        "Next: run backfill-live-replay-best-per-user.mjs against this environment so every " +
        "goal key is re-derived from the repaired curves."
      );
    }
    if (report.unrepairable.length > 0) process.exitCode = 1;
  } catch (error) {
    await run.fail(error);
    throw error;
  }
}

/**
 * Reads every board and plans the attempts that need republishing.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {{contextKey: string | null}} options Scope.
 * @return {Promise<object>} The plan and what was left alone.
 */
export async function planBackfill(db, {contextKey}) {
  const boards = contextKey ?
    [db.collection(LIVE_REPLAY_COLLECTION).doc(contextKey)] :
    await withRetry(() => db.collection(LIVE_REPLAY_COLLECTION).listDocuments(), {
      description: `listing of ${LIVE_REPLAY_COLLECTION}`,
    });
  const report = {
    boardsScanned: boards.length,
    candidates: 0,
    upToDate: 0,
    synthetic: 0,
    republishes: [],
    unrepairable: [],
  };

  for (const boardRef of boards) {
    const snapshot = await withRetry(() => bucketZero(boardRef)
      .where("completionDurationSeconds", ">=", FIRST_CLAMPED_DURATION_SECONDS)
      .get(), {description: `read of long attempts in ${boardRef.path}`});

    for (const entry of snapshot.docs) {
      report.candidates += 1;
      const data = entry.data();
      if (data.isSynthetic === true) {
        report.synthetic += 1;
        continue;
      }

      const userId = typeof data.userId === "string" ? data.userId : null;
      const workoutId = typeof data.workoutId === "string" ? data.workoutId : entry.id;
      if (userId === null) {
        report.unrepairable.push({board: boardRef.id, workoutId, reason: "entry has no userId"});
        continue;
      }

      const workout = await withRetry(
        () => db.doc(`users/${userId}/workouts/${workoutId}`).get(),
        {description: `read of users/${userId}/workouts/${workoutId}`}
      );
      const curve = boardCurveForWorkout(workout.data());
      if (curve.reason) {
        report.unrepairable.push({board: boardRef.id, workoutId, reason: curve.reason});
        continue;
      }

      const plan = planAttemptRepublish({entry: data, boardSteps: curve.boardSteps, workout: curve});
      if (plan.reason) {
        report.unrepairable.push({board: boardRef.id, workoutId, reason: plan.reason});
        continue;
      }
      if (plan.upToDate) {
        report.upToDate += 1;
        continue;
      }

      report.republishes.push({
        boardRef,
        entryId: entry.id,
        entry: data,
        userId,
        racesGoals: contextRacesGoals(String(data.contextType ?? "")),
        ...plan,
      });
    }
  }

  return report;
}

/**
 * The curve a workout backup publishes onto a board - exactly what the Cloud
 * Function derives from it - or the reason it cannot be derived.
 * @param {Record<string, unknown> | undefined} workout Workout document data.
 * @return {{boardSteps?: number[], finalSteps?: number,
 *   finalDurationSeconds?: number, reason?: string}} Curve or reason.
 */
export function boardCurveForWorkout(workout) {
  if (!workout) {
    return {reason: "workout backup is missing"};
  }
  if (workout.source !== HEADPHONE_MOTION_SOURCE || typeof workout.sourceMetadata !== "string") {
    return {reason: "workout backup carries no split curve"};
  }

  let metadata;
  try {
    metadata = JSON.parse(workout.sourceMetadata);
  } catch {
    return {reason: "workout sourceMetadata is not JSON"};
  }

  const splitIntervalSeconds = Number.isInteger(metadata.splitIntervalSeconds) &&
    metadata.splitIntervalSeconds > 0 ?
    metadata.splitIntervalSeconds :
    null;
  const splitSteps = Array.isArray(metadata.splitSteps) &&
    metadata.splitSteps.length > 0 &&
    metadata.splitSteps.every((step) => Number.isInteger(step) && step >= 0) ?
    metadata.splitSteps :
    null;
  const finalDurationSeconds = typeof workout.durationSeconds === "number" &&
    workout.durationSeconds >= 0 ?
    workout.durationSeconds :
    null;
  const finalSteps = Number.isInteger(workout.steps) && workout.steps >= 0 ? workout.steps : null;

  if (splitIntervalSeconds === null || splitSteps === null ||
    finalDurationSeconds === null || finalSteps === null) {
    return {reason: "workout split curve is unreadable"};
  }
  if (finalDurationSeconds > MAX_WORKOUT_DURATION_SECONDS) {
    return {reason: "session is longer than the 24-hour envelope the function publishes under"};
  }

  return {
    finalSteps,
    finalDurationSeconds,
    boardSteps: replayBoardSplitSteps({
      splitIntervalSeconds,
      splitSteps,
      finalDurationSeconds,
      finalSteps,
    }),
  };
}

/**
 * What one attempt's entries must change to match its board curve.
 * @param {object} input Planning input.
 * @param {Record<string, unknown>} input.entry Bucket-zero entry data.
 * @param {number[]} input.boardSteps The attempt's curve on the board grid.
 * @param {{finalSteps: number, finalDurationSeconds: number}} input.workout
 *   The workout the curve was derived from.
 * @return {object} `{upToDate: true}`, a `reason` it must be left alone, or
 *   the span and the buckets to create, update and remove.
 */
export function planAttemptRepublish({entry, boardSteps, workout}) {
  // A workout edited since it published is republished by the trigger on
  // that edit; writing its new curve under the old entry's numbers here would
  // publish a row that agrees with neither.
  if (entry.finalSteps !== workout.finalSteps ||
    Math.abs(Number(entry.completionDurationSeconds) - workout.finalDurationSeconds) > 0.001) {
    return {reason: "published entry no longer matches its workout backup"};
  }

  const span = boardSteps.length;
  const storedSpan = Number.isInteger(entry.splitBucketCount) && entry.splitBucketCount > 0 ?
    entry.splitBucketCount :
    PRE_FIX_SAMPLER_CHECKPOINTS;
  if (storedSpan === span && entry.stepsAtBucket === boardSteps[0] &&
    entry.splitIntervalSeconds === REPLAY_BOARD_INTERVAL_SECONDS) {
    return {upToDate: true};
  }

  const existing = Math.min(storedSpan, span);
  return {
    upToDate: false,
    span,
    boardSteps,
    updatedBuckets: range(1, existing),
    createdBuckets: range(existing, span),
    removedBuckets: range(span, storedSpan),
  };
}

/**
 * Writes every planned republish, each attempt's bucket zero only after the
 * rest of it has landed.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {object[]} republishes From `planBackfill`.
 * @return {Promise<number>} Writes committed.
 */
export async function applyRepublishes(db, republishes) {
  const writer = createBatchWriter(db, {...GOAL_KEY_COMMIT_BUDGET, batchSize: ENTRY_COMMIT_SIZE});
  const updatedAt = FieldValue.serverTimestamp();

  for (const plan of republishes) {
    for (const operation of republishOperations(plan, updatedAt)) {
      if (operation.kind === "set") writer.set(operation.ref, operation.data);
      else if (operation.kind === "update") writer.update(operation.ref, operation.data);
      else writer.delete(operation.ref);
    }
  }
  await writer.flush();

  for (const plan of republishes) {
    const zero = bucketZeroOperation(plan, updatedAt);
    writer.update(zero.ref, zero.data);
  }
  return writer.drain();
}

/**
 * Every write for one attempt except bucket zero, in commit order.
 * @param {object} plan One republish.
 * @param {unknown} updatedAt Write timestamp.
 * @return {object[]} Operations.
 */
export function republishOperations(plan, updatedAt) {
  const operations = [];
  const shared = {
    splitBucketCount: plan.span,
    splitIntervalSeconds: REPLAY_BOARD_INTERVAL_SECONDS,
    updatedAt,
  };

  for (const index of plan.createdBuckets) {
    operations.push({
      kind: "set",
      ref: entryRef(plan.boardRef, index, plan.entryId),
      data: {...plan.entry, ...shared, stepsAtBucket: plan.boardSteps[index]},
    });
  }
  for (const index of plan.updatedBuckets) {
    operations.push({
      kind: "update",
      ref: entryRef(plan.boardRef, index, plan.entryId),
      data: {...shared, stepsAtBucket: plan.boardSteps[index]},
    });
  }
  for (const index of plan.removedBuckets) {
    operations.push({kind: "delete", ref: entryRef(plan.boardRef, index, plan.entryId)});
  }
  if (plan.racesGoals) {
    operations.push({
      kind: "set",
      ref: plan.boardRef.collection(ATTEMPT_CURVES_COLLECTION).doc(plan.entryId),
      data: {
        finalDurationSeconds: plan.entry.completionDurationSeconds,
        finalSteps: plan.entry.finalSteps,
        schemaVersion: 1,
        splitIntervalSeconds: REPLAY_BOARD_INTERVAL_SECONDS,
        splitSteps: plan.boardSteps,
        updatedAt,
        userId: plan.userId,
        workoutId: plan.entryId,
      },
    });
  }

  return operations;
}

/**
 * The attempt's bucket-zero write, committed only after the rest.
 * @param {object} plan One republish.
 * @param {unknown} updatedAt Write timestamp.
 * @return {{ref: object, data: object}} The update.
 */
export function bucketZeroOperation(plan, updatedAt) {
  return {
    ref: entryRef(plan.boardRef, 0, plan.entryId),
    data: {
      splitBucketCount: plan.span,
      splitIntervalSeconds: REPLAY_BOARD_INTERVAL_SECONDS,
      stepsAtBucket: plan.boardSteps[0],
      updatedAt,
    },
  };
}

/**
 * The plan, rendered.
 * @param {object} report From `planBackfill`.
 * @param {{environment: object, apply: boolean}} context Run context.
 * @return {string} Report text.
 */
export function renderReport(report, {environment, apply}) {
  const lines = [
    `Operation: ${OPERATION_ID} v${OPERATION_VERSION}`,
    `Environment: ${environment.env} (${environment.projectId})`,
    `Mode: ${apply ? "apply" : "dry-run (plan only)"}`,
    `Boards scanned: ${report.boardsScanned}`,
    `Attempts of an hour or more: ${report.candidates}`,
    `Already republished (skipped): ${report.upToDate}`,
    `Seeded rows (skipped): ${report.synthetic}`,
    `Attempts to republish: ${report.republishes.length}`,
  ];
  for (const plan of report.republishes) {
    lines.push(
      `  ${plan.boardRef.id}/${plan.entryId}: ` +
      `${plan.createdBuckets.length} bucket(s) created, ${plan.updatedBuckets.length + 1} updated, ` +
      `${plan.removedBuckets.length} removed; span ${plan.span}` +
      `${plan.racesGoals ? ", attempt curve rewritten" : ""}`
    );
  }
  lines.push(`Left alone, needing a look: ${report.unrepairable.length}`);
  for (const skipped of report.unrepairable) {
    lines.push(`  ${skipped.board}/${skipped.workoutId}: ${skipped.reason}`);
  }
  return lines.join("\n");
}

function bucketZero(boardRef) {
  return boardRef.collection(SPLIT_BUCKETS_COLLECTION).doc("0").collection(ENTRIES_COLLECTION);
}

function entryRef(boardRef, bucketIndex, entryId) {
  return boardRef
    .collection(SPLIT_BUCKETS_COLLECTION)
    .doc(String(bucketIndex))
    .collection(ENTRIES_COLLECTION)
    .doc(entryId);
}

function range(from, to) {
  const values = [];
  for (let value = from; value < to; value += 1) values.push(value);
  return values;
}

function printUsage() {
  console.log(`Usage:
  node scripts/backfill-live-replay-long-attempts.mjs --env dev|staging [--apply] [--rerun] [--context-key <key>]
  node scripts/backfill-live-replay-long-attempts.mjs --env prod --confirm-production ascend-prod-9c8f2 [--apply]

Plans by default; --apply writes. Run backfill-live-replay-best-per-user.mjs afterwards.`);
}
