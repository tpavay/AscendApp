import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  FINALIZED_TIME_FRAMES,
  FinalizedTimeFrame,
  previousPeriod,
} from "./leaderboardPeriod.js";
import {
  LEADERBOARD_PLACINGS_COLLECTION,
  LEADERBOARD_RESULTS_COLLECTION,
  PeriodStandingsTruncatedError,
  RankedStanding,
  StandingRow,
  TOP_RANK_LIMIT,
  buildLeaderboardResult,
  rankStandings,
  readAwardStandings,
  readPeriodStandings,
  summarizePeriodStandings,
} from "./leaderboardResults.js";

const LEADERBOARD_PERIODS_COLLECTION = "leaderboard_periods";
const USERS_COLLECTION = "users";
const PROFILE_STATS_COLLECTION = "profile_stats";
const ACHIEVEMENTS_COLLECTION = "achievements";
const CURRENT_PROFILE_STATS_ID = "current";
const FINALIZING_LOCK_MINUTES = 30;
/**
 * Writes per commit, under Firestore's 500 with headroom. A normal period is
 * one commit; only a pathological tie at the award cutoff needs more.
 */
const MAX_WRITES_PER_COMMIT = 450;

/** One document write in a finalization commit. */
interface FinalizerWrite {
  ref: admin.firestore.DocumentReference;
  data: Record<string, unknown>;
  merge: boolean;
}

/**
 * Freezes closed leaderboard periods into user achievement records and the
 * period's final result.
 *
 * Active standings keep reading the current period from leaderboard_stats.
 * This job turns a closed period from that same materialized leaderboard well
 * into durable profile achievement rows, and into
 * `leaderboard_results/{timeFrame}_{periodKey}` with its `placings` - the
 * frozen board that crowns the period's champions
 * (docs/champion-recognition.md).
 */
export const finalizeLeaderboardAchievements = onSchedule(
  {
    schedule: "15 0 * * *",
    timeZone: "Etc/UTC",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const now = new Date();
    for (const timeFrame of FINALIZED_TIME_FRAMES) {
      await finalizeMostRecentClosedPeriod(timeFrame, now);
    }
  }
);

/**
 * Finalizes the most recently closed period of one time frame, once.
 *
 * The achievements, the result and its placings, and the period's `finalized`
 * status land in one commit. A pathological tie at the award cutoff can need
 * more writes than one commit holds; then the commits are split so that an
 * achievement and its profile counter always share a commit (the existence
 * check that makes a retry skip the award also has to skip the increment), and
 * the result and the `finalized` status always share the LAST commit. A crash
 * part-way therefore leaves the period unfinalized and resultless, and the
 * next run completes it without double-counting anything - a result that
 * exists always has its placings behind it.
 *
 * The awards need only the top-N query; the result needs the whole period's
 * standings. If that full scan is too large for its page bound - which no
 * retry can fix - the awards and the `finalized` status still commit and no
 * result is written at all - never a partial one - and a structured error
 * names the period so `scripts/backfill-leaderboard-results.mjs` can write it
 * later. Any other scan failure throws before anything is written, so the
 * next run retries the awards and the result together.
 * @param {FinalizedTimeFrame} timeFrame The board's window.
 * @param {Date} now The run instant.
 * @param {object} standingsOptions Paging for the full standings scan.
 * @return {Promise<void>} Resolves once committed, or when there is no work.
 */
async function finalizeMostRecentClosedPeriod(
  timeFrame: FinalizedTimeFrame,
  now: Date,
  standingsOptions: Parameters<typeof readPeriodStandings>[2] = {}
): Promise<void> {
  const db = admin.firestore();
  const period = previousPeriod(timeFrame, now);
  const periodId = `${period.timeFrame}_${period.key}`;
  const periodRef = db
    .collection(LEADERBOARD_PERIODS_COLLECTION)
    .doc(periodId);

  const shouldFinalize = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(periodRef);
    const data = snapshot.data();
    if (data?.status === "finalized") {
      return false;
    }

    const startedAt = timestampDate(data?.finalizingStartedAt);
    if (
      data?.status === "finalizing" &&
      startedAt &&
      now.getTime() - startedAt.getTime() <
        FINALIZING_LOCK_MINUTES * 60 * 1000
    ) {
      return false;
    }

    transaction.set(
      periodRef,
      {
        status: "finalizing",
        timeFrame: period.timeFrame,
        periodKey: period.key,
        periodStartAt: admin.firestore.Timestamp.fromDate(period.startAt),
        periodEndAt: admin.firestore.Timestamp.fromDate(period.endAt),
        finalizingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return true;
  });

  if (!shouldFinalize) {
    return;
  }

  const rankedRows = rankedQualifiers(await readAwardStandings(db, period));
  let summary: ReturnType<typeof summarizePeriodStandings> | null = null;
  try {
    summary = summarizePeriodStandings(
      await readPeriodStandings(db, period, standingsOptions)
    );
  } catch (error) {
    if (!(error instanceof PeriodStandingsTruncatedError)) {
      throw error;
    }
    logger.error("leaderboardAchievements.result_scan_failed", {
      periodId,
      timeFrame: period.timeFrame,
      periodKey: period.key,
      error: error.message,
      remedy: "scripts/backfill-leaderboard-results.mjs",
    });
  }
  const units: FinalizerWrite[][] = [];
  let achievementCount = 0;

  for (const row of rankedRows) {
    const achievementId =
      `global_steps_${period.timeFrame}_${period.key}`;
    const achievementRef = db
      .collection(USERS_COLLECTION)
      .doc(row.userId)
      .collection(ACHIEVEMENTS_COLLECTION)
      .doc(achievementId);
    const existingAchievement = await achievementRef.get();
    if (existingAchievement.exists) {
      continue;
    }

    units.push([
      {
        ref: achievementRef,
        data: {
          type: achievementType(period.timeFrame, row.rank),
          scope: "global",
          metric: "steps",
          value: row.totalSteps,
          valueUnit: "steps",
          rank: row.rank,
          periodKey: period.key,
          periodStartAt: admin.firestore.Timestamp.fromDate(period.startAt),
          periodEndAt: admin.firestore.Timestamp.fromDate(period.endAt),
          earnedAt: admin.firestore.Timestamp.fromDate(period.endAt),
          leaderboardStatsId: row.documentId,
          schemaVersion: 1,
          source: "leaderboard_finalizer",
        },
        merge: false,
      },
      {
        ref: db
          .collection(USERS_COLLECTION)
          .doc(row.userId)
          .collection(PROFILE_STATS_COLLECTION)
          .doc(CURRENT_PROFILE_STATS_ID),
        data: profileStatsIncrement(row.rank),
        merge: true,
      },
    ]);
    achievementCount += 1;
  }

  const outcome = summary ? buildLeaderboardResult({
    period,
    placed: rankedRows,
    summary,
    source: "leaderboard_finalizer",
  }) : null;
  const resultWrites: FinalizerWrite[] = [];
  if (outcome) {
    const resultRef = db
      .collection(LEADERBOARD_RESULTS_COLLECTION)
      .doc(outcome.resultId);
    for (const placing of outcome.placings) {
      units.push([{
        ref: resultRef
          .collection(LEADERBOARD_PLACINGS_COLLECTION)
          .doc(placing.userId),
        data: placing.data,
        merge: false,
      }]);
    }
    resultWrites.push({ref: resultRef, data: outcome.result, merge: false});
  }

  units.push([
    ...resultWrites,
    {
      ref: periodRef,
      data: {
        status: "finalized",
        finalizedAt: admin.firestore.FieldValue.serverTimestamp(),
        achievementCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      merge: true,
    },
  ]);

  const commits = packCommitUnits(units, MAX_WRITES_PER_COMMIT);
  for (const commit of commits) {
    const batch = db.batch();
    for (const write of commit) {
      if (write.merge) {
        batch.set(write.ref, write.data, {merge: true});
      } else {
        batch.set(write.ref, write.data);
      }
    }
    await batch.commit();
  }

  logger.info("leaderboardAchievements.finalized", {
    periodId,
    achievementCount,
    climberCount: summary?.climberCount ?? null,
    championCount: outcome ?
      (outcome.result.championUserIds as string[]).length :
      null,
    placingCount: outcome?.placings.length ?? 0,
    resultWritten: outcome !== null,
    commitCount: commits.length,
  });
}

/**
 * Packs write units into commits in order, never splitting a unit.
 *
 * Order is the guarantee: the last unit lands in the last commit, so whatever
 * a caller puts last is only ever written once everything before it has been.
 * @param {T[][]} units Writes that must commit together, in order.
 * @param {number} maxWrites Writes per commit.
 * @return {T[][]} Commits in order.
 * @template T
 */
function packCommitUnits<T>(units: T[][], maxWrites: number): T[][] {
  const commits: T[][] = [];
  let current: T[] = [];
  for (const unit of units) {
    if (unit.length > maxWrites) {
      throw new Error(
        `A ${unit.length}-write unit cannot fit a ${maxWrites}-write commit`
      );
    }
    if (current.length + unit.length > maxWrites) {
      commits.push(current);
      current = [];
    }
    current.push(...unit);
  }
  if (current.length > 0) {
    commits.push(current);
  }
  return commits;
}

/**
 * The awarded rows: every climber ranked 1-100. A tie at the cutoff can make
 * that more than 100 rows, and every tied climber is awarded.
 * @param {StandingRow[]} rows Deduplicated award rows in board order.
 * @return {RankedStanding[]} The awarded rows with their ranks.
 */
function rankedQualifiers(rows: StandingRow[]): RankedStanding[] {
  return rankStandings(rows, TOP_RANK_LIMIT);
}

function achievementType(
  timeFrame: FinalizedTimeFrame,
  rank: number
): string {
  if (rank === 1) return `${timeFrame}_top_1`;
  if (rank <= 3) return `${timeFrame}_top_3`;
  if (rank <= 10) return `${timeFrame}_top_10`;
  return `${timeFrame}_top_100`;
}

/**
 * These counters are deliberately time-frame agnostic: a weekly, monthly, or
 * yearly finish all land on the same band counter, because a profile badge
 * shows one total per band with no period noun. Counting is cumulative:
 * a Top 1 finish also counts toward Top 3, Top 10, and Top 100.
 * The per-frame breakdown - and the exact finishing rank the profile shelf
 * needs for its #2 and #3 badges, which no band counter can supply - lives on
 * the achievement records themselves, which is what the achievement history
 * sheet reads. See docs/quality/contracts/podium-placement-badge-ladder.md.
 * @param {number} rank Final leaderboard rank for the closed period.
 * @return {Record<string, unknown>} Merge payload for the profile stats doc.
 */
function profileStatsIncrement(
  rank: number
): Record<string, unknown> {
  const increment = admin.firestore.FieldValue.increment(1);
  const data: Record<string, unknown> = {
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (rank === 1) data.top_1_finishes = increment;
  if (rank <= 3) data.top_3_finishes = increment;
  if (rank <= 10) data.top_10_finishes = increment;
  if (rank <= 100) data.top_100_finishes = increment;
  return data;
}

export const leaderboardAchievementsTestHooks = {
  achievementType,
  finalizeMostRecentClosedPeriod,
  maxWritesPerCommit: MAX_WRITES_PER_COMMIT,
  packCommitUnits,
  profileStatsIncrement,
  previousPeriod,
  rankedQualifiers,
};

function timestampDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  return null;
}
