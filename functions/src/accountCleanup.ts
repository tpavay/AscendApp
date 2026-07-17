import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {buildRatingPromptEmailDedupeKey} from "./email/automation";
import {buildEmailJobId} from "./email/queue";

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";

/**
 * Firestore work the cleanup sweep needs, narrowed to a port so the sweep
 * logic can be tested without the Admin SDK or an emulator.
 */
export interface DeletedUserCleanupPort {
  listUserSubcollections(userId: string): Promise<string[]>;
  deleteSubcollection(userId: string, collectionId: string): Promise<void>;
  deleteLeaderboardStats(userId: string): Promise<number>;
  deleteReplayFinisherStatuses(userId: string): Promise<number>;
  deleteFeedbackDocuments(userId: string): Promise<number>;
  deleteLifecycleEmailJobs(userId: string): Promise<number>;
  deleteRateLimitDocument(userId: string): Promise<void>;
}

export interface CleanupSummary {
  deletedSubcollections: string[];
  deletedLeaderboardEntries: number;
  deletedReplayFinisherStatuses: number;
  deletedFeedbackDocuments: number;
  deletedLifecycleEmailJobs: number;
  failures: string[];
}

/**
 * Removes everything that outlives a deleted users/{uid} document.
 *
 * This is the authoritative sweep, not merely a safety net. The client deletes
 * what firestore.rules lets it delete, but the server-owned subcollections
 * (achievements, lifecycle, lifecycle_events, communication_preferences,
 * notification_devices, integrations, liveClimbPublishStatuses) are all
 * `allow write: if false`, so only the Admin SDK can clear them. The client
 * also cannot recover if it is interrupted mid-deletion: every rule here is
 * gated on isOwner(userId), and the auth user is gone by then.
 *
 * Subcollections are discovered rather than hardcoded so collections added
 * later are swept without anyone remembering to update this list. User-keyed
 * PII that lives *outside* the users/{uid} subtree cannot be discovered that
 * way, so each such record needs its own step here: leaderboard_stats,
 * userRateLimits, the replay finisher statuses, feedback, and the uid-keyed
 * email_jobs. Feedback is hard-deleted rather than anonymized because its
 * `message` is free text the user typed, so it can hold anything they chose to
 * disclose; the admin notification email already carries the report itself.
 *
 * Two records are deliberately left behind. The `firstAscent*` fields on a
 * replay context root outlive the account by product design, and
 * waitlist-welcome email_jobs are keyed by email hash rather than uid because
 * they belong to the newsletter relationship, which has its own unsubscribe
 * path and is not granted or revoked by owning an account.
 *
 * Each step is isolated: one failure must not abandon the rest of the PII.
 * @param {string} userId The uid of the deleted user.
 * @param {DeletedUserCleanupPort} port Firestore operations.
 * @return {Promise<CleanupSummary>} What was deleted and what failed.
 */
export async function cleanupDeletedUser(
  userId: string,
  port: DeletedUserCleanupPort
): Promise<CleanupSummary> {
  const deletedSubcollections: string[] = [];
  const failures: string[] = [];

  let subcollections: string[] = [];
  try {
    subcollections = await port.listUserSubcollections(userId);
  } catch (error) {
    failures.push(`listCollections: ${errorMessage(error)}`);
  }

  for (const collectionId of subcollections) {
    try {
      await port.deleteSubcollection(userId, collectionId);
      deletedSubcollections.push(collectionId);
    } catch (error) {
      failures.push(`${collectionId}: ${errorMessage(error)}`);
    }
  }

  let deletedLeaderboardEntries = 0;
  try {
    deletedLeaderboardEntries = await port.deleteLeaderboardStats(userId);
  } catch (error) {
    failures.push(`leaderboard_stats: ${errorMessage(error)}`);
  }

  let deletedReplayFinisherStatuses = 0;
  try {
    deletedReplayFinisherStatuses = await port.deleteReplayFinisherStatuses(
      userId
    );
  } catch (error) {
    failures.push(`live_replay_finishers: ${errorMessage(error)}`);
  }

  let deletedFeedbackDocuments = 0;
  try {
    deletedFeedbackDocuments = await port.deleteFeedbackDocuments(userId);
  } catch (error) {
    failures.push(`feedback: ${errorMessage(error)}`);
  }

  let deletedLifecycleEmailJobs = 0;
  try {
    deletedLifecycleEmailJobs = await port.deleteLifecycleEmailJobs(userId);
  } catch (error) {
    failures.push(`email_jobs: ${errorMessage(error)}`);
  }

  try {
    await port.deleteRateLimitDocument(userId);
  } catch (error) {
    failures.push(`userRateLimits: ${errorMessage(error)}`);
  }

  return {
    deletedFeedbackDocuments,
    deletedLeaderboardEntries,
    deletedLifecycleEmailJobs,
    deletedReplayFinisherStatuses,
    deletedSubcollections,
    failures,
  };
}

/**
 * Builds the Admin SDK backed port.
 * @param {admin.firestore.Firestore} firestore Handle to sweep through.
 * @return {DeletedUserCleanupPort} Production port.
 */
export function makeAdminPort(
  firestore: admin.firestore.Firestore = admin.firestore()
): DeletedUserCleanupPort {
  const userRef = (userId: string) =>
    firestore.collection("users").doc(userId);

  return {
    async listUserSubcollections(userId) {
      const collections = await userRef(userId).listCollections();
      return collections.map((collection) => collection.id);
    },

    async deleteSubcollection(userId, collectionId) {
      await firestore.recursiveDelete(userRef(userId).collection(collectionId));
    },

    async deleteLeaderboardStats(userId) {
      const snapshot = await firestore
        .collection("leaderboard_stats")
        .where("userId", "==", userId)
        .get();

      if (snapshot.empty) {
        return 0;
      }

      // close() resolves once the writes are no longer pending, never rejects,
      // so only the per-write promises report a permanently failed delete.
      // They are caught as they are created: a rejection with no handler
      // attached before close() settles would surface as an unhandled one.
      const writer = firestore.bulkWriter();
      const deletes = snapshot.docs.map((document) =>
        writer.delete(document.ref).then(
          () => null,
          (error: unknown) => errorMessage(error)
        )
      );
      await writer.close();

      const failures = (await Promise.all(deletes)).filter(
        (failure): failure is string => failure !== null
      );

      if (failures.length > 0) {
        throw new Error(
          `${failures.length} of ${snapshot.size} deletes failed: ` +
            failures.join("; ")
        );
      }

      return snapshot.size;
    },

    async deleteReplayFinisherStatuses(userId) {
      // The finisher document id is the uid, so every replay context is probed
      // directly. A collection group query would need its own index, and the
      // context count is bounded by the climb catalog.
      const contexts = await firestore
        .collection(LIVE_REPLAY_COLLECTION)
        .listDocuments();

      let deleted = 0;
      for (const context of contexts) {
        const finisher = context.collection("finishers").doc(userId);
        const snapshot = await finisher.get();

        if (!snapshot.exists) {
          continue;
        }

        await finisher.delete();
        deleted += 1;
      }

      return deleted;
    },

    async deleteFeedbackDocuments(userId) {
      const snapshot = await firestore
        .collection("feedback")
        .where("userId", "==", userId)
        .get();

      for (const document of snapshot.docs) {
        await document.ref.delete();
      }

      return snapshot.size;
    },

    async deleteLifecycleEmailJobs(userId) {
      // Job ids are the hash of a dedupe key, so only uid-keyed emails are
      // reachable from a uid. Add the key here when a new one is introduced.
      const dedupeKeys = [buildRatingPromptEmailDedupeKey(userId)];

      let deleted = 0;
      for (const dedupeKey of dedupeKeys) {
        const job = firestore
          .collection("email_jobs")
          .doc(buildEmailJobId(dedupeKey));
        const snapshot = await job.get();

        if (!snapshot.exists) {
          continue;
        }

        await job.delete();
        deleted += 1;
      }

      return deleted;
    },

    async deleteRateLimitDocument(userId) {
      await firestore.collection("userRateLimits").doc(userId).delete();
    },
  };
}

/**
 * Extracts a loggable message from an unknown thrown value.
 * @param {unknown} error Thrown value.
 * @return {string} Message.
 */
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Sweeps a deleted user's remaining data.
 *
 * Retries are enabled because this is the only path that can reach server-owned
 * PII once the auth user is gone. The sweep is idempotent: discovery skips
 * collections that are already empty, so re-running only deletes what remains.
 */
export const cleanupDeletedUserData = onDocumentDeleted(
  {document: "users/{userId}", retry: true, timeoutSeconds: 540},
  async (event) => {
    const userId = event.params.userId;
    const summary = await cleanupDeletedUser(userId, makeAdminPort());

    logger.info("Swept deleted user data", {
      deletedFeedbackDocuments: summary.deletedFeedbackDocuments,
      deletedLeaderboardEntries: summary.deletedLeaderboardEntries,
      deletedLifecycleEmailJobs: summary.deletedLifecycleEmailJobs,
      deletedReplayFinisherStatuses: summary.deletedReplayFinisherStatuses,
      deletedSubcollections: summary.deletedSubcollections,
      userId,
    });

    if (summary.failures.length > 0) {
      // Throwing schedules a retry, which is what we want: leftover PII here
      // is unreachable by any other actor.
      throw new Error(
        `Failed to sweep deleted user ${userId}: ${summary.failures.join("; ")}`
      );
    }
  }
);
