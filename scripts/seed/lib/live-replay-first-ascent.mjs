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
  "firstAscentIsSynthetic",
  "firstAscentPhotoURL",
  "firstAscentUserId",
  "firstAscentWorkoutId",
]);

/**
 * `activityTier` marking a summary seeded with an open First Ascent slot.
 *
 * Records what the seed intended for the climb, and nothing more. It is not the
 * slot's state: the seed writes the tier once and the Cloud Function's summary
 * merge never resets it, so a climb seeded open still reads "open" after a real
 * climber claims it. Read the state with `isOpenFirstAscentSummary`.
 */
export const FIRST_ASCENT_OPEN_ACTIVITY_TIER = "open";

/**
 * Reports whether a summary already carries a First Ascent holder.
 *
 * Mirrors `leaderboardHasFirstAscent` in the Cloud Function, which is the
 * predicate that decides whether a finisher can still claim the slot. Reading
 * the state any other way would pass a summary the server would refuse.
 * @param {Record<string, unknown> | undefined} summary Replay summary fields.
 * @return {boolean} True when the slot is already held.
 */
export function summaryHasFirstAscent(summary) {
  if (!summary) return false;

  return summary.firstAscentCompletedAt !== undefined ||
    (typeof summary.firstAscentUserId === "string" &&
      summary.firstAscentUserId.length > 0);
}

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
 * indistinguishable from claimed ones on the client. Every seed script that
 * publishes a holder goes through here - a hand-rolled literal is another copy
 * of the contract that drifts silently.
 * @param {object} holder Completion that holds the First Ascent.
 * @param {string} holder.id Workout/entry ID of the holding completion.
 * @param {string} holder.userId Holder's user ID.
 * @param {string} holder.displayName Holder's public display name.
 * @param {string} holder.avatarToken Holder's avatar token.
 * @param {string} [holder.photoURL] Holder's public photo URL, if any.
 * @param {Date|object} claimedAt Permanent claim date.
 * @param {object} [options] Trusted fixture options.
 * @param {boolean} [options.isSynthetic=true] Whether the holder is a first-party fixture.
 * @return {Record<string, unknown>} Firestore fields to merge.
 */
export function firstAscentSeedFields(holder, claimedAt, {isSynthetic = true} = {}) {
  return {
    firstAscentAvatarToken: holder.avatarToken,
    firstAscentCompletedAt: claimedAt,
    firstAscentDisplayName: holder.displayName,
    firstAscentIsSynthetic: isSynthetic,
    firstAscentPhotoURL: holder.photoURL ?? "",
    firstAscentUserId: holder.userId,
    firstAscentWorkoutId: holder.id,
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
 * Deletes every replay entry under a climb seeded with an open First Ascent.
 *
 * The seed can address its own rows by their deterministic IDs, but a real
 * climber's it cannot: the Cloud Function keys each entry by workoutId and
 * writes one per split bucket. Re-seeding by known ID would leave those rows
 * beside a summary reset to zero completions - the inverse dead state, on the
 * one fixture whose whole purpose is to be claimed and reset. So an open climb's
 * entries are found by query and dropped wholesale, which is safe precisely
 * because the fixture promises the climb has no completions at all.
 * @param {object} splitBucketsRef `splitBuckets` collection reference.
 * @param {object} writer BulkWriter that performs the deletes.
 * @return {Promise<number>} Count of entry documents deleted.
 */
export async function clearOpenFirstAscentEntries(splitBucketsRef, writer) {
  let deleted = 0;
  const bucketRefs = await splitBucketsRef.listDocuments();

  for (const bucketRef of bucketRefs) {
    const entries = await bucketRef.collection("entries").get();
    for (const entry of entries.docs) {
      writer.delete(entry.ref);
      deleted += 1;
    }
  }

  return deleted;
}

/**
 * Reports whether a climb's First Ascent slot is still open.
 *
 * Derived from the counts and the holder, never from `activityTier`: those are
 * the only fields both the seed and the Cloud Function maintain, so they are the
 * only ones that still describe the slot after a real climber claims it.
 * @param {object} state First Ascent state.
 * @param {number} state.completedCount Completions recorded for the climb.
 * @param {boolean} state.hasFirstAscent Whether a holder is recorded.
 * @return {boolean} True when the next finisher would claim the slot.
 */
export function isOpenFirstAscentSummary({completedCount, hasFirstAscent}) {
  return completedCount === 0 && !hasFirstAscent;
}

/**
 * Describes why a climb's First Ascent state is one the app can never produce,
 * or returns null when the state is reachable.
 *
 * The single definition of the contract. Both dead states are unreachable *and*
 * unleavable, so the seed asserts against this while building its plan and the
 * audit reports against it - one of them throwing and the other accumulating is
 * a difference in reporting, not in what counts as valid.
 *
 * Takes the state explicitly rather than reading it back off a write map: a
 * cleared summary carries delete sentinels rather than absent fields, so the
 * written values cannot distinguish "no holder" from "holder" on their own.
 * @param {object} state First Ascent state.
 * @param {string} state.climbId Climb identifier, for the message.
 * @param {number} state.completedCount Completions recorded for the climb.
 * @param {boolean} state.hasFirstAscent Whether a holder is recorded.
 * @return {string | null} Failure message, or null when the state is reachable.
 */
export function firstAscentInvariantFailure({climbId, completedCount, hasFirstAscent}) {
  if (completedCount > 0 && !hasFirstAscent) {
    return `${climbId}: ${completedCount} completions but no First Ascent ` +
      "holder. The slot would render as neither held nor open and could " +
      "never be claimed.";
  }

  if (completedCount === 0 && hasFirstAscent) {
    return `${climbId}: First Ascent holder with 0 completions. The slot ` +
      "would render as open but the server would refuse the claim.";
  }

  return null;
}

/**
 * Throws when a seeded climb is in a First Ascent state the app can never
 * produce.
 *
 * Run for every seeded climb while building the plan, so a bad fixture fails the
 * dry run rather than silently killing that climb's First Ascent slot.
 * @param {object} state Seeded First Ascent state.
 * @param {string} state.climbId Climb identifier, for the error message.
 * @param {number} state.completedCount Seeded completions for the climb.
 * @param {boolean} state.hasFirstAscent Whether a holder is being seeded.
 */
export function assertFirstAscentInvariant(state) {
  const failure = firstAscentInvariantFailure(state);
  if (failure) {
    throw new Error(failure);
  }
}
