import {
  renderFirstAscentClaimedEmailFromPayload,
  renderFirstClimbCompletedEmailFromPayload,
  renderLeaderboardFirstPlaceEmailFromPayload,
  renderOnboardingAbandonedAfterPaywallEmailFromPayload,
  renderOnboardingAbandonedBeforePaywallEmailFromPayload,
  renderRatingNegativeFeedbackEmailFromPayload,
  renderRatingPositiveFollowupEmailFromPayload,
  renderWaitlistWelcomeEmailFromPayload,
} from "./templates";
import type {
  EmailJobDocument,
  EmailJobPayload,
  EmailType,
  TransactionalEmailRenderResult,
} from "./types";

export interface EmailTypeDefinition {
  render: (payload: EmailJobPayload) => TransactionalEmailRenderResult;
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
  waitlist_welcome: {
    render: renderWaitlistWelcomeEmailFromPayload,
    retryDelaysMs: standardRetryDelaysMs,
    sendPolicy: "send_now",
  },
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
 * @param {EmailJobDocument} job - Queued email job
 * @return {TransactionalEmailRenderResult} Subject and rendered bodies
 */
export function renderEmailContentForJob(
  job: EmailJobDocument
): TransactionalEmailRenderResult {
  return emailTypeConfigs[job.type].render(job.payload);
}
