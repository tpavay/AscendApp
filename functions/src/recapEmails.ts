/**
 * Weekly and monthly recap emails.
 *
 * Two scheduled sweeps - one per cadence - that compose and enqueue a recap
 * for every climber who has ever had at least one eligible workout. An
 * ACTIVE climber (activity in the closed window) gets a stats recap: a
 * rank/percentile hero, an optional achievement callout, stat cards with
 * delta chips against the prior period, and an activity calendar heatmap. A
 * ZERO-ACTIVITY climber (no activity in the window, but a real history
 * before it) gets a gentle re-engagement email instead, naming the real gap
 * since they were last active and their First Ascents, if they hold any. A
 * climber who has never completed a climb at all gets neither - that gap
 * belongs to the onboarding-abandonment lifecycle emails, not this one, so a
 * brand-new signup mid-onboarding is never told "we missed you".
 *
 * Design direction (captain, 2026-09-24, Wispr-Flow-inspired layout,
 * Ascend's own dark/green/landmark brand - see templates.ts for the render
 * layer): bold editorial hero leading with the climber's rank AND percentile
 * shown together, an optional achievement callout (the app's existing
 * tracked achievements, reused rather than invented), stat cards with green
 * "up only" delta chips, and a per-day activity calendar heatmap. Copy is
 * past-tense throughout ("last week" / "last month") because every send
 * lands well after the period it describes has closed.
 *
 * Round 3 (2026-09-24) promoted rank and percentile to the hero's lead
 * metric (previously a secondary callout below the fold) and added the
 * achievement callout. Round 4 (2026-09-24, captain review of the rendered
 * emails) removed the milestone-unlocked callout entirely ("I don't like
 * the whole milestone unlocked thing. That doesn't make any sense."),
 * renamed every "on the board" phrase to "on the stair stepper", and
 * rewrote the zero-activity email around the real elapsed gap and the
 * climber's First Ascents instead of a generic "the board missed you".
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
 *   - RANK AND PERCENTILE come from ranking the already-loaded active cohort
 *     in memory (mirroring leaderboardAchievements.ts's standard competition
 *     ranking, uncapped) rather than a second Firestore read per user - the
 *     whole cohort is already resident for the active/inactive split, so
 *     ranking it is free. The separate ACHIEVEMENT callout (round 3) is the
 *     one per-user read this file still does beyond the workout query: an
 *     O(1) doc get on the same `global_steps_{cadence}_{periodKey}` record
 *     `finalizeLeaderboardAchievements` already writes, because "achievement"
 *     names the app's one existing tracked concept and must not drift from
 *     it by being re-derived from this file's own ranking math.
 * This never sweeps the full `users` collection and never reads a user's
 * full workout history. Each climber costs exactly one workout query,
 * bounded by cohort size: an active climber's is a `startedAt` range query
 * bounded to the single closed period, to resolve landmark completions and
 * the daily activity calendar; a zero-activity climber's is one indexed
 * `orderBy("startedAt", "desc").limit(1)` read of their latest workout, for
 * the real gap (`fetchLatestWorkoutStartedAt`). Neither is a scan.
 * Per-recipient composition and enqueue runs with bounded concurrency
 * (`RECIPIENT_CONCURRENCY`), not sequentially, so a large cohort cannot run
 * the 540s invocation out the clock and silently strand the rest of a
 * period's recipients - `onSchedule` does not retry a timed-out run.
 *
 * DOCUMENTED ASSUMPTIONS:
 *   - Send time: weekly Monday 13:00 UTC, monthly the 1st at 13:00 UTC. Both
 *     land comfortably after the 00:15 UTC finalizer
 *     (leaderboardAchievements.ts) has frozen that closed period's global
 *     steps achievements - moot for rank/percentile now that both are
 *     computed directly from `leaderboard_stats`, but still true for the
 *     permanent achievement records themselves.
 *   - The monthly recap does not suppress the weekly recap in the same
 *     calendar week (the two answer different questions - "last week" vs.
 *     "last month" - and neither is a subset view of the other; a week can
 *     straddle a month boundary, so nesting them is not even well-defined).
 *   - The CTA in every recap email is the App Store listing
 *     (`https://apps.apple.com/app/id6757202987`, Ascend's production App
 *     Store Connect app id), not a deep link into the app - no `/app/...`
 *     hosting route or universal link exists yet. A landmark named in copy
 *     (a finished landmark, a suggested comeback climb) is text only, never
 *     a link target. Upgrading the CTA to a universal link is a later,
 *     separate change.
 *   - Delta chips are built only for a genuine improvement over the prior
 *     period - never a decline or an unchanged figure - so the recap can
 *     never read as a scolding. A flat or down period simply shows no chip
 *     on that stat.
 *   - The zero-activity email's gap ("We haven't seen you in N weeks/
 *     months") reads the climber's latest workout `startedAt` - one indexed
 *     `orderBy("startedAt", "desc").limit(1)` read per zero-activity
 *     climber, never their history. The `all_time` row's `lastUpdated` is
 *     not a last-activity time: every reconcile (a demographics edit, an
 *     old workout's edit or delete, a backfill) restamps it. A latest
 *     workout at or after the closed period's end means the climber already
 *     came back, so no zero-activity email is sent. Falls back to the
 *     closed period's own start date on the defensive case where no
 *     workout is found.
 *   - First Ascents in the zero-activity email read
 *     `live_replay_leaderboards` where `firstAscentUserId == uid` - the one
 *     durable, permanent record `liveReplayLeaderboard.ts` writes when a
 *     climb's First Ascent is claimed - not a re-derivation. A climber with
 *     any First Ascents gets them named; a climber with none gets the
 *     existing suggested-comeback-climb nudge instead.
 *   - "Landmarks finished" (the active-recap stat, distinct from First
 *     Ascents above) uses `climbCompletions.ts`'s
 *     `parseCompletedLandmarkWorkout` (the single definition of "finished a
 *     landmark" shared with Swift and the backfill), not a bare "carried a
 *     climbId" check - an abandoned Live Climb attempt is never reported as
 *     finished. It does not re-apply leaderboardStats.ts's
 *     competition-eligibility source filter or plausibility envelope: a
 *     workout that finished a landmark but did not count toward the scored
 *     leaderboard total can still appear in the list, since the landmark was
 *     still finished regardless of whether it scored.
 *   - The suggested climb in a zero-activity email is the shortest currently
 *     available climb (most approachable comeback), the same pick for every
 *     recipient of one run - not personalized per climber, since nothing in
 *     the data model correlates a dormant climber to a specific landmark.
 *   - Streak is reimplemented server-side against `leaderboard_stats` weekly
 *     rows (UTC-Monday weeks), not the client's local-timezone SwiftData
 *     computation (Workout.calculateWeeklyStreak) - there is no server field
 *     to read, and the two are expected to differ by at most a day at a week
 *     boundary.
 *   - The weekly period label (round 3: "the captain was unsure how to label
 *     the week... flag [a cleaner idea] rather than guessing") is the
 *     captain's own given example, "Sep 15-21, 2026" - a concrete, dated
 *     range so a later reader knows exactly when it was, matching the
 *     monthly label's "month + year" concreteness. Implemented to also
 *     handle a week that straddles a month or year boundary (rare, but a
 *     UTC-Monday week can), even though the common case is exactly the given
 *     example.
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  type CompletedLandmarkWorkout,
  parseCompletedLandmarkWorkout,
} from "./climbCompletions";
import {
  type CatalogClimb,
  availableClimbIds,
  makeHostedClimbCatalogSource,
  referenceStepCount,
} from "./climbDropNotifications";
import {runWithBoundedConcurrency} from "./concurrency";
import {
  enqueueLifecycleEmailIfAllowed,
  type EnqueueLifecycleEmailOutcome,
} from "./email/queue";
import type {
  RecapActivePayload,
  RecapCalendarCell,
  RecapDeltaChip,
  RecapInactivePayload,
} from "./email/types";
import {
  type ClosedLeaderboardPeriod,
  currentPeriod,
  leaderboardDocumentId,
  previousPeriod,
} from "./leaderboardPeriod";

/**
 * Ascend's production App Store Connect app id (data/app-setup-runbook.md).
 * Deliberately environment-invariant, unlike `getMarketingWebsiteUrl()`: this
 * is the one public App Store listing, the same regardless of which Firebase
 * project the sweep happens to run in.
 */
const APP_STORE_URL = "https://apps.apple.com/app/id6757202987";

const USERS_COLLECTION = "users";
const WORKOUTS_COLLECTION = "workouts";
const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";
const ACHIEVEMENTS_COLLECTION = "achievements";
const LIVE_REPLAY_LEADERBOARDS_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";

/** Page size and page budget for the two `leaderboard_stats` cohort scans. */
const DEFAULT_COHORT_SCAN_BOUND: CohortScanBound = {
  maxPages: 50,
  pageSize: 200,
};
/** Bounds how far back the streak walk reads before giving up. */
const MAX_WEEKLY_STREAK_LOOKBACK = 26;
/** The widest achievement tier's ceiling rank ("Top 100"). */
const ACHIEVEMENT_TIER_CEILING = 100;
/** Recipients composed and enqueued at once, per sweep. */
const RECIPIENT_CONCURRENCY = 10;

export type RecapCadence = "weekly" | "monthly";

interface LeaderboardStatsRow {
  totalFloors: number;
  totalSteps: number;
  totalWorkouts: number;
}

export interface RecapStanding {
  fieldSize: number;
  rank: number;
}

export interface CohortScanBound {
  maxPages: number;
  pageSize: number;
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
 * Builds the one-send-per-user-per-period dedupe key for a recap email,
 * shared by both variants.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodKey - Closed period key (e.g. "2026-W38", "2026-M09")
 * @param {string} uid - Firebase Auth user ID
 * @return {string} Stable dedupe key
 */
export function buildRecapDedupeKey(
  cadence: RecapCadence,
  periodKey: string,
  uid: string
): string {
  return `${cadence}-recap:${periodKey}:${uid}`;
}

/**
 * Names the locked achievement tier for a finishing rank.
 * @param {number} rank - Final leaderboard rank for the closed period
 * @return {string} "Top 1" | "Top 3" | "Top 10" | "Top 100"
 */
export function achievementTierLabel(rank: number): string {
  return `Top ${achievementTierLimit(rank)}`;
}

/**
 * The upper rank bound of a finishing rank's achievement tier.
 * @param {number} rank - Final leaderboard rank for the closed period
 * @return {number} 1 | 3 | 10 | 100
 */
function achievementTierLimit(rank: number): number {
  if (rank === 1) return 1;
  if (rank <= 3) return 3;
  if (rank <= 10) return 10;
  return ACHIEVEMENT_TIER_CEILING;
}

/**
 * Formats a closed week as a concrete, dated range so a later reader knows
 * exactly when it was, e.g. "Sep 15-21, 2026". Handles a week that straddles
 * a month or year boundary, though the common case never does.
 * @param {ClosedLeaderboardPeriod} period - Closed weekly period
 * @return {string} Display label
 */
export function formatWeeklyPeriodLabel(
  period: ClosedLeaderboardPeriod
): string {
  const start = period.startAt;
  const end = new Date(period.endAt.getTime() - 24 * 60 * 60 * 1000);
  const monthName = (date: Date): string => date.toLocaleDateString("en-US", {
    month: "short",
    timeZone: "UTC",
  });

  const sameYear = start.getUTCFullYear() === end.getUTCFullYear();
  const sameMonth = sameYear && start.getUTCMonth() === end.getUTCMonth();

  if (sameMonth) {
    return `${monthName(start)} ${start.getUTCDate()}-${end.getUTCDate()}, ` +
      `${end.getUTCFullYear()}`;
  }
  if (sameYear) {
    return `${monthName(start)} ${start.getUTCDate()} - ` +
      `${monthName(end)} ${end.getUTCDate()}, ${end.getUTCFullYear()}`;
  }
  return `${monthName(start)} ${start.getUTCDate()}, ` +
    `${start.getUTCFullYear()} - ${monthName(end)} ${end.getUTCDate()}, ` +
    `${end.getUTCFullYear()}`;
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
 * Resolves landmark climb IDs to display names, deduped in first-seen order.
 * An ID the catalogue cannot resolve keeps its raw ID, so it still counts.
 * @param {string[]} climbIds - Distinct completed-landmark climb IDs
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
 * Ranks every active climber in a closed period against each other by total
 * steps, mirroring leaderboardAchievements.ts's standard competition ranking
 * (1, 2, 2, 4; tie-broken by user id for a stable order) and its exclusion of
 * zero-step rows - uncapped, since a
 * percentile callout needs a real rank for every climber, not just a top-100
 * band.
 * @param {Map<string, {totalSteps: number}>} rows - This period's active
 *   cohort, keyed by userId
 * @return {Map<string, RecapStanding>} Rank and field size per userId
 */
export function rankActiveCohort(
  rows: Map<string, {totalSteps: number}>
): Map<string, RecapStanding> {
  const sorted = [...rows.entries()]
    .filter(([, row]) => row.totalSteps > 0)
    .sort(([leftId, left], [rightId, right]) => {
      if (left.totalSteps !== right.totalSteps) {
        return right.totalSteps - left.totalSteps;
      }
      return leftId.localeCompare(rightId);
    });

  const fieldSize = sorted.length;
  const standings = new Map<string, RecapStanding>();
  let currentRank = 0;
  let previousSteps: number | null = null;

  sorted.forEach(([uid, row], index) => {
    if (previousSteps === null || previousSteps !== row.totalSteps) {
      currentRank = index + 1;
      previousSteps = row.totalSteps;
    }
    standings.set(uid, {fieldSize, rank: currentRank});
  });

  return standings;
}

/**
 * Whether a field holds enough climbers for a rank in it to mean anything -
 * the same honesty rule as the app's "1ST OF 1 CLIMBER never appears". The
 * concrete rank (`#N of M climbers`) is shown whenever this is true; a
 * percentile band is a further, optional badge alongside it.
 * @param {number} fieldSize - Total climbers ranked in the closed period
 * @return {boolean} True for a field of two or more
 */
export function isRankableField(fieldSize: number): boolean {
  return fieldSize > 1;
}

/**
 * Names the percentile band a rank falls in, if it reaches one - the
 * secondary badge shown alongside the always-stated concrete rank (round 3:
 * "show BOTH"). Nothing below the top half; a recap never claims a
 * percentile it did not earn.
 * @param {number} rank - This climber's rank in the closed period
 * @param {number} fieldSize - Total climbers ranked in the closed period
 * @return {string | undefined} "Top N%", or nothing below the top half
 */
export function percentileBand(
  rank: number,
  fieldSize: number
): string | undefined {
  if (!isRankableField(fieldSize)) {
    return undefined;
  }
  const percentile = (rank / fieldSize) * 100;
  if (percentile <= 1) return "Top 1%";
  if (percentile <= 5) return "Top 5%";
  if (percentile <= 10) return "Top 10%";
  if (percentile <= 25) return "Top 25%";
  if (percentile <= 50) return "Top 50%";
  return undefined;
}

/**
 * Builds a green "up" delta chip against the prior period - never a decline
 * or an unchanged figure, so a recap can never read as a scolding.
 * @param {number} current - This period's total
 * @param {number | null} previous - The prior period's total, if any
 * @param {string} label - Chip label, e.g. "vs last week"
 * @return {RecapDeltaChip | undefined} The chip, only for a genuine increase
 */
export function buildDeltaChip(
  current: number,
  previous: number | null,
  label: string
): RecapDeltaChip | undefined {
  if (previous === null || current <= previous) {
    return undefined;
  }
  return {direction: "up", label, value: formatCount(current - previous)};
}

/**
 * Whole weeks since an instant, floored at 1 - a zero-activity climber has
 * been gone at least a week by definition, so "0 weeks" never renders.
 * @param {Date} since - The climber's last known activity
 * @param {Date} now - The sweep's clock
 * @return {number} Weeks since, at least 1
 */
export function weeksSince(since: Date, now: Date): number {
  const weeks = Math.round(
    (now.getTime() - since.getTime()) / (7 * 24 * 60 * 60 * 1000)
  );
  return Math.max(1, weeks);
}

/**
 * Whole elapsed months since an instant, floored at 1 - a month only counts
 * once `now` has passed the same day-of-month and time-of-day as `since`.
 * @param {Date} since - The climber's last known activity
 * @param {Date} now - The sweep's clock
 * @return {number} Months since, at least 1
 */
export function monthsSince(since: Date, now: Date): number {
  let months = (now.getUTCFullYear() - since.getUTCFullYear()) * 12 +
    (now.getUTCMonth() - since.getUTCMonth());
  const nowWithinMonth = now.getTime() -
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
  const sinceWithinMonth = since.getTime() -
    Date.UTC(since.getUTCFullYear(), since.getUTCMonth(), 1);
  if (nowWithinMonth < sinceWithinMonth) {
    months -= 1;
  }
  return Math.max(1, months);
}

/**
 * Builds the period's activity calendar heatmap: one cell per day, plus
 * leading/trailing blank cells so a monthly grid aligns to its starting
 * weekday. A weekly grid is always exactly 7 filled cells, Monday first.
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @param {Map<string, number>} stepsByDayKey - Steps per UTC day
 *   ("YYYY-MM-DD") inside the period
 * @return {RecapCalendarCell[]} Calendar cells, Monday-aligned
 */
export function buildCalendarCells(
  period: ClosedLeaderboardPeriod,
  stepsByDayKey: Map<string, number>
): RecapCalendarCell[] {
  const totalDays = Math.round(
    (period.endAt.getTime() - period.startAt.getTime()) /
      (24 * 60 * 60 * 1000)
  );
  const leadingBlanks = (period.startAt.getUTCDay() + 6) % 7;

  let peakKey: string | null = null;
  let peakSteps = 0;
  for (let day = 0; day < totalDays; day++) {
    const key = dayKeyUTC(addDaysUTC(period.startAt, day));
    const steps = stepsByDayKey.get(key) ?? 0;
    if (steps > peakSteps) {
      peakSteps = steps;
      peakKey = key;
    }
  }

  const cells: RecapCalendarCell[] = [];
  for (let i = 0; i < leadingBlanks; i++) {
    cells.push({dayOfMonth: null, level: "blank"});
  }
  for (let day = 0; day < totalDays; day++) {
    const date = addDaysUTC(period.startAt, day);
    const key = dayKeyUTC(date);
    const steps = stepsByDayKey.get(key) ?? 0;
    const level: RecapCalendarCell["level"] = steps <= 0 ?
      "none" :
      key === peakKey ? "peak" : "active";
    cells.push({dayOfMonth: date.getUTCDate(), level});
  }
  const trailingBlanks = (7 - (cells.length % 7)) % 7;
  for (let i = 0; i < trailingBlanks; i++) {
    cells.push({dayOfMonth: null, level: "blank"});
  }

  return cells;
}

// =============================================================================
// Firestore-backed composition and enqueue
// =============================================================================

/**
 * Pages a `leaderboard_stats` query into a userId -> totals map.
 *
 * Ordered by document ID for a stable, index-free cursor (see
 * expireRevenueCatAccessGrants for the same shape). Bounded by a
 * `CohortScanBound` rather than resumed across runs -
 * documented as a scale assumption in the file header, not built ahead of
 * need - and reports and logs loudly if that bound is ever actually hit, so
 * a silent truncation cannot masquerade as a complete cohort.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {admin.firestore.Query} baseQuery - Query before ordering/paging
 * @param {string} label - Identifies which scan this is, for the truncation
 *   log
 * @param {CohortScanBound} bound - Page size and page budget
 * @return {Promise<{rows: Map<string, LeaderboardStatsRow>,
 *   truncated: boolean}>} Rows keyed by userId, and whether the page bound
 *   cut the scan short
 */
async function pageLeaderboardStatsRows(
  firestore: admin.firestore.Firestore,
  baseQuery: admin.firestore.Query,
  label: string,
  bound: CohortScanBound
): Promise<{rows: Map<string, LeaderboardStatsRow>; truncated: boolean}> {
  const rows = new Map<string, LeaderboardStatsRow>();
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
  let pagesRead = 0;

  for (let page = 0; page < bound.maxPages; page++) {
    pagesRead += 1;
    let query = baseQuery
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(bound.pageSize);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      return {rows, truncated: false};
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

    if (snapshot.size < bound.pageSize) {
      return {rows, truncated: false};
    }
  }

  logger.error("recapEmails.cohortScanTruncated", {
    label,
    pagesRead,
    rowsRead: rows.size,
  });
  return {rows, truncated: true};
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
 * Reads a closed period's workouts once and derives both the landmark
 * completions and the per-day step totals from the same rows - bounded to
 * that period's own date range, never the climber's full workout history.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @return {Promise<{completedClimbIds: string[], stepsByDayKey: Map<string,
 *   number>}>} Finished-landmark climb IDs and per-UTC-day step totals
 */
async function fetchPeriodWorkoutDetails(
  firestore: admin.firestore.Firestore,
  uid: string,
  period: ClosedLeaderboardPeriod
): Promise<{
  completedClimbIds: string[];
  stepsByDayKey: Map<string, number>;
}> {
  const snapshot = await firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(WORKOUTS_COLLECTION)
    .where("startedAt", ">=", admin.firestore.Timestamp.fromDate(period.startAt))
    .where("startedAt", "<", admin.firestore.Timestamp.fromDate(period.endAt))
    .select("startedAt", "steps", "durationSeconds", "source", "sourceMetadata")
    .get();

  const completedClimbIds: string[] = [];
  const stepsByDayKey = new Map<string, number>();

  for (const document of snapshot.docs) {
    const data = document.data();
    const completion: CompletedLandmarkWorkout | null =
      parseCompletedLandmarkWorkout(document.id, data);
    if (completion) {
      completedClimbIds.push(completion.climbId);
    }

    const startedAt = data.startedAt;
    const steps = numberValue(data.steps);
    if (startedAt instanceof admin.firestore.Timestamp && steps > 0) {
      const key = dayKeyUTC(startedAt.toDate());
      stepsByDayKey.set(key, (stepsByDayKey.get(key) ?? 0) + steps);
    }
  }

  return {completedClimbIds, stepsByDayKey};
}

/**
 * Reads when the climber's latest workout started, or null with none.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<Date | null>} Latest workout's start time
 */
async function fetchLatestWorkoutStartedAt(
  firestore: admin.firestore.Firestore,
  uid: string
): Promise<Date | null> {
  const snapshot = await firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(WORKOUTS_COLLECTION)
    .orderBy("startedAt", "desc")
    .limit(1)
    .select("startedAt")
    .get();
  const startedAt = snapshot.docs[0]?.get("startedAt");
  return startedAt instanceof admin.firestore.Timestamp ?
    startedAt.toDate() :
    null;
}

/**
 * Reads the prior period's totals for the same climber, when they had a
 * standing then, for the stat cards' delta chips.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ClosedLeaderboardPeriod} period - This recap's closed period
 * @return {Promise<LeaderboardStatsRow | null>} Prior period's totals
 */
async function fetchPreviousPeriodTotals(
  firestore: admin.firestore.Firestore,
  uid: string,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod
): Promise<LeaderboardStatsRow | null> {
  const oneDayBeforeThisPeriod = new Date(
    period.startAt.getTime() - 24 * 60 * 60 * 1000
  );
  const previousPeriodInfo = currentPeriod(cadence, oneDayBeforeThisPeriod);
  const docId = leaderboardDocumentId(uid, cadence, previousPeriodInfo.key);
  const snapshot = await firestore
    .collection(LEADERBOARD_STATS_COLLECTION)
    .doc(docId)
    .get();
  if (!snapshot.exists) {
    return null;
  }
  const data = snapshot.data() ?? {};
  return {
    totalFloors: numberValue(data.totalFloors),
    totalSteps: numberValue(data.totalSteps),
    totalWorkouts: numberValue(data.totalWorkouts),
  };
}

/**
 * Reads the closed period's global steps achievement, when the climber
 * earned one - the same permanent record `finalizeLeaderboardAchievements`
 * (leaderboardAchievements.ts) writes. Round 3: surface the app's existing
 * tracked achievements rather than inventing a new achievement concept for
 * the recap.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodKey - Closed period key
 * @return {Promise<string | undefined>} Achievement label, when earned
 */
async function fetchAchievementLabel(
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
  if (typeof rank !== "number" || rank < 1) {
    return undefined;
  }
  return `${achievementTierLabel(rank)} globally`;
}

/**
 * Reads every landmark a climber holds the permanent First Ascent of.
 *
 * `live_replay_leaderboards` is the durable record - `firstAscentUserId` is
 * set once, forever, the moment a climb's First Ascent is claimed
 * (liveReplayLeaderboard.ts). Just Climb's global board can carry a
 * `firstAscentUserId` too, so only `live_climb` contexts count as a landmark
 * First Ascent. The equality query is auto-indexed, so this is an index lookup
 * per climber, not a scan, and independent of catalogue size - cheaper than
 * the app's own profile screen, which loops the whole catalogue client-side
 * for one climber's own view of this same fact.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<string[]>} Climb IDs this climber holds the First Ascent
 *   of
 */
async function fetchFirstAscentClimbIds(
  firestore: admin.firestore.Firestore,
  uid: string
): Promise<string[]> {
  const snapshot = await firestore
    .collection(LIVE_REPLAY_LEADERBOARDS_COLLECTION)
    .where("firstAscentUserId", "==", uid)
    .select("contextId", "contextType")
    .get();

  const climbIds: string[] = [];
  for (const document of snapshot.docs) {
    if (document.get("contextType") !== LIVE_CLIMB_CONTEXT_TYPE) {
      continue;
    }
    const climbId = stringValue(document.get("contextId"));
    if (climbId) {
      climbIds.push(climbId);
    }
  }
  return climbIds;
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
 * @param {RecapStanding} standing - This period's rank and field size
 * @param {Map<string, string>} climbNameById - Catalogue name lookup
 * @param {RecapSweepSummary} summary - Sweep counters to update
 * @return {Promise<void>} Resolves once queued, suppressed, or skipped
 */
async function composeAndEnqueueActiveRecap(
  firestore: admin.firestore.Firestore,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod,
  uid: string,
  aggregate: LeaderboardStatsRow,
  standing: RecapStanding,
  climbNameById: Map<string, string>,
  summary: RecapSweepSummary
): Promise<void> {
  const email = await fetchUserEmail(firestore, uid);
  if (!email) {
    summary.skippedNoEmail += 1;
    return;
  }

  const [workoutDetails, previousTotals, achievementLabel] = await Promise.all([
    fetchPeriodWorkoutDetails(firestore, uid, period),
    fetchPreviousPeriodTotals(firestore, uid, cadence, period),
    fetchAchievementLabel(firestore, uid, cadence, period.key),
  ]);
  const landmarksFinished = dedupeLandmarkNames(
    workoutDetails.completedClimbIds,
    climbNameById
  );

  let currentStreakWeeks: number | undefined;
  if (cadence === "weekly") {
    currentStreakWeeks = await computeCurrentStreakWeeks(
      period,
      async (periodKey) => {
        const docId = leaderboardDocumentId(uid, "weekly", periodKey);
        const snapshot = await firestore
          .collection(LEADERBOARD_STATS_COLLECTION)
          .doc(docId)
          .get();
        return snapshot.exists &&
          numberValue(snapshot.get("totalWorkouts")) > 0;
      }
    );
  }

  const deltaLabel = cadence === "weekly" ? "vs last week" : "vs last month";
  const payload: RecapActivePayload = {
    achievementLabel,
    calendar: buildCalendarCells(period, workoutDetails.stepsByDayKey),
    climbsCompleted: aggregate.totalWorkouts,
    climbsDelta: buildDeltaChip(
      aggregate.totalWorkouts,
      previousTotals?.totalWorkouts ?? null,
      deltaLabel
    ),
    ctaUrl: APP_STORE_URL,
    currentStreakWeeks,
    fieldSize: standing.fieldSize,
    floorsDelta: buildDeltaChip(
      aggregate.totalFloors,
      previousTotals?.totalFloors ?? null,
      deltaLabel
    ),
    landmarksFinished,
    percentileBand: percentileBand(standing.rank, standing.fieldSize),
    periodLabel: cadence === "weekly" ?
      formatWeeklyPeriodLabel(period) :
      formatMonthlyPeriodLabel(period),
    rank: standing.rank,
    stepsDelta: buildDeltaChip(
      aggregate.totalSteps,
      previousTotals?.totalSteps ?? null,
      deltaLabel
    ),
    totalFloors: aggregate.totalFloors,
    totalSteps: aggregate.totalSteps,
  };

  const outcome = await enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey: buildRecapDedupeKey(cadence, period.key, uid),
    emailType: cadence === "weekly" ?
      "weekly_recap_active" :
      "monthly_recap_active",
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
 * @param {RecapSweepSummary} summary - Sweep counters to update
 * @return {Promise<void>} Resolves once queued, suppressed, or skipped
 */
async function composeAndEnqueueInactiveRecap(
  firestore: admin.firestore.Firestore,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod,
  now: Date,
  uid: string,
  suggestedClimb: CatalogClimb | null,
  climbNameById: Map<string, string>,
  summary: RecapSweepSummary
): Promise<void> {
  const lastActiveAt = await fetchLatestWorkoutStartedAt(firestore, uid);
  if (lastActiveAt && lastActiveAt >= period.endAt) {
    summary.suppressed += 1;
    return;
  }

  const email = await fetchUserEmail(firestore, uid);
  if (!email) {
    summary.skippedNoEmail += 1;
    return;
  }

  const firstAscentClimbIds = await fetchFirstAscentClimbIds(firestore, uid);
  const firstAscents = dedupeLandmarkNames(
    firstAscentClimbIds.filter((climbId) => climbNameById.has(climbId)),
    climbNameById
  );
  const since = lastActiveAt ?? period.startAt;

  const payload: RecapInactivePayload = {
    ctaUrl: APP_STORE_URL,
    firstAscents,
    gapCount: cadence === "weekly" ?
      weeksSince(since, now) :
      monthsSince(since, now),
    periodLabel: cadence === "weekly" ?
      formatWeeklyPeriodLabel(period) :
      formatMonthlyPeriodLabel(period),
    suggestedClimbName: suggestedClimb?.name,
  };

  const outcome = await enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey: buildRecapDedupeKey(cadence, period.key, uid),
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
 * @param {CohortScanBound} cohortScanBound - Cohort scan page bound,
 *   injectable for tests
 * @return {Promise<RecapSweepSummary>} What the sweep did
 */
export async function runRecapSweep(
  cadence: RecapCadence,
  now: Date,
  cohortScanBound: CohortScanBound = DEFAULT_COHORT_SCAN_BOUND
): Promise<RecapSweepSummary> {
  const firestore = admin.firestore();
  const period = previousPeriod(cadence, now);

  const [activeScan, allTimeScan, catalog] = await Promise.all([
    pageLeaderboardStatsRows(
      firestore,
      firestore
        .collection(LEADERBOARD_STATS_COLLECTION)
        .where("timeFrame", "==", cadence)
        .where(
          "periodStartAt",
          "==",
          admin.firestore.Timestamp.fromDate(period.startAt)
        ),
      "active",
      cohortScanBound
    ),
    pageLeaderboardStatsRows(
      firestore,
      firestore
        .collection(LEADERBOARD_STATS_COLLECTION)
        .where("timeFrame", "==", "all_time"),
      "all_time",
      cohortScanBound
    ),
    loadClimbCatalogSafely(),
  ]);

  const activeRows = activeScan.rows;
  const everActiveRows = new Map(
    [...allTimeScan.rows.entries()].filter(([, row]) => row.totalSteps > 0)
  );
  const standings = rankActiveCohort(activeRows);

  const summary: RecapSweepSummary = {
    activeUserCount: standings.size,
    alreadyQueued: 0,
    errors: 0,
    everActiveUserCount: everActiveRows.size,
    queued: 0,
    skippedNoEmail: 0,
    suppressed: 0,
  };

  if (activeScan.truncated) {
    logger.error("recapEmails.sweepSkipped", {
      cadence,
      periodKey: period.key,
      reason: "active_cohort_scan_truncated",
    });
    return summary;
  }

  const activeFailures = await runWithBoundedConcurrency(
    [...activeRows.entries()].filter(([uid]) => standings.has(uid)),
    RECIPIENT_CONCURRENCY,
    async ([uid, aggregate]) => {
      const standing = standings.get(uid);
      if (!standing) {
        return;
      }
      await composeAndEnqueueActiveRecap(
        firestore,
        cadence,
        period,
        uid,
        aggregate,
        standing,
        catalog.climbNameById,
        summary
      );
    }
  );
  for (const failure of activeFailures) {
    summary.errors += 1;
    logger.error("recapEmails.activeComposeFailed", {
      cadence,
      errorMessage: failure.error instanceof Error ?
        failure.error.message :
        "unknown_error",
      uid: failure.item[0],
    });
  }

  const inactiveEntries = [...everActiveRows.entries()]
    .filter(([uid]) => !activeRows.has(uid));
  const inactiveFailures = await runWithBoundedConcurrency(
    inactiveEntries,
    RECIPIENT_CONCURRENCY,
    async ([uid]) => {
      await composeAndEnqueueInactiveRecap(
        firestore,
        cadence,
        period,
        now,
        uid,
        catalog.suggestedClimb,
        catalog.climbNameById,
        summary
      );
    }
  );
  for (const failure of inactiveFailures) {
    summary.errors += 1;
    logger.error("recapEmails.inactiveComposeFailed", {
      cadence,
      errorMessage: failure.error instanceof Error ?
        failure.error.message :
        "unknown_error",
      uid: failure.item[0],
    });
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
 * Formats a count with thousands separators for chip and stat copy.
 * @param {number} value - Raw count
 * @return {string} Locale-formatted count
 */
function formatCount(value: number): string {
  return Math.max(0, Math.round(value)).toLocaleString("en-US");
}

/**
 * Shifts a UTC date by whole days.
 * @param {Date} date - Starting instant
 * @param {number} days - Days to add
 * @return {Date} Shifted instant
 */
function addDaysUTC(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

/**
 * Formats a UTC instant as a "YYYY-MM-DD" day key.
 * @param {Date} date - The instant
 * @return {string} Day key
 */
function dayKeyUTC(date: Date): string {
  const pad = (value: number): string => String(value).padStart(2, "0");
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-` +
    `${pad(date.getUTCDate())}`;
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
