/**
 * Cloud Functions for AscendApp
 *
 * - Email: Background transactional waitlist email processing
 */

import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

export {cleanupDeletedUserData} from "./accountCleanup";
export {processEmailJobs} from "./email/processor";
export {onLifecycleEventEmailAutomation} from "./email/automation";
export {onFeedbackCreated} from "./feedback";
export {recordLifecycleEvent} from "./lifecycle";
export {finalizeLeaderboardAchievements} from "./leaderboardAchievements";
export {onWorkoutReplaySplitsWritten} from "./liveReplayLeaderboard";
export {
  registerPushDevice,
  sendClimbDropNotification,
  unregisterPushDevice,
  updatePushNotificationPreferences,
} from "./pushNotifications";
export {joinWaitlist} from "./waitlist";

setGlobalOptions({maxInstances: 10});
