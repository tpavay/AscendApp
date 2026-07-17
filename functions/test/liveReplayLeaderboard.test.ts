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

test("rejects skipped attempts", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({
      sourceMetadata: makeSourceMetadata({stopReason: "skipped"}),
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

// Parsed with `requireEligibleParticipation: false` so the tracking-mode gate
// is the only thing that can reject the row. The eligibility gate would
// otherwise mask a regression here.
test("rejects routine tracking mode from the Just Climb replay context", () => {
  const document = makeWorkoutDocument({
    participations: [makeParticipation({contextType: "routine_template"})],
    sourceMetadata: makeSourceMetadata({
      climbId: undefined,
      routineTemplateId: "pyramid_climb",
      stopReason: "target_reached",
      trackingMode: "routine",
    }),
  });

  assert.equal(
    liveReplayLeaderboardTestHooks.parseJustClimbReplayPayload(document, {
      requireEligibleParticipation: false,
    }),
    null
  );
});

// Parsed with `requireEligibleParticipation: false` so the missing climbId is
// the only thing that can reject the row: a routine session has no landmark to
// publish against.
test(
  "rejects routine sessions without a climb id from the per-climb replay " +
    "context",
  () => {
    const document = makeWorkoutDocument({
      participations: [makeParticipation({contextType: "routine_template"})],
      sourceMetadata: makeSourceMetadata({
        climbId: undefined,
        routineTemplateId: "pyramid_climb",
        stopReason: "target_reached",
        trackingMode: "routine",
      }),
    });

    assert.equal(
      liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(document, {
        requireEligibleParticipation: false,
      }),
      null
    );
  }
);

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
      age: 31,
      avatarToken: "MC",
      displayName: "Maya C.",
      gender: "woman",
      locationCity: "Austin",
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

test("assigns next finisher after seeded completed rows", () => {
  assert.equal(
    liveReplayLeaderboardTestHooks.nextGlobalCompletionOrder({
      existingOrder: null,
      previousCompletedCount: 83,
    }),
    84
  );
});

test("assigns later finishers after existing completed count", () => {
  assert.equal(
    liveReplayLeaderboardTestHooks.nextGlobalCompletionOrder({
      existingOrder: null,
      previousCompletedCount: 84,
    }),
    85
  );
});

test("builds replay summary fields with coherent total climbers", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = liveReplayLeaderboardTestHooks.replaySummaryWrite({
    payload,
    completedCount: 84,
  });

  assert.deepEqual(write, {
    bucketIntervalSeconds: 10,
    completedCount: 84,
    contextId: "empire-state-building",
    contextType: "live_climb",
    schemaVersion: 1,
    targetStepCount: 2096,
    totalClimbers: 84,
  });
});

test("builds replay entry fields with context identity", () => {
  const updatedAt = "server-timestamp";
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = liveReplayLeaderboardTestHooks.replayEntryWrite({
    payload,
    userId: "user-a",
    entryId: "workout-a",
    publicUser: {
      age: 31,
      avatarToken: "MC",
      displayName: "Maya C.",
      gender: "woman",
      locationCity: "Austin",
      photoURL: null,
    },
    stepsAtBucket: 420,
    isBestForUser: true,
    updatedAt,
  });

  assert.deepEqual(write, {
    age: 31,
    avatarToken: "MC",
    completionDurationSeconds: 738,
    contextId: "empire-state-building",
    contextType: "live_climb",
    displayName: "Maya C.",
    finalSteps: 2096,
    gender: "woman",
    isBestForUser: true,
    locationCity: "Austin",
    photoURL: "",
    schemaVersion: 1,
    splitBucketCount: payload.splitSteps.length,
    splitIntervalSeconds: 10,
    stepsAtBucket: 420,
    updatedAt,
    userId: "user-a",
    workoutId: "workout-a",
  });
});

test("builds immutable rank-at-completion snapshot fields", () => {
  const rankedAt = "server-timestamp";
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = liveReplayLeaderboardTestHooks.completionRankSnapshotWrite({
    payload,
    userId: "user-a",
    entryId: "workout-a",
    rank: 18,
    completedCount: 62,
    rankedAt,
  });

  assert.deepEqual(write, {
    completedCount: 62,
    completionDurationSeconds: 738,
    contextId: "empire-state-building",
    contextType: "live_climb",
    finalSteps: 2096,
    rank: 18,
    rankedAt,
    rankingMetric: "completionDurationSeconds",
    schemaVersion: 1,
    targetStepCount: 2096,
    tiePolicy: "competition_rank_equal_durations_share_rank",
    userId: "user-a",
    workoutId: "workout-a",
  });
});

test("builds live climb publish status fields", () => {
  const updatedAt = "server-timestamp";
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const publishing = liveReplayLeaderboardTestHooks
    .liveClimbPublishStatusPublishingWrite({
      payload,
      userId: "user-a",
      entryId: "workout-a",
      updatedAt,
    });
  assert.equal(publishing.state, "publishing");
  assert.equal(publishing.climbId, "empire-state-building");
  assert.equal(publishing.workoutId, "workout-a");
  assert.equal(publishing.attemptSteps, 2096);

  const published = liveReplayLeaderboardTestHooks
    .liveClimbPublishStatusPublishedWrite({
      payload,
      userId: "user-a",
      entryId: "workout-a",
      updatedAt,
      rankAtCompletion: 18,
      completedCountAtCompletion: 62,
      finisherOrder: 47,
    });
  assert.equal(published.state, "published");
  assert.equal(published.rankAtCompletion, 18);
  assert.equal(published.completedCountAtCompletion, 62);
  assert.equal(published.finisherOrder, 47);

  const failed = liveReplayLeaderboardTestHooks
    .liveClimbPublishStatusFailedWrite({
      payload,
      userId: "user-a",
      entryId: "workout-a",
      updatedAt,
    }, new TypeError("internal failure"));
  assert.equal(failed.state, "failed_retryable");
  assert.equal(failed.lastErrorCode, "TypeError");
  assert.equal(failed.lastErrorMessageSafe, "Leaderboard sync failed.");
});

test("preserves rank snapshot when workout republishes same climb", () => {
  const beforePayload = liveReplayLeaderboardTestHooks
    .parseLiveClimbReplayPayload(
      makeWorkoutDocument(),
      {requireEligibleParticipation: false}
    );
  const afterPayload = liveReplayLeaderboardTestHooks
    .parseLiveClimbReplayPayload(
      makeWorkoutDocument({durationSeconds: 742}),
      {requireEligibleParticipation: true}
    );

  assert.ok(beforePayload);
  assert.ok(afterPayload);
  assert.equal(
    liveReplayLeaderboardTestHooks.shouldDeleteCompletionRankSnapshot(
      beforePayload,
      [afterPayload]
    ),
    false
  );
});

test("deletes rank snapshot when workout leaves climb context", () => {
  const beforePayload = liveReplayLeaderboardTestHooks
    .parseLiveClimbReplayPayload(
      makeWorkoutDocument(),
      {requireEligibleParticipation: false}
    );
  const afterPayload = liveReplayLeaderboardTestHooks
    .parseLiveClimbReplayPayload(
      makeWorkoutDocument({
        sourceMetadata: makeSourceMetadata({
          climbId: "burj-khalifa",
        }),
      }),
      {requireEligibleParticipation: true}
    );

  assert.ok(beforePayload);
  assert.ok(afterPayload);
  assert.equal(
    liveReplayLeaderboardTestHooks.shouldDeleteCompletionRankSnapshot(
      beforePayload,
      [afterPayload]
    ),
    true
  );
});

test("builds first finisher status with permanent completion order", () => {
  const completedAt = "server-timestamp";
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = liveReplayLeaderboardTestHooks.finisherStatusWrite({
    payload,
    userId: "user-a",
    entryId: "workout-a",
    publicUser: {
      age: 31,
      avatarToken: "MC",
      displayName: "Maya C.",
      gender: "woman",
      locationCity: "Austin",
      photoURL: null,
    },
    globalCompletionOrder: 47,
    existingData: undefined,
    completedAt,
  });

  assert.deepEqual(write, {
    age: 31,
    avatarToken: "MC",
    bestCompletionDurationSeconds: 738,
    bestWorkoutId: "workout-a",
    displayName: "Maya C.",
    firstCompletedAt: completedAt,
    firstWorkoutId: "workout-a",
    gender: "woman",
    globalCompletionOrder: 47,
    locationCity: "Austin",
    photoURL: "",
    schemaVersion: 1,
    updatedAt: completedAt,
    userId: "user-a",
  });
});

test("preserves finisher order on later attempts", () => {
  const completedAt = "server-timestamp";
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({durationSeconds: 760}),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = liveReplayLeaderboardTestHooks.finisherStatusWrite({
    payload,
    userId: "user-a",
    entryId: "workout-b",
    publicUser: {
      avatarToken: "MC",
      displayName: "Maya C.",
      photoURL: "https://example.com/maya.jpg",
    },
    globalCompletionOrder: 47,
    existingData: {
      bestCompletionDurationSeconds: 738,
      firstWorkoutId: "workout-a",
      globalCompletionOrder: 47,
    },
    completedAt,
  });

  assert.deepEqual(write, {
    avatarToken: "MC",
    displayName: "Maya C.",
    globalCompletionOrder: 47,
    photoURL: "https://example.com/maya.jpg",
    schemaVersion: 1,
    updatedAt: completedAt,
    userId: "user-a",
  });
});

test("races a repeat finisher as one opponent on their fastest attempt", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-slow", durationSeconds: 900}),
    makeAttemptEntry({workoutId: "workout-fast", durationSeconds: 700}),
    makeAttemptEntry({workoutId: "workout-middling", durationSeconds: 800}),
  ];

  const bestAttempts = applyFlagUpdates(
    attempts,
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(attempts)
  ).filter((attempt) => attempt.isBestForUser);

  assert.deepEqual(
    bestAttempts.map((attempt) => attempt.workoutId),
    ["workout-fast"]
  );
});

test("resolves tied completions to one deterministic best attempt", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-b", durationSeconds: 700}),
    makeAttemptEntry({workoutId: "workout-a", durationSeconds: 700}),
  ];

  assert.equal(
    liveReplayLeaderboardTestHooks.bestAttemptWorkoutId(attempts),
    "workout-a"
  );
  const reversedAttempts = [...attempts].reverse();
  assert.equal(
    liveReplayLeaderboardTestHooks.bestAttemptWorkoutId(reversedAttempts),
    "workout-a"
  );
});

test("demotes the standing best when a faster attempt lands", () => {
  const attempts = [
    makeAttemptEntry({
      workoutId: "workout-old",
      durationSeconds: 800,
      isBestForUser: true,
    }),
    makeAttemptEntry({workoutId: "workout-new", durationSeconds: 700}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(attempts),
    [
      {workoutId: "workout-old", splitBucketCount: 4, isBestForUser: false},
      {workoutId: "workout-new", splitBucketCount: 4, isBestForUser: true},
    ]
  );
});

test("promotes the next best when a flagged best attempt is deleted", () => {
  const remainingAttempts = [
    makeAttemptEntry({workoutId: "workout-slow", durationSeconds: 900}),
    makeAttemptEntry({workoutId: "workout-middling", durationSeconds: 800}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(remainingAttempts),
    [{workoutId: "workout-middling", splitBucketCount: 4, isBestForUser: true}]
  );
});

test("settles to zero writes once best-per-user flags are correct", () => {
  const attempts = [
    makeAttemptEntry({
      workoutId: "workout-fast",
      durationSeconds: 700,
      isBestForUser: true,
    }),
    makeAttemptEntry({workoutId: "workout-slow", durationSeconds: 900}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(attempts),
    []
  );
});

test("leaves a single completion flagged as its own best", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-only", durationSeconds: 700}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(attempts),
    [{workoutId: "workout-only", splitBucketCount: 4, isBestForUser: true}]
  );
});

test("derives bucket span for entries predating the flag", () => {
  assert.equal(
    liveReplayLeaderboardTestHooks.attemptSplitBucketCount({
      completionDurationSeconds: 738,
      splitIntervalSeconds: 10,
    }),
    74
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.attemptSplitBucketCount({
      completionDurationSeconds: 738,
      splitIntervalSeconds: 10,
      splitBucketCount: 80,
    }),
    80
  );
});

test("reads published attempts from bucket-zero entry documents", () => {
  assert.deepEqual(
    liveReplayLeaderboardTestHooks.userAttemptEntry(
      {
        completionDurationSeconds: 738,
        isBestForUser: true,
        splitBucketCount: 74,
        workoutId: "workout-a",
      },
      "workout-a"
    ),
    {
      workoutId: "workout-a",
      completionDurationSeconds: 738,
      splitBucketCount: 74,
      isBestForUser: true,
    }
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.userAttemptEntry({}, "workout-a"),
    null
  );
});

/**
 * Builds one published attempt as reconciliation sees it.
 * @param {object} overrides Attempt overrides.
 * @param {string} overrides.workoutId Owning workout ID.
 * @param {number} overrides.durationSeconds Completion duration.
 * @param {boolean} [overrides.isBestForUser] Currently published flag.
 * @return {object} Published attempt.
 */
function makeAttemptEntry(overrides: {
  workoutId: string;
  durationSeconds: number;
  isBestForUser?: boolean;
}): {
  workoutId: string;
  completionDurationSeconds: number;
  splitBucketCount: number;
  isBestForUser: boolean;
} {
  return {
    workoutId: overrides.workoutId,
    completionDurationSeconds: overrides.durationSeconds,
    splitBucketCount: 4,
    isBestForUser: overrides.isBestForUser ?? false,
  };
}

/**
 * Applies reconciliation updates the way BulkWriter would.
 * @param {object[]} attempts Published attempts.
 * @param {object[]} updates Flag updates to apply.
 * @return {object[]} Attempts carrying their reconciled flags.
 */
function applyFlagUpdates(
  attempts: ReturnType<typeof makeAttemptEntry>[],
  updates: {workoutId: string; isBestForUser: boolean}[]
): ReturnType<typeof makeAttemptEntry>[] {
  return attempts.map((attempt) => {
    const update = updates.find(
      (candidate) => candidate.workoutId === attempt.workoutId
    );

    return update ?
      {...attempt, isBestForUser: update.isBestForUser} :
      attempt;
  });
}

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
