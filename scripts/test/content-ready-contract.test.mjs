import assert from "node:assert/strict";
import {test} from "node:test";

import {
  CONTENT_READY_THRESHOLDS,
  contentReadinessFailures,
} from "../seed/lib/content-ready-contract.mjs";

function contentReadyState(overrides = {}) {
  const t = CONTENT_READY_THRESHOLDS;
  return {
    hasPublicProfile: true,
    hasProfileStats: true,
    workoutCount: t.minimumWorkouts + 2,
    climbsCompleted: t.minimumClimbsCompleted + 1,
    firstAscentsHeld: t.minimumFirstAscentsHeld,
    firstAscentBoards: [
      {contextKey: "live_climb__a", completedCount: 1, totalClimbers: 1},
    ],
    daysSinceNewestClimb: 0,
    historyDepthDays: t.minimumHistoryDepthDays + 2,
    accountStandingRows: t.minimumAccountStandingRows + 2,
    contestedClimbBoards: t.minimumContestedBoards + 2,
    openFirstAscentBoards: t.minimumOpenFirstAscentBoards + 11,
    routineTemplateCount: t.minimumRoutineTemplates,
    incoherentBoards: [],
    ...overrides,
  };
}

test("a fully seeded environment satisfies the content-ready contract", () => {
  assert.deepEqual(contentReadinessFailures(contentReadyState()), []);
});

test("a stale newest session fails, because a screenshot shows the date", () => {
  const failures = contentReadinessFailures(contentReadyState({
    daysSinceNewestClimb: CONTENT_READY_THRESHOLDS.maximumDaysSinceNewestClimb + 1,
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /reads as stale/);
});

test("an account with no sessions fails on the emptiness, not the recency", () => {
  const failures = contentReadinessFailures(contentReadyState({
    daysSinceNewestClimb: null,
    historyDepthDays: null,
    workoutCount: 0,
    climbsCompleted: 0,
  }));

  assert.ok(failures.some((failure) => failure.includes("no sessions at all")));
});

test("a First Ascent held on a contested board is a contradiction, not a pass", () => {
  const failures = contentReadinessFailures(contentReadyState({
    firstAscentBoards: [
      {contextKey: "live_climb__empire-state-building", completedCount: 84, totalClimbers: 84},
    ],
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /reads as first ever beside climbers who finished before it/);
});

test("boards whose two population fields disagree are reported by name", () => {
  const failures = contentReadinessFailures(contentReadyState({
    incoherentBoards: ["live_climb__taipei-101"],
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /live_climb__taipei-101/);
  assert.match(failures[0], /ranks against a population it does not have/);
});

test("seeding over every claimable slot fails the contract", () => {
  const failures = contentReadinessFailures(contentReadyState({
    openFirstAscentBoards: 4,
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /climb boards with an open First Ascent/);
});

test("every shortfall is reported, not just the first", () => {
  const failures = contentReadinessFailures(contentReadyState({
    hasProfileStats: false,
    climbsCompleted: 0,
    firstAscentsHeld: 0,
    firstAscentBoards: [],
    contestedClimbBoards: 0,
  }));

  assert.equal(failures.length, 4);
  assert.ok(failures.some((failure) => failure.includes("no profile stats")));
  assert.ok(failures.some((failure) => failure.includes("landmark climbs completed")));
  assert.ok(failures.some((failure) => failure.includes("First Ascents held")));
  assert.ok(failures.some((failure) => failure.includes("climbers")));
});
