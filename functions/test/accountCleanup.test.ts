import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  ANONYMIZED_FIRST_ASCENT_NAME,
  cleanupDeletedUser,
  DeletedUserCleanupPort,
  makeAdminPort,
} from "../src/accountCleanup.js";

interface FakePortOptions {
  subcollections?: string[];
  notificationDevices?: number;
  leaderboardEntries?: number;
  identityPropagationJobs?: number;
  replayEntries?: number;
  replayFinisherStatuses?: number;
  firstAscents?: number;
  feedbackDocuments?: number;
  moderationReports?: number;
  incomingBlockDocuments?: number;
  lifecycleEmailJobs?: number;
  failOn?: string[];
  failListing?: boolean;
}

/**
 * Builds an in-memory cleanup port that records what it deleted.
 * @param {FakePortOptions} options Collections to report, failures to inject.
 * @return {object} The port plus the ordered list of deleted collection ids.
 */
function makeFakePort(options: FakePortOptions = {}): {
  port: DeletedUserCleanupPort;
  deleted: string[];
} {
  const deleted: string[] = [];
  const failOn = new Set(options.failOn ?? []);

  const port: DeletedUserCleanupPort = {
    async listUserSubcollections() {
      if (options.failListing) {
        throw new Error("listCollections unavailable");
      }
      return options.subcollections ?? [];
    },

    async deleteSubcollection(userId, collectionId) {
      if (failOn.has(collectionId)) {
        throw new Error(`cannot delete ${collectionId}`);
      }
      deleted.push(collectionId);
    },

    async deleteNotificationDevices() {
      if (failOn.has("notification_devices_root")) {
        throw new Error("cannot delete notification_devices");
      }
      deleted.push("notification_devices_root");
      return options.notificationDevices ?? 0;
    },

    async deleteLeaderboardStats() {
      if (failOn.has("leaderboard_stats")) {
        throw new Error("cannot delete leaderboard_stats");
      }
      deleted.push("leaderboard_stats");
      return options.leaderboardEntries ?? 0;
    },

    async deleteIdentityPropagationJobs() {
      if (failOn.has("identity_propagation_jobs")) {
        throw new Error("cannot delete identity_propagation_jobs");
      }
      deleted.push("identity_propagation_jobs");
      return options.identityPropagationJobs ?? 0;
    },

    async anonymizeReplayEntries() {
      if (failOn.has("live_replay_entries")) {
        throw new Error("cannot anonymize live_replay_entries");
      }
      deleted.push("live_replay_entries");
      return options.replayEntries ?? 0;
    },

    async deleteReplayFinisherStatuses() {
      if (failOn.has("live_replay_finishers")) {
        throw new Error("cannot delete live_replay_finishers");
      }
      deleted.push("live_replay_finishers");
      return options.replayFinisherStatuses ?? 0;
    },

    async anonymizeFirstAscents() {
      if (failOn.has("live_replay_first_ascents")) {
        throw new Error("cannot anonymize live_replay_first_ascents");
      }
      deleted.push("live_replay_first_ascents");
      return options.firstAscents ?? 0;
    },

    async deleteFeedbackDocuments() {
      if (failOn.has("feedback")) {
        throw new Error("cannot delete feedback");
      }
      deleted.push("feedback");
      return options.feedbackDocuments ?? 0;
    },

    async deleteModerationReports() {
      if (failOn.has("moderation_reports")) {
        throw new Error("cannot delete moderation_reports");
      }
      deleted.push("moderation_reports");
      return options.moderationReports ?? 0;
    },

    async deleteIncomingBlockDocuments() {
      if (failOn.has("incoming_blocks")) {
        throw new Error("cannot delete incoming_blocks");
      }
      deleted.push("incoming_blocks");
      return options.incomingBlockDocuments ?? 0;
    },

    async deleteLifecycleEmailJobs() {
      if (failOn.has("email_jobs")) {
        throw new Error("cannot delete email_jobs");
      }
      deleted.push("email_jobs");
      return options.lifecycleEmailJobs ?? 0;
    },

    async deleteRateLimitDocument() {
      if (failOn.has("userRateLimits")) {
        throw new Error("cannot delete userRateLimits");
      }
      deleted.push("userRateLimits");
    },
  };

  return {deleted, port};
}

/**
 * Builds a Firestore stand-in whose leaderboard_stats query returns
 * `documentCount` documents and whose BulkWriter fails `failingDeletes` of
 * them the way a permanent error does: the per-write promise rejects while
 * close() still resolves.
 * @param {number} documentCount Matching leaderboard_stats documents.
 * @param {number} failingDeletes How many of those deletes reject.
 * @return {admin.firestore.Firestore} The stand-in.
 */
function makeLeaderboardFirestore(
  documentCount: number,
  failingDeletes: number
): admin.firestore.Firestore {
  const docs = Array.from({length: documentCount}, (_unused, index) => ({
    ref: {id: `entry-${index}`},
  }));

  let deleteCount = 0;
  const firestore = {
    bulkWriter() {
      return {
        delete() {
          deleteCount += 1;
          return deleteCount <= failingDeletes ?
            Promise.reject(new Error("7 PERMISSION_DENIED")) :
            Promise.resolve({});
        },
        // Mirrors the documented contract: "Returns a Promise that resolves
        // when there are no more pending writes. The Promise will never be
        // rejected."
        close() {
          return Promise.resolve();
        },
      };
    },
    collection() {
      return {
        where() {
          return {
            get() {
              return Promise.resolve({
                docs,
                empty: docs.length === 0,
                size: docs.length,
              });
            },
          };
        },
      };
    },
  };

  return firestore as unknown as admin.firestore.Firestore;
}

/**
 * Builds a collection-group stand-in for replay-entry anonymization.
 * @param {number} failingUpdates Number of BulkWriter updates to reject.
 * @return {object} Firestore stand-in, records, and observed query fields.
 */
function makeReplayEntriesFirestore(failingUpdates = 0) {
  const entries = [
    {
      avatarToken: "MC",
      displayName: "Maya Chen",
      elapsedTime: 1_234,
      finalSteps: 4_567,
      identityState: "published",
      isSynthetic: false,
      photoURL: "https://example.com/maya.jpg",
      rank: 2,
      stepsAtBucket: 3_000,
      userId: "user-a",
    },
    {
      avatarToken: "MA",
      displayName: "Maya Again",
      elapsedTime: 2_345,
      finalSteps: 5_678,
      identityState: "published",
      isSynthetic: false,
      photoURL: "https://example.com/maya-again.jpg",
      rank: 1,
      stepsAtBucket: 4_000,
      userId: "user-a",
    },
    {
      avatarToken: "OB",
      displayName: "Other",
      elapsedTime: 3_456,
      finalSteps: 6_789,
      identityState: "published",
      isSynthetic: false,
      photoURL: "https://example.com/other.jpg",
      rank: 3,
      stepsAtBucket: 5_000,
      userId: "user-b",
    },
  ];
  let queriedCollectionGroup: string | null = null;
  let queriedField: string | null = null;
  let updateCount = 0;

  const firestore = {
    bulkWriter() {
      return {
        async update(
          ref: {record: Record<string, unknown>},
          fields: Record<string, unknown>
        ) {
          updateCount += 1;
          if (updateCount <= failingUpdates) {
            throw new Error("7 PERMISSION_DENIED");
          }
          Object.assign(ref.record, fields);
        },
        async close() {},
      };
    },
    collectionGroup(collectionGroup: string) {
      queriedCollectionGroup = collectionGroup;
      return {
        where(field: string, _operator: string, userId: string) {
          queriedField = field;
          const docs = entries
            .filter((entry) => entry.userId === userId)
            .map((entry) => ({ref: {record: entry}}));
          return {
            async get() {
              return {
                docs,
                empty: docs.length === 0,
                size: docs.length,
              };
            },
          };
        },
      };
    },
  };

  return {
    entries,
    firestore: firestore as unknown as admin.firestore.Firestore,
    queriedCollectionGroup: () => queriedCollectionGroup,
    queriedField: () => queriedField,
  };
}

/**
 * Builds a Firestore stand-in holding one replay context whose First Ascent is
 * held by `holderId`, and records the merge the sweep applies to it.
 * @param {string} holderId Uid stored in firstAscentUserId.
 * @return {object} The stand-in plus the context's current fields.
 */
function makeFirstAscentFirestore(holderId: string): {
  firestore: admin.firestore.Firestore;
  context: Record<string, unknown>;
  queriedField: () => string | null;
} {
  const context: Record<string, unknown> = {
    firstAscentAvatarToken: "TP",
    firstAscentCompletedAt: "2026-06-11T00:00:00.000Z",
    firstAscentDisplayName: "Tyler Pavay",
    firstAscentPhotoURL: "https://example.com/tyler.jpg",
    firstAscentUserId: holderId,
    firstAscentWorkoutId: "workout-1",
  };

  let queriedField: string | null = null;
  const ref = {
    async update(fields: Record<string, unknown>) {
      Object.assign(context, fields);
    },
  };

  const firestore = {
    collection() {
      return {
        where(field: string, _op: string, value: string) {
          queriedField = field;
          const docs = context.firstAscentUserId === value ? [{ref}] : [];
          return {
            get() {
              return Promise.resolve({
                docs,
                empty: docs.length === 0,
                size: docs.length,
              });
            },
          };
        },
      };
    },
  };

  return {
    context,
    firestore: firestore as unknown as admin.firestore.Firestore,
    queriedField: () => queriedField,
  };
}

/**
 * Builds a collection-group stand-in for blocks held by other users.
 * @param {string[]} blockedUserIds Values stored in blockedUid.
 * @return {object} Firestore stand-in and the deleted values.
 */
function makeIncomingBlocksFirestore(
  blockedUserIds: string[]
): {
  firestore: admin.firestore.Firestore;
  deletedUserIds: string[];
} {
  const deletedUserIds: string[] = [];
  const firestore = {
    collectionGroup(collectionId: string) {
      assert.equal(collectionId, "blocked");
      return {
        where(field: string, operation: string, value: string) {
          assert.equal(field, "blockedUid");
          assert.equal(operation, "==");
          const matches = blockedUserIds.filter((userId) => userId === value);
          return {
            async get() {
              return {
                docs: matches.map((userId) => ({
                  ref: {
                    async delete() {
                      deletedUserIds.push(userId);
                    },
                  },
                })),
                size: matches.length,
              };
            },
          };
        },
      };
    },
  };

  return {
    deletedUserIds,
    firestore: firestore as unknown as admin.firestore.Firestore,
  };
}

test("sweeps server-owned subcollections a client cannot delete", async () => {
  const {deleted, port} = makeFakePort({
    subcollections: [
      "achievements",
      "communication_preferences",
      "integrations",
      "lifecycle",
      "lifecycle_events",
      "notification_devices",
    ],
  });

  const summary = await cleanupDeletedUser("user-a", port);

  // These are all `allow write: if false` in firestore.rules, so the Admin SDK
  // is the only actor that can ever clear them.
  assert.deepEqual(summary.deletedSubcollections, [
    "achievements",
    "communication_preferences",
    "integrations",
    "lifecycle",
    "lifecycle_events",
    "notification_devices",
  ]);
  assert.deepEqual(summary.failures, []);
  assert.ok(deleted.includes("achievements"));
});

test("sweeps mirrors left behind by an interrupted client", async () => {
  const {port} = makeFakePort({
    subcollections: ["profile_workouts", "public_profile", "workouts"],
  });

  const summary = await cleanupDeletedUser("user-a", port);

  assert.deepEqual(summary.deletedSubcollections, [
    "profile_workouts",
    "public_profile",
    "workouts",
  ]);
  assert.deepEqual(summary.failures, []);
});

test("discovers subcollections rather than assuming a fixed list", async () => {
  const {port} = makeFakePort({subcollections: ["some_future_collection"]});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.deepEqual(summary.deletedSubcollections, ["some_future_collection"]);
});

test("removes leaderboard entries so deleted users stop ranking", async () => {
  const {deleted, port} = makeFakePort({leaderboardEntries: 3});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedLeaderboardEntries, 3);
  assert.ok(deleted.includes("leaderboard_stats"));
});

test("removes all external identity propagation checkpoints", async () => {
  const {deleted, port} = makeFakePort({identityPropagationJobs: 4});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedIdentityPropagationJobs, 4);
  assert.ok(deleted.includes("identity_propagation_jobs"));
});

test("Admin cleanup deletes each persisted propagation kind", async () => {
  const deletedKinds: string[] = [];
  const kinds = ["leaderboard", "replayEntry", "replayFinisher", "firstAscent"];
  const firestore = {
    collection(collectionId: string) {
      assert.equal(collectionId, "_public_identity_propagation_jobs");
      return {
        doc(userId: string) {
          assert.equal(userId, "user-a");
          return {
            collection(subcollectionId: string) {
              assert.equal(subcollectionId, "kinds");
              return {
                async get() {
                  return {
                    docs: kinds.map((kind) => ({
                      ref: {
                        async delete() {
                          deletedKinds.push(kind);
                        },
                      },
                    })),
                    size: kinds.length,
                  };
                },
              };
            },
          };
        },
      };
    },
  } as unknown as admin.firestore.Firestore;

  const count = await makeAdminPort(firestore)
    .deleteIdentityPropagationJobs("user-a");

  assert.equal(count, 4);
  assert.deepEqual(deletedKinds, kinds);
});

test("a failing checkpoint sweep is reported without abandoning cleanup", async () => {
  const {deleted, port} = makeFakePort({
    failOn: ["identity_propagation_jobs"],
  });

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedIdentityPropagationJobs, 0);
  assert.match(
    summary.failures.join(" "),
    /identity_propagation_jobs: cannot delete identity_propagation_jobs/
  );
  assert.ok(deleted.includes("live_replay_finishers"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("anonymizes replay entries that can outlive the user root", async () => {
  const {deleted, port} = makeFakePort({replayEntries: 3});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.anonymizedReplayEntries, 3);
  assert.ok(deleted.includes("live_replay_entries"));
});

test("Admin replay cleanup preserves every competitive field", async () => {
  const store = makeReplayEntriesFirestore();

  const count = await makeAdminPort(store.firestore)
    .anonymizeReplayEntries("user-a");

  assert.equal(count, 2);
  assert.equal(store.queriedCollectionGroup(), "entries");
  assert.equal(store.queriedField(), "userId");
  for (const [index, entry] of store.entries.slice(0, 2).entries()) {
    assert.deepEqual({
      avatarToken: entry.avatarToken,
      displayName: entry.displayName,
      identityState: entry.identityState,
      isSynthetic: entry.isSynthetic,
      photoURL: entry.photoURL,
    }, {
      avatarToken: "",
      displayName: ANONYMIZED_FIRST_ASCENT_NAME,
      identityState: "deleted",
      isSynthetic: false,
      photoURL: "",
    });
    assert.equal(entry.elapsedTime, 1_234 + (index * 1_111));
    assert.equal(entry.finalSteps, 4_567 + (index * 1_111));
    assert.equal(entry.rank, 2 - index);
    assert.equal(entry.stepsAtBucket, 3_000 + (index * 1_000));
  }
  assert.equal(store.entries[2].displayName, "Other");
  assert.equal(store.entries[2].photoURL, "https://example.com/other.jpg");
});

test("a failing replay-entry sweep is reported without abandoning cleanup", async () => {
  const {deleted, port} = makeFakePort({
    failOn: ["live_replay_entries"],
  });

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.anonymizedReplayEntries, 0);
  assert.match(
    summary.failures.join(" "),
    /live_replay_entries: cannot anonymize live_replay_entries/
  );
  assert.ok(deleted.includes("live_replay_finishers"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("a permanently failed replay-entry update lands in failures", async () => {
  const {port} = makeFakePort();
  const adminPort = makeAdminPort(makeReplayEntriesFirestore(1).firestore);
  port.anonymizeReplayEntries = adminPort.anonymizeReplayEntries;

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.anonymizedReplayEntries, 0);
  assert.match(
    summary.failures.join(" "),
    /live_replay_entries: 1 of 2 updates failed: 7 PERMISSION_DENIED/
  );
});

/**
 * Builds a Firestore stand-in holding notification device records for two
 * users, recording which collection and field the sweep queried.
 * @return {object} The stand-in, the surviving document ids, and the query.
 */
function makeNotificationDeviceFirestore() {
  const devices = new Map<string, string>([
    ["hash-1", "user-a"],
    ["hash-2", "user-a"],
    ["hash-3", "user-b"],
  ]);
  let queriedCollection: string | null = null;
  let queriedField: string | null = null;

  const firestore = {
    collection(collectionId: string) {
      queriedCollection = collectionId;
      return {
        where(field: string, _op: string, value: string) {
          queriedField = field;
          const docs = [...devices.entries()]
            .filter(([, uid]) => uid === value)
            .map(([id]) => ({
              ref: {
                delete() {
                  devices.delete(id);
                  return Promise.resolve({});
                },
              },
            }));
          return {
            get() {
              return Promise.resolve({
                docs,
                empty: docs.length === 0,
                size: docs.length,
              });
            },
          };
        },
      };
    },
  };

  return {
    firestore: firestore as unknown as admin.firestore.Firestore,
    queriedCollection: () => queriedCollection,
    queriedField: () => queriedField,
    remaining: () => [...devices.keys()],
  };
}

test("deletes every device record the top-level uid field owns", async () => {
  const store = makeNotificationDeviceFirestore();

  // notification_devices keys its owner under `uid`, while the sibling
  // leaderboard_stats sweep keys it under `userId`. Mixing the two silently
  // leaves every delivery record behind.
  const port = makeAdminPort(store.firestore);

  assert.equal(await port.deleteNotificationDevices("user-a"), 2);

  assert.equal(store.queriedCollection(), "notification_devices");
  assert.equal(store.queriedField(), "uid");
  assert.deepEqual(store.remaining(), ["hash-3"]);
});

test("removes top-level notification delivery records", async () => {
  const {deleted, port} = makeFakePort({notificationDevices: 2});

  const summary = await cleanupDeletedUser("user-a", port);

  // The callable writes delivery records at notification_devices/{tokenHash},
  // outside the users/{uid} subtree discovered by listCollections().
  assert.equal(summary.deletedNotificationDevices, 2);
  assert.ok(deleted.includes("notification_devices_root"));
});

test("a failing notification device sweep is reported for retry", async () => {
  const {deleted, port} = makeFakePort({
    failOn: ["notification_devices_root"],
  });

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedNotificationDevices, 0);
  assert.equal(summary.failures.length, 1);
  assert.match(
    summary.failures[0],
    /notification_devices: cannot delete notification_devices/
  );
  assert.ok(deleted.includes("leaderboard_stats"));
});

test("removes replay finishers living outside users/{uid}", async () => {
  const {deleted, port} = makeFakePort({replayFinisherStatuses: 2});

  const summary = await cleanupDeletedUser("user-a", port);

  // finishers/{uid} carries displayName, photoURL and demographics, is
  // `allow write: if false`, and sits under live_replay_leaderboards, so
  // subcollection discovery under users/{uid} can never reach it.
  assert.equal(summary.deletedReplayFinisherStatuses, 2);
  assert.ok(deleted.includes("live_replay_finishers"));
});

test("de-identifies a First Ascent the deleted user holds", async () => {
  const {context, firestore} = makeFirstAscentFirestore("user-a");
  const port = makeAdminPort(firestore);

  assert.equal(await port.anonymizeFirstAscents("user-a"), 1);

  // The person is gone from the record; the claim is not.
  assert.equal(context.firstAscentDisplayName, ANONYMIZED_FIRST_ASCENT_NAME);
  assert.equal(context.firstAscentPhotoURL, "");
  assert.equal(context.firstAscentAvatarToken, "");
  assert.equal(context.firstAscentIdentityState, "deleted");
  assert.equal(context.firstAscentIsSynthetic, false);
});

test("a de-identified First Ascent keeps its slot and date", async () => {
  const {context, firestore} = makeFirstAscentFirestore("user-a");

  await makeAdminPort(firestore).anonymizeFirstAscents("user-a");

  // firestoreLiveReplayLeaderboardRepository gates the whole First Ascent on
  // firstAscentCompletedAt, so dropping it would reopen a slot that can never
  // be reclaimed. The uid stays as a pseudonymous key that resolves to nobody.
  assert.equal(context.firstAscentCompletedAt, "2026-06-11T00:00:00.000Z");
  assert.equal(context.firstAscentUserId, "user-a");
  assert.equal(context.firstAscentWorkoutId, "workout-1");
});

test("leaves First Ascents held by other climbers untouched", async () => {
  const {context, firestore} = makeFirstAscentFirestore("user-b");
  const port = makeAdminPort(firestore);

  assert.equal(await port.anonymizeFirstAscents("user-a"), 0);

  assert.equal(context.firstAscentDisplayName, "Tyler Pavay");
  assert.equal(context.firstAscentPhotoURL, "https://example.com/tyler.jpg");
});

test("finds First Ascents without needing a new Firestore index", async () => {
  const {firestore, queriedField} = makeFirstAscentFirestore("user-a");

  await makeAdminPort(firestore).anonymizeFirstAscents("user-a");

  // A single-field equality match on a top-level collection is served by the
  // automatic index; a collection group query would need one deployed first.
  assert.equal(queriedField(), "firstAscentUserId");
});

test("a failing First Ascent sweep is reported for retry", async () => {
  const {deleted, port} = makeFakePort({failOn: ["live_replay_first_ascents"]});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.anonymizedFirstAscents, 0);
  assert.equal(summary.failures.length, 1);
  assert.match(
    summary.failures[0],
    /live_replay_first_ascents: cannot anonymize live_replay_first_ascents/
  );
  assert.ok(deleted.includes("feedback"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("removes feedback carrying the user's email and message", async () => {
  const {deleted, port} = makeFakePort({feedbackDocuments: 2});

  const summary = await cleanupDeletedUser("user-a", port);

  // feedback/{id} is `allow read, update, delete: if false` and holds userId,
  // userEmail and free-text message, so only the Admin SDK can clear it.
  assert.equal(summary.deletedFeedbackDocuments, 2);
  assert.ok(deleted.includes("feedback"));
});

test("removes moderation reports submitted by or about the user", async () => {
  const {deleted, port} = makeFakePort({moderationReports: 3});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedModerationReports, 3);
  assert.ok(deleted.includes("moderation_reports"));
});

test(
  "removes the deleted user's own block list as a discovered subtree",
  async () => {
    const {port} = makeFakePort({subcollections: ["blocked"]});

    const summary = await cleanupDeletedUser("user-a", port);

    assert.deepEqual(summary.deletedSubcollections, ["blocked"]);
  }
);

test(
  "removes blocks of the deleted user held in other users' lists",
  async () => {
    const {deleted, port} = makeFakePort({incomingBlockDocuments: 3});

    const summary = await cleanupDeletedUser("user-a", port);

    assert.equal(summary.deletedIncomingBlockDocuments, 3);
    assert.ok(deleted.includes("incoming_blocks"));
  }
);

test(
  "Admin cleanup finds incoming blocks with a collection-group query",
  async () => {
    const {deletedUserIds, firestore} = makeIncomingBlocksFirestore([
      "user-a",
      "user-b",
      "user-a",
    ]);

    const count = await makeAdminPort(firestore)
      .deleteIncomingBlockDocuments("user-a");

    assert.equal(count, 2);
    assert.deepEqual(deletedUserIds, ["user-a", "user-a"]);
  }
);

test("a failing moderation report sweep is reported for retry", async () => {
  const {deleted, port} = makeFakePort({failOn: ["moderation_reports"]});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedModerationReports, 0);
  assert.match(
    summary.failures.join(" "),
    /moderation_reports: cannot delete moderation_reports/
  );
  assert.ok(deleted.includes("email_jobs"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("removes queued lifecycle email jobs holding a raw email", async () => {
  const {deleted, port} = makeFakePort({lifecycleEmailJobs: 1});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedLifecycleEmailJobs, 1);
  assert.ok(deleted.includes("email_jobs"));
});

test("one failing subcollection does not abandon other PII", async () => {
  const {deleted, port} = makeFakePort({
    failOn: ["lifecycle"],
    subcollections: ["achievements", "lifecycle", "public_profile"],
  });

  const summary = await cleanupDeletedUser("user-a", port);

  assert.deepEqual(summary.deletedSubcollections, [
    "achievements",
    "public_profile",
  ]);
  assert.equal(summary.failures.length, 1);
  assert.match(summary.failures[0], /lifecycle: cannot delete lifecycle/);
  assert.ok(deleted.includes("leaderboard_stats"));
  assert.ok(deleted.includes("live_replay_finishers"));
  assert.ok(deleted.includes("feedback"));
  assert.ok(deleted.includes("moderation_reports"));
  assert.ok(deleted.includes("email_jobs"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("a failing feedback sweep is reported for retry", async () => {
  const {deleted, port} = makeFakePort({failOn: ["feedback"]});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedFeedbackDocuments, 0);
  assert.equal(summary.failures.length, 1);
  assert.match(summary.failures[0], /feedback: cannot delete feedback/);
  assert.ok(deleted.includes("email_jobs"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("a failing leaderboard sweep is reported for retry", async () => {
  const {deleted, port} = makeFakePort({
    failOn: ["leaderboard_stats"],
    leaderboardEntries: 3,
  });

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedLeaderboardEntries, 0);
  assert.equal(summary.failures.length, 1);
  assert.match(
    summary.failures[0],
    /leaderboard_stats: cannot delete leaderboard_stats/
  );
  assert.ok(deleted.includes("live_replay_finishers"));
  assert.ok(deleted.includes("feedback"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("a permanently failed leaderboard delete is not a success", async () => {
  // BulkWriter.close() resolves even when a write permanently fails, so a
  // discarded per-write promise would report the ghost-on-leaderboard entry
  // as swept and the retry policy would never fire.
  const port = makeAdminPort(makeLeaderboardFirestore(3, 1));

  await assert.rejects(
    () => port.deleteLeaderboardStats("user-a"),
    /1 of 3 deletes failed: 7 PERMISSION_DENIED/
  );
});

test("a permanently failed leaderboard delete lands in failures", async () => {
  const {port} = makeFakePort();
  const adminPort = makeAdminPort(makeLeaderboardFirestore(2, 2));
  port.deleteLeaderboardStats = adminPort.deleteLeaderboardStats;

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedLeaderboardEntries, 0);
  assert.equal(summary.failures.length, 1);
  assert.match(summary.failures[0], /leaderboard_stats: 2 of 2 deletes failed/);
});

test("a leaderboard sweep counts only writes that succeeded", async () => {
  const port = makeAdminPort(makeLeaderboardFirestore(3, 0));

  assert.equal(await port.deleteLeaderboardStats("user-a"), 3);
});

test("a failing finisher sweep is reported for retry", async () => {
  const {deleted, port} = makeFakePort({failOn: ["live_replay_finishers"]});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.deletedReplayFinisherStatuses, 0);
  assert.equal(summary.failures.length, 1);
  assert.match(
    summary.failures[0],
    /live_replay_finishers: cannot delete live_replay_finishers/
  );
  assert.ok(deleted.includes("userRateLimits"));
});

test("a failed listing still clears the top-level user records", async () => {
  const {deleted, port} = makeFakePort({failListing: true});

  const summary = await cleanupDeletedUser("user-a", port);

  assert.deepEqual(summary.deletedSubcollections, []);
  assert.equal(summary.failures.length, 1);
  assert.match(
    summary.failures[0],
    /listCollections: listCollections unavailable/
  );
  assert.ok(deleted.includes("leaderboard_stats"));
  assert.ok(deleted.includes("userRateLimits"));
});

test("failures are reported so the trigger can retry", async () => {
  const {port} = makeFakePort({
    failOn: ["leaderboard_stats", "userRateLimits"],
    subcollections: [],
  });

  const summary = await cleanupDeletedUser("user-a", port);

  assert.equal(summary.failures.length, 2);
});
