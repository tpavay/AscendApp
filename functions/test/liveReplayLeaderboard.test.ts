import test from "node:test";
import assert from "node:assert/strict";
import {
  IdentityProtectedTransactionPort,
  PublicUserSnapshot,
  liveReplayLeaderboardTestHooks,
  runIdentityProtectedTransaction,
} from "../src/liveReplayLeaderboard.js";

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

// The client's `leaderboardEligible` boolean is an unbacked assertion, so the
// gate derives eligibility from the workout instead and ignores the flag in
// both directions: it can neither grant a row nor withhold one.
test("ignores a client leaderboardEligible: false on a real completion", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({
      participations: [makeParticipation({leaderboardEligible: false})],
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload?.contextId, "empire-state-building");
  assert.equal(payload?.firstAscentEligible, true);
});

test("ignores a client leaderboardEligible: true without the evidence", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({
      steps: 92,
      participations: [makeParticipation({leaderboardEligible: true})],
      sourceMetadata: makeSourceMetadata({stopReason: "user_stopped"}),
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

// A missing climb-attempt participation is the legacy document shape, not an
// eligibility signal: it drops out of the modern gate and into the legacy
// fallback, which publishes a row but never a First Ascent.
test("routes participation-less backups through the legacy fallback", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument({participations: []}),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload?.contextId, "empire-state-building");
  assert.equal(payload?.firstAscentEligible, false);
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
      identityState: "published",
      locationCity: "Austin",
      photoURL: null,
    },
    claimedAt,
  });

  assert.deepEqual(write, {
    firstAscentAvatarToken: "MC",
    firstAscentCompletedAt: claimedAt,
    firstAscentDisplayName: "Maya C.",
    firstAscentIdentityState: "published",
    firstAscentIsSynthetic: false,
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
    source: "live",
    targetStepCount: 2096,
    totalClimbers: 84,
  });
});

// The seed stamps `seeded` on a board it fills with synthetic competitors, and
// operators read that to mean nobody real is on it. Nothing used to move it off
// that value, so a board taking genuine finishes still reported itself seeded.
test("a publish stops a seeded board calling itself seeded", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = liveReplayLeaderboardTestHooks.replaySummaryWrite({
    payload,
    completedCount: 1,
  });

  assert.equal(write.source, "live");
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
      identityState: "published",
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
    identityState: "published",
    isBestForUser: true,
    isSynthetic: false,
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
      identityState: "published",
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
    identityState: "published",
    isSynthetic: false,
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
      identityState: "published",
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
    identityState: "published",
    isSynthetic: false,
    photoURL: "https://example.com/maya.jpg",
    schemaVersion: 1,
    updatedAt: completedAt,
    userId: "user-a",
  });
});

test("collapses repeat finishers in per-climb and template contexts", () => {
  const collapsesFor = (contextType: string) =>
    liveReplayLeaderboardTestHooks.collapsesRepeatFinishers({
      contextType,
    } as Parameters<
      typeof liveReplayLeaderboardTestHooks.collapsesRepeatFinishers
    >[0]);

  assert.equal(collapsesFor("live_climb"), true);
  assert.equal(collapsesFor("routine_template"), true);
  assert.equal(collapsesFor("just_climb"), false);
  // A user-created routine is a private board that never publishes.
  assert.equal(collapsesFor("routine"), false);
});

test("races every Just Climb attempt as its own opponent", () => {
  const payload = liveReplayLeaderboardTestHooks.parseJustClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);
  assert.equal(payload.contextType, "just_climb");

  // An open Just Climb session has no step target, so its shortest attempt is
  // the one the climber quit earliest. Flagging it would race their weakest
  // curve and drop their stronger session out of the field entirely.
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {
      bestCompletionDurationSeconds: 900,
      bestWorkoutId: "workout-b",
    }),
    null
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {}),
    null
  );
});

test("leaves the flag field off entries that race every attempt", () => {
  const payload = liveReplayLeaderboardTestHooks.parseJustClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = liveReplayLeaderboardTestHooks.replayEntryWrite({
    payload,
    userId: "user-a",
    entryId: "workout-a",
    publicUser: {
      avatarToken: "MC",
      displayName: "Maya C.",
      identityState: "published",
      photoURL: null,
    },
    stepsAtBucket: 420,
    isBestForUser: liveReplayLeaderboardTestHooks.seedBestForUser(
      payload,
      "workout-a",
      undefined
    ),
    updatedAt: "server-timestamp",
  });

  // Absent rather than false: Firestore equality never matches a missing field,
  // so an unflagged context cannot be filtered into a wrong winner.
  assert.equal("isBestForUser" in write, false);
});

test("copies account-authored identity from the public profile mirror", () => {
  const snapshot = liveReplayLeaderboardTestHooks.publicUserSnapshotFromData(
    {
      age: 31,
      displayName: "Maya Chen",
      gender: "woman",
      location_city: "Austin",
      photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
    },
    "user-a"
  );

  assert.deepEqual(snapshot, {
    age: 31,
    avatarToken: "MC",
    displayName: "Maya Chen",
    gender: "woman",
    identityState: "published",
    locationCity: "Austin",
    photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
  });
});

test("uses the stable uid handle when a mirror has no authored name", () => {
  const snapshot = liveReplayLeaderboardTestHooks.publicUserSnapshotFromData(
    {},
    "user-123"
  );

  assert.equal(snapshot.displayName, "Climber QRN9QT");
  assert.equal(snapshot.avatarToken, "CQ");
  assert.equal(snapshot.photoURL, null);
});

test(
  "late replay projections retry with identity edited after enumeration",
  async () => {
    const v1 = identitySnapshot(
      "Maya V1",
      "https://example.com/v1.jpg"
    );
    const v2 = identitySnapshot("Maya V2", null);
    const port = new RacingReplayIdentityPort(v1);

    port.beforeFirstCommit = () => {
      // The profile propagation trigger has already enumerated and found no
      // target. The publisher must still conflict on its source read and retry.
      port.propagationEnumeratedTargetCount = port.target === null ? 0 : 3;
      port.replaceSource(v2);
    };

    await runIdentityProtectedTransaction(
      port,
      "user-a",
      async (transaction, publicUser) => {
        transaction.writeAllIdentityTargets(publicUser);
      }
    );

    assert.equal(port.propagationEnumeratedTargetCount, 0);
    assert.equal(port.transactionAttempts, 2);
    assert.deepEqual(port.target, {
      entry: v2,
      finisher: v2,
      firstAscent: v2,
    });
    assert.equal(port.target?.entry.photoURL, null);
  }
);

test("late replay identity is anonymous after account deletion", () => {
  const fromSentinel =
    liveReplayLeaderboardTestHooks.currentPublicUserSnapshotFromData(
      {
        displayName: "Anonymous Climber",
        photoURL: "https://example.com/must-not-survive.jpg",
      },
      {displayName: "Maya Chen"},
      "user-a"
    );
  const fromDeletedRoot =
    liveReplayLeaderboardTestHooks.currentPublicUserSnapshotFromData(
      {
        displayName: "Maya Chen",
        photoURL: "https://example.com/must-not-survive.jpg",
      },
      undefined,
      "user-a"
    );

  for (const snapshot of [fromSentinel, fromDeletedRoot]) {
    assert.deepEqual(snapshot, {
      avatarToken: "",
      displayName: "Anonymous Climber",
      identityState: "deleted",
      photoURL: null,
    });
  }
});

test("missing public mirror never publishes surviving private identity", () => {
  const snapshot =
    liveReplayLeaderboardTestHooks.currentPublicUserSnapshotFromData(
      undefined,
      {
        age: 31,
        displayName: "Private Maya",
        gender: "woman",
        location_city: "Austin",
        profilePictureURL: "https://example.com/reported-private-photo.jpg",
      },
      "user-a"
    );

  assert.deepEqual(snapshot, {
    avatarToken: "",
    displayName: "Anonymous Climber",
    identityState: "pending_public_profile",
    photoURL: null,
  });
});

test(
  "mirror deletion racing late creation writes every target as pending",
  async () => {
    const validMirror = identitySnapshot(
      "Maya Public",
      "https://example.com/public.jpg"
    );
    const privateRoot = {
      age: 31,
      displayName: "Private Maya",
      gender: "woman",
      location_city: "Austin",
      profilePictureURL: "https://example.com/reported-private-photo.jpg",
    };
    const missingMirror =
      liveReplayLeaderboardTestHooks.currentPublicUserSnapshotFromData(
        undefined,
        privateRoot,
        "user-a"
      );
    const port = new RacingReplayIdentityPort(validMirror);

    port.beforeFirstCommit = () => {
      port.replaceSource(missingMirror);
    };

    await runIdentityProtectedTransaction(
      port,
      "user-a",
      async (transaction, publicUser) => {
        transaction.writeAllIdentityTargets(publicUser);
      }
    );

    assert.equal(port.transactionAttempts, 2);
    assert.deepEqual(port.target, {
      entry: missingMirror,
      finisher: missingMirror,
      firstAscent: missingMirror,
    });
    assert.equal(
      JSON.stringify(port.target).includes("reported-private-photo"),
      false
    );
    assert.equal(JSON.stringify(port.target).includes("Private Maya"), false);
    assert.equal(JSON.stringify(port.target).includes("Austin"), false);
    assert.equal(
      port.target?.entry.identityState,
      "pending_public_profile"
    );
  }
);

test("seeds the flag on a per-climb attempt without demoting the best", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);
  assert.equal(payload.finalDurationSeconds, 738);

  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {}),
    true
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {
      bestCompletionDurationSeconds: 900,
      bestWorkoutId: "workout-b",
    }),
    true
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {
      bestCompletionDurationSeconds: 738,
      bestWorkoutId: "workout-a",
    }),
    true
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {
      bestCompletionDurationSeconds: 700,
      bestWorkoutId: "workout-b",
    }),
    false
  );
});

// A routine collapses repeats too, but on steps: a higher-steps attempt or a
// republish of the standing best seeds the live flag; a weaker one does not.
test("seeds the flag on a routine attempt from its steps", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);
  assert.equal(payload.finalSteps, 1840);

  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {}),
    true
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {
      bestFinalSteps: 1700,
      bestWorkoutId: "workout-b",
    }),
    true
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {
      bestFinalSteps: 1840,
      bestWorkoutId: "workout-a",
    }),
    true
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.seedBestForUser(payload, "workout-a", {
      bestFinalSteps: 1900,
      bestWorkoutId: "workout-b",
    }),
    false
  );
});

test("races a repeat finisher as one opponent on their fastest attempt", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-slow", rankingValue: 900}),
    makeAttemptEntry({workoutId: "workout-fast", rankingValue: 700}),
    makeAttemptEntry({workoutId: "workout-middling", rankingValue: 800}),
  ];

  const bestAttempts = applyFlagUpdates(
    attempts,
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(
      attempts,
      "live_climb"
    )
  ).filter((attempt) => attempt.isBestForUser);

  assert.deepEqual(
    bestAttempts.map((attempt) => attempt.workoutId),
    ["workout-fast"]
  );
});

// A routine ranks on steps, so a climber's best is their highest-steps attempt,
// the inverse of the fastest-time rule a climb board uses.
test("races a routine finisher as one opponent on their highest steps", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-low", rankingValue: 1200}),
    makeAttemptEntry({workoutId: "workout-high", rankingValue: 1840}),
    makeAttemptEntry({workoutId: "workout-mid", rankingValue: 1500}),
  ];

  const bestAttempts = applyFlagUpdates(
    attempts,
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(
      attempts,
      "routine_template"
    )
  ).filter((attempt) => attempt.isBestForUser);

  assert.deepEqual(
    bestAttempts.map((attempt) => attempt.workoutId),
    ["workout-high"]
  );
});

test("resolves tied completions to one deterministic best attempt", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-b", rankingValue: 700}),
    makeAttemptEntry({workoutId: "workout-a", rankingValue: 700}),
  ];

  assert.equal(
    liveReplayLeaderboardTestHooks.bestAttemptWorkoutId(attempts, "live_climb"),
    "workout-a"
  );
  const reversedAttempts = [...attempts].reverse();
  assert.equal(
    liveReplayLeaderboardTestHooks.bestAttemptWorkoutId(
      reversedAttempts,
      "live_climb"
    ),
    "workout-a"
  );
});

// Steps are coarse integers, so routine ties are common; the workout ID breaks
// them the same way in both directions so recomputes never reshuffle.
test("resolves tied routine step counts on the workout id", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-b", rankingValue: 1840}),
    makeAttemptEntry({workoutId: "workout-a", rankingValue: 1840}),
  ];

  assert.equal(
    liveReplayLeaderboardTestHooks.bestAttemptWorkoutId(
      attempts,
      "routine_template"
    ),
    "workout-a"
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.bestAttemptWorkoutId(
      [...attempts].reverse(),
      "routine_template"
    ),
    "workout-a"
  );
});

test("demotes the standing best when a faster attempt lands", () => {
  const attempts = [
    makeAttemptEntry({
      workoutId: "workout-old",
      rankingValue: 800,
      isBestForUser: true,
    }),
    makeAttemptEntry({workoutId: "workout-new", rankingValue: 700}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(
      attempts,
      "live_climb"
    ),
    [
      {workoutId: "workout-old", splitBucketCount: 4, isBestForUser: false},
      {workoutId: "workout-new", splitBucketCount: 4, isBestForUser: true},
    ]
  );
});

test("promotes the next best when a flagged best attempt is deleted", () => {
  const remainingAttempts = [
    makeAttemptEntry({workoutId: "workout-slow", rankingValue: 900}),
    makeAttemptEntry({workoutId: "workout-middling", rankingValue: 800}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(
      remainingAttempts,
      "live_climb"
    ),
    [{workoutId: "workout-middling", splitBucketCount: 4, isBestForUser: true}]
  );
});

test("settles to zero writes once best-per-user flags are correct", () => {
  const attempts = [
    makeAttemptEntry({
      workoutId: "workout-fast",
      rankingValue: 700,
      isBestForUser: true,
    }),
    makeAttemptEntry({workoutId: "workout-slow", rankingValue: 900}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(
      attempts,
      "live_climb"
    ),
    []
  );
});

test("leaves a single completion flagged as its own best", () => {
  const attempts = [
    makeAttemptEntry({workoutId: "workout-only", rankingValue: 700}),
  ];

  assert.deepEqual(
    liveReplayLeaderboardTestHooks.bestForUserFlagUpdates(
      attempts,
      "live_climb"
    ),
    [{workoutId: "workout-only", splitBucketCount: 4, isBestForUser: true}]
  );
});

test("sweeps every bucket for entries predating the flag", () => {
  assert.equal(
    liveReplayLeaderboardTestHooks.attemptSplitBucketCount({
      completionDurationSeconds: 738,
      splitIntervalSeconds: 10,
    }),
    360
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.attemptSplitBucketCount({
      completionDurationSeconds: 738,
      splitIntervalSeconds: 10,
      splitBucketCount: 80,
    }),
    80
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.attemptSplitBucketCount({
      completionDurationSeconds: 738,
      splitIntervalSeconds: 10,
      splitBucketCount: 4_000,
    }),
    360
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
      "workout-a",
      "live_climb"
    ),
    {
      workoutId: "workout-a",
      rankingValue: 738,
      splitBucketCount: 74,
      isBestForUser: true,
    }
  );
  // A routine attempt ranks on its steps, read from the same entry document.
  assert.deepEqual(
    liveReplayLeaderboardTestHooks.userAttemptEntry(
      {
        completionDurationSeconds: 1200,
        finalSteps: 1840,
        splitBucketCount: 74,
        workoutId: "workout-a",
      },
      "workout-a",
      "routine_template"
    ),
    {
      workoutId: "workout-a",
      rankingValue: 1840,
      splitBucketCount: 74,
      isBestForUser: false,
    }
  );
  assert.equal(
    liveReplayLeaderboardTestHooks.userAttemptEntry(
      {},
      "workout-a",
      "live_climb"
    ),
    null
  );
  // A routine row missing its steps is unusable even with a duration present.
  assert.equal(
    liveReplayLeaderboardTestHooks.userAttemptEntry(
      {completionDurationSeconds: 1200},
      "workout-a",
      "routine_template"
    ),
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
  rankingValue: number;
  isBestForUser?: boolean;
}): {
  workoutId: string;
  rankingValue: number;
  splitBucketCount: number;
  isBestForUser: boolean;
} {
  return {
    workoutId: overrides.workoutId,
    rankingValue: overrides.rankingValue,
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

test("publishes a completed routine into its template's replay context", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument(),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload?.contextType, "routine_template");
  assert.equal(payload?.contextId, "social-pyramid-20");
  assert.equal(payload?.contextKey, "routine_template__social-pyramid-20");
  assert.equal(payload?.finalSteps, 1840);
  assert.equal(payload?.targetDurationSeconds, 1200);
});

// A skip burns the routine clock without taking steps, so the client saves the
// session as `skipped`. Publishing it would rank a shortcut against full runs.
test("rejects routine sessions that skipped an interval", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument({
      sourceMetadata: makeRoutineSourceMetadata({stopReason: "skipped"}),
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

test("rejects routine sessions the client marked ineligible", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument({
      participations: [
        makeParticipation({
          contextType: "routine_template",
          leaderboardEligible: false,
        }),
      ],
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

// The eligibility verdict is scoped to the participation's own template; a
// workout can never publish onto a board it was not judged eligible for.
test("rejects a routine whose participation targets another template", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument({
      participations: [
        makeParticipation({
          contextType: "routine_template",
          contextId: "some-other-template",
        }),
      ],
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

// A user-created routine is a private UUID nobody else can run, so it carries
// no template ID and its board could only ever hold its author.
test("rejects user-created routines that carry no template id", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument({
      participations: [
        makeParticipation({contextType: "routine", leaderboardEligible: false}),
      ],
      sourceMetadata: makeRoutineSourceMetadata({routineTemplateId: undefined}),
    }),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload, null);
});

// A First Ascent is landmark prestige, is permanent, and belongs to climbs.
test("never lets a routine claim a First Ascent", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument(),
    {requireEligibleParticipation: true}
  );

  assert.equal(payload?.firstAscentEligible, false);
});

test("publishes a routine into exactly one replay context", () => {
  const payloads = liveReplayLeaderboardTestHooks.replayPayloadsForWorkout(
    makeRoutineWorkoutDocument(),
    {requireEligibleParticipation: true}
  );

  assert.deepEqual(
    payloads.map((payload: {contextType: string}) => payload.contextType),
    ["routine_template"]
  );
});

test("ranks routines on steps and climbs on duration", () => {
  const {rankingMetric, tiePolicy} = liveReplayLeaderboardTestHooks;

  assert.equal(rankingMetric("live_climb"), "completionDurationSeconds");
  assert.equal(rankingMetric("just_climb"), "completionDurationSeconds");
  assert.equal(rankingMetric("routine_template"), "finalSteps");
  assert.equal(
    tiePolicy("live_climb"),
    "competition_rank_equal_durations_share_rank"
  );
  assert.equal(
    tiePolicy("routine_template"),
    "competition_rank_equal_steps_share_rank"
  );
});

test("stamps the routine rank snapshot with its metric and window", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const snapshot = liveReplayLeaderboardTestHooks.completionRankSnapshotWrite({
    payload,
    userId: "user-1",
    entryId: "workout-1",
    rank: 3,
    completedCount: 9,
    rankedAt: "now",
  });

  assert.equal(snapshot.rankingMetric, "finalSteps");
  assert.equal(snapshot.tiePolicy, "competition_rank_equal_steps_share_rank");
  assert.equal(snapshot.targetDurationSeconds, 1200);
});

// Steps only rank honestly between runs of the same length, so every routine
// row records the window it ran in rather than trusting the template to be
// frozen.
test("stamps the guided window only on steps-ranked rows", () => {
  const routinePayload = liveReplayLeaderboardTestHooks
    .parseRoutineReplayPayload(
      makeRoutineWorkoutDocument(),
      {requireEligibleParticipation: true}
    );
  const climbPayload = liveReplayLeaderboardTestHooks
    .parseLiveClimbReplayPayload(
      makeWorkoutDocument(),
      {requireEligibleParticipation: true}
    );
  assert.ok(routinePayload);
  assert.ok(climbPayload);

  const routineEntry = liveReplayLeaderboardTestHooks.replayEntryWrite({
    payload: routinePayload,
    userId: "user-1",
    entryId: "workout-1",
    publicUser: makePublicUser(),
    stepsAtBucket: 120,
    isBestForUser: null,
    updatedAt: "now",
  });
  const climbEntry = liveReplayLeaderboardTestHooks.replayEntryWrite({
    payload: climbPayload,
    userId: "user-1",
    entryId: "workout-1",
    publicUser: makePublicUser(),
    stepsAtBucket: 120,
    isBestForUser: null,
    updatedAt: "now",
  });

  assert.equal(routineEntry.targetDurationSeconds, 1200);
  assert.equal("targetDurationSeconds" in climbEntry, false);
});

test("tracks a routine finisher's best on steps rather than duration", () => {
  const payload = liveReplayLeaderboardTestHooks.parseRoutineReplayPayload(
    makeRoutineWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = (existingData: Record<string, unknown> | undefined) =>
    liveReplayLeaderboardTestHooks.finisherStatusWrite({
      payload,
      userId: "user-1",
      entryId: "workout-2",
      publicUser: makePublicUser(),
      globalCompletionOrder: 4,
      existingData,
      completedAt: "now",
    });

  const firstEver = write(undefined);
  assert.equal(firstEver.bestFinalSteps, 1840);
  assert.equal(firstEver.bestWorkoutId, "workout-2");
  assert.equal("bestCompletionDurationSeconds" in firstEver, false);

  const improved = write({bestFinalSteps: 1700, bestWorkoutId: "workout-1"});
  assert.equal(improved.bestFinalSteps, 1840);
  assert.equal(improved.bestWorkoutId, "workout-2");

  const notImproved = write({bestFinalSteps: 1900, bestWorkoutId: "workout-1"});
  assert.equal("bestFinalSteps" in notImproved, false);
  assert.equal(notImproved.bestWorkoutId, undefined);
});

// A slower run on a climb board must not overwrite the standing best time.
test("keeps a climb finisher's best on the fastest completion", () => {
  const payload = liveReplayLeaderboardTestHooks.parseLiveClimbReplayPayload(
    makeWorkoutDocument(),
    {requireEligibleParticipation: true}
  );
  assert.ok(payload);

  const write = (existingData: Record<string, unknown> | undefined) =>
    liveReplayLeaderboardTestHooks.finisherStatusWrite({
      payload,
      userId: "user-1",
      entryId: "workout-2",
      publicUser: makePublicUser(),
      globalCompletionOrder: 4,
      existingData,
      completedAt: "now",
    });

  assert.equal(write(undefined).bestCompletionDurationSeconds, 738);
  assert.equal(
    write({bestCompletionDurationSeconds: 900}).bestCompletionDurationSeconds,
    738
  );
  assert.equal(
    "bestCompletionDurationSeconds" in write({
      bestCompletionDurationSeconds: 600,
    }),
    false
  );
});

interface RacingReplayTransaction {
  writeAllIdentityTargets(publicUser: PublicUserSnapshot): void;
}

class RacingReplayIdentityPort implements
  IdentityProtectedTransactionPort<RacingReplayTransaction> {
  source: PublicUserSnapshot;
  target: {
    entry: PublicUserSnapshot;
    finisher: PublicUserSnapshot;
    firstAscent: PublicUserSnapshot;
  } | null = null;
  transactionAttempts = 0;
  propagationEnumeratedTargetCount: number | null = null;
  beforeFirstCommit: (() => void) | undefined;

  private sourceRevision = 0;
  private didRace = false;

  constructor(source: PublicUserSnapshot) {
    this.source = source;
  }

  replaceSource(source: PublicUserSnapshot): void {
    this.source = source;
    this.sourceRevision += 1;
  }

  async readCurrentPublicUser(): Promise<PublicUserSnapshot> {
    return {...this.source};
  }

  async runTransaction(
    operation: (transaction: RacingReplayTransaction) => Promise<void>
  ): Promise<void> {
    while (true) {
      this.transactionAttempts += 1;
      const sourceRevision = this.sourceRevision;
      let pending: typeof this.target = null;

      await operation({
        writeAllIdentityTargets: (publicUser) => {
          pending = {
            entry: {...publicUser},
            finisher: {...publicUser},
            firstAscent: {...publicUser},
          };
        },
      });

      if (!this.didRace && this.beforeFirstCommit !== undefined) {
        this.didRace = true;
        this.beforeFirstCommit();
      }

      if (sourceRevision !== this.sourceRevision) {
        continue;
      }

      this.target = pending;
      return;
    }
  }
}

function identitySnapshot(
  displayName: string,
  photoURL: string | null
): PublicUserSnapshot {
  return {
    avatarToken: displayName
      .split(" ")
      .map((component) => component[0])
      .join(""),
    displayName,
    identityState: "published",
    photoURL,
  };
}

/**
 * Builds a completed routine workout backup document.
 * @param {Record<string, unknown>} overrides Document overrides.
 * @return {Record<string, unknown>} Workout backup document.
 */
function makeRoutineWorkoutDocument(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return makeWorkoutDocument({
    durationSeconds: 1200,
    participations: [
      makeParticipation({
        contextType: "routine_template",
        contextId: "social-pyramid-20",
      }),
    ],
    sourceMetadata: makeRoutineSourceMetadata(),
    steps: 1840,
    ...overrides,
  });
}

/**
 * Builds encoded routine source metadata.
 * @param {Record<string, unknown>} overrides Metadata overrides.
 * @return {string} JSON metadata string.
 */
function makeRoutineSourceMetadata(
  overrides: Record<string, unknown> = {}
): string {
  return makeSourceMetadata({
    climbId: undefined,
    climbTargetStepCount: undefined,
    routineId: "6E1B0C1E-0E1A-4E5B-9C2E-0C6F0B7A1D22",
    routineTemplateId: "social-pyramid-20",
    splitSteps: [0, 150, 320, 610, 940, 1310, 1840],
    targetDurationSeconds: 1200,
    targetStepCount: 1900,
    trackingMode: "routine",
    ...overrides,
  });
}

/**
 * Builds a public user snapshot for entry and finisher writes.
 * @return {PublicUserSnapshot} Public user snapshot.
 */
function makePublicUser(): PublicUserSnapshot {
  return {
    avatarToken: "TP",
    displayName: "Tyler P",
    identityState: "published",
    photoURL: null,
  };
}

/**
 * The frozen standing stamped on a finished attempt is permanent, so its two
 * halves have to count one population by construction. That population is
 * completed attempts - the rows the static per-climb board ranks - because the
 * summary is where *this attempt* landed and the climber reads it against that
 * board.
 *
 * Ranking climbers here instead is what told a repeat climber they came first
 * with a slower time than their own record: their own faster completion was
 * counted ahead of them and then subtracted straight back out.
 *
 * An impossible pairing still throws rather than being clamped into a plausible
 * lie.
 */
test("seats a slower repeat attempt behind the climber's own faster one", () => {
  // The captain's St Peter's Basilica pair: one climber, two completions, the
  // second slower. It is second of two, exactly as climb detail shows it.
  const standing = liveReplayLeaderboardTestHooks.frozenCompletionStanding({
    reading: {betterRowCount: 1, attemptCount: 2},
    contextKey: "live_climb__st-peters-basilica",
  });

  assert.deepEqual(standing, {rank: 2, population: 2});
});

test("keeps a first finisher at first of one", () => {
  const standing = liveReplayLeaderboardTestHooks.frozenCompletionStanding({
    reading: {betterRowCount: 0, attemptCount: 1},
    contextKey: "live_climb__st-peters-basilica",
  });

  assert.deepEqual(standing, {rank: 1, population: 1});
});

test("puts a faster repeat attempt back in front", () => {
  // Beating your own record takes first and leaves the older, slower row
  // behind it - three completions on the board, this one leading them all.
  const standing = liveReplayLeaderboardTestHooks.frozenCompletionStanding({
    reading: {betterRowCount: 0, attemptCount: 3},
    contextKey: "live_climb__st-peters-basilica",
  });

  assert.deepEqual(standing, {rank: 1, population: 3});
});

test("shares a rank with every attempt tied on the metric", () => {
  // Competition rank: only strictly better rows count, so two attempts on the
  // same time both read second of three.
  const standing = liveReplayLeaderboardTestHooks.frozenCompletionStanding({
    reading: {betterRowCount: 1, attemptCount: 3},
    contextKey: "live_climb__st-peters-basilica",
  });

  assert.deepEqual(standing, {rank: 2, population: 3});
});

test("counts every repeat attempt on a board that races attempts", () => {
  // No target, so a climber's shortest attempt is the one they quit earliest.
  // All five of a rival's faster attempts are real opponents.
  const standing = liveReplayLeaderboardTestHooks.frozenCompletionStanding({
    reading: {betterRowCount: 5, attemptCount: 6},
    contextKey: "just_climb__global",
  });

  assert.deepEqual(standing, {rank: 6, population: 6});
});

test("refuses to freeze a rank its population cannot hold", () => {
  // Two halves counting different things. Freezing any number from that is
  // worse than failing the publish, so nothing is clamped.
  assert.throws(
    () => liveReplayLeaderboardTestHooks.frozenCompletionStanding({
      reading: {betterRowCount: 5, attemptCount: 3},
      contextKey: "live_climb__st-peters-basilica",
    }),
    /rank 6 of 3/
  );
});

test("refuses to freeze an attempt rank with no attempt count", () => {
  assert.throws(
    () => liveReplayLeaderboardTestHooks.frozenCompletionStanding({
      reading: {betterRowCount: 0, attemptCount: null},
      contextKey: "just_climb__global",
    }),
    /rank 1 of 0/
  );
});

test("names the finisher field each board's numerator counts", () => {
  const {finisherBestMetric} = liveReplayLeaderboardTestHooks;

  // The numerator is an inequality over this field, and a finisher document
  // missing it is invisible to that query. Every new finisher document carries
  // the one its board ranks on - see the finisher status write tests.
  assert.equal(finisherBestMetric("live_climb"), "bestCompletionDurationSeconds");
  assert.equal(finisherBestMetric("routine_template"), "bestFinalSteps");
});

test("ranks a routine on steps and a climb on the clock", () => {
  const {beatsOnMetric} = liveReplayLeaderboardTestHooks;

  assert.equal(beatsOnMetric("routine_template", 1900, 1840), true);
  assert.equal(beatsOnMetric("routine_template", 1800, 1840), false);
  assert.equal(beatsOnMetric("live_climb", 700, 738), true);
  assert.equal(beatsOnMetric("live_climb", 800, 738), false);
  assert.equal(beatsOnMetric("just_climb", 700, 738), true);
});

