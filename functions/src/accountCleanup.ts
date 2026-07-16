import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

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
  deleteRateLimitDocument(userId: string): Promise<void>;
}

export interface CleanupSummary {
  deletedSubcollections: string[];
  deletedLeaderboardEntries: number;
  deletedReplayFinisherStatuses: number;
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
 * userRateLimits, and the replay finisher statuses.
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

  try {
    await port.deleteRateLimitDocument(userId);
  } catch (error) {
    failures.push(`userRateLimits: ${errorMessage(error)}`);
  }

  return {
    deletedLeaderboardEntries,
    deletedReplayFinisherStatuses,
    deletedSubcollections,
    failures,
  };
}

/**
 * Builds the Admin SDK backed port.
 * @return {DeletedUserCleanupPort} Production port.
 */
function makeAdminPort(): DeletedUserCleanupPort {
  const firestore = admin.firestore();
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

      const writer = firestore.bulkWriter();
      for (const document of snapshot.docs) {
        void writer.delete(document.ref);
      }
      await writer.close();

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
  {document: "users/{userId}", retry: true},
  async (event) => {
    const userId = event.params.userId;
    const summary = await cleanupDeletedUser(userId, makeAdminPort());

    logger.info("Swept deleted user data", {
      deletedLeaderboardEntries: summary.deletedLeaderboardEntries,
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
