import assert from "node:assert/strict";
import {test} from "node:test";

import {
  CONTENT_READY_THRESHOLDS,
  contentReadinessFailures,
  unphotographableAccountPhoto,
  unphotographableDisplayName,
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
      {
        contextKey: "live_climb__a",
        completedCount: 1,
        totalClimbers: 1,
        holderCompletionOrder: 1,
      },
    ],
    daysSinceNewestClimb: 0,
    historyDepthDays: t.minimumHistoryDepthDays + 2,
    accountStandingRows: t.minimumAccountStandingRows + 2,
    contestedClimbBoards: t.minimumContestedBoards + 2,
    openFirstAscentBoards: t.minimumOpenFirstAscentBoards + 11,
    routineTemplateCount: t.minimumRoutineTemplates,
    accountDisplayName: "Morgan Hale",
    accountPhotoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-staging-fa7d5.firebasestorage.app/o/users%2Fu1%2Fprofile_pictures%2Flive-replay-v1-staging.jpg?alt=media&token=abc",
    seededRowsSampled: 896,
    seededRowsWithoutPhoto: 0,
    seededRowsWithPlaceholderName: 0,
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

test("a First Ascent claimed behind another climber is a contradiction, not a pass", () => {
  const failures = contentReadinessFailures(contentReadyState({
    firstAscentBoards: [{
      contextKey: "live_climb__empire-state-building",
      completedCount: 84,
      totalClimbers: 84,
      holderCompletionOrder: 12,
    }],
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /finished 12th/);
  assert.match(failures[0], /reads as first ever beside climbers who finished before it/);
});

// First ever, not only ever. Requiring the board to hold exactly one completion
// was a different and wrong claim: on staging other climbers do finish a board
// after the account claims it, and every one of them turned a legitimate First
// Ascent into a failure the seed had no way to fix.
test("a First Ascent stands on a board other climbers have since finished", () => {
  assert.deepEqual(contentReadinessFailures(contentReadyState({
    firstAscentBoards: [{
      contextKey: "live_climb__875-north-michigan-avenue",
      completedCount: 3,
      totalClimbers: 3,
      holderCompletionOrder: 1,
    }],
  })), []);
});

test("a First Ascent with no finisher document behind it fails", () => {
  const failures = contentReadinessFailures(contentReadyState({
    firstAscentBoards: [{
      contextKey: "live_climb__a",
      completedCount: 1,
      totalClimbers: 1,
      holderCompletionOrder: null,
    }],
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /nothing records that it finished at all/);
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

test("a name with a digit in it is not fit to be photographed", () => {
  assert.match(unphotographableDisplayName("Climber 061"), /reads as tooling/);
  assert.match(unphotographableDisplayName("Qa G4 Noname"), /reads as tooling/);
});

test("tooling placeholders are rejected however they are cased", () => {
  assert.match(unphotographableDisplayName("Content Capture"), /placeholder/);
  assert.match(unphotographableDisplayName("product tester"), /placeholder/);
  assert.match(unphotographableDisplayName("CHANGE ME"), /placeholder/);
});

test("an ordinary human name passes", () => {
  assert.equal(unphotographableDisplayName("Morgan Hale"), null);
  assert.equal(unphotographableDisplayName("Ren Kobayashi"), null);
  // One word is a name a real climber can publish, and several in staging do.
  assert.equal(unphotographableDisplayName("Bryce"), null);
});

// `SuppliedNameAdoption` publishes whatever Sign in with Apple or Google hands
// over, which is a given name and a family name. An initial for a surname is
// therefore something only a fixture produces, and a podium showed it: the seed's
// "Tyler R." stood next to the capture account's own "Tyler Pavay".
test("an initial for a surname reads as fixture data", () => {
  assert.match(unphotographableDisplayName("Sarah K."), /initial for a surname/);
  assert.match(unphotographableDisplayName("Tyler R"), /initial for a surname/);
  assert.match(unphotographableDisplayName("Mateo G."), /initial for a surname/);
});

test("an account publishing a placeholder name fails the contract", () => {
  const failures = contentReadinessFailures(contentReadyState({
    accountDisplayName: "Content Capture",
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /placeholder, not a climber/);
});

// The avatars live in Storage and the rows only carry URLs into them, so a run
// that could not resolve the set still writes a complete-looking board.
test("seeded rows with no photo fail the contract", () => {
  const failures = contentReadinessFailures(contentReadyState({
    seededRowsWithoutPhoto: 903,
    seededRowsSampled: 903,
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /903 of 903 seeded leaderboard rows carry no photo/);
});

test("seeded rows with a machine-shaped name fail the contract", () => {
  const failures = contentReadinessFailures(contentReadyState({
    seededRowsWithPlaceholderName: 23,
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /23 seeded leaderboard rows carry a machine-shaped/);
});

// The seeded-row sampler skips anything with isSynthetic !== true, which is
// exactly the real account - so its photo needs its own check or the one row
// every screenshot is centered on goes unexamined.
test("an account with no photo fails the contract", () => {
  const failures = contentReadinessFailures(contentReadyState({
    accountPhotoURL: "",
  }));

  assert.equal(failures.length, 1);
  assert.match(failures[0], /renders as an empty circle/);
});

test("an account photo the server would drop fails the contract", () => {
  assert.match(
    unphotographableAccountPhoto("https://example.test/avatar.jpg"),
    /not a Firebase Storage download URL/
  );
  assert.match(unphotographableAccountPhoto(null), /publishes no profile photo/);
});

test("a real Storage download URL passes", () => {
  assert.equal(
    unphotographableAccountPhoto(contentReadyState().accountPhotoURL),
    null
  );
});
