import test from "node:test";
import assert from "node:assert/strict";
import {
  IDENTITY_PROJECTION_KINDS,
  IdentityPropagationJob,
  IdentityPropagationJobPort,
  IdentityPropagationJobTransaction,
  IdentityPropagationPort,
  IdentityPropagationTransaction,
  IdentityProjectionPage,
  IdentityProjectionReference,
  identityFieldsForProjection,
  identitySourceGeneration,
  processIdentityPropagationJob,
  propagateCurrentPublicIdentity,
  publicIdentitySourceChanged,
  scheduledIdentityPropagationJob,
  shouldScheduleIdentityPropagationJobs,
} from "../src/publicIdentityPropagation.js";

const changedAt = {seconds: 100};
const identity = {
  avatarToken: "MC",
  displayName: "Maya Chen",
  identityChangedAt: changedAt,
  identityPolicyVersion: 1,
  identityState: "published" as const,
  photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
};

test("demographic-only profile writes do not schedule identity fanout", () => {
  const before = {
    displayName: "Maya Chen",
    photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
    identityPolicyVersion: 1,
    identityChangedAt: {seconds: 100, nanoseconds: 5},
    age: 31,
  };

  assert.equal(
    publicIdentitySourceChanged(before, {...before, age: 32}),
    false
  );
  assert.equal(
    publicIdentitySourceChanged(before, {
      ...before,
      displayName: "Maya Patel",
    }),
    true
  );
  assert.equal(
    publicIdentitySourceChanged(before, {
      ...before,
      identityChangedAt: {seconds: 101, nanoseconds: 0},
    }),
    true
  );
});

test("writes identity only and copies policy metadata to leaderboard", () => {
  const fields = identityFieldsForProjection(
    "leaderboard",
    {
      age: 31,
      displayName: "Old",
      photoURL: "",
      rank: 2,
      totalSteps: 3_000,
      userId: "user-1",
    },
    identity
  );

  assert.deepEqual(fields, {
    displayName: "Maya Chen",
    identityChangedAt: changedAt,
    identityPolicyVersion: 1,
    identityState: "published",
    photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
  });
  assert.deepEqual(Object.keys(fields ?? {}).sort(), [
    "displayName",
    "identityChangedAt",
    "identityPolicyVersion",
    "identityState",
    "photoURL",
  ]);
});

test("treats an already-current leaderboard row as a no-op", () => {
  // identityChangedAt is a Timestamp, and two Timestamp instances are never
  // strictly equal, so a raw === guard rewrote every row on every pass.
  const current = {
    displayName: identity.displayName,
    identityChangedAt: {seconds: 100, nanoseconds: 0},
    identityPolicyVersion: 1,
    identityState: "published",
    photoURL: identity.photoURL,
    totalSteps: 3_000,
    userId: "user-1",
  };

  assert.equal(
    identityFieldsForProjection("leaderboard", current, {
      ...identity,
      identityChangedAt: {seconds: 100, nanoseconds: 0},
    }),
    null
  );
  assert.notEqual(
    identityFieldsForProjection("leaderboard", current, {
      ...identity,
      identityChangedAt: {seconds: 200, nanoseconds: 0},
    }),
    null
  );
});

test("preserves synthetic, deleted, and legacy anonymous projections", () => {
  assert.equal(
    identityFieldsForProjection(
      "replayEntry",
      {displayName: "Rival", isSynthetic: true},
      identity
    ),
    null
  );
  assert.equal(
    identityFieldsForProjection(
      "leaderboard",
      {displayName: "Rival", source: "synthetic"},
      identity
    ),
    null
  );
  assert.equal(
    identityFieldsForProjection(
      "firstAscent",
      {
        firstAscentDisplayName: "Seed",
        firstAscentIsSynthetic: true,
      },
      identity
    ),
    null
  );
  assert.equal(
    identityFieldsForProjection(
      "replayFinisher",
      {displayName: "Anonymous Climber"},
      identity
    ),
    null
  );
  assert.equal(
    identityFieldsForProjection(
      "replayEntry",
      {
        displayName: "Anonymous Climber",
        identityState: "deleted",
      },
      identity
    ),
    null
  );
  assert.equal(
    identityFieldsForProjection(
      "leaderboard",
      {
        displayName: "Anonymous Climber",
        identityState: "deleted",
        photoURL: "https://example.com/stale-deleted-photo.jpg",
      },
      identity
    ),
    null
  );
});

test("uses an independent bounded checkpoint for every projection kind", () => {
  assert.deepEqual(IDENTITY_PROJECTION_KINDS, [
    "leaderboard",
    "replayEntry",
    "replayFinisher",
    "firstAscent",
  ]);
});

test("source generations preserve sub-millisecond Firestore precision", () => {
  const first = identitySourceGeneration({
    nanoseconds: 100_100,
    seconds: 1_000,
  });
  const second = identitySourceGeneration({
    nanoseconds: 100_900,
    seconds: 1_000,
  });

  assert.notEqual(first, second);
  assert.equal(identitySourceGeneration(undefined), "missing");
});

test("scheduling resets cursors for each unique source delivery", () => {
  const complete = {
    ...propagationJob("replayFinisher"),
    complete: true,
    cursor: "contexts/a/finishers/user-1",
    sequence: 7,
  };

  assert.equal(
    scheduledIdentityPropagationJob(
      complete,
      "user-1",
      "replayFinisher",
      complete.sourceDeliveryId,
      complete.sourceTransitionGeneration,
      complete.sourceGeneration
    ),
    null
  );
  assert.deepEqual(
    scheduledIdentityPropagationJob(
      complete,
      "user-1",
      "replayFinisher",
      "delivery-v2",
      "present:200:0:write",
      "source-v2"
    ),
    {
      complete: false,
      cursor: null,
      kind: "replayFinisher",
      sequence: 8,
      sourceDeliveryId: "delivery-v2",
      sourceTransitionGeneration: "present:200:0:write",
      sourceGeneration: "source-v2",
      userId: "user-1",
    }
  );
});

test("a delete-create-delete ABA schedules the second missing sweep", () => {
  const completedFirstDelete = {
    ...propagationJob("leaderboard"),
    complete: true,
    sequence: 9,
    sourceDeliveryId: "delete-delivery-a",
    sourceTransitionGeneration: "present:100:100:delete",
    sourceGeneration: "missing",
  };

  const secondDelete = scheduledIdentityPropagationJob(
    completedFirstDelete,
    "user-1",
    "leaderboard",
    "delete-delivery-b",
    "present:200:200:delete",
    "missing"
  );

  assert.deepEqual(secondDelete, {
    complete: false,
    cursor: null,
    kind: "leaderboard",
    sequence: 10,
    sourceDeliveryId: "delete-delivery-b",
    sourceTransitionGeneration: "present:200:200:delete",
    sourceGeneration: "missing",
    userId: "user-1",
  });
  assert.equal(
    scheduledIdentityPropagationJob(
      secondDelete ?? undefined,
      "user-1",
      "leaderboard",
      "delete-delivery-b",
      "present:200:200:delete",
      "missing"
    ),
    null
  );
});

test("a delayed or duplicated older delivery cannot reset a newer job", () => {
  const current = {
    ...propagationJob("leaderboard"),
    sourceDeliveryId: "delivery-new",
    sourceTransitionGeneration: "present:200:900:delete",
  };

  assert.equal(
    scheduledIdentityPropagationJob(
      current,
      "user-1",
      "leaderboard",
      "delivery-old",
      "present:100:900:delete",
      "source-v1"
    ),
    null
  );
  assert.equal(
    scheduledIdentityPropagationJob(
      current,
      "user-1",
      "leaderboard",
      "redelivery-with-new-id",
      "present:200:900:delete",
      "source-v1"
    ),
    null
  );
});

test("deleting a just-created version resets its completed create sweep", () => {
  const completedCreate = {
    ...propagationJob("leaderboard"),
    complete: true,
    sourceDeliveryId: "create-delivery",
    sourceTransitionGeneration: "present:300:400:write",
  };

  assert.deepEqual(
    scheduledIdentityPropagationJob(
      completedCreate,
      "user-1",
      "leaderboard",
      "delete-delivery",
      "present:300:400:delete",
      "missing"
    ),
    {
      ...completedCreate,
      complete: false,
      cursor: null,
      sequence: 2,
      sourceDeliveryId: "delete-delivery",
      sourceGeneration: "missing",
      sourceTransitionGeneration: "present:300:400:delete",
    }
  );
});

test("a delayed source deletion cannot recreate jobs after root deletion", () => {
  assert.equal(shouldScheduleIdentityPropagationJobs(false), false);
  assert.equal(shouldScheduleIdentityPropagationJobs(true), true);
});

test("a bounded job page advances its own checkpoint and preserves metrics", async () => {
  const job = propagationJob("replayEntry");
  const targets = [
    jobTarget("replayEntry", "contexts/a/entries/1"),
    jobTarget("replayEntry", "contexts/a/entries/2"),
  ];
  const port = new JobPort(
    job,
    {
      hasMore: true,
      nextCursor: "contexts/a/entries/2",
      targets,
    },
    new Map(targets.map((target, index) => [
      target.path,
      {
        displayName: "Old Name",
        finalSteps: 2_000 + index,
        photoURL: "",
        userId: "user-1",
      },
    ]))
  );

  const writes = await processIdentityPropagationJob(job, port, 2);

  assert.equal(port.requestedPageSize, 2);
  assert.equal(writes, 2);
  assert.deepEqual(port.job, {
    ...job,
    complete: false,
    cursor: "contexts/a/entries/2",
    sequence: 2,
  });
  assert.equal(port.targetData.get(targets[0].path)?.displayName, "Maya Chen");
  assert.equal(port.targetData.get(targets[0].path)?.finalSteps, 2_000);
});

test("a delayed job event cannot advance or overwrite a newer checkpoint", async () => {
  const eventJob = propagationJob("leaderboard");
  const liveJob = {
    ...eventJob,
    cursor: "weekly_current",
    sequence: 2,
  };
  const target = jobTarget("leaderboard", "leaderboard_stats/weekly_next");
  const port = new JobPort(
    liveJob,
    {hasMore: false, nextCursor: "weekly_next", targets: [target]},
    new Map([[
      target.path,
      {
        displayName: "Newest Name",
        identityState: "published",
        totalSteps: 4_000,
        userId: "user-1",
      },
    ]])
  );

  const writes = await processIdentityPropagationJob(eventJob, port);

  assert.equal(writes, 0);
  assert.deepEqual(port.job, liveJob);
  assert.equal(
    port.targetData.get(target.path)?.displayName,
    "Newest Name"
  );
});

test("a source generation change resets the kind before writing targets", async () => {
  const job = {
    ...propagationJob("firstAscent"),
    cursor: "climb-a",
    sourceGeneration: "source-v1",
  };
  const target = jobTarget(
    "firstAscent",
    "live_replay_leaderboards/climb-b"
  );
  const port = new JobPort(
    job,
    {hasMore: false, nextCursor: "climb-b", targets: [target]},
    new Map([[
      target.path,
      {
        firstAscentDisplayName: "Old Name",
        firstAscentUserId: "user-1",
      },
    ]]),
    "source-v2"
  );

  const writes = await processIdentityPropagationJob(job, port);

  assert.equal(writes, 0);
  assert.deepEqual(port.job, {
    ...job,
    complete: false,
    cursor: null,
    sequence: 2,
    sourceGeneration: "source-v2",
  });
  assert.equal(
    port.targetData.get(target.path)?.firstAscentDisplayName,
    "Old Name"
  );
});

test("an out-of-order invocation commits the newest source identity", async () => {
  const port = new RacingPort(source("Old Event"), target("Old Projection"));
  port.beforeFirstCommit = () => {
    port.sourceData = source("Newest Name", {
      identityChangedAt: {seconds: 200},
    });
  };

  const writes = await propagateCurrentPublicIdentity("user-1", port);

  assert.equal(writes, 1);
  assert.equal(port.targetData.displayName, "Newest Name");
  assert.deepEqual(port.targetData.identityChangedAt, {seconds: 200});
  assert.equal(port.transactionAttempts, 2);
});

test("a source deletion racing global propagation anonymizes as pending", async () => {
  const port = new RacingPort(
    source("Maya Chen"),
    target("Old Projection", {identityState: "published"})
  );
  port.beforeFirstCommit = () => {
    port.sourceData = undefined;
  };

  const writes = await propagateCurrentPublicIdentity("user-1", port);

  assert.equal(writes, 1);
  assert.equal(port.targetData.displayName, "Anonymous Climber");
  assert.equal(port.targetData.photoURL, "");
  assert.equal(port.targetData.identityState, "pending_public_profile");
  assert.equal(port.transactionAttempts, 2);
});

test("a mirror deletion racing replay propagation anonymizes as pending", async () => {
  const port = new RacingPort(
    source("Maya Chen"),
    target("Old Projection", {identityState: "published"}),
    "replayEntry"
  );
  port.beforeFirstCommit = () => {
    port.sourceData = undefined;
  };

  const writes = await propagateCurrentPublicIdentity("user-1", port);

  assert.equal(writes, 1);
  assert.equal(port.targetData.displayName, "Anonymous Climber");
  assert.equal(port.targetData.photoURL, "");
  assert.equal(port.targetData.identityState, "pending_public_profile");
  assert.equal(port.transactionAttempts, 2);
});

test("a deletion sentinel permanently anonymizes an existing replay row", async () => {
  const port = new RacingPort(
    source("Anonymous Climber"),
    target("Maya Chen", {identityState: "published"}),
    "replayFinisher"
  );

  const deletionWrites = await propagateCurrentPublicIdentity("user-1", port);

  assert.equal(deletionWrites, 1);
  assert.equal(port.targetData.displayName, "Anonymous Climber");
  assert.equal(port.targetData.photoURL, "");
  assert.equal(port.targetData.identityState, "deleted");

  port.sourceData = source("Restored Name");
  const restorationWrites = await propagateCurrentPublicIdentity(
    "user-1",
    port
  );

  assert.equal(restorationWrites, 0);
  assert.equal(port.targetData.displayName, "Anonymous Climber");
  assert.equal(port.targetData.identityState, "deleted");
});

test("a deletion sentinel permanently anonymizes an existing global row", async () => {
  const port = new RacingPort(
    source("Anonymous Climber"),
    target("Maya Chen", {identityState: "published"})
  );

  const deletionWrites = await propagateCurrentPublicIdentity("user-1", port);

  assert.equal(deletionWrites, 1);
  assert.equal(port.targetData.displayName, "Anonymous Climber");
  assert.equal(port.targetData.photoURL, "");
  assert.equal(port.targetData.identityState, "deleted");

  port.sourceData = source("Restored Name");
  const restorationWrites = await propagateCurrentPublicIdentity(
    "user-1",
    port
  );

  assert.equal(restorationWrites, 0);
  assert.equal(port.targetData.displayName, "Anonymous Climber");
  assert.equal(port.targetData.identityState, "deleted");
});

test("a target anonymized during propagation is never restored", async () => {
  const port = new RacingPort(source("Maya Chen"), target("Old Projection"));
  port.beforeFirstCommit = () => {
    port.targetData = target("Anonymous Climber", {
      identityState: "deleted",
    });
  };

  const writes = await propagateCurrentPublicIdentity("user-1", port);

  assert.equal(writes, 0);
  assert.equal(port.targetData.displayName, "Anonymous Climber");
  assert.equal(port.transactionAttempts, 2);
});

test(
  "actual propagation publishes every pending replay identity target",
  async () => {
    const targets: Array<{
      reference: IdentityProjectionReference;
      data: Record<string, unknown>;
    }> = [
      {
        reference: {
          kind: "leaderboard",
          path: "leaderboard_stats/weekly_2026-W31_user-1",
        },
        data: {
          displayName: "Anonymous Climber",
          identityChangedAt: null,
          identityPolicyVersion: 1,
          identityState: "pending_public_profile",
          photoURL: "",
          totalSteps: 48_000,
          userId: "user-1",
        },
      },
      {
        reference: {
          kind: "replayEntry",
          path: "live_replay_leaderboards/climb/buckets/0/entries/workout",
        },
        data: {
          displayName: "Anonymous Climber",
          identityState: "pending_public_profile",
          performanceField: 2_096,
          photoURL: "",
          userId: "user-1",
        },
      },
      {
        reference: {
          kind: "replayFinisher",
          path: "live_replay_leaderboards/climb/finishers/user-1",
        },
        data: {
          displayName: "Anonymous Climber",
          identityState: "pending_public_profile",
          permanentOrder: 4,
          photoURL: "",
          userId: "user-1",
        },
      },
      {
        reference: {
          kind: "firstAscent",
          path: "live_replay_leaderboards/climb",
        },
        data: {
          firstAscentDisplayName: "Anonymous Climber",
          firstAscentIdentityState: "pending_public_profile",
          firstAscentPhotoURL: "",
          firstAscentUserId: "user-1",
          permanentClaim: true,
        },
      },
    ];
    const port = new MultiTargetPort(source("Maya Chen"), targets);

    const writes = await propagateCurrentPublicIdentity("user-1", port);

    assert.equal(writes, 4);
    assert.deepEqual(port.dataFor(targets[0].reference.path), {
      displayName: "Maya Chen",
      identityChangedAt: changedAt,
      identityPolicyVersion: 1,
      identityState: "published",
      photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
      totalSteps: 48_000,
      userId: "user-1",
    });
    assert.deepEqual(port.dataFor(targets[1].reference.path), {
      avatarToken: "MC",
      displayName: "Maya Chen",
      identityState: "published",
      isSynthetic: false,
      performanceField: 2_096,
      photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
      userId: "user-1",
    });
    assert.deepEqual(port.dataFor(targets[2].reference.path), {
      avatarToken: "MC",
      displayName: "Maya Chen",
      identityState: "published",
      isSynthetic: false,
      permanentOrder: 4,
      photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
      userId: "user-1",
    });
    assert.deepEqual(port.dataFor(targets[3].reference.path), {
      firstAscentAvatarToken: "MC",
      firstAscentDisplayName: "Maya Chen",
      firstAscentIdentityState: "published",
      firstAscentIsSynthetic: false,
      firstAscentPhotoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
      firstAscentUserId: "user-1",
      permanentClaim: true,
    });
  }
);

test("a target reassigned during propagation is never overwritten", async () => {
  const port = new RacingPort(source("Maya Chen"), target("Old Projection"));
  port.beforeFirstCommit = () => {
    port.targetData = target("New Owner", {userId: "user-2"});
  };

  const writes = await propagateCurrentPublicIdentity("user-1", port);

  assert.equal(writes, 0);
  assert.equal(port.targetData.displayName, "New Owner");
  assert.equal(port.transactionAttempts, 2);
});

function propagationJob(
  kind: IdentityProjectionReference["kind"]
): IdentityPropagationJob {
  return {
    complete: false,
    cursor: null,
    kind,
    sequence: 1,
    sourceDeliveryId: "delivery-v1",
    sourceTransitionGeneration: "present:100:0:write",
    sourceGeneration: "source-v1",
    userId: "user-1",
  };
}

function jobTarget(
  kind: IdentityProjectionReference["kind"],
  path: string
): IdentityProjectionReference {
  return {kind, path};
}

class JobPort implements IdentityPropagationJobPort {
  requestedPageSize = 0;

  constructor(
    public job: IdentityPropagationJob,
    private readonly page: IdentityProjectionPage,
    public readonly targetData:
      Map<string, Record<string, unknown> | undefined>,
    private readonly sourceGeneration = "source-v1"
  ) {}

  async listTargetPage(
    _job: IdentityPropagationJob,
    pageSize: number
  ): Promise<IdentityProjectionPage> {
    this.requestedPageSize = pageSize;
    return this.page;
  }

  async runTransaction(
    operation: (
      transaction: IdentityPropagationJobTransaction
    ) => Promise<number>
  ): Promise<number> {
    return operation({
      readJob: async () => ({...this.job}),
      readSource: async () => ({
        data: source("Maya Chen"),
        generation: this.sourceGeneration,
      }),
      readTargets: async (targets) => new Map(
        targets.map((target) => [
          target.path,
          this.targetData.get(target.path),
        ])
      ),
      updateJob: (fields) => {
        this.job = {...this.job, ...fields};
      },
      updateTarget: (target, fields) => {
        const current = this.targetData.get(target.path);
        this.targetData.set(target.path, {...current, ...fields});
      },
    });
  }
}

class RacingPort implements IdentityPropagationPort {
  sourceData: Record<string, unknown> | undefined;
  targetData: Record<string, unknown>;
  transactionAttempts = 0;
  beforeFirstCommit: (() => void) | undefined;

  private sourceRevision = 0;
  private targetRevision = 0;
  private didRace = false;

  constructor(
    sourceData: Record<string, unknown>,
    targetData: Record<string, unknown>,
    private readonly targetKind: IdentityProjectionReference["kind"] =
    "leaderboard"
  ) {
    this.sourceData = sourceData;
    this.targetData = targetData;
  }

  async listTargets(): Promise<IdentityProjectionReference[]> {
    return [{
      kind: this.targetKind,
      path: "leaderboard_stats/weekly_user-1",
    }];
  }

  async runTransaction(
    operation: (
      transaction: IdentityPropagationTransaction
    ) => Promise<boolean>
  ): Promise<boolean> {
    while (true) {
      this.transactionAttempts += 1;
      const sourceRevision = this.sourceRevision;
      const targetRevision = this.targetRevision;
      let pendingFields: Record<string, unknown> | undefined;
      const didWrite = await operation({
        readSource: async () => this.sourceData === undefined ?
          undefined :
          {...this.sourceData},
        readTarget: async () => ({...this.targetData}),
        updateTarget: (_target, fields) => {
          pendingFields = fields;
        },
      });

      if (!this.didRace && this.beforeFirstCommit !== undefined) {
        this.didRace = true;
        const previousSource = this.sourceData;
        const previousTarget = this.targetData;
        this.beforeFirstCommit();
        if (previousSource !== this.sourceData) {
          this.sourceRevision += 1;
        }
        if (previousTarget !== this.targetData) {
          this.targetRevision += 1;
        }
      }

      if (
        sourceRevision !== this.sourceRevision ||
        targetRevision !== this.targetRevision
      ) {
        continue;
      }

      if (didWrite && pendingFields !== undefined) {
        this.targetData = {...this.targetData, ...pendingFields};
        this.targetRevision += 1;
      }
      return didWrite;
    }
  }
}

class MultiTargetPort implements IdentityPropagationPort {
  private readonly targets: IdentityProjectionReference[];
  private readonly targetData: Map<string, Record<string, unknown>>;

  constructor(
    private readonly sourceData: Record<string, unknown>,
    targets: Array<{
      reference: IdentityProjectionReference;
      data: Record<string, unknown>;
    }>
  ) {
    this.targets = targets.map(({reference}) => reference);
    this.targetData = new Map(
      targets.map(({reference, data}) => [reference.path, {...data}])
    );
  }

  async listTargets(): Promise<IdentityProjectionReference[]> {
    return this.targets;
  }

  async runTransaction(
    operation: (
      transaction: IdentityPropagationTransaction
    ) => Promise<boolean>
  ): Promise<boolean> {
    let update:
      {target: IdentityProjectionReference; fields: Record<string, unknown>} |
      undefined;
    const didWrite = await operation({
      readSource: async () => ({...this.sourceData}),
      readTarget: async (target) => {
        const data = this.targetData.get(target.path);
        return data === undefined ? undefined : {...data};
      },
      updateTarget: (target, fields) => {
        update = {target, fields};
      },
    });

    if (didWrite && update !== undefined) {
      const existing = this.targetData.get(update.target.path) ?? {};
      this.targetData.set(update.target.path, {
        ...existing,
        ...update.fields,
      });
    }
    return didWrite;
  }

  dataFor(path: string): Record<string, unknown> | undefined {
    return this.targetData.get(path);
  }
}

function source(
  displayName: string,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    displayName,
    identityChangedAt: changedAt,
    identityPolicyVersion: 1,
    photoURL: "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/users%2Fuser-1%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc",
    ...overrides,
  };
}

function target(
  displayName: string,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    displayName,
    photoURL: "",
    userId: "user-1",
    ...overrides,
  };
}
