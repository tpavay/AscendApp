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
 * Stats for a climber who had activity in a closed weekly or monthly window.
 * `bestRankLabel`, `currentStreakWeeks`, and `comparisonNote` are each
 * omitted rather than sent as zero/null when there is nothing to report -
 * an absent field renders no line, never a hollow "0 week streak".
 */
export interface RecapActivePayload {
  periodLabel: string;
  climbsCompleted: number;
  totalSteps: number;
  totalFloors: number;
  landmarksFinished: string[];
  bestRankLabel?: string;
  currentStreakWeeks?: number;
  comparisonNote?: string;
  climbsUrl: string;
}

/** Gentle re-engagement copy for a climber with no activity in the window. */
export interface RecapInactivePayload {
  periodLabel: string;
  suggestedClimbName?: string;
  suggestedClimbUrl: string;
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
