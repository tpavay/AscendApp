import assert from "node:assert/strict";
import {test} from "node:test";

import {
  ANONYMOUS_DISPLAY_NAME,
  compareVersions,
  renderedAchievement,
  renderedCompletionRow,
  renderedLeaderboardRow,
  renderedProfileWorkout,
  renderedPublicProfile,
  renderedRoutineTemplate,
  rendersPhotoAvatar,
  replayContextKey,
  resolvedIdentity,
  systemHandle,
} from "../lib/app-render-contract.mjs";

const PERIOD_START = Date.UTC(2026, 7, 24);
const STORAGE_PHOTO =
  "https://firebasestorage.googleapis.com:443/v0/b/ascend-staging-fa7d5.firebasestorage.app/" +
  "o/users%2Fu1%2Fprofile_pictures%2Flive-replay-v1-staging.jpg?alt=media&token=abc";

function timestamp(milliseconds) {
  return {toDate: () => new Date(milliseconds)};
}

function leaderboardDocument(overrides = {}) {
  return {
    userId: "u1",
    identityPolicyVersion: 1,
    identityState: "published",
    identityChangedAt: timestamp(PERIOD_START),
    timeFrame: "weekly",
    periodKey: "2026-W35",
    periodStartAt: timestamp(PERIOD_START),
    lastUpdated: timestamp(PERIOD_START),
    displayName: "Morgan Hale",
    photoURL: STORAGE_PHOTO,
    totalSteps: 42_000,
    totalFloors: 400,
    totalWorkouts: 9,
    totalDuration: 12_000,
    stepsPerMinute: 62,
    ...overrides,
  };
}

test("a complete leaderboard document renders with its published identity", () => {
  const judged = renderedLeaderboardRow(leaderboardDocument(), {periodStartAtMs: PERIOD_START});

  assert.equal(judged.renders, true);
  assert.equal(judged.row.displayName, "Morgan Hale");
  assert.equal(judged.row.photoURL, STORAGE_PHOTO);
  assert.equal(judged.row.usesGenericAvatar, false);
});

test("a leaderboard row from an older identity policy is dropped, and says so", () => {
  const judged = renderedLeaderboardRow(
    leaderboardDocument({identityPolicyVersion: 0}),
    {periodStartAtMs: PERIOD_START}
  );

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /identityPolicyVersion 0/u);
});

test("a published row with no identityChangedAt is dropped", () => {
  const judged = renderedLeaderboardRow(
    leaderboardDocument({identityChangedAt: null}),
    {periodStartAtMs: PERIOD_START}
  );

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /identityChangedAt/u);
});

test("a row belonging to another period is dropped even though the query returned it", () => {
  const judged = renderedLeaderboardRow(
    leaderboardDocument({periodStartAt: timestamp(PERIOD_START - 86_400_000)}),
    {periodStartAtMs: PERIOD_START}
  );

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /different period/u);
});

test("a row with nothing but zeroes to rank is dropped", () => {
  const judged = renderedLeaderboardRow(
    leaderboardDocument({
      totalSteps: 0,
      totalFloors: 0,
      totalWorkouts: 0,
      totalDuration: 0,
    }),
    {periodStartAtMs: PERIOD_START}
  );

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /zeroes/u);
});

test("an unpublished identity renders anonymously, photo and all", () => {
  const judged = renderedLeaderboardRow(
    leaderboardDocument({identityState: "deleted", identityChangedAt: null}),
    {periodStartAtMs: PERIOD_START}
  );

  assert.equal(judged.renders, true);
  assert.equal(judged.row.displayName, ANONYMOUS_DISPLAY_NAME);
  assert.equal(judged.row.photoURL, null);
  assert.equal(judged.row.usesGenericAvatar, true);
});

test("a row with no display name renders as the system handle the app invents", () => {
  const judged = renderedLeaderboardRow(
    leaderboardDocument({displayName: "   ", photoURL: null}),
    {periodStartAtMs: PERIOD_START}
  );

  assert.equal(judged.renders, true);
  assert.equal(judged.row.displayName, systemHandle("u1"));
  assert.match(judged.row.displayName, /^Climber [2346789AEFJMNQRT]{6}$/u);
  assert.equal(judged.row.usesGenericAvatar, true);
});

test("the system handle is stable per uid and never repeats a character back to back", () => {
  assert.equal(systemHandle("u1"), systemHandle("u1"));
  assert.notEqual(systemHandle("u1"), systemHandle("u2"));

  for (let index = 0; index < 400; index += 1) {
    const token = systemHandle(`uid-${index}`).replace("Climber ", "");
    assert.match(token, /^[2346789AEFJMNQRT]{6}$/u);
    assert.equal(/(.)\1/u.test(token), false, `${token} repeats a character`);
  }
});

test("a stored name of Anonymous Climber always renders anonymously", () => {
  const identity = resolvedIdentity({
    userId: "u1",
    displayName: " Anonymous Climber ",
    photoURL: STORAGE_PHOTO,
  });

  assert.equal(identity.displayName, ANONYMOUS_DISPLAY_NAME);
  assert.equal(identity.photoURL, null);
  assert.equal(identity.usesGenericAvatar, true);
});

test("a completion row with no duration is dropped, which is how a board loses a row it counted", () => {
  const judged = renderedCompletionRow("w1", {
    userId: "u1",
    displayName: "Morgan Hale",
    isSynthetic: true,
  });

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /completionDurationSeconds/u);
});

test("a completion row keeps its seeded identity and reports a lettered circle", () => {
  const judged = renderedCompletionRow("w1", {
    userId: "seed_u1",
    displayName: "Morgan Hale",
    completionDurationSeconds: 1006,
    stepsAtBucket: 900,
    isSynthetic: true,
  });

  assert.equal(judged.renders, true);
  assert.equal(judged.row.displayName, "Morgan Hale");
  assert.equal(judged.row.photoURL, null);
  assert.equal(rendersPhotoAvatar(judged.row.photoURL), false);
});

test("a photo on a host the identity projection would drop is not an avatar", () => {
  assert.equal(rendersPhotoAvatar(STORAGE_PHOTO), true);
  assert.equal(rendersPhotoAvatar("https://example.com/face.jpg"), false);
  assert.equal(rendersPhotoAvatar(null), false);
  assert.equal(rendersPhotoAvatar(""), false);
});

test("an achievement this build cannot name is dropped", () => {
  const unknown = renderedAchievement("a1", {
    type: "weekly_top_7",
    earnedAt: timestamp(PERIOD_START),
  });
  assert.equal(unknown.renders, false);
  assert.match(unknown.reason, /weekly_top_7/u);

  const undated = renderedAchievement("a2", {type: "first_ascent"});
  assert.equal(undated.renders, false);
  assert.match(undated.reason, /earnedAt/u);

  const good = renderedAchievement("a3", {
    type: "first_ascent",
    earnedAt: timestamp(PERIOD_START),
    climbId: "eiffel-tower",
  });
  assert.equal(good.renders, true);
  assert.equal(good.row.climbId, "eiffel-tower");
});

test("a profile session with an unknown source is dropped", () => {
  const judged = renderedProfileWorkout("w1", {
    name: "Empire State Building",
    startedAt: timestamp(PERIOD_START),
    source: "peloton",
  });

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /peloton/u);
});

test("a profile session the app can render carries its start date back", () => {
  const judged = renderedProfileWorkout("w1", {
    name: "Empire State Building",
    startedAt: timestamp(PERIOD_START),
    source: "headphone_motion",
    steps: 1_576,
  });

  assert.equal(judged.renders, true);
  assert.equal(judged.row.startedAtMs, PERIOD_START);
  assert.equal(judged.row.steps, 1_576);
});

test("a routine template published for a later build is invisible on the capture device", () => {
  const template = {
    status: "published",
    name: "Tower Intervals",
    minAppVersion: "1.1",
    intervals: [{durationSeconds: 120, level: 8}],
  };

  assert.equal(renderedRoutineTemplate("t1", template, {appVersion: "1.0"}).renders, false);
  assert.match(
    renderedRoutineTemplate("t1", template, {appVersion: "1.0"}).reason,
    /requires app version 1\.1/u
  );
  assert.equal(renderedRoutineTemplate("t1", template, {appVersion: "1.1"}).renders, true);
});

test("a routine template with no usable interval is dropped", () => {
  const judged = renderedRoutineTemplate("t1", {
    status: "published",
    name: "Tower Intervals",
    intervals: [{durationSeconds: 0}],
  }, {appVersion: "1.0"});

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /positive duration/u);
});

test("a draft routine template is never read at all", () => {
  const judged = renderedRoutineTemplate("t1", {
    status: "draft",
    name: "Tower Intervals",
    intervals: [{durationSeconds: 120}],
  }, {appVersion: "1.0"});

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /"draft"/u);
});

test("a public profile with no identityChangedAt renders as nothing to another climber", () => {
  const judged = renderedPublicProfile("u1", {
    identityPolicyVersion: 1,
    displayName: "Morgan Hale",
  });

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /identityChangedAt/u);
});

test("a missing public profile is reported as missing rather than as a blank name", () => {
  const judged = renderedPublicProfile("u1", null);

  assert.equal(judged.renders, false);
  assert.match(judged.reason, /no public profile document/u);
});

test("the replay context key matches the one the client builds", () => {
  assert.equal(
    replayContextKey("live_climb", "empire-state-building"),
    "live_climb__empire-state-building"
  );
  assert.equal(replayContextKey("just_climb", "global"), "just_climb__global");
  assert.equal(replayContextKey("live_climb", "st peter's"), "live_climb__st_peter_s");
});

test("version comparison treats a missing component as zero", () => {
  assert.equal(compareVersions("1.0", "1.0.0"), 0);
  assert.equal(compareVersions("1.0", "1.1"), -1);
  assert.equal(compareVersions("1.10", "1.9"), 1);
  assert.equal(compareVersions("2", "1.9.9"), 1);
});
