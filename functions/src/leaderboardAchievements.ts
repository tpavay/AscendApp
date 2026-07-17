import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

/* eslint-disable require-jsdoc */

const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";
const LEADERBOARD_PERIODS_COLLECTION = "leaderboard_periods";
const USERS_COLLECTION = "users";
const PROFILE_STATS_COLLECTION = "profile_stats";
const ACHIEVEMENTS_COLLECTION = "achievements";
const CURRENT_PROFILE_STATS_ID = "current";
const TOP_RANK_LIMIT = 100;
const QUERY_LIMIT = 250;
const FINALIZING_LOCK_MINUTES = 30;
const FINALIZED_TIME_FRAMES = ["weekly", "monthly", "yearly"] as const;

type FinalizedTimeFrame = typeof FINALIZED_TIME_FRAMES[number];

interface LeaderboardPeriod {
  timeFrame: FinalizedTimeFrame;
  key: string;
  startAt: Date;
  endAt: Date;
}

interface LeaderboardRow {
  documentId: string;
  userId: string;
  totalSteps: number;
  lastUpdated: Date;
}

/**
 * Freezes closed leaderboard periods into user achievement records.
 *
 * Active standings keep reading the current period from leaderboard_stats.
 * This job turns a closed period from that same materialized leaderboard well
 * into durable profile achievement rows.
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

async function finalizeMostRecentClosedPeriod(
  timeFrame: FinalizedTimeFrame,
  now: Date
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

  const rows = await leaderboardRowsForPeriod(period);
  const rankedRows = rankedQualifiers(rows);
  const batch = db.batch();
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

    batch.set(achievementRef, {
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
    });

    batch.set(
      db
        .collection(USERS_COLLECTION)
        .doc(row.userId)
        .collection(PROFILE_STATS_COLLECTION)
        .doc(CURRENT_PROFILE_STATS_ID),
      profileStatsIncrement(row.rank),
      {merge: true}
    );
    achievementCount += 1;
  }

  batch.set(
    periodRef,
    {
      status: "finalized",
      finalizedAt: admin.firestore.FieldValue.serverTimestamp(),
      achievementCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  await batch.commit();
}

async function leaderboardRowsForPeriod(
  period: LeaderboardPeriod
): Promise<LeaderboardRow[]> {
  const snapshot = await admin.firestore()
    .collection(LEADERBOARD_STATS_COLLECTION)
    .where("timeFrame", "==", period.timeFrame)
    .where(
      "periodStartAt",
      "==",
      admin.firestore.Timestamp.fromDate(period.startAt)
    )
    .orderBy("totalSteps", "desc")
    .limit(QUERY_LIMIT)
    .get();

  const byUser = new Map<string, LeaderboardRow>();
  for (const document of snapshot.docs) {
    const data = document.data();
    const userId = stringValue(data.userId);
    const totalSteps = numberValue(data.totalSteps);
    const lastUpdated = timestampDate(data.lastUpdated) ?? new Date(0);
    if (!userId || totalSteps <= 0) {
      continue;
    }

    const existing = byUser.get(userId);
    if (!existing || lastUpdated > existing.lastUpdated) {
      byUser.set(userId, {
        documentId: document.id,
        userId,
        totalSteps,
        lastUpdated,
      });
    }
  }

  return [...byUser.values()].sort((lhs, rhs) => {
    if (lhs.totalSteps !== rhs.totalSteps) {
      return rhs.totalSteps - lhs.totalSteps;
    }
    return lhs.userId.localeCompare(rhs.userId);
  });
}

function rankedQualifiers(
  rows: LeaderboardRow[]
): Array<LeaderboardRow & {rank: number}> {
  const ranked: Array<LeaderboardRow & {rank: number}> = [];
  let previousSteps: number | null = null;
  let currentRank = 0;

  rows.forEach((row, index) => {
    if (previousSteps !== row.totalSteps) {
      currentRank = index + 1;
      previousSteps = row.totalSteps;
    }

    if (currentRank <= TOP_RANK_LIMIT) {
      ranked.push({...row, rank: currentRank});
    }
  });

  return ranked;
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
 * yearly finish all land on the same band counter, because the profile badges
 * show one total per band (CHAMPION / TOP 3 / TOP 10 / TOP 100) with no period
 * noun. The per-frame breakdown lives on the achievement records themselves,
 * which is what the achievement history sheet reads. Counting is cumulative:
 * a Top 1 finish also counts toward Top 3, Top 10, and Top 100.
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

function previousPeriod(
  timeFrame: FinalizedTimeFrame,
  date: Date
): LeaderboardPeriod {
  switch (timeFrame) {
  case "weekly": {
    const endAt = startOfWeekUTC(date);
    const startAt = addDays(endAt, -7);
    const {year, week} = weekInfoUTC(startAt);
    return {
      timeFrame,
      key: `${year}-W${String(week).padStart(2, "0")}`,
      startAt,
      endAt,
    };
  }
  case "monthly": {
    const endAt = utcDate(date.getUTCFullYear(), date.getUTCMonth(), 1);
    const startAt = utcDate(endAt.getUTCFullYear(), endAt.getUTCMonth() - 1, 1);
    return {
      timeFrame,
      key:
          `${startAt.getUTCFullYear()}-M` +
          `${String(startAt.getUTCMonth() + 1).padStart(2, "0")}`,
      startAt,
      endAt,
    };
  }
  case "yearly": {
    const endAt = utcDate(date.getUTCFullYear(), 0, 1);
    const startAt = utcDate(endAt.getUTCFullYear() - 1, 0, 1);
    return {
      timeFrame,
      key: `${startAt.getUTCFullYear()}`,
      startAt,
      endAt,
    };
  }
  }
}

export const leaderboardAchievementsTestHooks = {
  achievementType,
  profileStatsIncrement,
};

function timestampDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  return null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value :
    null;
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.trunc(value) :
    0;
}

function utcDate(year: number, month: number, day: number): Date {
  return new Date(Date.UTC(year, month, day));
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date.getTime());
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

function startOfWeekUTC(date: Date): Date {
  const start = utcDate(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate()
  );
  const daysSinceMonday = (start.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - daysSinceMonday);
  return start;
}

function weekInfoUTC(date: Date): {year: number; week: number} {
  const normalizedDate = utcDate(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate()
  );
  const weekStart = startOfWeekUTC(normalizedDate);
  const calendarYear = normalizedDate.getUTCFullYear();
  const firstWeekStart = startOfWeekUTC(utcDate(calendarYear, 0, 1));

  if (weekStart < firstWeekStart) {
    return weekInfoUTC(utcDate(calendarYear - 1, 11, 31));
  }

  const nextYearFirstWeekStart = startOfWeekUTC(
    utcDate(calendarYear + 1, 0, 1)
  );
  if (weekStart >= nextYearFirstWeekStart) {
    return {year: calendarYear + 1, week: 1};
  }

  const diffDays = Math.round(
    (weekStart.getTime() - firstWeekStart.getTime()) /
      (1000 * 60 * 60 * 24)
  );
  return {
    year: calendarYear,
    week: Math.floor(diffDays / 7) + 1,
  };
}
