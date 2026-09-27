/**
 * How far a seeded Live Replay board publishes.
 *
 * A seeded row holds its attempt's final steps from its own finish to the end
 * of its board's window, and is counted home only past the window. So a
 * window that stops before an attempt finishes cuts that rival short: from the
 * bucket it stops at, the live race reads the rival as home at its final
 * steps - the jump a real rival made at 60:00 before the split fix.
 */

/** The live race's bucket grid: every client reads `floor(elapsed / 10)`. */
export const BUCKET_INTERVAL_SECONDS = 10;

/**
 * The global Just Climb board spans every seeded attempt through its finish.
 *
 * It used to stop at 60:00, like the pre-fix publish, so every seeded rival
 * slower than an hour - 39 of them on staging, up to 1:40:00 - jumped to its
 * finish at 60:10. That board is the one a climber past the hour races on, so
 * it reaches the slowest finish rather than a percentile of them.
 * @param {{durationSeconds: number}[]} attempts Every seeded attempt on it.
 * @return {number} Highest bucket index the board publishes.
 */
export function justClimbBucketLimit(attempts) {
  return attempts.reduce(
    (limit, attempt) => Math.max(limit, Math.ceil(attempt.durationSeconds / BUCKET_INTERVAL_SECONDS)),
    12
  );
}
