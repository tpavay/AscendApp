/**
 * Who a lifecycle drip email is still right for, decided from the documents
 * the server already holds. One function answers it for both callers: the
 * sweep asks before it queues, and `processEmailJobs` asks again right before
 * it sends, because a job can sit queued (or retrying) while the climber
 * moves on - buys, starts the week, climbs, cancels.
 *
 * Each email goes only for the furthest stage a climber reached. A later stage
 * suppresses an earlier email, so none of the checks below is optional.
 *
 * The facts come from three places, all server-written:
 *   - `users/{uid}/lifecycle_events/*` (`recordLifecycleEvent`): the first
 *     paywall shown and closed. The welcome offer and the founder letter are
 *     NOT recorded there, which is why those two stages have no email.
 *   - `users/{uid}/trial/free_week` and `users/{uid}/entitlements/app_access`:
 *     the free week and every grant the RevenueCat webhook projects
 *     (`docs/revenuecat-server-entitlement-enforcement.md`).
 *   - `users/{uid}/workouts` and `users/{uid}/attempt_heartbeats`: a climb
 *     saved or started.
 */

import * as admin from "firebase-admin";
import type {DripEmailType} from "./dripCopy";
import type {EmailJobDocument, EmailType} from "./types";

export const DRIP_EMAIL_TYPES: readonly DripEmailType[] = [
  "drip_paywall_abandoned",
  "drip_free_week_unused",
  "drip_trial_reminder",
];

export const FIRST_PAYWALL_SHOWN_EVENT = "paywall_shown_app_access_gate_v1";
export const FIRST_PAYWALL_DISMISSED_EVENT =
  "paywall_dismissed_app_access_gate_v1";

/**
 * The welcome product, the only one that carries a 7-day free trial
 * (`docs/superwall-paywall-setup.md`). The yearly product's trial is a month
 * and is not what the reminder promises, so it is deliberately not here.
 */
export const WELCOME_PRODUCT_IDS: readonly string[] = [
  "ascend_yearly_welcome",
  "ascend_staging_yearly_welcome",
];

/**
 * For a grant written before the projection carried `willRenew` and
 * `periodType`: the RevenueCat event types it may last have been written by
 * while the climber is still on an uncancelled first trial. Anything else - a
 * renewal (converted), a cancellation (opted out), a billing issue, a product
 * change - means the reminder is wrong or unneeded, so the list is an
 * allowlist and an unknown value fails closed.
 */
export const TRIAL_PENDING_SOURCE_EVENTS: readonly string[] = [
  "INITIAL_PURCHASE",
  "UNCANCELLATION",
  "CLIENT_RECONCILIATION",
];

/**
 * For a grant written before the projection carried `periodType`: a first
 * trial is seven days, and a free week can run before the purchase, so a
 * grant document older than this when it expires cannot be a first trial. It
 * is what keeps a welcome-product year bought without a trial from being
 * mistaken for one when its first year ends.
 */
export const TRIAL_MAX_GRANT_AGE_MS = 15 * 24 * 60 * 60 * 1000;

/** The subscriber's renewal state, as the projection recorded it. */
export interface DripGrantRenewal {
  periodType: string | null;
  willRenew: boolean | null;
}

export interface DripGrantFacts {
  createdAtMs: number | null;
  expiresAtMs: number | null;
  productId: string | null;
  /** Null for a grant written before the projection recorded renewal. */
  renewal: DripGrantRenewal | null;
  source: string | null;
  sourceEventType: string | null;
}

/** What the rules read, behind a port so the decision is testable alone. */
export interface DripFactReader {
  /** `users/{uid}/entitlements/app_access`, or null when there is none. */
  grant(uid: string): Promise<DripGrantFacts | null>;
  /** `users/{uid}/trial/free_week`'s window, or null when never started. */
  freeWeek(uid: string): Promise<{expiresAtMs: number | null} | null>;
  /** Whether a lifecycle event document exists. */
  hasLifecycleEvent(uid: string, eventDocId: string): Promise<boolean>;
  /** A workout saved or a headphone session started, ever. */
  hasClimbActivity(uid: string): Promise<boolean>;
}

export type DripSuppressionReason =
  | "has_access"
  | "free_week_started"
  | "closed_first_paywall"
  | "first_paywall_not_recorded"
  | "no_free_week"
  | "free_week_over"
  | "has_paid_access"
  | "already_climbed"
  | "no_trial"
  | "not_welcome_trial"
  | "not_first_trial"
  | "trial_cancelled"
  | "trial_converted_or_changed"
  | "trial_ended"
  | "trial_moved";

export interface DripEligibilityContext {
  /** The trial end the reminder was queued for. Absent when only sweeping. */
  expectedTrialEndsAtMs?: number;
  now: Date;
}

/**
 * Why this climber should no longer get this email, or null when they should.
 * @param {DripEmailType} type - Which drip email
 * @param {string} uid - The climber
 * @param {DripFactReader} reader - Where the facts come from
 * @param {DripEligibilityContext} context - Clock and queued expectations
 * @return {Promise<DripSuppressionReason | null>} Reason, or null to send
 */
export async function dripSuppressionReasonFor(
  type: DripEmailType,
  uid: string,
  reader: DripFactReader,
  context: DripEligibilityContext
): Promise<DripSuppressionReason | null> {
  const nowMs = context.now.getTime();

  switch (type) {
  case "drip_paywall_abandoned": {
    // Anything past the first paywall is a later stage than this email is for.
    if (await reader.grant(uid)) return "has_access";
    if (await reader.freeWeek(uid)) return "free_week_started";
    if (await reader.hasLifecycleEvent(uid, FIRST_PAYWALL_DISMISSED_EVENT)) {
      return "closed_first_paywall";
    }
    if (!await reader.hasLifecycleEvent(uid, FIRST_PAYWALL_SHOWN_EVENT)) {
      return "first_paywall_not_recorded";
    }
    return null;
  }

  case "drip_free_week_unused": {
    const week = await reader.freeWeek(uid);
    if (!week) return "no_free_week";
    if (week.expiresAtMs === null || week.expiresAtMs <= nowMs) {
      return "free_week_over";
    }
    const grant = await reader.grant(uid);
    // A grant that is not the week is a purchase or a comp: a later stage.
    if (grant && grant.source !== "trial") return "has_paid_access";
    if (await reader.hasClimbActivity(uid)) return "already_climbed";
    return null;
  }

  case "drip_trial_reminder": {
    const grant = await reader.grant(uid);
    if (!grant) return "no_trial";
    if (grant.source === "trial" || !grant.productId ||
      !WELCOME_PRODUCT_IDS.includes(grant.productId)) {
      return "not_welcome_trial";
    }
    const pending = grant.renewal ?
      renewalTrialState(grant.renewal) :
      legacyTrialState(grant);
    if (pending) return pending;
    if (grant.expiresAtMs === null || grant.expiresAtMs <= nowMs) {
      return "trial_ended";
    }
    if (!grant.renewal && (grant.createdAtMs === null ||
      grant.expiresAtMs - grant.createdAtMs > TRIAL_MAX_GRANT_AGE_MS)) {
      return "not_first_trial";
    }
    if (context.expectedTrialEndsAtMs !== undefined &&
      grant.expiresAtMs !== context.expectedTrialEndsAtMs) {
      return "trial_moved";
    }
    return null;
  }
  }
}

/**
 * Whether the recorded renewal state is a trial that will still renew.
 * @param {DripGrantRenewal} renewal - What the projection recorded
 * @return {DripSuppressionReason | null} Reason, or null for a live trial
 */
function renewalTrialState(
  renewal: DripGrantRenewal
): DripSuppressionReason | null {
  if (renewal.willRenew === false) return "trial_cancelled";
  if (renewal.willRenew !== true || renewal.periodType !== "trial") {
    return "trial_converted_or_changed";
  }
  return null;
}

/**
 * The same question for a grant that predates the renewal fields, answered
 * from the last event that wrote it.
 * @param {DripGrantFacts} grant - The grant
 * @return {DripSuppressionReason | null} Reason, or null for a live trial
 */
function legacyTrialState(grant: DripGrantFacts): DripSuppressionReason | null {
  if (grant.sourceEventType === "CANCELLATION") return "trial_cancelled";
  if (!grant.sourceEventType ||
    !TRIAL_PENDING_SOURCE_EVENTS.includes(grant.sourceEventType)) {
    return "trial_converted_or_changed";
  }
  return null;
}

/**
 * Whether an email type is one of the lifecycle drip emails.
 * @param {string} type - A queued job's type
 * @return {boolean} True for a drip type
 */
export function isDripEmailType(type: string): type is DripEmailType {
  return (DRIP_EMAIL_TYPES as readonly string[]).includes(type);
}

function toMillis(value: unknown): number | null {
  return value instanceof admin.firestore.Timestamp ? value.toMillis() : null;
}

/**
 * The Firestore-backed fact reader.
 * @param {admin.firestore.Firestore} firestore - Admin Firestore instance
 * @return {DripFactReader} Reader over the climber's own documents
 */
export function makeFirestoreDripFactReader(
  firestore: admin.firestore.Firestore
): DripFactReader {
  const userRef = (uid: string) => firestore.collection("users").doc(uid);
  return {
    async grant(uid) {
      const snapshot = await userRef(uid)
        .collection("entitlements").doc("app_access").get();
      if (!snapshot.exists) return null;
      return {
        createdAtMs: snapshot.createTime?.toMillis() ?? null,
        expiresAtMs: toMillis(snapshot.get("accessUntil")) ??
          toMillis(snapshot.get("expiresAt")),
        productId: typeof snapshot.get("productId") === "string" ?
          snapshot.get("productId") : null,
        renewal: snapshot.get("willRenew") === undefined ? null : {
          periodType: typeof snapshot.get("periodType") === "string" ?
            snapshot.get("periodType") : null,
          willRenew: typeof snapshot.get("willRenew") === "boolean" ?
            snapshot.get("willRenew") : null,
        },
        source: typeof snapshot.get("source") === "string" ?
          snapshot.get("source") : null,
        sourceEventType: typeof snapshot.get("sourceEventType") === "string" ?
          snapshot.get("sourceEventType") : null,
      };
    },
    async freeWeek(uid) {
      const snapshot = await userRef(uid)
        .collection("trial").doc("free_week").get();
      return snapshot.exists ?
        {expiresAtMs: toMillis(snapshot.get("expiresAt"))} : null;
    },
    async hasLifecycleEvent(uid, eventDocId) {
      return (await userRef(uid)
        .collection("lifecycle_events").doc(eventDocId).get()).exists;
    },
    async hasClimbActivity(uid) {
      const [workouts, heartbeats] = await Promise.all([
        userRef(uid).collection("workouts").limit(1).select().get(),
        userRef(uid).collection("attempt_heartbeats").limit(1).select().get(),
      ]);
      return !workouts.empty || !heartbeats.empty;
    },
  };
}

/**
 * Send-time suppression for a claimed job, read by `processEmailJobs`.
 * A read failure throws, so a transient error can never deliver mail that
 * should have been held back (the job stays claimed and is reclaimed).
 * @param {Pick<EmailJobDocument, "recipientUid" | "type" | "payload">} job
 *   Claimed email job
 * @param {Date} now - The worker's clock
 * @param {DripFactReader} reader - Fact reader, injectable for tests
 * @return {Promise<DripSuppressionReason | null>} Reason, or null to send
 */
export async function dripSuppressionReasonForJob(
  job: Pick<EmailJobDocument, "recipientUid" | "type" | "payload">,
  now: Date,
  reader: DripFactReader = makeFirestoreDripFactReader(admin.firestore())
): Promise<DripSuppressionReason | null> {
  if (!isDripEmailType(job.type as EmailType)) {
    return null;
  }
  if (!job.recipientUid) {
    return "no_trial";
  }
  const payload = job.payload as {trialEndsAtMs?: unknown};
  return dripSuppressionReasonFor(
    job.type as DripEmailType,
    job.recipientUid,
    reader,
    {
      now,
      ...(typeof payload.trialEndsAtMs === "number" ?
        {expectedTrialEndsAtMs: payload.trialEndsAtMs} : {}),
    }
  );
}
