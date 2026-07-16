import test from "node:test";
import assert from "node:assert/strict";
import {
  cleanupDeletedUser,
  DeletedUserCleanupPort,
} from "../src/accountCleanup.js";

interface FakePortOptions {
  subcollections?: string[];
  leaderboardEntries?: number;
  replayFinisherStatuses?: number;
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
