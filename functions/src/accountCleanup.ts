import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {buildRatingPromptEmailDedupeKey} from "./email/automation";
import {buildEmailJobId} from "./email/queue";
import {PUBLIC_IDENTITY_STATE_DELETED} from "./publicIdentity";
import {
  ANALYTICS_OUTBOX_COLLECTION,
} from "./revenueCat/firestoreStore";

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";

/**
 * Display name a First Ascent slot falls back to once its holder deletes their
 * account. The slot stays claimed forever, so it always needs a name to render;
 * an empty one would read as a bug, and the client's generic "Climber" fallback
 * means "no name was stored" rather than "this climber is gone".
 */
export const ANONYMIZED_FIRST_ASCENT_NAME = "Anonymous Climber";

/**
 * Firestore work the cleanup sweep needs, narrowed to a port so the sweep
 * logic can be tested without the Admin SDK or an emulator.
 */
export interface DeletedUserCleanupPort {
  listUserSubcollections(userId: string): Promise<string[]>;
  deleteSubcollection(userId: string, collectionId: string): Promise<void>;
  deleteNotificationDevices(userId: string): Promise<number>;
  deleteLeaderboardStats(userId: string): Promise<number>;
  deleteIdentityPropagationJobs(userId: string): Promise<number>;
  anonymizeReplayEntries(userId: string): Promise<number>;
  deleteReplayFinisherStatuses(userId: string): Promise<number>;
  anonymizeFirstAscents(userId: string): Promise<number>;
  deleteFeedbackDocuments(userId: string): Promise<number>;
  deleteModerationReports(userId: string): Promise<number>;
  deleteIncomingBlockDocuments(userId: string): Promise<number>;
  deleteLifecycleEmailJobs(userId: string): Promise<number>;
  deleteRevenueCatAnalyticsOutbox(userId: string): Promise<number>;
  deleteRateLimitDocument(userId: string): Promise<void>;
}

export interface CleanupSummary {
  deletedSubcollections: string[];
  deletedNotificationDevices: number;
  deletedLeaderboardEntries: number;
  deletedIdentityPropagationJobs: number;
  anonymizedReplayEntries: number;
  deletedReplayFinisherStatuses: number;
  anonymizedFirstAscents: number;
  deletedFeedbackDocuments: number;
  deletedModerationReports: number;
  deletedIncomingBlockDocuments: number;
  deletedLifecycleEmailJobs: number;
  deletedRevenueCatAnalyticsOutbox: number;
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
 * way, so each such record needs its own step here: notification_devices,
 * leaderboard_stats, identity propagation checkpoints, replay entries,
 * userRateLimits, the replay finisher statuses, feedback, moderation_reports,
 * incoming block documents, the uid-keyed email_jobs, and the RevenueCat
 * analytics outbox rows that carry the uid as Mixpanel distinct_id.
 * Feedback and moderation reports are
 * hard-deleted rather than anonymized because their free-text or safety context
 * can identify the user after their account is gone.
 *
 * A First Ascent is de-identified rather than deleted. The claim outlives the
 * account by product design - the slot can never be reclaimed - so the holder's
 * uid, workout id and completion date stay, while the name, photo and avatar
 * token that identify a person are stripped. The uid is kept deliberately: it
 * no longer resolves to anyone once users/{uid} and the auth user are gone, and
 * the client still reads it to decide whether the viewer holds the slot.
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

  let deletedNotificationDevices = 0;
  try {
    deletedNotificationDevices = await port.deleteNotificationDevices(userId);
  } catch (error) {
    failures.push(`notification_devices: ${errorMessage(error)}`);
  }

  let deletedLeaderboardEntries = 0;
  try {
    deletedLeaderboardEntries = await port.deleteLeaderboardStats(userId);
  } catch (error) {
    failures.push(`leaderboard_stats: ${errorMessage(error)}`);
  }

  let deletedIdentityPropagationJobs = 0;
  try {
    deletedIdentityPropagationJobs =
      await port.deleteIdentityPropagationJobs(userId);
  } catch (error) {
    failures.push(`identity_propagation_jobs: ${errorMessage(error)}`);
  }

  let anonymizedReplayEntries = 0;
  try {
    anonymizedReplayEntries = await port.anonymizeReplayEntries(userId);
  } catch (error) {
    failures.push(`live_replay_entries: ${errorMessage(error)}`);
  }

  let deletedReplayFinisherStatuses = 0;
  try {
    deletedReplayFinisherStatuses = await port.deleteReplayFinisherStatuses(
      userId
    );
  } catch (error) {
    failures.push(`live_replay_finishers: ${errorMessage(error)}`);
  }

  let anonymizedFirstAscents = 0;
  try {
    anonymizedFirstAscents = await port.anonymizeFirstAscents(userId);
  } catch (error) {
    failures.push(`live_replay_first_ascents: ${errorMessage(error)}`);
  }

  let deletedFeedbackDocuments = 0;
  try {
    deletedFeedbackDocuments = await port.deleteFeedbackDocuments(userId);
  } catch (error) {
    failures.push(`feedback: ${errorMessage(error)}`);
  }

  let deletedModerationReports = 0;
  try {
    deletedModerationReports = await port.deleteModerationReports(userId);
  } catch (error) {
    failures.push(`moderation_reports: ${errorMessage(error)}`);
  }

  let deletedIncomingBlockDocuments = 0;
  try {
    deletedIncomingBlockDocuments =
      await port.deleteIncomingBlockDocuments(userId);
  } catch (error) {
    failures.push(`incoming_blocks: ${errorMessage(error)}`);
  }

  let deletedLifecycleEmailJobs = 0;
  try {
    deletedLifecycleEmailJobs = await port.deleteLifecycleEmailJobs(userId);
  } catch (error) {
    failures.push(`email_jobs: ${errorMessage(error)}`);
  }

  let deletedRevenueCatAnalyticsOutbox = 0;
  try {
    deletedRevenueCatAnalyticsOutbox =
      await port.deleteRevenueCatAnalyticsOutbox(userId);
  } catch (error) {
    failures.push(`revenuecat_analytics_outbox: ${errorMessage(error)}`);
  }

  try {
    await port.deleteRateLimitDocument(userId);
  } catch (error) {
    failures.push(`userRateLimits: ${errorMessage(error)}`);
  }

  return {
    anonymizedFirstAscents,
    anonymizedReplayEntries,
    deletedFeedbackDocuments,
    deletedModerationReports,
    deletedIncomingBlockDocuments,
    deletedIdentityPropagationJobs,
    deletedLeaderboardEntries,
    deletedLifecycleEmailJobs,
    deletedNotificationDevices,
    deletedReplayFinisherStatuses,
    deletedRevenueCatAnalyticsOutbox,
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

    async deleteNotificationDevices(userId) {
      const snapshot = await firestore
        .collection("notification_devices")
        .where("uid", "==", userId)
        .get();

      for (const document of snapshot.docs) {
        await document.ref.delete();
      }

      return snapshot.size;
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

    async deleteIdentityPropagationJobs(userId) {
      const snapshot = await firestore
        .collection("_public_identity_propagation_jobs")
        .doc(userId)
        .collection("kinds")
        .get();

      for (const document of snapshot.docs) {
        await document.ref.delete();
      }

      return snapshot.size;
    },

    async anonymizeReplayEntries(userId) {
      const snapshot = await firestore
        .collectionGroup("entries")
        .where("userId", "==", userId)
        .get();

      if (snapshot.empty) {
        return 0;
      }

      const fields = {
        avatarToken: "",
        displayName: ANONYMIZED_FIRST_ASCENT_NAME,
        identityState: PUBLIC_IDENTITY_STATE_DELETED,
        isSynthetic: false,
        photoURL: "",
      };
      const writer = firestore.bulkWriter();
      const updates = snapshot.docs.map((document) =>
        writer.update(document.ref, fields).then(
          () => null,
          (error: unknown) => errorMessage(error)
        )
      );
      await writer.close();

      const failures = (await Promise.all(updates)).filter(
        (failure): failure is string => failure !== null
      );
      if (failures.length > 0) {
        throw new Error(
          `${failures.length} of ${snapshot.size} updates failed: ` +
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

    async anonymizeFirstAscents(userId) {
      // firstAscentUserId sits on the context root of a top-level collection,
      // so Firestore's automatic single-field index already serves this. The
      // finisher sweep above cannot do the same because those documents are in
      // a subcollection, where matching on a field would need its own index.
      const snapshot = await firestore
        .collection(LIVE_REPLAY_COLLECTION)
        .where("firstAscentUserId", "==", userId)
        .get();

      for (const document of snapshot.docs) {
        // firstAscentUserId, firstAscentWorkoutId and firstAscentCompletedAt
        // are left alone: they keep the slot claimed and dated, which is the
        // permanent prestige the climb is meant to carry.
        await document.ref.update({
          firstAscentAvatarToken: "",
          firstAscentDisplayName: ANONYMIZED_FIRST_ASCENT_NAME,
          firstAscentIdentityState: PUBLIC_IDENTITY_STATE_DELETED,
          firstAscentIsSynthetic: false,
          firstAscentPhotoURL: "",
        });
      }

      return snapshot.size;
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

    async deleteModerationReports(userId) {
      const [submittedReports, reportsAboutUser] = await Promise.all([
        firestore
          .collection("moderation_reports")
          .where("reporterUserId", "==", userId)
          .get(),
        firestore
          .collection("moderation_reports")
          .where("reportedUserId", "==", userId)
          .get(),
      ]);

      const reportsByPath = new Map(
        [...submittedReports.docs, ...reportsAboutUser.docs].map((document) => [
          document.ref.path,
          document.ref,
        ])
      );

      for (const report of reportsByPath.values()) {
        await report.delete();
      }

      return reportsByPath.size;
    },

    async deleteIncomingBlockDocuments(userId) {
      const snapshot = await firestore
        .collectionGroup("blocked")
        .where("blockedUid", "==", userId)
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

    async deleteRevenueCatAnalyticsOutbox(userId) {
      const snapshot = await firestore
        .collection(ANALYTICS_OUTBOX_COLLECTION)
        .where("distinctId", "==", userId)
        .get();

      for (const document of snapshot.docs) {
        await document.ref.delete();
      }
      return snapshot.size;
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
      anonymizedFirstAscents: summary.anonymizedFirstAscents,
      anonymizedReplayEntries: summary.anonymizedReplayEntries,
      deletedFeedbackDocuments: summary.deletedFeedbackDocuments,
      deletedModerationReports: summary.deletedModerationReports,
      deletedIncomingBlockDocuments:
        summary.deletedIncomingBlockDocuments,
      deletedIdentityPropagationJobs:
        summary.deletedIdentityPropagationJobs,
      deletedLeaderboardEntries: summary.deletedLeaderboardEntries,
      deletedLifecycleEmailJobs: summary.deletedLifecycleEmailJobs,
      deletedNotificationDevices: summary.deletedNotificationDevices,
      deletedReplayFinisherStatuses: summary.deletedReplayFinisherStatuses,
      deletedRevenueCatAnalyticsOutbox:
        summary.deletedRevenueCatAnalyticsOutbox,
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
