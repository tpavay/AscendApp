import type {AppAccessProjection} from "./types";

/**
 * The one ordering rule every projection writer shares.
 *
 * RevenueCat `request_date_ms` stamps when the subscriber snapshot was read,
 * so an out-of-order webhook or a slow reconciliation cannot move access
 * backward. An equal stamp still replaces, because a re-derived snapshot of
 * the same moment carries the same answer.
 * @param {number | null | undefined} existingRequestDateMs - Stored stamp
 * @param {AppAccessProjection} candidate - Newly derived projection
 * @return {boolean} Whether the candidate may replace what is stored
 */
export function shouldReplaceProjection(
  existingRequestDateMs: number | null | undefined,
  candidate: AppAccessProjection
): boolean {
  return typeof existingRequestDateMs !== "number" ||
    candidate.revenueCatRequestDateMs >= existingRequestDateMs;
}
