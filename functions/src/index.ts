/**
 * Cloud Functions for AscendApp
 *
 * - Strava: OAuth and activity sync integration
 * - Email: Background transactional waitlist email processing
 */

import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

export {processEmailJobs} from "./email/processor";
export {onFeedbackCreated} from "./feedback";
export {onWorkoutReplaySplitsWritten} from "./liveReplayLeaderboard";
export {joinWaitlist} from "./waitlist";

export {
  stravaCallback,
  stravaCreateOAuthState,
  stravaCreateActivity,
  stravaDisconnect,
} from "./strava";

setGlobalOptions({maxInstances: 10});
