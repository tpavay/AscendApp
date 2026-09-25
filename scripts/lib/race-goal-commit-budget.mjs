/**
 * How many `bestForGoals` array elements one Firestore commit may carry.
 *
 * Firestore refuses a commit whose index fan-out is too large with
 * `INVALID_ARGUMENT: Transaction too big. Decrease transaction size.`, and it
 * refuses the same commit on every retry. `bestForGoals` is what makes a Live
 * Replay entry write heavy: each key is its own entry in the array-contains
 * single-field index and in every array-contains composite index over the
 * field. Measured on staging on 2026-09-25, one commit of 360 entry updates:
 *
 *   45 keys per row = 16,245 elements   committed
 *   65 keys per row = 23,400 elements   refused
 *
 * The budget is under a third of the largest commit seen to succeed. An
 * update that replaces keys also removes the old ones' index entries, so a
 * rewrite of a row can cost up to twice its new key count; at this budget
 * even a commit made entirely of such rewrites stays under the measured
 * success. A smaller budget only costs extra commits.
 */
export const MAX_GOAL_KEYS_PER_COMMIT = 5_000;

/**
 * The `bestForGoals` elements one queued write carries.
 * @param {{data?: Record<string, unknown>}} operation A `createBatchWriter`
 *   or `planCommits` operation.
 * @return {number} Array elements.
 */
export function goalKeysInOperation(operation) {
  const keys = operation?.data?.bestForGoals;
  return Array.isArray(keys) ? keys.length : 0;
}

/**
 * The split options every write of `bestForGoals` goes through: pass to
 * `createBatchWriter` or `planCommits`.
 */
export const GOAL_KEY_COMMIT_BUDGET = Object.freeze({
  maxWeight: MAX_GOAL_KEYS_PER_COMMIT,
  weigh: goalKeysInOperation,
});
