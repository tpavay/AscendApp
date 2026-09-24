/**
 * Weekly and monthly recap emails.
 *
 * Two scheduled sweeps - one per cadence - that compose and enqueue a recap
 * for every climber who has ever had at least one eligible workout. An
 * ACTIVE climber (activity in the closed window) gets their stats; a
 * ZERO-ACTIVITY climber (no activity in the window, but a real history
 * before it) gets a gentle re-engagement email instead. A climber who has
 * never completed a climb at all gets neither - that gap belongs to the
 * onboarding-abandonment lifecycle emails, not this one, so a brand-new
 * signup mid-onboarding is never told "the board missed you".
 *
 * REUSE, NOT A SECOND PATH. Every send goes through the same
 * `enqueueLifecycleEmailIfAllowed` transaction the rating-prompt automation
 * uses (email/queue.ts) - same dedupe-by-job-id mechanics, same
 * queue-time consent gate, same send-time re-check in the processor. This
 * file only decides who gets what content; email/catalog.ts, templates.ts,
 * processor.ts, and unsubscribe.ts are untouched apart from registering the
 * four new EmailType entries.
 *
 * EFFICIENT SOURCING. `leaderboard_stats` already carries one document per
 * {user, timeFrame, period} with totals derived from that user's workouts
 * (leaderboardStats.ts), and a period with zero workouts never gets a row at
 * all (see deriveLeaderboardRows). So:
 *   - The ACTIVE cohort for a closed period is exactly the rows at
 *     {timeFrame, periodStartAt} - one cheap paginated collection scan, no
 *     per-user workout history read.
 *   - The "has ever climbed" population is exactly the rows at
 *     {timeFrame: "all_time"} - same shape, same cost.
 *   - ZERO-ACTIVITY is the set difference of those two, computed in memory.
 * This never sweeps the full `users` collection and never reads a user's
 * full workout history: the one per-user workout query load-bears is a
 * `startedAt` range query bounded to the single closed period, run only for
 * the (small) active cohort, to resolve which landmarks they finished.
 *
 * DOCUMENTED ASSUMPTIONS (no captain decision needed to proceed, brief
 * allows proceeding with assumptions on exactly these two points):
 *   - Send time: weekly Monday 13:00 UTC, monthly the 1st at 13:00 UTC. Both
 *     land comfortably after the 00:15 UTC finalizer
 *     (leaderboardAchievements.ts) has frozen that closed period's global
 *     steps achievements, so "notable rank moments" are never read before
 *     they exist.
 *   - The monthly recap does not suppress the weekly recap in the same
 *     calendar week (the two answer different questions - "this week" vs.
 *     "this month" - and neither is a subset view of the other; a week can
 *     straddle a month boundary, so nesting them is not even well-defined).
 *   - "Notable rank moments / best placements" is scoped to the closed
 *     period's GLOBAL steps leaderboard achievement tier
 *     (users/{uid}/achievements/global_steps_{timeFrame}_{periodKey}, the
 *     one leaderboardAchievements.ts already derives) - not a re-derivation
 *     of live per-climb rank or First Ascent status, which already has its
 *     own immediate `first_ascent_claimed` email and a materially more
 *     complex derivation (liveReplayLeaderboard.ts).
 *   - "Landmarks finished" is distinct `climbId`s among that closed period's
 *     workouts, names resolved off the same hosted climb catalogue
 *     `announceClimbDrops` reads (climbDropNotifications.ts) - not
 *     `landmarkResults`, whose `firstCompletedAtMillis` records only a
 *     climber's first-ever finish of a landmark, not "finished in this
 *     window".
 *   - The suggested climb in a zero-activity email is the shortest currently
 *     available climb (most approachable comeback), the same pick for every
 *     recipient of one run - not personalized per climber, since nothing in
 *     the data model correlates a dormant climber to a specific landmark.
 *   - Streak is reimplemented server-side against `leaderboard_stats` weekly
 *     rows (UTC-Monday weeks), not the client's local-timezone SwiftData
 *     computation (Workout.calculateWeeklyStreak) - there is no server field
 *     to read, and the two are expected to differ by at most a day at a week
 *     boundary.
 *   - "Landmarks finished" does not re-apply leaderboardStats.ts's
 *     competition-eligibility source filter or plausibility envelope: a
 *     workout that finished a landmark but did not count toward the
 *     leaderboard total (a rare, non-scoring source or an implausible
 *     session already excluded from `climbsCompleted`) can still appear in
 *     the list, since the landmark was still finished regardless of whether
 *     it scored.
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  CatalogClimb,
  availableClimbIds,
  makeHostedClimbCatalogSource,
  referenceStepCount,
} from "./climbDropNotifications";
import {getMarketingWebsiteUrl} from "./email/config";
import {
  enqueueLifecycleEmailIfAllowed,
  type EnqueueLifecycleEmailOutcome,
} from "./email/queue";
import type {RecapActivePayload, RecapInactivePayload} from "./email/types";
import {
  ClosedLeaderboardPeriod,
  currentPeriod,
  leaderboardDocumentId,
  previousPeriod,
} from "./leaderboardPeriod";

const USERS_COLLECTION = "users";
const WORKOUTS_COLLECTION = "workouts";
const ACHIEVEMENTS_COLLECTION = "achievements";
const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";

/** Page size and page budget for the two `leaderboard_stats` cohort scans. */
const COHORT_PAGE_SIZE = 200;
const MAX_COHORT_PAGES = 50;
/** Bounds how far back the streak walk reads before giving up. */
const MAX_WEEKLY_STREAK_LOOKBACK = 26;
/** Matches TOP_RANK_LIMIT in leaderboardAchievements.ts. */
const ACHIEVEMENT_RANK_LIMIT = 100;

export type RecapCadence = "weekly" | "monthly";
type RecapVariant = "active" | "inactive";

interface LeaderboardStatsRow {
  totalFloors: number;
  totalSteps: number;
  totalWorkouts: number;
}

export interface RecapSweepSummary {
  activeUserCount: number;
  alreadyQueued: number;
  errors: number;
  everActiveUserCount: number;
  queued: number;
  skippedNoEmail: number;
  suppressed: number;
}

// =============================================================================
// Pure helpers - unit-testable without Firestore
// =============================================================================

/**
 * Builds the one-send-per-user-per-period dedupe key for a recap email.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {RecapVariant} variant - Active-stats or zero-activity re-engagement
 * @param {string} periodKey - Closed period key (e.g. "2026-W38", "2026-M09")
 * @param {string} uid - Firebase Auth user ID
 * @return {string} Stable dedupe key
 */
export function buildRecapDedupeKey(
  cadence: RecapCadence,
  variant: RecapVariant,
  periodKey: string,
  uid: string
): string {
  return `${cadence}-recap-${variant}:${periodKey}:${uid}`;
}

/**
 * Names the locked achievement tier for a finishing rank.
 * @param {number} rank - Final leaderboard rank for the closed period
 * @return {string} "Top 1" | "Top 3" | "Top 10" | "Top 100"
 */
export function achievementTierLabel(rank: number): string {
  if (rank === 1) return "Top 1";
  if (rank <= 3) return "Top 3";
  if (rank <= 10) return "Top 10";
  return "Top 100";
}

/**
 * Builds the recap sentence for a closed-period global steps achievement.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {number} rank - Final leaderboard rank for the closed period
 * @return {string} One-sentence rank callout
 */
export function buildBestRankLabel(
  cadence: RecapCadence,
  rank: number
): string {
  const cadenceNoun = cadence === "weekly" ? "week" : "month";
  return `You placed ${achievementTierLabel(rank)} globally this ` +
    `${cadenceNoun} - #${rank}.`;
}

/**
 * Formats a closed week as a short date range, e.g. "Sep 15 – Sep 21".
 * @param {ClosedLeaderboardPeriod} period - Closed weekly period
 * @return {string} Display label
 */
export function formatWeeklyPeriodLabel(
  period: ClosedLeaderboardPeriod
): string {
  const lastDay = new Date(period.endAt.getTime() - 24 * 60 * 60 * 1000);
  const format = (date: Date): string => date.toLocaleDateString("en-US", {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
  });
  return `${format(period.startAt)} – ${format(lastDay)}`;
}

/**
 * Formats a closed month, e.g. "September 2026".
 * @param {ClosedLeaderboardPeriod} period - Closed monthly period
 * @return {string} Display label
 */
export function formatMonthlyPeriodLabel(
  period: ClosedLeaderboardPeriod
): string {
  return period.startAt.toLocaleDateString("en-US", {
    month: "long",
    timeZone: "UTC",
    year: "numeric",
  });
}

/**
 * Resolves the closed period's workout climb IDs to display names, deduped
 * in first-seen order.
 * @param {string[]} climbIds - Raw climb IDs from the period's workouts
 * @param {Map<string, string>} climbNameById - Catalogue name lookup
 * @return {string[]} Distinct display names
 */
export function dedupeLandmarkNames(
  climbIds: string[],
  climbNameById: Map<string, string>
): string[] {
  const seen = new Set<string>();
  const names: string[] = [];
  for (const climbId of climbIds) {
    if (seen.has(climbId)) {
      continue;
    }
    seen.add(climbId);
    names.push(climbNameById.get(climbId) ?? climbId);
  }
  return names;
}

/**
 * Picks the most approachable currently-available climb for a comeback
 * nudge: the shortest race distance, tie-broken by ID for determinism.
 * @param {CatalogClimb[]} climbs - Full hosted catalogue
 * @return {CatalogClimb | null} The suggested climb, or null with no
 *   available climb
 */
export function pickSuggestedClimb(
  climbs: CatalogClimb[]
): CatalogClimb | null {
  const availableIds = new Set(availableClimbIds(climbs));
  const available = climbs.filter((climb) => availableIds.has(climb.id));
  if (available.length === 0) {
    return null;
  }

  return [...available].sort((left, right) => {
    const difference = (referenceStepCount(left) ?? Number.POSITIVE_INFINITY) -
      (referenceStepCount(right) ?? Number.POSITIVE_INFINITY);
    return difference !== 0 ? difference : left.id.localeCompare(right.id);
  })[0];
}

/**
 * Walks back consecutive UTC-Monday weeks from the most recently closed one,
 * counting how many in a row had activity. Stops at the first gap or once
 * `maxLookback` weeks have been checked, so one active climber never costs
 * an unbounded number of reads.
 * @param {ClosedLeaderboardPeriod} mostRecentClosedWeek - This recap's week
 * @param {(periodKey: string) => Promise<boolean>} hadActivityInWeek - Reads
 *   whether the given week's period key had any workouts
 * @param {number} maxLookback - Maximum weeks to check
 * @return {Promise<number>} Current streak length in weeks
 */
export async function computeCurrentStreakWeeks(
  mostRecentClosedWeek: ClosedLeaderboardPeriod,
  hadActivityInWeek: (periodKey: string) => Promise<boolean>,
  maxLookback: number = MAX_WEEKLY_STREAK_LOOKBACK
): Promise<number> {
  let streak = 0;
  let period: ClosedLeaderboardPeriod = mostRecentClosedWeek;

  for (let i = 0; i < maxLookback; i++) {
    if (!(await hadActivityInWeek(period.key))) {
      break;
    }
    streak += 1;
    const oneDayBeforeThisWeek = new Date(
      period.startAt.getTime() - 24 * 60 * 60 * 1000
    );
    period = currentPeriod(
      "weekly",
      oneDayBeforeThisWeek
    ) as ClosedLeaderboardPeriod;
  }

  return streak;
}

/**
 * Builds the monthly progress-vs-prior-period sentence. Omitted entirely
 * rather than claiming a comparison when there is no prior month to compare
 * against.
 * @param {number} currentSteps - This month's total steps
 * @param {number | null} previousSteps - Prior month's total steps, if any
 * @return {string | undefined} Comparison sentence, when comparable
 */
export function buildComparisonNote(
  currentSteps: number,
  previousSteps: number | null
): string | undefined {
  if (previousSteps === null || previousSteps <= 0) {
    return undefined;
  }

  const deltaPercent = Math.round(
    ((currentSteps - previousSteps) / previousSteps) * 100
  );
  if (deltaPercent > 0) {
    return `Up ${deltaPercent}% from last month.`;
  }
  if (deltaPercent < 0) {
    return `Down ${Math.abs(deltaPercent)}% from last month.`;
  }
  return "Even with last month.";
}

// =============================================================================
// Firestore-backed composition and enqueue
// =============================================================================

/**
 * Pages a `leaderboard_stats` query into a userId -> totals map.
 *
 * Ordered by document ID for a stable, index-free cursor (see
 * expireRevenueCatAccessGrants for the same shape). Bounded by
 * `COHORT_PAGE_SIZE` / `MAX_COHORT_PAGES` rather than resumed across runs -
 * documented as a scale assumption in the file header, not built ahead of
 * need.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {admin.firestore.Query} baseQuery - Query before ordering/paging
 * @return {Promise<Map<string, LeaderboardStatsRow>>} Rows keyed by userId
 */
async function pageLeaderboardStatsRows(
  firestore: admin.firestore.Firestore,
  baseQuery: admin.firestore.Query
): Promise<Map<string, LeaderboardStatsRow>> {
  const rows = new Map<string, LeaderboardStatsRow>();
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  for (let page = 0; page < MAX_COHORT_PAGES; page++) {
    let query = baseQuery
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(COHORT_PAGE_SIZE);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];

    for (const document of snapshot.docs) {
      const data = document.data();
      const userId = stringValue(data.userId);
      if (!userId) {
        continue;
      }
      rows.set(userId, {
        totalFloors: numberValue(data.totalFloors),
        totalSteps: numberValue(data.totalSteps),
        totalWorkouts: numberValue(data.totalWorkouts),
      });
    }

    if (snapshot.size < COHORT_PAGE_SIZE) {
      break;
    }
  }

  return rows;
}

/**
 * Reads a climber's registered email, or null when there is none to mail.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<string | null>} Registered email, when present
 */
async function fetchUserEmail(
  firestore: admin.firestore.Firestore,
  uid: string
): Promise<string | null> {
  const snapshot = await firestore.collection(USERS_COLLECTION).doc(uid).get();
  return stringValue(snapshot.get("email"));
}

/**
 * Reads the distinct landmark climb IDs a climber finished during a closed
 * period, bounded to that period's own date range - never the climber's
 * full workout history.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @return {Promise<string[]>} Climb IDs, in completion order
 */
async function fetchPeriodClimbIds(
  firestore: admin.firestore.Firestore,
  uid: string,
  period: ClosedLeaderboardPeriod
): Promise<string[]> {
  const snapshot = await firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(WORKOUTS_COLLECTION)
    .where("startedAt", ">=", admin.firestore.Timestamp.fromDate(period.startAt))
    .where("startedAt", "<", admin.firestore.Timestamp.fromDate(period.endAt))
    .get();

  const climbIds: string[] = [];
  for (const document of snapshot.docs) {
    const climbId = stringValue(document.get("climbId"));
    if (climbId) {
      climbIds.push(climbId);
    }
  }
  return climbIds;
}

/**
 * Reads the closed period's global steps achievement, when the climber
 * earned one - the same document `finalizeLeaderboardAchievements` writes.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodKey - Closed period key
 * @return {Promise<string | undefined>} Rank callout sentence, when earned
 */
async function fetchBestRankLabel(
  firestore: admin.firestore.Firestore,
  uid: string,
  cadence: RecapCadence,
  periodKey: string
): Promise<string | undefined> {
  const achievementId = `global_steps_${cadence}_${periodKey}`;
  const snapshot = await firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(ACHIEVEMENTS_COLLECTION)
    .doc(achievementId)
    .get();
  if (!snapshot.exists) {
    return undefined;
  }

  const rank = snapshot.get("rank");
  if (typeof rank !== "number" || rank < 1 || rank > ACHIEVEMENT_RANK_LIMIT) {
    return undefined;
  }
  return buildBestRankLabel(cadence, rank);
}

/**
 * Reads the prior month's total steps for the same climber, when they had a
 * standing then.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {ClosedLeaderboardPeriod} currentMonth - This recap's closed month
 * @return {Promise<number | null>} Prior month's total steps
 */
async function fetchPreviousMonthSteps(
  firestore: admin.firestore.Firestore,
  uid: string,
  currentMonth: ClosedLeaderboardPeriod
): Promise<number | null> {
  const oneDayBeforeThisMonth = new Date(
    currentMonth.startAt.getTime() - 24 * 60 * 60 * 1000
  );
  const previousMonth = currentPeriod("monthly", oneDayBeforeThisMonth);
  const docId = leaderboardDocumentId(uid, "monthly", previousMonth.key);
  const snapshot = await firestore
    .collection(LEADERBOARD_STATS_COLLECTION)
    .doc(docId)
    .get();
  if (!snapshot.exists) {
    return null;
  }
  const totalSteps = snapshot.get("totalSteps");
  return typeof totalSteps === "number" ? totalSteps : null;
}

/**
 * Fetches the hosted climb catalogue once per run, tolerating failure.
 *
 * A catalogue fetch failure degrades this run's copy (no landmark names, no
 * specific suggested climb) rather than failing the whole sweep - the same
 * posture `runClimbDropSweep` takes on its own catalogue read.
 * @return {Promise<{climbNameById: Map<string, string>, suggestedClimb:
 *   CatalogClimb | null}>} Catalogue lookups for this run
 */
async function loadClimbCatalogSafely(): Promise<{
  climbNameById: Map<string, string>;
  suggestedClimb: CatalogClimb | null;
}> {
  try {
    const source = makeHostedClimbCatalogSource();
    const manifest = await source.fetchManifest();
    const climbs = await source.fetchClimbs(manifest);
    return {
      climbNameById: new Map(climbs.map((climb) => [climb.id, climb.name])),
      suggestedClimb: pickSuggestedClimb(climbs),
    };
  } catch (error) {
    logger.error("recapEmails.catalogFetchFailed", {
      errorMessage: error instanceof Error ? error.message : "unknown_error",
    });
    return {climbNameById: new Map(), suggestedClimb: null};
  }
}

/**
 * Composes and enqueues one active climber's recap.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @param {string} uid - Firebase Auth user ID
 * @param {LeaderboardStatsRow} aggregate - This period's totals
 * @param {Map<string, string>} climbNameById - Catalogue name lookup
 * @param {string} climbsUrl - Generic "keep climbing" CTA URL
 * @param {RecapSweepSummary} summary - Sweep counters to update
 * @return {Promise<void>} Resolves once queued, suppressed, or skipped
 */
async function composeAndEnqueueActiveRecap(
  firestore: admin.firestore.Firestore,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod,
  uid: string,
  aggregate: LeaderboardStatsRow,
  climbNameById: Map<string, string>,
  climbsUrl: string,
  summary: RecapSweepSummary
): Promise<void> {
  const email = await fetchUserEmail(firestore, uid);
  if (!email) {
    summary.skippedNoEmail += 1;
    return;
  }

  const [climbIds, bestRankLabel] = await Promise.all([
    fetchPeriodClimbIds(firestore, uid, period),
    fetchBestRankLabel(firestore, uid, cadence, period.key),
  ]);

  const payload: RecapActivePayload = {
    bestRankLabel,
    climbsCompleted: aggregate.totalWorkouts,
    climbsUrl,
    landmarksFinished: dedupeLandmarkNames(climbIds, climbNameById),
    periodLabel: cadence === "weekly" ?
      formatWeeklyPeriodLabel(period) :
      formatMonthlyPeriodLabel(period),
    totalFloors: aggregate.totalFloors,
    totalSteps: aggregate.totalSteps,
  };

  if (cadence === "weekly") {
    payload.currentStreakWeeks = await computeCurrentStreakWeeks(
      period,
      async (periodKey) => {
        const docId = leaderboardDocumentId(uid, "weekly", periodKey);
        const snapshot = await firestore
          .collection(LEADERBOARD_STATS_COLLECTION)
          .doc(docId)
          .get();
        return snapshot.exists && numberValue(snapshot.get("totalWorkouts")) > 0;
      }
    );
  } else {
    const previousSteps = await fetchPreviousMonthSteps(firestore, uid, period);
    payload.comparisonNote = buildComparisonNote(
      aggregate.totalSteps,
      previousSteps
    );
  }

  const outcome = await enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey: buildRecapDedupeKey(cadence, "active", period.key, uid),
    emailType: cadence === "weekly" ? "weekly_recap_active" : "monthly_recap_active",
    payload,
    recipientEmail: email,
    sourceRef: `leaderboard_stats/${leaderboardDocumentId(uid, cadence, period.key)}`,
    uid,
  });
  recordOutcome(summary, outcome);
}

/**
 * Composes and enqueues one zero-activity climber's re-engagement email.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @param {string} uid - Firebase Auth user ID
 * @param {CatalogClimb | null} suggestedClimb - This run's comeback pick
 * @param {string} climbsUrl - Fallback CTA when no climb could be suggested
 * @param {RecapSweepSummary} summary - Sweep counters to update
 * @return {Promise<void>} Resolves once queued, suppressed, or skipped
 */
async function composeAndEnqueueInactiveRecap(
  firestore: admin.firestore.Firestore,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod,
  uid: string,
  suggestedClimb: CatalogClimb | null,
  climbsUrl: string,
  summary: RecapSweepSummary
): Promise<void> {
  const email = await fetchUserEmail(firestore, uid);
  if (!email) {
    summary.skippedNoEmail += 1;
    return;
  }

  const payload: RecapInactivePayload = {
    periodLabel: cadence === "weekly" ?
      formatWeeklyPeriodLabel(period) :
      formatMonthlyPeriodLabel(period),
    suggestedClimbName: suggestedClimb?.name,
    suggestedClimbUrl: suggestedClimb ?
      `${climbsUrl}/${suggestedClimb.id}` :
      climbsUrl,
  };

  const outcome = await enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey: buildRecapDedupeKey(cadence, "inactive", period.key, uid),
    emailType: cadence === "weekly" ?
      "weekly_recap_inactive" :
      "monthly_recap_inactive",
    payload,
    recipientEmail: email,
    sourceRef: null,
    uid,
  });
  recordOutcome(summary, outcome);
}

/**
 * Applies one enqueue outcome to the sweep summary.
 * @param {RecapSweepSummary} summary - Sweep counters to update
 * @param {EnqueueLifecycleEmailOutcome} outcome - What the enqueue did
 * @return {void}
 */
function recordOutcome(
  summary: RecapSweepSummary,
  outcome: EnqueueLifecycleEmailOutcome
): void {
  if (outcome === "queued") {
    summary.queued += 1;
  } else if (outcome === "already_queued") {
    summary.alreadyQueued += 1;
  } else {
    summary.suppressed += 1;
  }
}

/**
 * Runs one weekly or monthly recap sweep end to end.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {Date} now - The sweep's clock, injectable for tests
 * @return {Promise<RecapSweepSummary>} What the sweep did
 */
export async function runRecapSweep(
  cadence: RecapCadence,
  now: Date
): Promise<RecapSweepSummary> {
  const firestore = admin.firestore();
  const period = previousPeriod(cadence, now);
  const climbsUrl = `${getMarketingWebsiteUrl()}/app/climbs`;

  const [activeRows, everActiveRows, catalog] = await Promise.all([
    pageLeaderboardStatsRows(
      firestore,
      firestore
        .collection(LEADERBOARD_STATS_COLLECTION)
        .where("timeFrame", "==", cadence)
        .where(
          "periodStartAt",
          "==",
          admin.firestore.Timestamp.fromDate(period.startAt)
        )
    ),
    pageLeaderboardStatsRows(
      firestore,
      firestore
        .collection(LEADERBOARD_STATS_COLLECTION)
        .where("timeFrame", "==", "all_time")
    ),
    loadClimbCatalogSafely(),
  ]);

  const summary: RecapSweepSummary = {
    activeUserCount: activeRows.size,
    alreadyQueued: 0,
    errors: 0,
    everActiveUserCount: everActiveRows.size,
    queued: 0,
    skippedNoEmail: 0,
    suppressed: 0,
  };

  for (const [uid, aggregate] of activeRows) {
    try {
      await composeAndEnqueueActiveRecap(
        firestore,
        cadence,
        period,
        uid,
        aggregate,
        catalog.climbNameById,
        climbsUrl,
        summary
      );
    } catch (error) {
      summary.errors += 1;
      logger.error("recapEmails.activeComposeFailed", {
        cadence,
        errorMessage: error instanceof Error ? error.message : "unknown_error",
        uid,
      });
    }
  }

  for (const uid of everActiveRows.keys()) {
    if (activeRows.has(uid)) {
      continue;
    }
    try {
      await composeAndEnqueueInactiveRecap(
        firestore,
        cadence,
        period,
        uid,
        catalog.suggestedClimb,
        climbsUrl,
        summary
      );
    } catch (error) {
      summary.errors += 1;
      logger.error("recapEmails.inactiveComposeFailed", {
        cadence,
        errorMessage: error instanceof Error ? error.message : "unknown_error",
        uid,
      });
    }
  }

  return summary;
}

/**
 * Reads a trimmed non-empty string field, or null.
 * @param {unknown} value - Candidate field value
 * @return {string | null} Trimmed string, when usable
 */
function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim() :
    null;
}

/**
 * Reads a finite number field, defaulting to zero.
 * @param {unknown} value - Candidate field value
 * @return {number} The number, or zero
 */
function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/**
 * Sends every eligible climber their weekly recap.
 *
 * Monday 13:00 UTC: comfortably after the 00:15 UTC finalizer has frozen the
 * week that just closed (see file header for the send-time assumption).
 */
export const weeklyRecapEmails = onSchedule(
  {
    memory: "512MiB",
    schedule: "0 13 * * 1",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    const summary = await runRecapSweep("weekly", new Date());
    const write = summary.errors > 0 ? logger.error : logger.log;
    write("weeklyRecapEmails sweep completed", summary);
  }
);

/**
 * Sends every eligible climber their monthly recap. 1st of month, 13:00 UTC.
 */
export const monthlyRecapEmails = onSchedule(
  {
    memory: "512MiB",
    schedule: "0 13 1 * *",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    const summary = await runRecapSweep("monthly", new Date());
    const write = summary.errors > 0 ? logger.error : logger.log;
    write("monthlyRecapEmails sweep completed", summary);
  }
);
