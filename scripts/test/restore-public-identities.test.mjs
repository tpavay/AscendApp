import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {
  RESTORATION_OPERATION_VERSION,
  StaleIdentityRestorationPlanError,
  applyFreshUserIdentityRestoration,
  auditFreshUserIdentityRestoration,
  auditOrphanProjectionIdentityRestoration,
  auditUserIdentityRestoration,
  parseRestorationArgs,
  planOrphanProjectionIdentityRestoration,
  planUserIdentityRestoration,
  publicSystemHandle,
  restoredIdentityForUser,
} from "../lib/public-identity-restoration.mjs";

const restorationRunnerSource = readFileSync(
  new URL("../restore-public-identities.mjs", import.meta.url),
  "utf8"
);

test("requires one explicit mode and a named environment", () => {
  assert.throws(
    () => parseRestorationArgs(["node", "script", "--env", "dev"]),
    /exactly one/
  );
  assert.deepEqual(
    parseRestorationArgs([
      "node",
      "script",
      "--env",
      "staging",
      "--dry-run",
    ]),
    {
      env: "staging",
      mode: "dry-run",
      rerun: false,
      productionConfirmation: null,
      batchSize: 400,
      help: false,
    }
  );
  assert.throws(
    () => parseRestorationArgs([
      "node",
      "script",
      "--env",
      "prod",
      "--dry-run",
      "--apply",
    ]),
    /exactly one/
  );
});

test("restored fallback handles match Swift and Functions", () => {
  assert.equal(publicSystemHandle("user-123"), "Climber 7TPMNX");
  assert.equal(publicSystemHandle("user-456"), "Climber ZA5MJ6");
  assert.deepEqual(restoredIdentityForUser("user-123", {
    displayName: "",
    profilePictureURL: "javascript:alert(1)",
  }), {
    avatarToken: "C7",
    displayName: "Climber 7TPMNX",
    photoURL: "",
  });
});

test("restoration rejects compatibility and Unicode confusable profanity", () => {
  for (const displayName of [
    "fυck",
    "fucκ",
    "fսck",
    "ｆｕｃｋ",
    "ｎｉｇｇｅｒ",
    "fųck",
    "f𝕦ck",
    "Maaaya",
  ]) {
    assert.equal(
      restoredIdentityForUser("user-123", {displayName}).displayName,
      "Climber 7TPMNX"
    );
  }
});

test("plans every real projection with actual account identity", () => {
  const plan = planUserIdentityRestoration(makeInput());

  assert.equal(plan.userId, "user-123");
  assert.deepEqual(plan.identity, {
    avatarToken: "MC",
    displayName: "Maya Chen",
    photoURL: "https://example.com/maya.jpg",
  });
  assert.deepEqual(plan.writes.map((write) => write.path), [
    "users/user-123/public_profile/current",
    "leaderboard_stats/weekly_user-123",
    "contexts/a/splitBuckets/0/entries/workout",
    "contexts/a/finishers/user-123",
    "live_replay_leaderboards/a",
  ]);
  assert.deepEqual(plan.writes[1].fields, {
    displayName: "Maya Chen",
    identityChangedAt: {nanoseconds: 0, seconds: 100},
    identityPolicyVersion: 1,
    identityState: "published",
    photoURL: "https://example.com/maya.jpg",
  });
  assert.deepEqual(plan.writes[2].fields, {
    avatarToken: "MC",
    displayName: "Maya Chen",
    identityState: "published",
    isSynthetic: false,
    photoURL: "https://example.com/maya.jpg",
  });
  assert.deepEqual(plan.writes[4].fields, {
    firstAscentAvatarToken: "MC",
    firstAscentDisplayName: "Maya Chen",
    firstAscentIdentityState: "published",
    firstAscentIsSynthetic: false,
    firstAscentPhotoURL: "https://example.com/maya.jpg",
  });
});

test("preserves synthetic and deletion-anonymized projections", () => {
  const input = makeInput();
  input.replayEntries.push({
    path: "contexts/a/entries/synthetic",
    data: {
      displayName: "Summit Sprinter",
      isSynthetic: true,
      photoURL: "https://fixture.example/summit.jpg",
    },
  });
  input.replayFinishers.push({
    path: "contexts/a/finishers/deleted",
    data: {
      displayName: "Deletion race",
      identityState: "deleted",
      photoURL: "",
    },
  });
  input.replayFinishers.push({
    path: "contexts/a/finishers/legacy-anonymous",
    data: {displayName: "Anonymous Climber", photoURL: ""},
  });
  input.firstAscents.push({
    path: "live_replay_leaderboards/seeded",
    data: {
      firstAscentDisplayName: "Seeded Rival",
      firstAscentIsSynthetic: true,
      firstAscentPhotoURL: "https://fixture.example/seeded.jpg",
    },
  });

  const paths = planUserIdentityRestoration(input)
    .writes
    .map((write) => write.path);
  assert.ok(!paths.includes("contexts/a/entries/synthetic"));
  assert.ok(!paths.includes("contexts/a/finishers/deleted"));
  assert.ok(!paths.includes("contexts/a/finishers/legacy-anonymous"));
  assert.ok(!paths.includes("live_replay_leaderboards/seeded"));
});

test("restores only explicitly pending anonymous projections", () => {
  const input = makeInput();
  input.replayFinishers = [{
    path: "contexts/a/finishers/pending",
    data: {
      displayName: "Anonymous Climber",
      identityState: "pending_public_profile",
      photoURL: "",
      userId: "user-123",
    },
    version: 1,
  }];

  const write = planUserIdentityRestoration(input).writes.find(
    (candidate) => candidate.path === "contexts/a/finishers/pending"
  );

  assert.deepEqual(write?.fields, {
    avatarToken: "MC",
    displayName: "Maya Chen",
    identityState: "published",
    isSynthetic: false,
    photoURL: "https://example.com/maya.jpg",
  });
});

test("global lifecycle restores pending and permanently migrates legacy anonymous", () => {
  const input = makeInput();
  input.leaderboards = [
    {
      path: "leaderboard_stats/weekly_pending",
      data: {
        displayName: "Anonymous Climber",
        identityChangedAt: null,
        identityPolicyVersion: 1,
        identityState: "pending_public_profile",
        photoURL: "",
        userId: "user-123",
      },
      version: 1,
    },
    {
      path: "leaderboard_stats/weekly_deleted",
      data: {
        displayName: "Anonymous Climber",
        identityChangedAt: null,
        identityPolicyVersion: 1,
        identityState: "deleted",
        photoURL: "",
        userId: "user-123",
      },
      version: 1,
    },
    {
      path: "leaderboard_stats/weekly_legacy_anonymous",
      data: {
        age: 31,
        displayName: "Anonymous Climber",
        location_city: "Chicago",
        photoURL: "https://example.com/stale-deleted-photo.jpg",
        rank: 3,
        totalSteps: 9_000,
        userId: "user-123",
      },
      version: 1,
    },
  ];

  const writes = planUserIdentityRestoration(input).writes;
  const pending = writes.find(
    (candidate) => candidate.path === "leaderboard_stats/weekly_pending"
  );
  const deleted = writes.find(
    (candidate) => candidate.path === "leaderboard_stats/weekly_deleted"
  );
  const legacyAnonymous = writes.find(
    (candidate) =>
      candidate.path === "leaderboard_stats/weekly_legacy_anonymous"
  );

  assert.deepEqual(pending?.fields, {
    displayName: "Maya Chen",
    identityChangedAt: {nanoseconds: 0, seconds: 100},
    identityPolicyVersion: 1,
    identityState: "published",
    photoURL: "https://example.com/maya.jpg",
  });
  assert.equal(deleted, undefined);
  assert.deepEqual(legacyAnonymous?.fields, {
    displayName: "Anonymous Climber",
    identityChangedAt: null,
    identityPolicyVersion: 1,
    identityState: "deleted",
    photoURL: "",
  });
  assert.equal(
    Object.hasOwn(legacyAnonymous?.fields ?? {}, "rank"),
    false
  );
  assert.equal(
    Object.hasOwn(legacyAnonymous?.fields ?? {}, "totalSteps"),
    false
  );
  const migratedData = {
    ...input.leaderboards[2].data,
    ...legacyAnonymous.fields,
  };
  assert.equal(migratedData.rank, 3);
  assert.equal(migratedData.totalSteps, 9_000);
  assert.equal(migratedData.age, 31);
  assert.equal(migratedData.location_city, "Chicago");
});

test("normalizes malformed deleted global identity without reopening it", () => {
  const input = makeInput();
  input.leaderboards = [{
    path: "leaderboard_stats/weekly_deleted",
    data: {
      displayName: "Stale Real Name",
      identityChangedAt: {nanoseconds: 0, seconds: 50},
      identityPolicyVersion: 0,
      identityState: "deleted",
      photoURL: "https://example.com/stale-real-photo.jpg",
      totalSteps: 6_000,
      userId: "user-123",
    },
    version: 1,
  }];

  const plan = planUserIdentityRestoration(input);

  assert.deepEqual(plan.writes.find(
    (candidate) => candidate.path === "leaderboard_stats/weekly_deleted"
  )?.fields, {
    displayName: "Anonymous Climber",
    identityChangedAt: null,
    identityPolicyVersion: 1,
    identityState: "deleted",
    photoURL: "",
  });
});

test("normalizes an orphan global row while preserving rank and metrics", () => {
  const record = {
    path: "leaderboard_stats/weekly_orphan",
    data: {
      age: 31,
      displayName: "Stale Real Name",
      identityChangedAt: {nanoseconds: 1, seconds: 50},
      identityPolicyVersion: 0,
      identityState: "published",
      location_city: "Chicago",
      photoURL: "https://example.com/stale-real-photo.jpg",
      rank: 3,
      totalSteps: 9_000,
      userId: "deleted-user",
    },
    version: "row-v1",
  };

  const write = planOrphanProjectionIdentityRestoration(
    record,
    false,
    "leaderboard"
  );

  assert.deepEqual(write, {
    fields: {
      displayName: "Anonymous Climber",
      identityChangedAt: null,
      identityPolicyVersion: 1,
      identityState: "deleted",
      photoURL: "",
    },
    path: "leaderboard_stats/weekly_orphan",
    targetVersion: "row-v1",
  });
  const merged = {...record.data, ...write.fields};
  assert.equal(merged.rank, 3);
  assert.equal(merged.totalSteps, 9_000);
  assert.equal(merged.age, 31);
  assert.equal(merged.location_city, "Chicago");
  assert.match(
    auditOrphanProjectionIdentityRestoration(
      record,
      false,
      "leaderboard"
    )[0],
    /without a user root/
  );
  assert.equal(
    auditOrphanProjectionIdentityRestoration(
      {...record, data: merged},
      false,
      "leaderboard"
    ).length,
    0
  );
});

test("orphan sweep leaves existing users and trusted fixtures untouched", () => {
  const realRow = {
    path: "leaderboard_stats/weekly_real",
    data: {
      displayName: "Maya Chen",
      photoURL: "https://example.com/maya.jpg",
      userId: "user-123",
    },
    version: "row-v1",
  };
  const seededRow = {
    path: "leaderboard_stats/weekly_seeded",
    data: {
      displayName: "Summit Sprinter",
      isSynthetic: true,
      photoURL: "https://fixture.example/summit.jpg",
      userId: "seeded:summit",
    },
    version: "row-v1",
  };

  assert.equal(
    planOrphanProjectionIdentityRestoration(realRow, true, "leaderboard"),
    null
  );
  assert.equal(
    planOrphanProjectionIdentityRestoration(
      seededRow,
      false,
      "leaderboard"
    ),
    null
  );
});

test("normalizes every orphan replay identity shape without deleting results", () => {
  const replayRecord = {
    path: "contexts/a/splitBuckets/0/entries/workout",
    data: {
      avatarToken: "SR",
      displayName: "Stale Rival",
      finalSteps: 3_200,
      identityState: "published",
      isSynthetic: false,
      photoURL: "https://example.com/stale.jpg",
      rank: 2,
      userId: "deleted-user",
    },
    version: "entry-v1",
  };
  const finisherRecord = {
    ...replayRecord,
    path: "contexts/a/finishers/deleted-user",
    version: "finisher-v1",
  };
  const firstAscentRecord = {
    path: "live_replay_leaderboards/a",
    data: {
      completedCount: 7,
      firstAscentAvatarToken: "SR",
      firstAscentDisplayName: "Stale Rival",
      firstAscentIdentityState: "published",
      firstAscentIsSynthetic: false,
      firstAscentPhotoURL: "https://example.com/stale.jpg",
      firstAscentUserId: "deleted-user",
    },
    version: "context-v1",
  };

  for (const record of [replayRecord, finisherRecord]) {
    const write = planOrphanProjectionIdentityRestoration(
      record,
      false,
      "replay"
    );
    assert.deepEqual(write?.fields, {
      avatarToken: "",
      displayName: "Anonymous Climber",
      identityState: "deleted",
      isSynthetic: false,
      photoURL: "",
    });
    const merged = {...record.data, ...write.fields};
    assert.equal(merged.rank, 2);
    assert.equal(merged.finalSteps, 3_200);
  }

  const firstAscentWrite = planOrphanProjectionIdentityRestoration(
    firstAscentRecord,
    false,
    "firstAscent"
  );
  assert.deepEqual(firstAscentWrite?.fields, {
    firstAscentAvatarToken: "",
    firstAscentDisplayName: "Anonymous Climber",
    firstAscentIdentityState: "deleted",
    firstAscentIsSynthetic: false,
    firstAscentPhotoURL: "",
  });
  const mergedFirstAscent = {
    ...firstAscentRecord.data,
    ...firstAscentWrite.fields,
  };
  assert.equal(mergedFirstAscent.completedCount, 7);
  assert.equal(mergedFirstAscent.firstAscentUserId, "deleted-user");
});

test("orphan sweep ignores open first ascents and synthetic replay fixtures", () => {
  assert.equal(
    planOrphanProjectionIdentityRestoration(
      {
        path: "live_replay_leaderboards/open",
        data: {completedCount: 0},
        version: "open-v1",
      },
      false,
      "firstAscent"
    ),
    null
  );
  assert.equal(
    planOrphanProjectionIdentityRestoration(
      {
        path: "contexts/a/splitBuckets/0/entries/seeded",
        data: {
          displayName: "Summit Sprinter",
          isSynthetic: true,
          userId: "seeded:summit",
        },
        version: "seed-v1",
      },
      false,
      "replay"
    ),
    null
  );
});

test("runner independently audits every orphan projection collection", () => {
  assert.match(
    restorationRunnerSource,
    /collection\("leaderboard_stats"\)/
  );
  assert.match(restorationRunnerSource, /collectionGroup\("entries"\)/);
  assert.match(restorationRunnerSource, /collectionGroup\("finishers"\)/);
  assert.match(
    restorationRunnerSource,
    /collection\("live_replay_leaderboards"\)/
  );
});

test("legacy anonymous migration changes the audit fingerprint and converges", () => {
  const input = makeInput();
  input.leaderboards = [{
    path: "leaderboard_stats/weekly_legacy_anonymous",
    data: {
      displayName: "Anonymous Climber",
      photoURL: "https://example.com/stale-photo.jpg",
      totalSteps: 5_000,
      userId: "user-123",
    },
    version: "legacy-v1",
  }];
  const legacyPlan = planUserIdentityRestoration(input);

  assert.ok(legacyPlan.writes.some(
    (candidate) =>
      candidate.path === "leaderboard_stats/weekly_legacy_anonymous"
  ));
  assert.match(
    auditUserIdentityRestoration(legacyPlan, undefined)[0],
    /stale public identity/
  );

  for (const write of legacyPlan.writes) {
    const record = allRecords(input).find(
      (candidate) => candidate.path === write.path
    );
    assert.ok(record);
    Object.assign(record.data, write.fields);
  }
  const migratedPlan = planUserIdentityRestoration(input);

  assert.notEqual(
    migratedPlan.targetFingerprint,
    legacyPlan.targetFingerprint
  );
  assert.deepEqual(migratedPlan.writes, []);
  assert.deepEqual(
    auditUserIdentityRestoration(migratedPlan, {
      identityDigest: migratedPlan.identityDigest,
      operationVersion: RESTORATION_OPERATION_VERSION,
      sourceVersion: migratedPlan.sourceVersion,
    }),
    []
  );
});

test("a complete rerun plans zero projection writes", () => {
  const input = makeInput();
  const firstPlan = planUserIdentityRestoration(input);
  for (const write of firstPlan.writes) {
    const record = allRecords(input).find(
      (candidate) => candidate.path === write.path
    );
    assert.ok(record);
    Object.assign(record.data, write.fields);
  }

  const secondPlan = planUserIdentityRestoration(input);
  assert.deepEqual(secondPlan.writes, []);
  assert.deepEqual(
    auditUserIdentityRestoration(secondPlan, {
      identityDigest: secondPlan.identityDigest,
      operationVersion: RESTORATION_OPERATION_VERSION,
      sourceVersion: secondPlan.sourceVersion,
    }),
    []
  );
});

test("a concurrent root edit replans and publishes only the new identity", async () => {
  const input = makeInput();
  let attempt = 0;
  let appliedPlan;

  const outcome = await applyFreshUserIdentityRestoration({
    async loadFreshPlan() {
      return planUserIdentityRestoration(input);
    },
    async applyPlan(plan) {
      attempt += 1;
      if (attempt === 1) {
        input.userData.displayName = "Newest Name";
        input.sourceVersion = "source-v2";
        input.identityChangedAt = {nanoseconds: 0, seconds: 200};
        throw new StaleIdentityRestorationPlanError("root changed");
      }
      appliedPlan = plan;
      return plan.writes.length;
    },
  });

  assert.equal(outcome.status, "applied");
  assert.equal(attempt, 2);
  assert.equal(appliedPlan.identity.displayName, "Newest Name");
  assert.ok(appliedPlan.writes.every((write) =>
    write.fields.displayName === undefined ||
    write.fields.displayName === "Newest Name"
  ));
});

test("audit replans when identity changes after planning", async () => {
  const input = makeInput();
  let markerReads = 0;

  const result = await auditFreshUserIdentityRestoration({
    async loadFreshPlan() {
      return currentPlanWithMatchingProjections(input);
    },
    async loadMarkerForCurrentSource(plan) {
      markerReads += 1;
      if (markerReads === 1) {
        input.userData.displayName = "Newest Name";
        input.sourceVersion = "source-v2";
        input.identityChangedAt = {nanoseconds: 0, seconds: 200};
        throw new StaleIdentityRestorationPlanError(
          "source changed after planning"
        );
      }
      return {
        identityDigest: plan.identityDigest,
        operationVersion: RESTORATION_OPERATION_VERSION,
        sourceVersion: plan.sourceVersion,
      };
    },
  });

  assert.equal(result.attempts, 2);
  assert.equal(result.plan.identity.displayName, "Newest Name");
  assert.equal(result.plan.sourceVersion, "source-v2");
  assert.deepEqual(result.failures, []);
});

test("audit catches a zero-write target edit after planning", async () => {
  const input = makeInput();
  const initialPlan = currentPlanWithMatchingProjections(input);
  const initialMarker = {
    identityDigest: initialPlan.identityDigest,
    operationVersion: RESTORATION_OPERATION_VERSION,
    sourceVersion: initialPlan.sourceVersion,
  };
  let markerReads = 0;

  const result = await auditFreshUserIdentityRestoration({
    async loadFreshPlan() {
      return planUserIdentityRestoration(input);
    },
    async loadMarkerForCurrentSource() {
      markerReads += 1;
      if (markerReads === 1) {
        input.leaderboards[0].data.displayName = "Concurrent Edit";
        input.leaderboards[0].version = "leaderboard-v2";
      }
      return initialMarker;
    },
  });

  assert.equal(initialPlan.writes.length, 0);
  assert.equal(result.attempts, 2);
  assert.equal(markerReads, 2);
  assert.notEqual(
    result.plan.targetFingerprint,
    initialPlan.targetFingerprint
  );
  assert.equal(result.plan.writes.length, 1);
  assert.match(result.failures[0], /stale public identity/);
});

test("a root deletion during apply replans to a no-write skip", async () => {
  const input = makeInput();
  let deleted = false;
  let committedWrites = 0;

  const outcome = await applyFreshUserIdentityRestoration({
    async loadFreshPlan() {
      return deleted ? {
        missingPublicProfile: false,
        skipReason: "source user deleted during restoration",
        userId: "user-123",
        writes: [],
      } : planUserIdentityRestoration(input);
    },
    async applyPlan() {
      deleted = true;
      throw new StaleIdentityRestorationPlanError("root deleted");
    },
  });

  committedWrites += outcome.projectionWrites;
  assert.equal(outcome.status, "skipped");
  assert.equal(committedWrites, 0);
});

test("a missing public profile is explicitly skipped and audited", async () => {
  const input = makeInput();
  input.publicProfile = null;
  const plan = planUserIdentityRestoration(input);

  const outcome = await applyFreshUserIdentityRestoration({
    async loadFreshPlan() {
      return plan;
    },
    async applyPlan() {
      assert.fail("missing public profile must never be written");
    },
  });

  assert.equal(outcome.status, "skipped");
  assert.deepEqual(plan.writes, []);
  assert.match(
    auditUserIdentityRestoration(plan, undefined)[0],
    /missing public_profile/
  );
});

test("missing public profile still permits permanent legacy normalization", async () => {
  const input = makeInput();
  input.publicProfile = null;
  input.leaderboards = [{
    path: "leaderboard_stats/weekly_legacy_anonymous",
    data: {
      displayName: "Anonymous Climber",
      photoURL: "https://example.com/stale-photo.jpg",
      totalSteps: 5_000,
      userId: "user-123",
    },
    version: "legacy-v1",
  }];
  const plan = planUserIdentityRestoration(input);
  let applied;

  const outcome = await applyFreshUserIdentityRestoration({
    async loadFreshPlan() {
      return plan;
    },
    async applyPlan(candidate) {
      applied = candidate.writes;
      return candidate.writes.length;
    },
  });

  assert.equal(outcome.status, "applied");
  assert.deepEqual(applied, [{
    fields: {
      displayName: "Anonymous Climber",
      identityChangedAt: null,
      identityPolicyVersion: 1,
      identityState: "deleted",
      photoURL: "",
    },
    path: "leaderboard_stats/weekly_legacy_anonymous",
    targetVersion: "legacy-v1",
  }]);
  assert.match(
    auditUserIdentityRestoration(plan, undefined)[0],
    /missing public_profile/
  );
});

test("audit reports stale projections and an incomplete marker", () => {
  const plan = planUserIdentityRestoration(makeInput());
  const failures = auditUserIdentityRestoration(plan, undefined);

  assert.equal(failures.length, plan.writes.length + 1);
  assert.match(failures.at(-1), /completion marker/);
});

/**
 * Builds one user with every projection shape.
 * @return {object} Planner input.
 */
function makeInput() {
  return {
    userId: "user-123",
    sourceVersion: "source-v1",
    identityChangedAt: {nanoseconds: 0, seconds: 100},
    userData: {
      displayName: "Maya Chen",
      profilePictureURL: "https://example.com/maya.jpg",
    },
    publicProfile: record(
      "users/user-123/public_profile/current",
      {displayName: "Climber", photoURL: ""}
    ),
    leaderboards: [
      record(
        "leaderboard_stats/weekly_user-123",
        {displayName: "Climber", photoURL: "", totalSteps: 5_000}
      ),
    ],
    replayEntries: [
      record(
        "contexts/a/splitBuckets/0/entries/workout",
        {
          avatarToken: "",
          displayName: "Climber",
          isSynthetic: false,
          photoURL: "",
          rank: 2,
        }
      ),
    ],
    replayFinishers: [
      record(
        "contexts/a/finishers/user-123",
        {
          avatarToken: "",
          displayName: "Climber",
          isSynthetic: false,
          photoURL: "",
        }
      ),
    ],
    firstAscents: [
      record(
        "live_replay_leaderboards/a",
        {
          firstAscentAvatarToken: "",
          firstAscentDisplayName: "Climber",
          firstAscentIsSynthetic: false,
          firstAscentPhotoURL: "",
          firstAscentUserId: "user-123",
        }
      ),
    ],
  };
}

/**
 * Returns every mutable planner record.
 * @param {object} input Planner input.
 * @return {object[]} All projection records.
 */
function allRecords(input) {
  return [
    input.publicProfile,
    ...input.leaderboards,
    ...input.replayEntries,
    ...input.replayFinishers,
    ...input.firstAscents,
  ];
}

/**
 * Updates the in-memory projections to match the source before planning.
 * @param {object} input Planner input.
 * @return {object} Current no-write plan.
 */
function currentPlanWithMatchingProjections(input) {
  const firstPlan = planUserIdentityRestoration(input);
  for (const write of firstPlan.writes) {
    const record = allRecords(input).find(
      (candidate) => candidate.path === write.path
    );
    assert.ok(record);
    Object.assign(record.data, write.fields);
  }
  return planUserIdentityRestoration(input);
}

/**
 * Builds a projection record.
 * @param {string} path Firestore path.
 * @param {object} data Projection fields.
 * @return {object} Projection record.
 */
function record(path, data) {
  return {path, data, version: `${path}-v1`};
}
