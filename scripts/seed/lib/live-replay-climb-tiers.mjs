/**
 * How the seed pack divides the catalogue between contested boards and
 * claimable First Ascent slots.
 *
 * Shared because the division is a contract between two scripts, not a detail of
 * either: `seed-live-replay-leaderboards.mjs` writes it, and
 * `seed-demo-user.mjs` has to place its account's First Ascent outside the
 * contested set or that claim reads as first-ever on a board with a field
 * already on it.
 */

export const ACTIVE_CLIMBS = [
  // 0.33 rather than 0.36: at 0.36 this board seeded 89 finishers, past the 83
  // distinct names and avatars the pack can give them, so its last six rows had
  // no human name and no face. See `assertSeededIdentitySupply`.
  {id: "merdeka-118", totalClimbers: 247, replayEntries: 96, completionRate: 0.33},
  // 0.41 rather than 0.42: at 0.42 this board seeded 83 finishers, one past the
  // 82 distinct names and competitor avatars the pack can give them.
  {id: "empire-state-building", totalClimbers: 198, replayEntries: 88, completionRate: 0.41},
  {id: "burj-khalifa", totalClimbers: 173, replayEntries: 84, completionRate: 0.34},
  {id: "reunion-tower", totalClimbers: 166, replayEntries: 72, completionRate: 0.48},
  {id: "eiffel-tower", totalClimbers: 156, replayEntries: 72, completionRate: 0.44},
  {id: "lotte-world-tower", totalClimbers: 142, replayEntries: 68, completionRate: 0.38},
  {id: "cn-tower", totalClimbers: 137, replayEntries: 64, completionRate: 0.36},
  {id: "statue-of-liberty", totalClimbers: 128, replayEntries: 60, completionRate: 0.54},
  {id: "eureka-tower", totalClimbers: 118, replayEntries: 56, completionRate: 0.35},
  {id: "q1-tower", totalClimbers: 104, replayEntries: 52, completionRate: 0.46},
];

export const WARM_CLIMBS = [
  {id: "space-needle", totalClimbers: 62, replayEntries: 30, completionRate: 0.44},
  {id: "torre-latinoamericana", totalClimbers: 58, replayEntries: 28, completionRate: 0.48},
  {id: "willis-tower", totalClimbers: 54, replayEntries: 28, completionRate: 0.36},
  {id: "one-world-trade-center", totalClimbers: 49, replayEntries: 26, completionRate: 0.34},
  {id: "farol-santander", totalClimbers: 46, replayEntries: 24, completionRate: 0.40},
  {id: "monserrate", totalClimbers: 42, replayEntries: 24, completionRate: 0.40},
  {id: "st-peters-basilica", totalClimbers: 39, replayEntries: 22, completionRate: 0.46},
  {id: "sacre-coeur", totalClimbers: 36, replayEntries: 20, completionRate: 0.58},
  {id: "elizabeth-tower", totalClimbers: 34, replayEntries: 20, completionRate: 0.58},
  {id: "tokyo-tower", totalClimbers: 32, replayEntries: 20, completionRate: 0.40},
  {id: "shanghai-tower", totalClimbers: 29, replayEntries: 18, completionRate: 0.34},
  {id: "taipei-101", totalClimbers: 28, replayEntries: 18, completionRate: 0.34},
  {id: "canton-tower", totalClimbers: 27, replayEntries: 18, completionRate: 0.34},
  {id: "leaning-tower-of-pisa", totalClimbers: 24, replayEntries: 16, completionRate: 0.56},
  {id: "berlin-tv-tower", totalClimbers: 23, replayEntries: 16, completionRate: 0.44},
  {id: "sydney-tower", totalClimbers: 21, replayEntries: 16, completionRate: 0.56},
];

/**
 * Release state a climb has to be in before the seed gives it a board.
 *
 * A hidden or coming-soon climb cannot be raced, so an open First Ascent on one
 * is an opportunity nobody can take.
 */
export const RACEABLE_RELEASE_STATE = "available";

/**
 * Builds the open-First Ascent configs: every raceable climb the pack does not
 * contest.
 *
 * Seeding is what decides how much of the catalogue can still demonstrate a
 * First Ascent, and it used to spend that budget without meaning to. The server
 * only lets a finisher claim a slot on a board with no completions, so every
 * climb the pack fills with synthetic competitors takes its First Ascent off the
 * table for good - that is the rule working, not a defect. What was wrong was
 * the other 28 raceable climbs, which had no summary at all: the open-slot
 * surfaces key off an existing summary (`ProfileFirstAscentService` requires
 * `updatedAt != nil && completedCount == 0`), so a climb with no document reads
 * as nothing rather than as a claimable opportunity, and staging offered four
 * claimable climbs out of thirty-two.
 *
 * So the split is explicit: `ACTIVE_CLIMBS` and `WARM_CLIMBS` are the boards
 * that exist to look contested, and every other raceable climb gets an empty
 * summary so its slot is both open and visibly open. Which four reach the
 * profile's open preview is unchanged - it fills in catalog order and caps at
 * four, and the four that sort first are the same ones this list named by hand.
 * @param {Map<string, object>} climbsById Climb catalog by id.
 * @param {Set<string>} contestedIds Climbs seeded with synthetic competitors.
 * @return {object[]} Open-slot climb configs.
 */
export function firstAscentOpenConfigs(climbsById, contestedIds) {
  return Array.from(climbsById.values())
    .filter((climb) => climb.releaseState === RACEABLE_RELEASE_STATE &&
      !contestedIds.has(climb.id))
    .map((climb) => ({
      id: climb.id,
      totalClimbers: 0,
      replayEntries: 0,
      completionRate: 0,
    }));
}

/**
 * Every climb the pack seeds with synthetic competitors.
 *
 * A contested board's First Ascent is spent the moment the seed lands, so this
 * set is also the list of climbs no account may be given a First Ascent on.
 * @return {Set<string>} Contested climb ids.
 */
export function contestedClimbIds() {
  return new Set([...ACTIVE_CLIMBS, ...WARM_CLIMBS].map((config) => config.id));
}
