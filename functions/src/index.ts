/**
 * Cloud Functions for AscendApp
 *
 * - Strava: OAuth and activity sync integration
 */

import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

// Initialize Firebase Admin (only once)
admin.initializeApp();

// ============================================
// RE-EXPORT STRAVA FUNCTIONS
// ============================================

export {
  stravaCallback,
  stravaCreateOAuthState,
  stravaCreateActivity,
  stravaDisconnect,
} from "./strava";

// Global options for cost control
setGlobalOptions({maxInstances: 10});
