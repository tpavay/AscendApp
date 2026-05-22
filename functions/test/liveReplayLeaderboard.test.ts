import test from "node:test";
import assert from "node:assert/strict";
import {liveReplayLeaderboardTestHooks} from "../src/liveReplayLeaderboard.js";

test("parses full target-reached live climb completions", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload?.contextId, "empire-state-building");
  assert.equal(payload?.finalSteps, 2096);
  assert.equal(payload?.targetStepCount, 2096);
});

test("rejects user-stopped live climb attempts", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({
      steps: 92,
      sourceMetadata: makeSourceMetadata({
        stopReason: "user_stopped",
        targetStepCount: 2096,
        climbTargetStepCount: 2096,
      }),
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

test("rejects resumed partial target hits", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({
      steps: 92,
      sourceMetadata: makeSourceMetadata({
        stopReason: "target_reached",
        targetStepCount: 92,
        climbTargetStepCount: 2096,
        attemptBaselineSteps: 2004,
      }),
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

test("rejects target-reached rows without eligible climb participation", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({
      participations: [makeParticipation({leaderboardEligible: false})],
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

test("detects permanent First Ascent claims on replay summaries", () => {
  assert.equal(
    liveReplayLeaderboardTestHooks.leaderboardHasFirstAscent(undefined),
    false
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.leaderboardHasFirstAscent({
      firstAscentCompletedAt: "timestamp",
    }),
    true
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.leaderboardHasFirstAscent({
      firstAscentUserId: "user-a",
    }),
    true
  );
});

test("builds First Ascent replay summary fields", () => {
  const claimedAt = "server-timestamp";
  const write = liveReplayLeaderboardTestHooks.firstAscentWrite({
    userId: "user-a",
    entryId: "workout-a",
    publicUser: {
      avatarToken: "MC",
      displayName: "Maya C.",
      photoURL: null,
    },
    claimedAt,
  });

  assert.deepEqual(write, {
    firstAscentAvatarToken: "MC",
    firstAscentCompletedAt: claimedAt,
    firstAscentDisplayName: "Maya C.",
    firstAscentPhotoURL: "",
    firstAscentUserId: "user-a",
    firstAscentWorkoutId: "workout-a",
  });
});

/**
 * Builds a private workout backup document.
 * @param {Record<string, unknown>} overrides Document overrides.
 * @return {Record<string, unknown>} Workout backup document.
 */
function makeWorkoutDocument(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    durationSeconds: 738,
    participations: [makeParticipation()],
    source: "headphone_motion",
    sourceMetadata: makeSourceMetadata(),
    steps: 2096,
    ...overrides,
  };
}

/**
 * Builds a workout participation payload.
 * @param {Record<string, unknown>} overrides Participation overrides.
 * @return {Record<string, unknown>} Participation payload.
 */
function makeParticipation(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    contextType: "climb_attempt",
    leaderboardEligible: true,
    ...overrides,
  };
}

/**
 * Builds encoded headphone-motion source metadata.
 * @param {Record<string, unknown>} overrides Metadata overrides.
 * @return {string} JSON metadata string.
 */
function makeSourceMetadata(
  overrides: Record<string, unknown> = {}
): string {
  return JSON.stringify({
    climbId: "empire-state-building",
    climbTargetStepCount: 2096,
    splitIntervalSeconds: 10,
    splitSteps: [0, 28, 56, 84, 112, 140],
    stopReason: "target_reached",
    targetStepCount: 2096,
    trackingMode: "live_climb",
    ...overrides,
  });
}
