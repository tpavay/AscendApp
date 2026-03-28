import {emailTypeConfigs} from "./catalog";
import type {EmailType} from "./types";

/**
 * Returns the next retry delay after a failed send attempt.
 * @param {EmailType} type - Email type
 * @param {number} attemptCount - Total attempts made so far
 * @return {number | null} Delay in milliseconds, or null if exhausted
 */
export function getNextRetryDelayMs(
  type: EmailType,
  attemptCount: number
): number | null {
  return emailTypeConfigs[type].retryDelaysMs[attemptCount - 1] ?? null;
}
