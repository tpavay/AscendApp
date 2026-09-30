import * as admin from "firebase-admin";

export type TransactionalEmailProvider = "resend";
export type EmailType =
  | "rating_positive_followup"
  | "rating_negative_feedback"
  | "onboarding_abandoned_before_paywall"
  | "onboarding_abandoned_after_paywall"
  | "first_climb_completed"
  | "first_ascent_claimed"
  | "leaderboard_first_place"
  | "weekly_recap_active"
  | "weekly_recap_inactive"
  | "monthly_recap_active"
  | "monthly_recap_inactive";
export type EmailJobStatus =
  | "queued"
  | "processing"
  | "sent"
  | "failed"
  // Deliberately not delivered, e.g. the recipient unsubscribed after the job
  // was queued. A terminal outcome with nothing to retry and no error.
  | "skipped";

export interface TransactionalEmailConfig {
  provider: TransactionalEmailProvider;
  apiKey: string;
  feedbackNotificationEmail?: string;
  fromEmail: string;
  fromName: string;
  replyTo?: string;
  unsubscribeSigningKey: string;
  websiteUrl: string;
}

export interface TransactionalEmailMessage {
  idempotencyKey: string;
  html: string;
  replyTo?: string;
  subject: string;
  text: string;
  to: string[];
  unsubscribeUrl?: string | null;
}

/**
 * Per-recipient context threaded into templates at render time. Values are
 * resolved from the job, never stored on the template payload.
 */
export interface EmailRenderContext {
  unsubscribeUrl?: string | null;
}

export interface TransactionalEmailDelivery {
  provider: TransactionalEmailProvider;
  messageId: string;
}

export interface TransactionalEmailRenderResult {
  html: string;
  subject: string;
  text: string;
}

export interface EmptyEmailPayload {
  appUrl?: string;
}

export interface FirstClimbCompletedPayload {
  climbName?: string;
  resultUrl: string;
}

export interface FirstAscentClaimedPayload {
  climbName: string;
  climbUrl: string;
}

export interface LeaderboardFirstPlacePayload {
  leaderboardName: string;
  leaderboardUrl: string;
}

/**
 * A small green "up" callout comparing a stat to the prior period. Only ever
 * built for a genuine improvement - never a decline or an unchanged figure -
 * so a recap never reads like a scolding.
 */
export interface RecapDeltaChip {
  direction: "up";
  label: string;
  value: string;
}

/**
 * One cell of the period's activity calendar heatmap.
 * `dayOfMonth` is null only for a "blank" filler cell used to align a
 * monthly grid to its starting weekday - a weekly calendar never has one.
 */
export interface RecapCalendarCell {
  dayOfMonth: number | null;
  level: "blank" | "none" | "active" | "peak";
}

/**
 * One of the app's own tracked achievement badges, earned for the period (or,
 * for a First Ascent in the zero-activity email, ever) - reusing
 * `ProfileAchievementCatalogue`'s real badge artwork, names, and tiers
 * (`ascend-leaderboards`' locked Top 10 / Top 100 / First Ascent
 * terminology) rather than inventing new ones. `id` selects the artwork
 * (`AscendApp/Resources/Assets.xcassets/Images/LeaderboardTop10`,
 * `LeaderboardTop100`, `FirstAscentBadgeDetailed`, copied email-safe into
 * `web/public/images/badges/`); `detail` carries the landmark name(s) for a
 * First Ascent badge and "globally" for a rank badge.
 */
export interface RecapEarnedBadge {
  id: "top10" | "top100" | "first-ascent";
  label: string;
  detail?: string;
}

/**
 * Stats for a climber who had activity in a closed weekly or monthly window.
 * Every optional field is omitted rather than sent as zero/hollow when there
 * is nothing to report - no delta chip for a flat or down period, no rank
 * line with too small a field to mean anything.
 *
 * `rank`/`fieldSize` are the hero's lead metric (round 3): shown together as
 * "#{rank} of {fieldSize} climbers" whenever `fieldSize` is large enough for
 * a rank to mean anything, with `percentileBand` as an optional secondary
 * badge alongside it. `earnedBadges` (round 5) is the app's real achievement
 * badge artwork earned for the period - a Top 10 or Top 100 badge sourced
 * from the same tracked achievement record the old text-only
 * `achievementLabel` callout read (not re-derived from `rank`), plus a First
 * Ascent badge for any landmark first-ascended during this period
 * specifically (a strict subset of `landmarksFinished`, never a lifetime
 * total) - empty when the climber earned neither. There is deliberately no
 * milestone field (round 4: the captain found the milestone-unlocked concept
 * confusing and asked for it to be removed).
 */
export interface RecapActivePayload {
  earnedBadges: RecapEarnedBadge[];
  periodLabel: string;
  climbsCompleted: number;
  climbsDelta?: RecapDeltaChip;
  totalSteps: number;
  stepsDelta?: RecapDeltaChip;
  totalFloors: number;
  floorsDelta?: RecapDeltaChip;
  landmarksFinished: string[];
  rank?: number;
  fieldSize?: number;
  percentileBand?: string;
  currentStreakWeeks?: number;
  calendar: RecapCalendarCell[];
  ctaUrl: string;
}

/**
 * Gentle re-engagement copy for a climber with no activity in the window
 * (round 4). `gapCount` is the real elapsed weeks (weekly) or months
 * (monthly) since the climber was last active, always at least 1.
 * `firstAscents` lists every landmark the climber holds the permanent First
 * Ascent of; when it is non-empty the email names them instead of the
 * generic `suggestedClimbName` nudge, and `earnedBadges` (round 5) carries
 * the matching First Ascent badge artwork alongside that same list - empty
 * with no First Ascents, never a rank badge (there is no ranked period to
 * have earned one in).
 */
export interface RecapInactivePayload {
  periodLabel: string;
  gapCount: number;
  firstAscents: string[];
  earnedBadges: RecapEarnedBadge[];
  suggestedClimbName?: string;
  ctaUrl: string;
}

export type EmailJobPayload =
  | EmptyEmailPayload
  | FirstClimbCompletedPayload
  | FirstAscentClaimedPayload
  | LeaderboardFirstPlacePayload
  | RecapActivePayload
  | RecapInactivePayload;

export interface EmailJobDocument {
  attemptCount: number;
  createdAt: admin.firestore.Timestamp;
  dedupeKey: string;
  lastErrorCode: string | null;
  lastErrorMessage: string | null;
  payload: EmailJobPayload;
  processingStartedAt: admin.firestore.Timestamp | null;
  provider: TransactionalEmailProvider | null;
  providerMessageId: string | null;
  readyAt: admin.firestore.Timestamp;
  recipientEmail: string;
  recipientHash: string;
  // Present only for emails addressed to a signed-in user. Drives the
  // per-recipient unsubscribe link; null for admin mail.
  recipientUid: string | null;
  scheduledFor: admin.firestore.Timestamp;
  sentAt: admin.firestore.Timestamp | null;
  sourceRef: string | null;
  status: EmailJobStatus;
  type: EmailType;
  updatedAt: admin.firestore.Timestamp;
}

export interface FeedbackAdminNotifyPayload {
  appVersion: string;
  buildNumber: string;
  deviceModel: string;
  feedbackId: string;
  message: string;
  osVersion: string;
  type: string;
  userEmail: string;
  userId: string;
}
