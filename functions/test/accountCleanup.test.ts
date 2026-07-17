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
  leaderboardEntries?: number;
  replayFinisherStatuses?: number;
  firstAscents?: number;
  feedbackDocuments?: number;
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

    async deleteLeaderboardStats() {
      if (failOn.has("leaderboard_stats")) {
        throw new Error("cannot delete leaderboard_stats");
      }
      deleted.push("leaderboard_stats");
      return options.leaderboardEntries ?? 0;
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
