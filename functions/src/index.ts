/**
 * Cloud Functions for AscendApp
 *
 * - Email: Background transactional email processing
 */

import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

export {cleanupDeletedUserData} from "./accountCleanup";
export {announceClimbDrops} from "./climbDropNotifications";
export {onWorkoutWritten} from "./climbCompletions";
export {processEmailJobs} from "./email/processor";
export {onLifecycleEventEmailAutomation} from "./email/automation";
export {unsubscribeFromEmails} from "./email/unsubscribe";
export {onFeedbackCreated} from "./feedback";
export {recordLifecycleEvent} from "./lifecycle";
export {finalizeLeaderboardAchievements} from "./leaderboardAchievements";
export {
  onUserDemographicsWrittenLeaderboardStats,
  onWorkoutWrittenLeaderboardStats,
} from "./leaderboardStats";
export {onWorkoutReplaySplitsWritten} from "./liveReplayLeaderboard";
export {
  onPublicIdentityPropagationJobWritten,
  onPublicProfileIdentityWritten,
} from "./publicIdentityPropagation";
export {
  registerPushDevice,
  sendClimbDropNotification,
  unregisterPushDevice,
  updatePushNotificationPreferences,
} from "./pushNotifications";
export {revenueCatWebhook} from "./revenueCat/webhook";
export {
  processRevenueCatAnalyticsOutbox,
} from "./revenueCat/analyticsExporter";
export {reconcileAppAccess} from "./revenueCat/reconciliation";
export {
  expireRevenueCatEntitlements,
} from "./revenueCat/expiration";

setGlobalOptions({maxInstances: 10});
