import * as admin from "firebase-admin";

export type TransactionalEmailProvider = "resend";
export type EmailType = "waitlist_welcome";
export type EmailJobStatus = "queued" | "processing" | "sent" | "failed";

export interface TransactionalEmailConfig {
  provider: TransactionalEmailProvider;
  apiKey: string;
  betaInviteUrl?: string;
  feedbackNotificationEmail?: string;
  fromEmail: string;
  fromName: string;
  replyTo?: string;
  websiteUrl?: string;
}

export interface TransactionalEmailMessage {
  idempotencyKey: string;
  html: string;
  replyTo?: string;
  subject: string;
  text: string;
  to: string[];
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

export type EmailJobPayload = WaitlistWelcomePayload;

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
