/**
 * `source` on a live replay summary: what produced the completions it counts.
 *
 * The field exists to answer one question - "is anyone real on this board?" -
 * and it only answers it if every writer maintains it. `replaySummaryWrite` in
 * `functions/src/liveReplayLeaderboard.ts` stamps `live` on every publish, so a
 * board that has taken a genuine finish stops calling itself seeded. This is the
 * seed side of the same two values.
 *
 * `seedPackId` and `seededAttemptCount` still record how many synthetic rows the
 * seed wrote, so a live board does not lose the count of what is fixture.
 */

/** Only the seed has written completions here. */
export const REPLAY_SUMMARY_SOURCE_SEEDED = "seeded";

/** At least one real climber has completed this context. */
export const REPLAY_SUMMARY_SOURCE_LIVE = "live";

/**
 * Prefix every synthetic climber id carries.
 *
 * A finisher document is keyed by the climber's uid, so this is what separates
 * the seed's own competitors from a real account on the same board. The Cloud
 * Functions identity propagation reads the same prefix for the same reason.
 */
export const SYNTHETIC_USER_ID_PREFIX = "seeded:";

/**
 * Reports whether a finisher document id belongs to a synthetic competitor.
 * @param {unknown} userId Finisher document id (the climber's uid).
 * @return {boolean} True when the seed wrote this climber.
 */
export function isSyntheticUserId(userId) {
  return typeof userId === "string" &&
    userId.startsWith(SYNTHETIC_USER_ID_PREFIX);
}

/**
 * The `source` a seed run may claim for one board.
 *
 * A seed pack clears and rewrites its own rows, but it cannot clear a real
 * climber's - so stamping `seeded` unconditionally would re-assert "nobody real
 * is here" over a board that still carries a genuine finisher, which is the
 * same lie the Cloud Function used to leave behind.
 * @param {object} board Board state after this seed run lands.
 * @param {string[]} board.survivingFinisherIds Finisher ids left standing.
 * @return {string} `seeded` or `live`.
 */
export function seededSummarySource({survivingFinisherIds}) {
  return survivingFinisherIds.every(isSyntheticUserId) ?
    REPLAY_SUMMARY_SOURCE_SEEDED :
    REPLAY_SUMMARY_SOURCE_LIVE;
}
