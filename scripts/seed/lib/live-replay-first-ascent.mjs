/**
 * First Ascent contract for seeded live replay leaderboard summaries.
 *
 * A climb's First Ascent slot only has two states the app can ever produce:
 *
 *   open  - no completions and no holder. The next finisher claims it.
 *   held  - at least one completion and a permanent holder.
 *
 * `publishLiveClimbCompletion` in functions/src/liveReplayLeaderboard.ts claims
 * the slot only when `!hasFirstAscent && previousCompletedCount === 0`. So a
 * summary carrying completions but no holder is unreachable *and* unleavable:
 * it renders as neither held nor open, and no later finisher can ever claim it.
 * Seeding that state gives every seeded climb a permanently dead slot.
 *
 * These helpers keep seeded summaries on one of the two reachable states. The
 * field names mirror `firstAscentWrite` in the Cloud Function - the seed script
 * and the server must publish the identical shape or the client reads one but
 * not the other.
 */

import {hashString} from "./deterministic.mjs";

/**
 * Every First Ascent field a replay summary can carry.
 *
 * Clearing a seed pack must remove all of them: leaving any behind while
 * resetting `completedCount` to 0 strands the summary in the inverse dead
 * state, where the UI reads "open" but the server refuses the claim.
 */
export const FIRST_ASCENT_FIELD_NAMES = Object.freeze([
  "firstAscentAvatarToken",
  "firstAscentCompletedAt",
  "firstAscentDisplayName",
  "firstAscentPhotoURL",
  "firstAscentUserId",
  "firstAscentWorkoutId",
]);

/**
 * Anchor for synthetic First Ascent dates.
 *
 * A First Ascent is a permanent historical fact, so seeded holders get a fixed
 * past date rather than one relative to the seed run. Re-seeding then merges the
 * same date back instead of quietly rewriting when the climb was first topped.
 */
const FIRST_ASCENT_EPOCH_MS = Date.UTC(2026, 0, 5);
const FIRST_ASCENT_SPREAD_DAYS = 120;
const MILLISECONDS_PER_DAY = 86_400_000;

/**
 * Resolves the permanent claim date for a seeded climb's First Ascent.
 *
 * Dates are spread deterministically per climb so held First Ascents sort into a
 * stable, non-uniform order on profile surfaces.
 * @param {string} seedPackId Seed pack identifier.
 * @param {string} climbId Climb identifier.
 * @return {Date} Deterministic claim date.
 */
export function firstAscentClaimedAt(seedPackId, climbId) {
  const dayOffset = hashString(`${seedPackId}:first-ascent:${climbId}`) %
    FIRST_ASCENT_SPREAD_DAYS;
  return new Date(FIRST_ASCENT_EPOCH_MS - dayOffset * MILLISECONDS_PER_DAY);
}

/**
 * Builds the First Ascent fields for a seeded holder.
 *
 * Mirrors the server's `firstAscentWrite` payload so seeded holders are
 * indistinguishable from claimed ones on the client.
 * @param {object} attempt Seeded attempt that holds the First Ascent.
 * @param {Date} claimedAt Permanent claim date.
 * @return {Record<string, unknown>} Firestore fields to merge.
 */
export function firstAscentSeedFields(attempt, claimedAt) {
  return {
    firstAscentAvatarToken: attempt.avatarToken,
    firstAscentCompletedAt: claimedAt,
    firstAscentDisplayName: attempt.displayName,
    firstAscentPhotoURL: attempt.photoURL ?? "",
    firstAscentUserId: attempt.userId,
    firstAscentWorkoutId: attempt.id,
  };
}

/**
 * Builds the field map that removes every First Ascent field from a summary.
 * @param {unknown} deleteSentinel Sentinel that deletes a field (FieldValue.delete()).
 * @return {Record<string, unknown>} Firestore fields to merge.
 */
export function clearedFirstAscentFields(deleteSentinel) {
  return Object.fromEntries(
    FIRST_ASCENT_FIELD_NAMES.map((field) => [field, deleteSentinel])
  );
}

/**
 * Throws when a seeded climb is in a First Ascent state the app can never
 * produce.
 *
 * Takes the state explicitly rather than reading it back off a write map: a
 * cleared summary carries delete sentinels rather than absent fields, so the
 * written values cannot distinguish "no holder" from "holder" on their own.
 *
 * Run for every seeded climb while building the plan, so a bad fixture fails the
 * dry run rather than silently killing that climb's First Ascent slot.
 * @param {object} state Seeded First Ascent state.
 * @param {string} state.climbId Climb identifier, for the error message.
 * @param {number} state.completedCount Seeded completions for the climb.
 * @param {boolean} state.hasFirstAscent Whether a holder is being seeded.
 */
export function assertFirstAscentInvariant({climbId, completedCount, hasFirstAscent}) {
  if (completedCount > 0 && !hasFirstAscent) {
    throw new Error(
      `${climbId}: ${completedCount} seeded completions but no First Ascent ` +
        "holder. The slot would render as neither held nor open and could " +
        "never be claimed."
    );
  }

  if (completedCount === 0 && hasFirstAscent) {
    throw new Error(
      `${climbId}: First Ascent holder with 0 completions. The slot would ` +
        "render as open but the server would refuse the claim."
    );
  }
}
