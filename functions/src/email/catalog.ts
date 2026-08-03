import {
  renderFirstAscentClaimedEmailFromPayload,
  renderFirstClimbCompletedEmailFromPayload,
  renderLeaderboardFirstPlaceEmailFromPayload,
  renderOnboardingAbandonedAfterPaywallEmailFromPayload,
  renderOnboardingAbandonedBeforePaywallEmailFromPayload,
  renderRatingNegativeFeedbackEmailFromPayload,
  renderRatingPositiveFollowupEmailFromPayload,
} from "./templates";
import type {
  EmailJobDocument,
  EmailJobPayload,
  EmailRenderContext,
  EmailType,
  TransactionalEmailRenderResult,
} from "./types";

export interface EmailTypeDefinition {
  render: (
    payload: EmailJobPayload,
    context: EmailRenderContext
  ) => TransactionalEmailRenderResult;
  retryDelaysMs: number[];
  sendPolicy: "send_now";
}

const standardRetryDelaysMs = [
  5 * 60 * 1000,
  30 * 60 * 1000,
  2 * 60 * 60 * 1000,
  12 * 60 * 60 * 1000,
];

export const emailTypeConfigs: Record<EmailType, EmailTypeDefinition> = {
  rating_positive_followup: {
    render: renderRatingPositiveFollowupEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
  rating_negative_feedback: {
    render: renderRatingNegativeFeedbackEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
  onboarding_abandoned_before_paywall: {
    render: renderOnboardingAbandonedBeforePaywallEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
  onboarding_abandoned_after_paywall: {
    render: renderOnboardingAbandonedAfterPaywallEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
  first_climb_completed: {
    render: renderFirstClimbCompletedEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
  first_ascent_claimed: {
    render: renderFirstAscentClaimedEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
  leaderboard_first_place: {
    render: renderLeaderboardFirstPlaceEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
};

/**
 * Renders email content for a queued job using the type config map.
 *
 * A job already in Firestore can name a type this build no longer ships, so
 * the lookup is checked rather than assumed. Naming the retired type is what
 * makes the resulting `invalid_payload` failure readable; an unchecked lookup
 * would surface as a property access on undefined.
 * @param {EmailJobDocument} job - Queued email job
 * @param {EmailRenderContext} context - Per-recipient render context
 * @return {TransactionalEmailRenderResult} Subject and rendered bodies
 */
export function renderEmailContentForJob(
  job: EmailJobDocument,
  context: EmailRenderContext = {}
): TransactionalEmailRenderResult {
  const typeConfig = emailTypeConfigs[job.type];
  if (!typeConfig) {
    throw new Error(`unsupported_email_type:${job.type}`);
  }

  return typeConfig.render(job.payload, context);
}
