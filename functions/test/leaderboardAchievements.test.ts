import test from "node:test";
import assert from "node:assert/strict";
import {
  leaderboardAchievementsTestHooks,
} from "../src/leaderboardAchievements.js";

const {achievementType, profileStatsIncrement} =
  leaderboardAchievementsTestHooks;

/**
 * Lists the profile band counters a finish at the given rank increments.
 * @param {number} rank Final leaderboard rank for the closed period.
 * @return {string[]} Sorted profile_stats field names, minus lastUpdated.
 */
function incrementedBands(rank: number): string[] {
  return Object.keys(profileStatsIncrement(rank))
    .filter((key) => key !== "lastUpdated")
    .sort();
}

test("a top 1 finish counts cumulatively through every band", () => {
  assert.deepEqual(incrementedBands(1), [
    "top_100_finishes",
    "top_10_finishes",
    "top_1_finishes",
    "top_3_finishes",
  ]);
});

test("a top 3 finish does not count toward top 1", () => {
  assert.deepEqual(incrementedBands(3), [
    "top_100_finishes",
    "top_10_finishes",
    "top_3_finishes",
  ]);
});

test("a top 10 finish counts only toward top 10 and top 100", () => {
  assert.deepEqual(incrementedBands(10), [
    "top_100_finishes",
    "top_10_finishes",
  ]);
});

test("a top 100 finish counts only toward top 100", () => {
  assert.deepEqual(incrementedBands(100), ["top_100_finishes"]);
});

test("a finish outside the top 100 counts toward no band", () => {
  assert.deepEqual(incrementedBands(101), []);
});

test("profile stat counters never write the misnamed _weeks fields", () => {
  for (const rank of [1, 3, 10, 100]) {
    const written = Object.keys(profileStatsIncrement(rank));
    const misnamed = written.filter((key) => key.endsWith("_weeks"));
    assert.deepEqual(misnamed, [], `rank ${rank} wrote ${misnamed.join(", ")}`);
  }
});

test("achievement records stay namespaced per time frame and band", () => {
  // The time frame lives here, on the record, and nowhere else. The profile
  // band counters are deliberately frame-agnostic -- badges show one total per
  // band with no period noun -- so a monthly or yearly finish lands on the same
  // counter as a weekly one. The history sheet reads the frame off these
  // records. If that ever needs to change, it is a product decision about what
  // a badge counts, not a bug in the counters.
  assert.equal(achievementType("weekly", 1), "weekly_top_1");
  assert.equal(achievementType("monthly", 2), "monthly_top_3");
  assert.equal(achievementType("yearly", 10), "yearly_top_10");
  assert.equal(achievementType("weekly", 42), "weekly_top_100");
});
