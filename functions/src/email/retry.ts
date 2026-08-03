import {emailTypeConfigs} from "./catalog";
import type {EmailType} from "./types";

/**
 * Returns the next retry delay after a failed send attempt.
 *
 * A job already in Firestore can name a type this build no longer ships, so the
 * lookup is checked rather than assumed. A missing retry schedule means there
 * is no next delay, so the caller's exhausted path retires the job as a
 * terminal failure instead of the worker faulting mid-batch.
 * @param {EmailType} type - Email type
 * @param {number} attemptCount - Total attempts made so far
 * @return {number | null} Delay in milliseconds, or null if exhausted
 */
export function getNextRetryDelayMs(
  type: EmailType,
  attemptCount: number
): number | null {
  const typeConfig = emailTypeConfigs[type];
  if (!typeConfig) {
    return null;
  }

  return typeConfig.retryDelaysMs[attemptCount - 1] ?? null;
}
