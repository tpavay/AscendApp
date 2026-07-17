import * as admin from "firebase-admin";

export type TransactionalEmailProvider = "resend";
export type EmailType =
  | "waitlist_welcome"
  | "rating_positive_followup"
  | "rating_negative_feedback"
  | "onboarding_abandoned_before_paywall"
  | "onboarding_abandoned_after_paywall"
  | "first_climb_completed"
  | "first_ascent_claimed"
  | "leaderboard_first_place";
export type EmailJobStatus = "queued" | "processing" | "sent" | "failed";

export interface TransactionalEmailConfig {
  provider: TransactionalEmailProvider;
  apiKey: string;
  betaInviteUrl?: string;
  feedbackNotificationEmail?: string;
  fromEmail: string;
  fromName: string;
  replyTo?: string;
  unsubscribeSigningKey: string;
  websiteUrl?: string;
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

export interface WaitlistWelcomePayload {
  source: string;
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

export type EmailJobPayload =
  | WaitlistWelcomePayload
  | EmptyEmailPayload
  | FirstClimbCompletedPayload
  | FirstAscentClaimedPayload
  | LeaderboardFirstPlacePayload;

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
  // per-recipient unsubscribe link; null for waitlist and admin mail.
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

export interface EmailRateLimitDocument {
  createdAt: admin.firestore.Timestamp;
  ipHash: string;
  longWindowCount: number;
  longWindowStartedAt: admin.firestore.Timestamp;
  shortWindowCount: number;
  shortWindowStartedAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

export interface EmailRateLimitState {
  ipHash: string;
  longWindowCount: number;
  longWindowStartedAtMs: number;
  shortWindowCount: number;
  shortWindowStartedAtMs: number;
}
