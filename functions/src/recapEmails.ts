/**
 * Weekly and monthly period recaps: one composition, two channels.
 *
 * COMPOSE (00:30 UTC, `composeWeeklyRecaps` / `composeMonthlyRecaps`) writes
 * `users/{uid}/recaps/{cadence}_{periodKey}` once per climber for the period
 * that just closed (docs/champion-recognition.md owns the document contract).
 * An ACTIVE climber (activity in the closed window) gets the `active`
 * variant: rank, climber count, percentile band, climbs/steps/floors with
 * their prior-period values, award rank, the period's First Ascents,
 * landmarks finished, streak and calendar - raw values the app renders. A
 * ZERO-ACTIVITY climber (no activity in the window, but a real history
 * before it) gets the `inactive` variant: the real gap since they last
 * climbed, the First Ascents they hold, and a suggested comeback climb. An
 * account that has never climbed but holds `entitlements/app_access` gets
 * `never_climbed`, which carries neither map. Compose writes for every such
 * climber whether or not they have an email address, and never overwrites a
 * recap that already exists - a re-run can never reset a `seenAt`.
 *
 * SEND (13:00 UTC, `weeklyRecapEmails` / `monthlyRecapEmails`) reads those
 * stored recaps back and maps each one onto the existing email payloads, so
 * the app and the email can never disagree about a climber's period. The
 * send keeps every rule the emails always had: an email address is
 * required, consent is gated at enqueue, the dedupe key is per climber per
 * period, and a zero-activity climber who has already come back (latest
 * workout at or after the period's end) gets no "we missed you" email. A
 * `never_climbed` recap is app-only - that gap belongs to the
 * onboarding-abandonment lifecycle emails, not this one, so a brand-new
 * signup mid-onboarding is never told "we missed you". If compose never ran
 * for the period, send logs an error and sends nothing rather than composing
 * a second, different answer.
 *
 * Design direction (captain, 2026-09-24, Wispr-Flow-inspired layout,
 * Ascend's own dark/green/landmark brand - see templates.ts for the render
 * layer): bold editorial hero leading with the climber's rank AND percentile
 * shown together, real achievement badge artwork for whatever the climber
 * earned (the app's existing tracked achievements, reused rather than
 * invented), stat cards with green "up only" delta chips, and a per-day
 * activity calendar heatmap. Copy is past-tense throughout ("last week" /
 * "last month") because every send lands well after the period it describes
 * has closed.
 *
 * Round 3 (2026-09-24) promoted rank and percentile to the hero's lead
 * metric (previously a secondary callout below the fold) and added a
 * text-only achievement callout. Round 4 (2026-09-24, captain review of the
 * rendered emails) removed the milestone-unlocked callout entirely ("I
 * don't like the whole milestone unlocked thing. That doesn't make any
 * sense."), renamed every "on the board" phrase to "on the stair stepper",
 * and rewrote the zero-activity email around the real elapsed gap and the
 * climber's First Ascents instead of a generic "the board missed you".
 * Round 5 (2026-09-24, captain review of the round-4 emails: "we should
 * include our achievement badges that we have in the app - if you were top
 * 10, if you were top 100, if you got any first ascents") replaced that
 * text-only callout with the app's real badge artwork
 * (`ProfileAchievementCatalogue`'s Top 10 / Top 100 / First Ascent images,
 * copied email-safe into `web/public/images/badges/`) via `earnedBadges` on
 * both payload types, and added a First Ascent badge to the ACTIVE recap
 * scoped to landmarks first-ascended during that period specifically (the
 * INACTIVE recap's `firstAscents` stays lifetime-scoped, unchanged).
 *
 * REUSE, NOT A SECOND PATH. Every send goes through the same
 * `enqueueLifecycleEmailIfAllowed` transaction the rating-prompt automation
 * uses (email/queue.ts) - same dedupe-by-job-id mechanics, same
 * queue-time consent gate, same send-time re-check in the processor. This
 * file only decides who gets what content; email/catalog.ts, templates.ts,
 * processor.ts, and unsubscribe.ts are untouched apart from registering the
 * four new EmailType entries.
 *
 * COMPOSE WAITS FOR THE FINALIZER. The award rank is read from the
 * achievement record `finalizeLeaderboardAchievements` writes at 00:15 UTC,
 * and a recap is written once, for good - so compose first checks that the
 * closed period's `leaderboard_periods/{cadence}_{periodKey}` record reads
 * `finalized` (the finalizer commits that status last, once every
 * achievement has landed). Until it does, and for up to an hour after the
 * period closed, compose writes nothing and fails the run so Cloud Scheduler
 * retries it ten minutes later; past that hour it composes anyway and logs
 * the missing finalization loudly, because a recap without a badge beats no
 * recap at all.
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
 *   - NEVER-CLIMBED is every `users/{uid}/entitlements/app_access` grant
 *     (a collection-group read on the `accessUntil` index the expiry sweep
 *     already uses) whose holder is in neither set. A grant exists only
 *     while access is live, so this is exactly the paying and comped
 *     accounts. It is skipped outright when the `all_time` scan was
 *     truncated: a climber past that cutoff would otherwise be told, for
 *     good, that they have never climbed.
 *   - RANK AND PERCENTILE come from ranking the already-loaded active cohort
 *     in memory (mirroring leaderboardAchievements.ts's standard competition
 *     ranking, uncapped) rather than a second Firestore read per user - the
 *     whole cohort is already resident for the active/inactive split, so
 *     ranking it is free. The separate rank BADGE (round 3 text, round 5
 *     artwork) is the one per-user read this file still does beyond the
 *     workout query: an O(1) doc get on the same
 *     `global_steps_{cadence}_{periodKey}` record
 *     `finalizeLeaderboardAchievements` already writes, because "achievement"
 *     names the app's one existing tracked concept and must not drift from
 *     it by being re-derived from this file's own ranking math.
 *   - The ACTIVE recap's period-scoped FIRST ASCENT badge (round 5) is a
 *     second per-user read: the same equality-only, index-free
 *     `live_replay_leaderboards` query `fetchFirstAscentRecords` already
 *     used for the inactive email's lifetime list, now also selecting
 *     `firstAscentWorkoutId` and matched in memory against the closed
 *     period's completed-landmark workouts the workout query already read -
 *     never a second Firestore filter, so no new composite index. It runs
 *     only when the closed period holds a completed landmark, since without
 *     one the climber cannot have a First Ascent badge that period.
 * This never sweeps the full `users` collection and never reads a user's
 * full workout history. Each climber costs exactly one workout query,
 * bounded by cohort size: an active climber's is a `startedAt` range query
 * bounded to the single closed period, to resolve landmark completions and
 * the daily activity calendar; a zero-activity climber's is one indexed
 * `orderBy("startedAt", "desc").limit(1)` read of their latest workout
 * before the period closed, for the real gap
 * (`fetchLatestWorkoutStartedAt`). Neither is a scan. The send step adds one
 * more of those latest-workout reads per zero-activity recap, unbounded by
 * the period this time, because "already came back" is a fact about 13:00,
 * not about 00:30. Per-recipient composition, and per-recipient enqueue,
 * run with bounded concurrency (`RECIPIENT_CONCURRENCY`), not sequentially,
 * so a large cohort cannot run the 540s invocation out the clock and
 * silently strand the rest of a period's recipients - a timed-out
 * `onSchedule` run is not resumed where it stopped.
 *
 * DOCUMENTED ASSUMPTIONS:
 *   - Compose time: weekly Monday 00:30 UTC, monthly the 1st at 00:30 UTC,
 *     fifteen minutes after the 00:15 UTC finalizer
 *     (leaderboardAchievements.ts) - see COMPOSE WAITS FOR THE FINALIZER.
 *     Send time: weekly Monday 13:00 UTC, monthly the 1st at 13:00 UTC,
 *     unchanged from when the email composed itself.
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
 *   - The zero-activity gap ("We haven't seen you in N weeks/months") reads
 *     the climber's latest workout `startedAt` before the closed period's
 *     end - one indexed `orderBy("startedAt", "desc").limit(1)` read per
 *     zero-activity climber, never their history - measured against the
 *     compose run's clock and stored as `inactive.gapCount`. The `all_time`
 *     row's `lastUpdated` is not a last-activity time: every reconcile (a
 *     demographics edit, an old workout's edit or delete, a backfill)
 *     restamps it. The send step re-runs compose first, so a climb that
 *     synced after 00:30 but started inside the period recomposes that
 *     climber's stored inactive recap as active (keeping `seenAt`), and the
 *     email and the app read the same corrected document. At send time a
 *     latest workout at or after the closed period's start means the climber
 *     climbed in it or already came back, so no zero-activity email is ever
 *     sent for it; one newer than the stored `lastClimbAt` but before the
 *     period (an older climb that synced late) rewrites the stored gap
 *     before the email is sent. Falls back to the closed period's own start
 *     date on the defensive case where no workout is found.
 *   - First Ascents in the zero-activity email read
 *     `live_replay_leaderboards` where `firstAscentUserId == uid` - the one
 *     durable, permanent record `liveReplayLeaderboard.ts` writes when a
 *     climb's First Ascent is claimed - not a re-derivation. A climber with
 *     any First Ascents gets them named, plus the real First Ascent badge
 *     artwork (round 5); a climber with none gets the existing
 *     suggested-comeback-climb nudge instead, and no badge.
 *   - The active recap's First Ascent badge (round 5) reads the same
 *     `live_replay_leaderboards` record but keeps only a claim whose
 *     `firstAscentWorkoutId` is one of the closed period's own
 *     completed-landmark workouts - the same `startedAt` window every other
 *     period stat uses, not the server's claim time, which a late sync can
 *     push into the next period. So the badge is always a subset of
 *     landmarks finished, and a climber who merely re-climbed a landmark
 *     they first-ascended in an earlier period is never told it was a new
 *     achievement this week/month. A landmark the catalogue cannot name
 *     keeps the badge but drops its detail line rather than print a raw ID.
 *   - Achievement badges reuse the app's real artwork and locked terminology
 *     (`ProfileAchievementCatalogue`, `ascend-leaderboards`): a rank badge is
 *     "Top 10" for any achievement rank <= 10 (the app's own cumulative
 *     counting - a Top 1 or Top 3 finish also counts toward Top 10) and
 *     "Top 100" for 11-100, sourced from the same achievement record the
 *     rank hero already reads elsewhere, never re-derived from this file's
 *     in-memory `rankActiveCohort` standing (a different, uncapped ranking
 *     over a potentially larger cohort than the finalizer's own top-250
 *     read). No Top 1/Top 3/podium-medal badge is shown here - the captain's
 *     ask named exactly Top 10, Top 100, and First Ascent, and the rank hero
 *     already states the exact placement precisely.
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
  claimReceipt,
  makeHostedClimbCatalogSource,
  referenceStepCount,
} from "./climbDropNotifications";
import {runWithBoundedConcurrency} from "./concurrency";
import {keepNewestRow} from "./leaderboardResults";
import {
  enqueueLifecycleEmailIfAllowed,
  type EnqueueLifecycleEmailOutcome,
} from "./email/queue";
import type {
  EmailJobPayload,
  EmailType,
  RecapActivePayload,
  RecapCalendarCell,
  RecapDeltaChip,
  RecapEarnedBadge,
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
const RECAPS_COLLECTION = "recaps";
const ENTITLEMENTS_COLLECTION = "entitlements";
const APP_ACCESS_ENTITLEMENT_ID = "app_access";
const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";
const LEADERBOARD_PERIODS_COLLECTION = "leaderboard_periods";
const ACHIEVEMENTS_COLLECTION = "achievements";
const LIVE_REPLAY_LEADERBOARDS_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const RECAP_SCHEMA_VERSION = 1;

/**
 * Page size and page budget for each cohort scan: the two
 * `leaderboard_stats` scans and the `app_access` grant scan.
 */
const DEFAULT_COHORT_SCAN_BOUND: CohortScanBound = {
  maxPages: 50,
  pageSize: 200,
};
/**
 * Page size and page budget for the send step's read of a period's stored
 * recaps. Every cohort compose writes lands here, so it gets the sum of
 * their budgets.
 */
const DEFAULT_RECAP_SCAN_BOUND: CohortScanBound = {
  maxPages: 150,
  pageSize: 200,
};
/**
 * How long after a period closes compose keeps waiting for the finalizer
 * before it composes without the achievement records.
 */
const FINALIZATION_GRACE_MS = 60 * 60 * 1000;
/** Bounds how far back the streak walk reads before giving up. */
const MAX_WEEKLY_STREAK_LOOKBACK = 26;
/** Recipients composed and enqueued at once, per sweep. */
const RECIPIENT_CONCURRENCY = 10;

export type RecapCadence = "weekly" | "monthly";
export type RecapVariant = "active" | "inactive" | "never_climbed";

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

/** A First Ascent claimed in the recap's period, as stored. */
export interface StoredRecapFirstAscent {
  climbId: string;
  /** Null when the hosted catalogue could not name the climb. */
  name: string | null;
}

/**
 * The `active` map of a stored recap: raw values the app renders, never
 * pre-formatted email chips. docs/champion-recognition.md documents each
 * field.
 */
export interface StoredRecapActive {
  awardRank: number | null;
  calendar: RecapCalendarCell[];
  climberCount: number | null;
  climbs: number;
  currentStreakWeeks: number | null;
  firstAscents: StoredRecapFirstAscent[];
  floors: number;
  landmarksFinished: string[];
  percentileBand: string | null;
  previousClimbs: number | null;
  previousFloors: number | null;
  previousSteps: number | null;
  rank: number;
  steps: number;
}

/** The `inactive` map of a stored recap. */
export interface StoredRecapInactive {
  firstAscentsHeld: string[];
  gapCount: number;
  lastClimbAt: admin.firestore.Timestamp | null;
  suggestedClimbId: string | null;
  suggestedClimbName: string | null;
}

interface StoredRecapBase {
  cadence: RecapCadence;
  periodKey: string;
  periodLabel: string;
}

/** A stored recap as the send step reads it back. */
export type StoredRecap =
  | StoredRecapBase & {
      active: StoredRecapActive;
      inactive: null;
      variant: "active";
    }
  | StoredRecapBase & {
      active: null;
      inactive: StoredRecapInactive;
      variant: "inactive";
    }
  | StoredRecapBase & {
      active: null;
      inactive: null;
      variant: "never_climbed";
    };

/** Who a compose run writes a recap for, one list per variant. */
export interface RecapCohortPlan {
  active: string[];
  inactive: string[];
  neverClimbed: string[];
}

/**
 * How a compose run ended. `awaiting_finalization` wrote nothing and asks
 * for a retry; `skipped_truncated` wrote nothing because the active cohort
 * could not be read whole.
 */
export type RecapComposeOutcome =
  | "composed"
  | "awaiting_finalization"
  | "skipped_truncated";

export interface RecapComposeSummary {
  activeCount: number;
  alreadyComposed: number;
  composed: number;
  /** Stored inactive recaps a late-synced climb in the period made active. */
  recomposed: number;
  entitledUserCount: number;
  errors: number;
  everActiveUserCount: number;
  inactiveCount: number;
  neverClimbedCount: number;
  outcome: RecapComposeOutcome;
  periodKey: string;
}

export interface RecapSendSummary {
  alreadyQueued: number;
  /** Recaps the send's own compose pass had to create. */
  composedAtSend: number;
  errors: number;
  periodKey: string;
  queued: number;
  recapCount: number;
  /** True when compose left nothing to send for the period. */
  recapsMissing: boolean;
  skippedNeverClimbed: number;
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
 * Builds the id of a climber's stored recap for one closed period, under
 * `users/{uid}/recaps/`.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodKey - Closed period key (e.g. "2026-W38")
 * @return {string} Recap document id, e.g. "weekly_2026-W38"
 */
export function buildRecapDocumentId(
  cadence: RecapCadence,
  periodKey: string
): string {
  return `${cadence}_${periodKey}`;
}

/**
 * Builds the real Top 10 / Top 100 badge earned for an achievement rank -
 * the app's own cumulative counting (a Top 1 or Top 3 finish also counts
 * toward Top 10), collapsed to exactly the two badges the captain asked
 * for. No Top 1/Top 3/podium-medal badge exists here; the rank hero already
 * states the exact placement.
 * @param {number} rank - The closed period's achievement rank (from the
 *   `global_steps_{cadence}_{periodKey}` record), always >= 1
 * @return {RecapEarnedBadge} The earned rank badge
 */
export function buildRankBadge(rank: number): RecapEarnedBadge {
  const id = rank <= 10 ? "top10" : "top100";
  return {detail: "globally", id, label: id === "top10" ? "Top 10" : "Top 100"};
}

/**
 * Builds the First Ascent badge for a non-empty list of first-ascended
 * landmark climb IDs, or nothing for an empty one. Shared by the active
 * recap (period-scoped) and the zero-activity recap (lifetime-scoped) so
 * both read the same label and pluralization. The detail names every
 * landmark only when the catalogue resolves all of them; otherwise the
 * badge carries no detail rather than a raw climb ID.
 * @param {string[]} climbIds - First-ascended landmark climb IDs
 * @param {Map<string, string>} climbNameById - Catalogue name lookup
 * @return {RecapEarnedBadge | undefined} The badge, or nothing with none
 */
export function buildFirstAscentBadge(
  climbIds: string[],
  climbNameById: Map<string, string>
): RecapEarnedBadge | undefined {
  const distinctIds = [...new Set(climbIds)];
  if (distinctIds.length === 0) {
    return undefined;
  }
  const allResolved = distinctIds.every((climbId) =>
    climbNameById.has(climbId));
  return firstAscentBadge(
    distinctIds.length,
    allResolved ? dedupeLandmarkNames(distinctIds, climbNameById) : null
  );
}

/**
 * Builds the First Ascent badge for the lifetime-held First Ascents a
 * zero-activity recap stores by name - every one already resolved by the
 * catalogue at compose time, so the badge always names them.
 * @param {string[]} names - Held First Ascent landmark names
 * @return {RecapEarnedBadge | undefined} The badge, or nothing with none
 */
export function buildHeldFirstAscentBadge(
  names: string[]
): RecapEarnedBadge | undefined {
  return names.length === 0 ? undefined : firstAscentBadge(names.length, names);
}

/**
 * The one shape of a First Ascent badge, singular or plural.
 * @param {number} count - Distinct landmarks first-ascended
 * @param {string[] | null} names - Every landmark's name, or null when any
 *   one of them could not be named
 * @return {RecapEarnedBadge} The badge
 */
function firstAscentBadge(
  count: number,
  names: string[] | null
): RecapEarnedBadge {
  return {
    ...(names ? {detail: names.join(", ")} : {}),
    id: "first-ascent",
    label: count === 1 ? "First Ascent" : "First Ascents",
  };
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
 * Formats a closed period's label for its cadence.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @return {string} Display label
 */
export function formatRecapPeriodLabel(
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod
): string {
  return cadence === "weekly" ?
    formatWeeklyPeriodLabel(period) :
    formatMonthlyPeriodLabel(period);
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

/**
 * Decides which recap variant each climber gets for one closed period.
 *
 * `active` is every climber ranked this period (steps above zero).
 * `inactive` is every climber with lifetime steps and no row at all this
 * period. `never_climbed` is every `app_access` holder in neither set. A
 * climber with a zero-step row this period is in none of them: they logged a
 * session, so "we missed you" and "start your first climb" would both be
 * wrong, and there is no rank to show - the same silence the recap email
 * always kept for them. `entitledUserIds` is null when the lifetime cohort
 * could not be read whole, which withholds every `never_climbed` recap
 * rather than risk telling a veteran past the scan cutoff, permanently, that
 * they have never climbed.
 * @param {object} input - The period's cohorts
 * @return {RecapCohortPlan} Climber ids per variant
 */
export function planRecapCohorts(input: {
  activeRows: Map<string, unknown>;
  entitledUserIds: Set<string> | null;
  everActiveUserIds: Set<string>;
  standings: Map<string, RecapStanding>;
}): RecapCohortPlan {
  const active = [...input.standings.keys()];
  const inactive = [...input.everActiveUserIds]
    .filter((uid) => !input.activeRows.has(uid));
  const neverClimbed = input.entitledUserIds === null ?
    [] :
    [...input.entitledUserIds].filter((uid) =>
      !input.everActiveUserIds.has(uid) && !input.activeRows.has(uid));
  return {active, inactive, neverClimbed};
}

/**
 * Whether compose must hold off because the finalizer has not frozen the
 * closed period's achievements yet. Past the grace window it stops waiting:
 * a recap missing its award badge beats no recap at all.
 * @param {boolean} finalized - Whether the period record reads `finalized`
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @param {Date} now - The compose run's clock
 * @param {number} graceMs - How long after the close to keep waiting
 * @return {boolean} True when compose should write nothing and retry
 */
export function shouldAwaitFinalization(
  finalized: boolean,
  period: ClosedLeaderboardPeriod,
  now: Date,
  graceMs: number = FINALIZATION_GRACE_MS
): boolean {
  return !finalized && now.getTime() - period.endAt.getTime() < graceMs;
}

/**
 * Builds the stored `active` map from what compose read for one climber.
 * @param {object} input - The climber's period, standing, and reads
 * @return {StoredRecapActive} Raw values the app renders
 */
export function buildStoredActiveRecap(input: {
  aggregate: LeaderboardStatsRow;
  awardRank: number | null;
  climbNameById: Map<string, string>;
  completedClimbIds: string[];
  currentStreakWeeks: number | null;
  firstAscentClimbIds: string[];
  period: ClosedLeaderboardPeriod;
  previousTotals: LeaderboardStatsRow | null;
  standing: RecapStanding;
  stepsByDayKey: Map<string, number>;
}): StoredRecapActive {
  const {aggregate, previousTotals, standing} = input;
  return {
    awardRank: input.awardRank,
    calendar: buildCalendarCells(input.period, input.stepsByDayKey),
    climberCount: isRankableField(standing.fieldSize) ?
      standing.fieldSize :
      null,
    climbs: aggregate.totalWorkouts,
    currentStreakWeeks: input.currentStreakWeeks,
    firstAscents: [...new Set(input.firstAscentClimbIds)].map((climbId) => ({
      climbId,
      name: input.climbNameById.get(climbId) ?? null,
    })),
    floors: aggregate.totalFloors,
    landmarksFinished: dedupeLandmarkNames(
      input.completedClimbIds,
      input.climbNameById
    ),
    percentileBand: percentileBand(standing.rank, standing.fieldSize) ?? null,
    previousClimbs: previousTotals?.totalWorkouts ?? null,
    previousFloors: previousTotals?.totalFloors ?? null,
    previousSteps: previousTotals?.totalSteps ?? null,
    rank: standing.rank,
    steps: aggregate.totalSteps,
  };
}

/**
 * Builds the stored `inactive` map from what compose read for one climber.
 * A First Ascent the catalogue cannot name is left out rather than shown as
 * a raw id.
 * @param {object} input - The climber's last climb, holdings, and the run
 * @return {StoredRecapInactive} Raw values the app renders
 */
export function buildStoredInactiveRecap(input: {
  cadence: RecapCadence;
  climbNameById: Map<string, string>;
  firstAscentClimbIds: string[];
  lastClimbAt: Date | null;
  now: Date;
  period: ClosedLeaderboardPeriod;
  suggestedClimb: CatalogClimb | null;
}): StoredRecapInactive {
  const heldClimbIds = input.firstAscentClimbIds
    .filter((climbId) => input.climbNameById.has(climbId));
  const since = input.lastClimbAt ?? input.period.startAt;
  return {
    firstAscentsHeld: dedupeLandmarkNames(heldClimbIds, input.climbNameById),
    gapCount: input.cadence === "weekly" ?
      weeksSince(since, input.now) :
      monthsSince(since, input.now),
    lastClimbAt: input.lastClimbAt ?
      admin.firestore.Timestamp.fromDate(input.lastClimbAt) :
      null,
    suggestedClimbId: input.suggestedClimb?.id ?? null,
    suggestedClimbName: input.suggestedClimb?.name ?? null,
  };
}

/**
 * Maps a stored `active` recap onto the active email's payload - the one
 * place the email's chips and badges are derived from the app's raw values.
 * A missing `climberCount` means a field of one: the climber holds a rank,
 * so the field is at least one, and it was stored only above one.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodLabel - The stored period label
 * @param {StoredRecapActive} active - The stored `active` map
 * @return {RecapActivePayload} The email payload
 */
export function buildActiveRecapEmailPayload(
  cadence: RecapCadence,
  periodLabel: string,
  active: StoredRecapActive
): RecapActivePayload {
  const deltaLabel = cadence === "weekly" ? "vs last week" : "vs last month";
  const firstAscentNames = new Map<string, string>();
  for (const firstAscent of active.firstAscents) {
    if (firstAscent.name !== null) {
      firstAscentNames.set(firstAscent.climbId, firstAscent.name);
    }
  }
  const earnedBadges: RecapEarnedBadge[] = [
    active.awardRank !== null ? buildRankBadge(active.awardRank) : undefined,
    buildFirstAscentBadge(
      active.firstAscents.map((firstAscent) => firstAscent.climbId),
      firstAscentNames
    ),
  ].filter((badge): badge is RecapEarnedBadge => badge !== undefined);

  return {
    calendar: active.calendar,
    earnedBadges,
    climbsCompleted: active.climbs,
    climbsDelta: buildDeltaChip(
      active.climbs,
      active.previousClimbs,
      deltaLabel
    ),
    ctaUrl: APP_STORE_URL,
    currentStreakWeeks: active.currentStreakWeeks ?? undefined,
    fieldSize: active.climberCount ?? 1,
    floorsDelta: buildDeltaChip(
      active.floors,
      active.previousFloors,
      deltaLabel
    ),
    landmarksFinished: active.landmarksFinished,
    percentileBand: active.percentileBand ?? undefined,
    periodLabel,
    rank: active.rank,
    stepsDelta: buildDeltaChip(
      active.steps,
      active.previousSteps,
      deltaLabel
    ),
    totalFloors: active.floors,
    totalSteps: active.steps,
  };
}

/**
 * Maps a stored `inactive` recap onto the zero-activity email's payload.
 * @param {string} periodLabel - The stored period label
 * @param {StoredRecapInactive} inactive - The stored `inactive` map
 * @return {RecapInactivePayload} The email payload
 */
export function buildInactiveRecapEmailPayload(
  periodLabel: string,
  inactive: StoredRecapInactive
): RecapInactivePayload {
  return {
    ctaUrl: APP_STORE_URL,
    earnedBadges: [
      buildHeldFirstAscentBadge(inactive.firstAscentsHeld),
    ].filter(
      (badge): badge is RecapEarnedBadge => badge !== undefined
    ),
    firstAscents: inactive.firstAscentsHeld,
    gapCount: inactive.gapCount,
    periodLabel,
    suggestedClimbName: inactive.suggestedClimbName ?? undefined,
  };
}

/**
 * Reads a stored recap document back, refusing a malformed one rather than
 * sending an email built from half of it.
 * @param {Record<string, unknown>} data - The recap document's fields
 * @return {StoredRecap | null} The recap, or null when it is malformed
 */
export function parseStoredRecap(
  data: Record<string, unknown>
): StoredRecap | null {
  const cadence = data.cadence;
  const periodKey = stringValue(data.periodKey);
  const periodLabel = stringValue(data.periodLabel);
  if ((cadence !== "weekly" && cadence !== "monthly") ||
    !periodKey ||
    !periodLabel) {
    return null;
  }
  const base = {cadence, periodKey, periodLabel} as const;

  switch (data.variant) {
  case "active": {
    const active = parseStoredActive(data.active);
    return active && data.inactive === null ?
      {...base, active, inactive: null, variant: "active"} :
      null;
  }
  case "inactive": {
    const inactive = parseStoredInactive(data.inactive);
    return inactive && data.active === null ?
      {...base, active: null, inactive, variant: "inactive"} :
      null;
  }
  case "never_climbed":
    return data.active === null && data.inactive === null ?
      {...base, active: null, inactive: null, variant: "never_climbed"} :
      null;
  default:
    return null;
  }
}

/**
 * Parses a stored `active` map.
 * @param {unknown} value - Candidate map
 * @return {StoredRecapActive | null} The map, or null when malformed
 */
function parseStoredActive(value: unknown): StoredRecapActive | null {
  if (!isPlainRecord(value)) {
    return null;
  }
  const rank = value.rank;
  const counts = [value.climbs, value.steps, value.floors];
  const calendar = parseCalendar(value.calendar);
  const firstAscents = parseFirstAscents(value.firstAscents);
  const landmarksFinished = parseStringArray(value.landmarksFinished);
  const nullableNumbers = [
    value.awardRank,
    value.climberCount,
    value.currentStreakWeeks,
    value.previousClimbs,
    value.previousFloors,
    value.previousSteps,
  ];
  if (typeof rank !== "number" || rank < 1 ||
    !counts.every(isFiniteNumber) ||
    !nullableNumbers.every((entry) =>
      entry === null || isFiniteNumber(entry)) ||
    (value.percentileBand !== null &&
      typeof value.percentileBand !== "string") ||
    !calendar || !firstAscents || !landmarksFinished) {
    return null;
  }
  return {
    awardRank: value.awardRank as number | null,
    calendar,
    climberCount: value.climberCount as number | null,
    climbs: value.climbs as number,
    currentStreakWeeks: value.currentStreakWeeks as number | null,
    firstAscents,
    floors: value.floors as number,
    landmarksFinished,
    percentileBand: value.percentileBand as string | null,
    previousClimbs: value.previousClimbs as number | null,
    previousFloors: value.previousFloors as number | null,
    previousSteps: value.previousSteps as number | null,
    rank,
    steps: value.steps as number,
  };
}

/**
 * Parses a stored `inactive` map.
 * @param {unknown} value - Candidate map
 * @return {StoredRecapInactive | null} The map, or null when malformed
 */
function parseStoredInactive(value: unknown): StoredRecapInactive | null {
  if (!isPlainRecord(value)) {
    return null;
  }
  const firstAscentsHeld = parseStringArray(value.firstAscentsHeld);
  const lastClimbAt = value.lastClimbAt;
  const optionalStrings = [value.suggestedClimbId, value.suggestedClimbName];
  if (!firstAscentsHeld ||
    !isFiniteNumber(value.gapCount) ||
    (lastClimbAt !== null &&
      !(lastClimbAt instanceof admin.firestore.Timestamp)) ||
    !optionalStrings.every((entry) =>
      entry === null || typeof entry === "string")) {
    return null;
  }
  return {
    firstAscentsHeld,
    gapCount: value.gapCount as number,
    lastClimbAt: lastClimbAt as admin.firestore.Timestamp | null,
    suggestedClimbId: value.suggestedClimbId as string | null,
    suggestedClimbName: value.suggestedClimbName as string | null,
  };
}

/**
 * Parses stored calendar cells.
 * @param {unknown} value - Candidate array
 * @return {RecapCalendarCell[] | null} The cells, or null when malformed
 */
function parseCalendar(value: unknown): RecapCalendarCell[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const levels = new Set(["blank", "none", "active", "peak"]);
  const cells: RecapCalendarCell[] = [];
  for (const cell of value) {
    if (!isPlainRecord(cell) ||
      !(cell.dayOfMonth === null || isFiniteNumber(cell.dayOfMonth)) ||
      typeof cell.level !== "string" ||
      !levels.has(cell.level)) {
      return null;
    }
    cells.push({
      dayOfMonth: cell.dayOfMonth as number | null,
      level: cell.level as RecapCalendarCell["level"],
    });
  }
  return cells;
}

/**
 * Parses stored period First Ascents.
 * @param {unknown} value - Candidate array
 * @return {StoredRecapFirstAscent[] | null} The entries, or null when
 *   malformed
 */
function parseFirstAscents(value: unknown): StoredRecapFirstAscent[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const firstAscents: StoredRecapFirstAscent[] = [];
  for (const entry of value) {
    if (!isPlainRecord(entry) ||
      typeof entry.climbId !== "string" ||
      !(entry.name === null || typeof entry.name === "string")) {
      return null;
    }
    firstAscents.push({climbId: entry.climbId, name: entry.name});
  }
  return firstAscents;
}

/**
 * Parses a stored array of strings.
 * @param {unknown} value - Candidate array
 * @return {string[] | null} The strings, or null when malformed
 */
function parseStringArray(value: unknown): string[] | null {
  return Array.isArray(value) &&
    value.every((entry) => typeof entry === "string") ?
    value as string[] :
    null;
}

/**
 * Whether a value is a plain field map.
 * @param {unknown} value - Candidate value
 * @return {boolean} True for a non-array object
 */
function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Whether a value is a finite number.
 * @param {unknown} value - Candidate value
 * @return {boolean} True for a finite number
 */
function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
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
  const rows = new Map<
    string,
    LeaderboardStatsRow & {userId: string; lastUpdated: Date}
  >();
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
      keepNewestRow(rows, {
        userId,
        lastUpdated: data.lastUpdated instanceof admin.firestore.Timestamp ?
          data.lastUpdated.toDate() :
          new Date(0),
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
 * @return {Promise<{completedClimbIds: string[], completedWorkoutIds:
 *   Set<string>, stepsByDayKey: Map<string, number>}>} Finished-landmark
 *   climb IDs, the workouts that finished them, and per-UTC-day step totals
 */
async function fetchPeriodWorkoutDetails(
  firestore: admin.firestore.Firestore,
  uid: string,
  period: ClosedLeaderboardPeriod
): Promise<{
  completedClimbIds: string[];
  completedWorkoutIds: Set<string>;
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
  const completedWorkoutIds = new Set<string>();
  const stepsByDayKey = new Map<string, number>();

  for (const document of snapshot.docs) {
    const data = document.data();
    const completion: CompletedLandmarkWorkout | null =
      parseCompletedLandmarkWorkout(document.id, data);
    if (completion) {
      completedClimbIds.push(completion.climbId);
      completedWorkoutIds.add(completion.workoutId);
    }

    const startedAt = data.startedAt;
    const steps = numberValue(data.steps);
    if (startedAt instanceof admin.firestore.Timestamp && steps > 0) {
      const key = dayKeyUTC(startedAt.toDate());
      stepsByDayKey.set(key, (stepsByDayKey.get(key) ?? 0) + steps);
    }
  }

  return {completedClimbIds, completedWorkoutIds, stepsByDayKey};
}

/**
 * Reads when the climber's latest workout started, or null with none.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {Date} [before] - Only consider workouts that started before this
 *   instant
 * @return {Promise<Date | null>} Latest workout's start time
 */
async function fetchLatestWorkoutStartedAt(
  firestore: admin.firestore.Firestore,
  uid: string,
  before?: Date
): Promise<Date | null> {
  let query: admin.firestore.Query = firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(WORKOUTS_COLLECTION);
  if (before) {
    query = query.where(
      "startedAt",
      "<",
      admin.firestore.Timestamp.fromDate(before)
    );
  }
  const snapshot = await query
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
 * Reads the closed period's global steps achievement rank, when the climber
 * earned one - the same permanent record `finalizeLeaderboardAchievements`
 * (leaderboardAchievements.ts) writes. Round 3: surface the app's existing
 * tracked achievements rather than inventing a new achievement concept for
 * the recap; round 5: return the rank rather than a formatted label, so the
 * caller can build the real Top 10 / Top 100 badge artwork from it.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {string} periodKey - Closed period key
 * @return {Promise<number | undefined>} Achievement rank, when earned
 */
async function fetchAchievementRank(
  firestore: admin.firestore.Firestore,
  uid: string,
  cadence: RecapCadence,
  periodKey: string
): Promise<number | undefined> {
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
  return typeof rank === "number" && rank >= 1 ? rank : undefined;
}

interface FirstAscentRecord {
  climbId: string;
  workoutId: string | null;
}

/**
 * Reads every landmark a climber holds the permanent First Ascent of, with
 * the workout that claimed each.
 *
 * `live_replay_leaderboards` is the durable record - `firstAscentUserId` is
 * set once, forever, the moment a climb's First Ascent is claimed
 * (liveReplayLeaderboard.ts). Just Climb's global board can carry a
 * `firstAscentUserId` too, so only `live_climb` contexts count as a landmark
 * First Ascent. The equality query is auto-indexed, so this is an index lookup
 * per climber, not a scan, and independent of catalogue size - cheaper than
 * the app's own profile screen, which loops the whole catalogue client-side
 * for one climber's own view of this same fact. `firstAscentWorkoutId` is
 * selected alongside the existing fields so a caller can match a claim to the
 * closed period's own workouts in memory, without a second Firestore query or
 * a new composite index. It is the claiming workout, not
 * `firstAscentCompletedAt`: that is the server's processing time, which a
 * late sync pushes past the period the climb actually happened in.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {string} uid - Firebase Auth user ID
 * @return {Promise<FirstAscentRecord[]>} Climb IDs this climber holds the
 *   First Ascent of, with the workout that claimed each
 */
async function fetchFirstAscentRecords(
  firestore: admin.firestore.Firestore,
  uid: string
): Promise<FirstAscentRecord[]> {
  const snapshot = await firestore
    .collection(LIVE_REPLAY_LEADERBOARDS_COLLECTION)
    .where("firstAscentUserId", "==", uid)
    .select("contextId", "contextType", "firstAscentWorkoutId")
    .get();

  const records: FirstAscentRecord[] = [];
  for (const document of snapshot.docs) {
    if (document.get("contextType") !== LIVE_CLIMB_CONTEXT_TYPE) {
      continue;
    }
    const climbId = stringValue(document.get("contextId"));
    if (!climbId) {
      continue;
    }
    records.push({
      climbId,
      workoutId: stringValue(document.get("firstAscentWorkoutId")),
    });
  }
  return records;
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
 * Pages every live `users/{uid}/entitlements/app_access` grant into the set
 * of their holders.
 *
 * A grant exists only while access is live (revenueCat/firestoreStore.ts
 * deletes it when access ends, and the expiry sweep deletes it the moment
 * `accessUntil` passes), so holding one is holding paid or comped access.
 * The query rides the `accessUntil` collection-group index the expiry sweep
 * already uses; the `entitlements` group is shared with any other
 * subcollection of that name, so only an `app_access` grant under a user
 * counts.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {Date} now - The compose run's clock
 * @param {CohortScanBound} bound - Page size and page budget
 * @return {Promise<{truncated: boolean, userIds: Set<string>}>} Holders, and
 *   whether the page bound cut the scan short
 */
async function pageEntitledUserIds(
  firestore: admin.firestore.Firestore,
  now: Date,
  bound: CohortScanBound
): Promise<{truncated: boolean; userIds: Set<string>}> {
  const userIds = new Set<string>();
  const baseQuery = firestore.collectionGroup(ENTITLEMENTS_COLLECTION)
    .where("accessUntil", ">", admin.firestore.Timestamp.fromDate(now))
    .orderBy("accessUntil");
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  for (let page = 0; page < bound.maxPages; page++) {
    const query = cursor ?
      baseQuery.startAfter(cursor).limit(bound.pageSize) :
      baseQuery.limit(bound.pageSize);
    const snapshot = await query.get();
    if (snapshot.empty) {
      return {truncated: false, userIds};
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];

    for (const document of snapshot.docs) {
      const segments = document.ref.path.split("/");
      if (segments.length === 4 &&
        segments[0] === USERS_COLLECTION &&
        segments[2] === ENTITLEMENTS_COLLECTION &&
        segments[3] === APP_ACCESS_ENTITLEMENT_ID) {
        userIds.add(segments[1]);
      }
    }

    if (snapshot.size < bound.pageSize) {
      return {truncated: false, userIds};
    }
  }

  logger.error("recapEmails.cohortScanTruncated", {
    label: "app_access",
    pagesRead: bound.maxPages,
    rowsRead: userIds.size,
  });
  return {truncated: true, userIds};
}

/**
 * Reads whether the finalizer has frozen the closed period yet - the
 * `leaderboard_periods` record it marks `finalized` in its last commit, once
 * every one of the period's achievements has landed.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @return {Promise<boolean>} True once the period is finalized
 */
async function isPeriodFinalized(
  firestore: admin.firestore.Firestore,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod
): Promise<boolean> {
  const snapshot = await firestore
    .collection(LEADERBOARD_PERIODS_COLLECTION)
    .doc(`${cadence}_${period.key}`)
    .get();
  return snapshot.get("status") === "finalized";
}

/**
 * Reads everything one active climber's recap needs and builds its stored
 * `active` map.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @param {string} uid - Firebase Auth user ID
 * @param {LeaderboardStatsRow} aggregate - This period's totals
 * @param {RecapStanding} standing - This period's rank and field size
 * @param {Map<string, string>} climbNameById - Catalogue name lookup
 * @return {Promise<StoredRecapActive>} The stored `active` map
 */
async function composeActiveRecap(
  firestore: admin.firestore.Firestore,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod,
  uid: string,
  aggregate: LeaderboardStatsRow,
  standing: RecapStanding,
  climbNameById: Map<string, string>
): Promise<StoredRecapActive> {
  const [workoutDetails, previousTotals, achievementRank] = await Promise.all([
    fetchPeriodWorkoutDetails(firestore, uid, period),
    fetchPreviousPeriodTotals(firestore, uid, cadence, period),
    fetchAchievementRank(firestore, uid, cadence, period.key),
  ]);
  const firstAscentRecords = workoutDetails.completedWorkoutIds.size > 0 ?
    await fetchFirstAscentRecords(firestore, uid) :
    [];
  const firstAscentClimbIds = firstAscentRecords
    .filter((record) => record.workoutId !== null &&
      workoutDetails.completedWorkoutIds.has(record.workoutId))
    .map((record) => record.climbId);

  const currentStreakWeeks = cadence === "weekly" ?
    await computeCurrentStreakWeeks(
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
    ) :
    null;

  return buildStoredActiveRecap({
    aggregate,
    awardRank: achievementRank ?? null,
    climbNameById,
    completedClimbIds: workoutDetails.completedClimbIds,
    currentStreakWeeks,
    firstAscentClimbIds,
    period,
    previousTotals,
    standing,
    stepsByDayKey: workoutDetails.stepsByDayKey,
  });
}

/**
 * Reads everything one zero-activity climber's recap needs and builds its
 * stored `inactive` map. The last climb is the latest one before the period
 * closed: a climber who came back in the half hour before compose ran still
 * had an empty period, and the send step is what keeps them from being told
 * they were missed.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @param {Date} now - The compose run's clock
 * @param {string} uid - Firebase Auth user ID
 * @param {CatalogClimb | null} suggestedClimb - This run's comeback pick
 * @param {Map<string, string>} climbNameById - Catalogue name lookup
 * @return {Promise<StoredRecapInactive>} The stored `inactive` map
 */
async function composeInactiveRecap(
  firestore: admin.firestore.Firestore,
  cadence: RecapCadence,
  period: ClosedLeaderboardPeriod,
  now: Date,
  uid: string,
  suggestedClimb: CatalogClimb | null,
  climbNameById: Map<string, string>
): Promise<StoredRecapInactive> {
  const [lastClimbAt, firstAscentRecords] = await Promise.all([
    fetchLatestWorkoutStartedAt(firestore, uid, period.endAt),
    fetchFirstAscentRecords(firestore, uid),
  ]);
  return buildStoredInactiveRecap({
    cadence,
    climbNameById,
    firstAscentClimbIds: firstAscentRecords.map((record) => record.climbId),
    lastClimbAt,
    now,
    period,
    suggestedClimb,
  });
}

/**
 * Writes one climber's recap unless it already exists.
 *
 * The existence read comes first so a re-run - a Cloud Scheduler retry, an
 * operator re-running a period, or the send step's own pass - skips the
 * composition reads for every climber already done. The write is still a
 * `create`, so a recap that appeared between the read and the write is never
 * overwritten and its `seenAt` never reset. `claimReceipt` is the same
 * bounded create-once primitive the climb-drop sweep claims its devices with.
 *
 * The one exception: a stored inactive recap for a climber who now stands in
 * the period's active cohort - a climb inside the period that synced after
 * compose ran - is recomposed as active, updating only the payload so
 * `seenAt` is kept. Nobody is told they were missed for a week they climbed.
 * @param {admin.firestore.DocumentReference} reference - The recap document
 * @param {object} identity - The document's cadence, period, and variant
 * @param {Function} composeMaps - Reads and builds the variant's maps
 * @return {Promise<"composed" | "already_composed">} What happened
 */
async function writeRecapOnce(
  reference: admin.firestore.DocumentReference,
  identity: {
    cadence: RecapCadence;
    period: ClosedLeaderboardPeriod;
    variant: RecapVariant;
  },
  composeMaps: () => Promise<{
    active: StoredRecapActive | null;
    inactive: StoredRecapInactive | null;
  }>
): Promise<"composed" | "already_composed" | "recomposed"> {
  const existing = await reference.get();
  if (existing.exists) {
    if (identity.variant !== "active" || existing.get("variant") !== "inactive") {
      return "already_composed";
    }
    const {active, inactive} = await composeMaps();
    await reference.update({
      active,
      composedAt: admin.firestore.FieldValue.serverTimestamp(),
      inactive,
      variant: identity.variant,
    });
    return "recomposed";
  }
  const {active, inactive} = await composeMaps();
  const {cadence, period, variant} = identity;
  const claim = await claimReceipt(() => reference.create({
    active,
    cadence,
    composedAt: admin.firestore.FieldValue.serverTimestamp(),
    inactive,
    periodEndAt: admin.firestore.Timestamp.fromDate(period.endAt),
    periodKey: period.key,
    periodLabel: formatRecapPeriodLabel(cadence, period),
    periodStartAt: admin.firestore.Timestamp.fromDate(period.startAt),
    schemaVersion: RECAP_SCHEMA_VERSION,
    seenAt: null,
    variant,
  }));
  return claim === "claimed" ? "composed" : "already_composed";
}

/**
 * Composes and stores every climber's recap for the period that just
 * closed. Idempotent: an existing recap is never rewritten.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {Date} now - The compose run's clock, injectable for tests
 * @param {CohortScanBound} cohortScanBound - Cohort scan page bound,
 *   injectable for tests
 * @return {Promise<RecapComposeSummary>} What the run did
 */
export async function runRecapCompose(
  cadence: RecapCadence,
  now: Date,
  cohortScanBound: CohortScanBound = DEFAULT_COHORT_SCAN_BOUND
): Promise<RecapComposeSummary> {
  const firestore = admin.firestore();
  const period = previousPeriod(cadence, now);
  const summary: RecapComposeSummary = {
    activeCount: 0,
    alreadyComposed: 0,
    composed: 0,
    entitledUserCount: 0,
    recomposed: 0,
    errors: 0,
    everActiveUserCount: 0,
    inactiveCount: 0,
    neverClimbedCount: 0,
    outcome: "composed",
    periodKey: period.key,
  };

  const finalized = await isPeriodFinalized(firestore, cadence, period);
  if (shouldAwaitFinalization(finalized, period, now)) {
    summary.outcome = "awaiting_finalization";
    return summary;
  }
  if (!finalized) {
    logger.error("recapEmails.composedBeforeFinalization", {
      cadence,
      periodKey: period.key,
    });
  }

  const [activeScan, allTimeScan, entitledScan, catalog] = await Promise.all([
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
    pageEntitledUserIds(firestore, now, cohortScanBound),
    loadClimbCatalogSafely(),
  ]);

  if (activeScan.truncated) {
    logger.error("recapEmails.sweepSkipped", {
      cadence,
      periodKey: period.key,
      reason: "active_cohort_scan_truncated",
    });
    summary.outcome = "skipped_truncated";
    return summary;
  }
  if (allTimeScan.truncated) {
    logger.error("recapEmails.neverClimbedSkipped", {
      cadence,
      periodKey: period.key,
      reason: "all_time_scan_truncated",
    });
  }

  const activeRows = activeScan.rows;
  const everActiveUserIds = new Set(
    [...allTimeScan.rows.entries()]
      .filter(([, row]) => row.totalSteps > 0)
      .map(([uid]) => uid)
  );
  const standings = rankActiveCohort(activeRows);
  const plan = planRecapCohorts({
    activeRows,
    entitledUserIds: allTimeScan.truncated ? null : entitledScan.userIds,
    everActiveUserIds,
    standings,
  });
  summary.activeCount = plan.active.length;
  summary.entitledUserCount = entitledScan.userIds.size;
  summary.everActiveUserCount = everActiveUserIds.size;
  summary.inactiveCount = plan.inactive.length;
  summary.neverClimbedCount = plan.neverClimbed.length;

  const recapRef = (uid: string) => firestore
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(RECAPS_COLLECTION)
    .doc(buildRecapDocumentId(cadence, period.key));
  const record = (
    outcome: "composed" | "already_composed" | "recomposed"
  ) => {
    if (outcome === "composed") {
      summary.composed += 1;
    } else if (outcome === "recomposed") {
      summary.recomposed += 1;
    } else {
      summary.alreadyComposed += 1;
    }
  };
  const reportFailures = (
    variant: RecapVariant,
    failures: Array<{error: unknown; item: string}>
  ) => {
    for (const failure of failures) {
      summary.errors += 1;
      logger.error("recapEmails.composeFailed", {
        cadence,
        errorMessage: failure.error instanceof Error ?
          failure.error.message :
          "unknown_error",
        uid: failure.item,
        variant,
      });
    }
  };

  reportFailures("active", await runWithBoundedConcurrency(
    plan.active,
    RECIPIENT_CONCURRENCY,
    async (uid) => {
      const aggregate = activeRows.get(uid);
      const standing = standings.get(uid);
      if (!aggregate || !standing) {
        return;
      }
      record(await writeRecapOnce(
        recapRef(uid),
        {cadence, period, variant: "active"},
        async () => ({
          active: await composeActiveRecap(
            firestore,
            cadence,
            period,
            uid,
            aggregate,
            standing,
            catalog.climbNameById
          ),
          inactive: null,
        })
      ));
    }
  ));

  reportFailures("inactive", await runWithBoundedConcurrency(
    plan.inactive,
    RECIPIENT_CONCURRENCY,
    async (uid) => {
      record(await writeRecapOnce(
        recapRef(uid),
        {cadence, period, variant: "inactive"},
        async () => ({
          active: null,
          inactive: await composeInactiveRecap(
            firestore,
            cadence,
            period,
            now,
            uid,
            catalog.suggestedClimb,
            catalog.climbNameById
          ),
        })
      ));
    }
  ));

  reportFailures("never_climbed", await runWithBoundedConcurrency(
    plan.neverClimbed,
    RECIPIENT_CONCURRENCY,
    async (uid) => {
      record(await writeRecapOnce(
        recapRef(uid),
        {cadence, period, variant: "never_climbed"},
        async () => ({active: null, inactive: null})
      ));
    }
  ));

  return summary;
}

/**
 * Builds and enqueues one stored recap's email.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @param {ClosedLeaderboardPeriod} period - The closed window
 * @param {admin.firestore.DocumentReference} reference - The recap document
 * @param {StoredRecap} recap - The parsed recap
 * @param {RecapSendSummary} summary - Sweep counters to update
 * @param {Date} now - The sweep's clock
 * @return {Promise<void>} Resolves once queued, suppressed, or skipped
 */
async function sendStoredRecap(
  firestore: admin.firestore.Firestore,
  period: ClosedLeaderboardPeriod,
  reference: admin.firestore.DocumentReference,
  recap: StoredRecap,
  summary: RecapSendSummary,
  now: Date
): Promise<void> {
  if (recap.variant === "never_climbed") {
    summary.skippedNeverClimbed += 1;
    return;
  }
  const uid = reference.parent.parent?.id;
  if (!uid) {
    return;
  }

  let inactive = recap.variant === "inactive" ? recap.inactive : null;
  if (inactive) {
    const lastActiveAt = await fetchLatestWorkoutStartedAt(firestore, uid);
    if (lastActiveAt && lastActiveAt >= period.startAt) {
      summary.suppressed += 1;
      return;
    }
    const storedLastClimbAt = inactive.lastClimbAt?.toDate() ?? null;
    if (
      lastActiveAt &&
      (!storedLastClimbAt || lastActiveAt > storedLastClimbAt)
    ) {
      inactive = {
        ...inactive,
        gapCount: recap.cadence === "weekly" ?
          weeksSince(lastActiveAt, now) :
          monthsSince(lastActiveAt, now),
        lastClimbAt: admin.firestore.Timestamp.fromDate(lastActiveAt),
      };
      await reference.update({inactive});
    }
  }

  const email = await fetchUserEmail(firestore, uid);
  if (!email) {
    summary.skippedNoEmail += 1;
    return;
  }

  const weekly = recap.cadence === "weekly";
  const content: {emailType: EmailType; payload: EmailJobPayload} =
    recap.variant === "active" ?
      {
        emailType: weekly ? "weekly_recap_active" : "monthly_recap_active",
        payload: buildActiveRecapEmailPayload(
          recap.cadence,
          recap.periodLabel,
          recap.active
        ),
      } :
      {
        emailType: weekly ? "weekly_recap_inactive" : "monthly_recap_inactive",
        payload: buildInactiveRecapEmailPayload(
          recap.periodLabel,
          inactive ?? recap.inactive
        ),
      };
  const outcome = await enqueueLifecycleEmailIfAllowed(firestore, {
    dedupeKey: buildRecapDedupeKey(recap.cadence, recap.periodKey, uid),
    emailType: content.emailType,
    payload: content.payload,
    recipientEmail: email,
    sourceRef: reference.path,
    uid,
  });
  recordOutcome(summary, outcome);
}

/**
 * Applies one enqueue outcome to the sweep summary.
 * @param {RecapSendSummary} summary - Sweep counters to update
 * @param {EnqueueLifecycleEmailOutcome} outcome - What the enqueue did
 * @return {void}
 */
function recordOutcome(
  summary: RecapSendSummary,
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
 * Sends the recap email for every recap stored for the period that just
 * closed, always from the stored document so the app and the email agree.
 *
 * It first runs compose itself - create-only, so a stored recap and its
 * `seenAt` are never replaced - which makes the send self-sufficient when
 * the 00:30 compose never ran (a first deploy after it), and recomposes an
 * inactive recap a late-synced climb in the period made active.
 * @param {RecapCadence} cadence - Weekly or monthly
 * @param {Date} now - The sweep's clock, injectable for tests
 * @param {CohortScanBound} recapScanBound - Stored-recap scan page bound,
 *   injectable for tests
 * @param {CohortScanBound} cohortScanBound - The compose pass's cohort scan
 *   page bound, injectable for tests
 * @return {Promise<RecapSendSummary>} What the sweep did
 */
export async function runRecapSend(
  cadence: RecapCadence,
  now: Date,
  recapScanBound: CohortScanBound = DEFAULT_RECAP_SCAN_BOUND,
  cohortScanBound: CohortScanBound = DEFAULT_COHORT_SCAN_BOUND
): Promise<RecapSendSummary> {
  const firestore = admin.firestore();
  const period = previousPeriod(cadence, now);
  const recapId = buildRecapDocumentId(cadence, period.key);
  const compose = await runRecapCompose(cadence, now, cohortScanBound);
  if (compose.errors > 0 || compose.outcome !== "composed") {
    logger.error("recapEmails.composeAtSendDegraded", compose);
  }
  const summary: RecapSendSummary = {
    alreadyQueued: 0,
    composedAtSend: compose.composed,
    errors: 0,
    periodKey: period.key,
    queued: 0,
    recapCount: 0,
    recapsMissing: false,
    skippedNeverClimbed: 0,
    skippedNoEmail: 0,
    suppressed: 0,
  };

  // The composite index on `cadence` + `periodKey` ends in the implicit
  // document-name order, so this pages without a second index.
  const baseQuery = firestore.collectionGroup(RECAPS_COLLECTION)
    .where("cadence", "==", cadence)
    .where("periodKey", "==", period.key)
    .orderBy(admin.firestore.FieldPath.documentId());
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
  let exhausted = false;

  for (let page = 0; page < recapScanBound.maxPages; page++) {
    const query = cursor ?
      baseQuery.startAfter(cursor).limit(recapScanBound.pageSize) :
      baseQuery.limit(recapScanBound.pageSize);
    const snapshot = await query.get();
    if (snapshot.empty) {
      exhausted = true;
      break;
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];

    const recaps = snapshot.docs.filter((document) => {
      const segments = document.ref.path.split("/");
      return segments.length === 4 &&
        segments[0] === USERS_COLLECTION &&
        segments[3] === recapId;
    });
    summary.recapCount += recaps.length;

    const failures = await runWithBoundedConcurrency(
      recaps,
      RECIPIENT_CONCURRENCY,
      async (document) => {
        const recap = parseStoredRecap(document.data());
        if (!recap) {
          throw new Error("malformed_recap");
        }
        await sendStoredRecap(
          firestore,
          period,
          document.ref,
          recap,
          summary,
          now
        );
      }
    );
    for (const failure of failures) {
      summary.errors += 1;
      logger.error("recapEmails.sendFailed", {
        cadence,
        errorMessage: failure.error instanceof Error ?
          failure.error.message :
          "unknown_error",
        path: failure.item.ref.path,
      });
    }

    if (snapshot.size < recapScanBound.pageSize) {
      exhausted = true;
      break;
    }
  }

  if (!exhausted) {
    logger.error("recapEmails.recapScanTruncated", {
      cadence,
      pagesRead: recapScanBound.maxPages,
      periodKey: period.key,
      recapsRead: summary.recapCount,
    });
  }
  if (summary.recapCount === 0) {
    summary.recapsMissing = true;
    logger.error("recapEmails.recapsMissing", {
      cadence,
      periodKey: period.key,
      reason: "compose_did_not_run",
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
 * Runs one scheduled compose and reports it.
 *
 * Throwing is what asks Cloud Scheduler for a retry (`RECAP_COMPOSE_RETRY`):
 * a run still waiting on the finalizer throws before writing anything, and a
 * run that failed some climbers throws after writing everyone else, so the
 * retry - which skips every recap already stored - picks up exactly the
 * ones that failed.
 * @param {string} name - The scheduled function's name, for the log line
 * @param {RecapCadence} cadence - Weekly or monthly
 * @return {Promise<void>} Resolves when the run needs no retry
 */
async function runScheduledRecapCompose(
  name: string,
  cadence: RecapCadence
): Promise<void> {
  const summary = await runRecapCompose(cadence, new Date());
  if (summary.outcome === "awaiting_finalization") {
    logger.log(`${name} waiting for the leaderboard finalizer`, summary);
    throw new Error(
      `${name}: ${cadence} ${summary.periodKey} is not finalized yet`
    );
  }
  const degraded = summary.errors > 0 || summary.outcome !== "composed";
  const write = degraded ? logger.error : logger.log;
  write(`${name} completed`, summary);
  if (summary.errors > 0) {
    throw new Error(`${name}: ${summary.errors} recaps failed to compose`);
  }
}

/**
 * Cloud Scheduler's retry for a compose run: every ten minutes, five times.
 * Enough to outlast the finalizer grace window with room to spare for a
 * transient failure, bounded so a persistent one stops.
 */
const RECAP_COMPOSE_RETRY = {
  maxBackoffSeconds: 600,
  maxDoublings: 0,
  minBackoffSeconds: 600,
  retryCount: 5,
};

/**
 * Stores every climber's weekly recap. Monday 00:30 UTC, fifteen minutes
 * after the 00:15 UTC finalizer froze the week that just closed.
 */
export const composeWeeklyRecaps = onSchedule(
  {
    ...RECAP_COMPOSE_RETRY,
    memory: "512MiB",
    schedule: "30 0 * * 1",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    await runScheduledRecapCompose("composeWeeklyRecaps", "weekly");
  }
);

/**
 * Stores every climber's monthly recap. The 1st of the month, 00:30 UTC.
 */
export const composeMonthlyRecaps = onSchedule(
  {
    ...RECAP_COMPOSE_RETRY,
    memory: "512MiB",
    schedule: "30 0 1 * *",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    await runScheduledRecapCompose("composeMonthlyRecaps", "monthly");
  }
);

/**
 * Runs one scheduled send and reports it.
 * @param {string} name - The scheduled function's name, for the log line
 * @param {RecapCadence} cadence - Weekly or monthly
 * @return {Promise<void>} Resolves when the sweep is done
 */
async function runScheduledRecapSend(
  name: string,
  cadence: RecapCadence
): Promise<void> {
  const summary = await runRecapSend(cadence, new Date());
  const degraded = summary.errors > 0 || summary.recapsMissing;
  const write = degraded ? logger.error : logger.log;
  write(`${name} sweep completed`, summary);
}

/**
 * Emails every eligible climber the weekly recap compose stored. Monday
 * 13:00 UTC.
 */
export const weeklyRecapEmails = onSchedule(
  {
    memory: "512MiB",
    schedule: "0 13 * * 1",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    await runScheduledRecapSend("weeklyRecapEmails", "weekly");
  }
);

/**
 * Emails every eligible climber the monthly recap compose stored. The 1st
 * of the month, 13:00 UTC.
 */
export const monthlyRecapEmails = onSchedule(
  {
    memory: "512MiB",
    schedule: "0 13 1 * *",
    timeoutSeconds: 540,
    timeZone: "Etc/UTC",
  },
  async () => {
    await runScheduledRecapSend("monthlyRecapEmails", "monthly");
  }
);
