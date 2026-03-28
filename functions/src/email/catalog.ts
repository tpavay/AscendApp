import {
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

export const emailTypeConfigs: Record<EmailType, EmailTypeDefinition> = {
  waitlist_welcome: {
    render: renderWaitlistWelcomeEmailFromPayload,
    retryDelaysMs: [
      5 * 60 * 1000,
      30 * 60 * 1000,
      2 * 60 * 60 * 1000,
      12 * 60 * 60 * 1000,
    ],
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
