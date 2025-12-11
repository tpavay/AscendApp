/**
 * Strava Integration Cloud Functions
 *
 * Handles OAuth flow, activity creation, and disconnection
 * for Strava integration.
 * Client secret is stored in Firebase Functions config (never in the app).
 */

import {onRequest, onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {randomUUID} from "crypto";

// Strava API endpoints
const STRAVA_AUTH_URL = "https://www.strava.com/oauth/token";
const STRAVA_API_BASE = "https://www.strava.com/api/v3";
const STRAVA_DEAUTHORIZE_URL = "https://www.strava.com/oauth/deauthorize";

// OAuth state expiry (10 minutes)
const STATE_EXPIRY_MS = 10 * 60 * 1000;

// ============================================
// TYPES
// ============================================

interface StravaTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  athlete: {
    id: number;
    firstname: string;
    lastname: string;
  };
}

// StravaActivityResponse kept for potential future use
// interface StravaActivityResponse {
//   id: number;
//   name: string;
//   type: string;
//   sport_type: string;
// }

interface WorkoutPayload {
  workoutId: string;
  name: string;
  date: string; // ISO 8601
  duration: number; // seconds
  floors: number;
  steps: number;
  notes?: string;
  tcxContent: string; // Base64-encoded TCX file content
  primaryMetric: "steps" | "floors"; // User's preferred metric
  avgSPM: number; // Average steps per minute
}

interface StravaUploadResponse {
  id: number;
  id_str: string;
  external_id: string;
  error: string | null;
  status: string;
  activity_id: number | null;
}

// ============================================
// HELPER: Exchange code for tokens
// ============================================

/**
 * Exchanges an OAuth authorization code for Strava access tokens.
 * @param {string} code - The authorization code from Strava OAuth flow
 * @return {Promise<StravaTokenResponse>} The token response from Strava
 */
async function exchangeCodeForTokens(
  code: string
): Promise<StravaTokenResponse> {
  const clientId = process.env.STRAVA_CLIENT_ID;
  const clientSecret = process.env.STRAVA_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    throw new Error("Strava credentials not configured");
  }

  const response = await fetch(STRAVA_AUTH_URL, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      code: code,
      grant_type: "authorization_code",
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    console.error("Strava token exchange failed:", response.status, error);
    throw new Error(`Token exchange failed: ${response.status}`);
  }

  return response.json();
}

// ============================================
// HELPER: Refresh tokens if expired
// ============================================

/**
 * Refreshes Strava access token if expired, otherwise returns cached token.
 * @param {string} userId - The Firebase user ID
 * @return {Promise<string>} A valid Strava access token
 */
async function refreshTokensIfNeeded(
  userId: string
): Promise<string> {
  const db = admin.firestore();
  const docRef = db.doc(`users/${userId}/integrations/strava`);
  const doc = await docRef.get();

  if (!doc.exists) {
    throw new HttpsError("not-found", "Not connected to Strava");
  }

  const data = doc.data();
  if (!data) {
    throw new HttpsError("not-found", "Not connected to Strava");
  }
  const expiresAt = data.expiresAt?.toDate?.() || new Date(data.expiresAt);
  const now = new Date();

  // If token is still valid (with 5 min buffer), return it
  if (expiresAt.getTime() - now.getTime() > 5 * 60 * 1000) {
    return data.accessToken;
  }

  // Refresh the token
  const clientId = process.env.STRAVA_CLIENT_ID;
  const clientSecret = process.env.STRAVA_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    throw new Error("Strava credentials not configured");
  }

  const response = await fetch(STRAVA_AUTH_URL, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: data.refreshToken,
      grant_type: "refresh_token",
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    console.error("Strava token refresh failed:", response.status, error);
    throw new HttpsError("unauthenticated", "Failed to refresh Strava token");
  }

  const tokenData: StravaTokenResponse = await response.json();

  // Update tokens in Firestore
  await docRef.update({
    accessToken: tokenData.access_token,
    refreshToken: tokenData.refresh_token,
    expiresAt: admin.firestore.Timestamp.fromMillis(
      tokenData.expires_at * 1000
    ),
  });

  return tokenData.access_token;
}

// ============================================
// CALLABLE: Create OAuth State
// ============================================

export const stravaCreateOAuthState = onCall(
  {
    secrets: ["STRAVA_CLIENT_ID"],
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    const stateId = randomUUID();
    const db = admin.firestore();

    await db.collection("oauthStates").doc(stateId).set({
      userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Return stateId and clientId for building the auth URL
    return {
      stateId,
      clientId: process.env.STRAVA_CLIENT_ID,
    };
  }
);

// ============================================
// HTTP: OAuth Callback Handler
// ============================================

export const stravaCallback = onRequest(
  {
    secrets: ["STRAVA_CLIENT_ID", "STRAVA_CLIENT_SECRET"],
  },
  async (req, res) => {
    const code = req.query.code as string;
    const state = req.query.state as string;
    const error = req.query.error as string;

    // Handle user denial
    if (error) {
      console.log("User denied Strava authorization:", error);
      res.redirect("ascendapp://strava-callback?status=error&message=denied");
      return;
    }

    if (!code || !state) {
      console.error("Missing code or state in callback");
      res.redirect(
        "ascendapp://strava-callback?status=error&message=invalid_request"
      );
      return;
    }

    try {
      const db = admin.firestore();

      // 1. Look up and validate state
      const stateRef = db.collection("oauthStates").doc(state);
      const stateDoc = await stateRef.get();

      if (!stateDoc.exists) {
        console.error("Invalid state:", state);
        res.redirect(
          "ascendapp://strava-callback?status=error&message=invalid_state"
        );
        return;
      }

      const stateData = stateDoc.data();
      if (!stateData) {
        console.error("State data missing:", state);
        res.redirect(
          "ascendapp://strava-callback?status=error&message=invalid_state"
        );
        return;
      }
      const createdAt = stateData.createdAt?.toDate?.() ||
        new Date(stateData.createdAt);
      const age = Date.now() - createdAt.getTime();

      if (age > STATE_EXPIRY_MS) {
        console.error("State expired:", state, "age:", age);
        await stateRef.delete();
        res.redirect(
          "ascendapp://strava-callback?status=error&message=state_expired"
        );
        return;
      }

      const userId = stateData.userId;

      // Delete state (one-time use)
      await stateRef.delete();

      // 2. Exchange code for tokens
      const tokenData = await exchangeCodeForTokens(code);

      // 3. Store tokens in Firestore
      const athleteName = `${tokenData.athlete.firstname} ${
        tokenData.athlete.lastname.charAt(0)
      }.`;

      await db.doc(`users/${userId}/integrations/strava`).set({
        accessToken: tokenData.access_token,
        refreshToken: tokenData.refresh_token,
        expiresAt: admin.firestore.Timestamp.fromMillis(
          tokenData.expires_at * 1000
        ),
        athleteId: tokenData.athlete.id,
        athleteName,
        connectedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(
        "Strava connected for user:", userId, "athlete:", athleteName
      );

      // 4. Redirect to app
      res.redirect("ascendapp://strava-callback?status=success");
    } catch (err) {
      console.error("Strava callback error:", err);
      res.redirect(
        "ascendapp://strava-callback?status=error&message=server_error"
      );
    }
  }
);

// ============================================
// HELPER: Build multipart form data
// ============================================

/**
 * Builds a multipart/form-data body for file upload.
 * @param {string} boundary - The multipart boundary string
 * @param {Record<string, string>} fields - Form fields to include
 * @param {object} file - File to upload with name, content, and filename
 * @return {Buffer} The complete multipart form data body
 */
function buildMultipartFormData(
  boundary: string,
  fields: Record<string, string>,
  file: {name: string; content: Buffer; filename: string}
): Buffer {
  const parts: Buffer[] = [];

  // Add text fields
  for (const [key, value] of Object.entries(fields)) {
    parts.push(Buffer.from(
      `--${boundary}\r\n` +
      "Content-Disposition: form-data; name=\"" + key + "\"\r\n\r\n" +
      `${value}\r\n`
    ));
  }

  // Add file field
  parts.push(Buffer.from(
    `--${boundary}\r\n` +
    "Content-Disposition: form-data; name=\"" + file.name + "\"; " +
    "filename=\"" + file.filename + "\"\r\n" +
    "Content-Type: application/octet-stream\r\n\r\n"
  ));
  parts.push(file.content);
  parts.push(Buffer.from("\r\n"));

  // Add closing boundary
  parts.push(Buffer.from(`--${boundary}--\r\n`));

  return Buffer.concat(parts);
}

/**
 * Polls Strava upload status until complete or error.
 * @param {number} uploadId - The Strava upload ID to poll
 * @param {string} accessToken - Valid Strava access token
 * @param {number} maxAttempts - Maximum polling attempts (default 30)
 * @param {number} delayMs - Delay between polls in ms (default 2000)
 * @return {Promise<object>} Object with activityId or error
 */
async function pollUploadStatus(
  uploadId: number,
  accessToken: string,
  maxAttempts = 30,
  delayMs = 2000
): Promise<{activityId: number | null; error: string | null}> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const response = await fetch(
      `${STRAVA_API_BASE}/uploads/${uploadId}`,
      {
        headers: {"Authorization": `Bearer ${accessToken}`},
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error("Upload status check failed:", response.status, error);
      throw new Error(`Upload status check failed: ${response.status}`);
    }

    const status: StravaUploadResponse = await response.json();
    console.log(
      "Upload status:", status.status,
      "activity_id:", status.activity_id,
      "error:", status.error
    );

    // Check if processing is complete
    if (status.activity_id) {
      return {activityId: status.activity_id, error: null};
    }

    // Check for error
    if (status.error) {
      // Check for duplicate
      if (status.error.includes("duplicate")) {
        return {activityId: null, error: "duplicate"};
      }
      return {activityId: null, error: status.error};
    }

    // Wait before next poll
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }

  throw new Error("Upload processing timed out");
}

// ============================================
// CALLABLE: Create Activity (via TCX Upload)
// ============================================

export const stravaCreateActivity = onCall(
  {
    secrets: ["STRAVA_CLIENT_ID", "STRAVA_CLIENT_SECRET"],
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    const workout = request.data.workout as WorkoutPayload;
    if (!workout || !workout.workoutId) {
      throw new HttpsError("invalid-argument", "Missing workout data");
    }

    if (!workout.tcxContent) {
      throw new HttpsError("invalid-argument", "Missing TCX content");
    }

    try {
      // Get valid access token (refreshing if needed)
      const accessToken = await refreshTokensIfNeeded(userId);

      // Decode base64 TCX content
      const tcxBuffer = Buffer.from(workout.tcxContent, "base64");

      // Build description based on user's preferred metric
      const isSteps = workout.primaryMetric === "steps";
      const primaryValue = isSteps ? workout.steps : workout.floors;
      const primaryLabel = isSteps ? "steps" : "floors";

      let description = `${primaryValue} ${primaryLabel}\n`;
      description += `Avg SPM: ${workout.avgSPM}`;

      if (workout.notes) {
        description += `\n\n${workout.notes}`;
      }

      // Build external_id for idempotency
      const externalId = `ascend_${userId}_${workout.workoutId}`;

      // Build multipart form data
      const boundary = `----AscendUpload${Date.now()}`;
      const formData = buildMultipartFormData(
        boundary,
        {
          name: workout.name || "Stair Climbing",
          description: description,
          sport_type: "StairStepper",
          trainer: "1",
          data_type: "tcx",
          external_id: externalId,
        },
        {
          name: "file",
          content: tcxBuffer,
          filename: `${externalId}.tcx`,
        }
      );

      // Upload to Strava
      console.log(
        "Uploading TCX to Strava for user:", userId,
        "external_id:", externalId,
        "size:", tcxBuffer.length, "bytes"
      );

      const response = await fetch(`${STRAVA_API_BASE}/uploads`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": `multipart/form-data; boundary=${boundary}`,
        },
        body: new Uint8Array(formData),
      });

      if (!response.ok) {
        const error = await response.text();
        console.error(
          "Strava upload failed:",
          response.status,
          error,
          "userId:", userId,
          "external_id:", externalId
        );

        // Check for duplicate in error response
        if (response.status === 409 || error.includes("duplicate")) {
          return {
            success: true,
            alreadyExists: true,
            message: "Activity already synced to Strava",
          };
        }

        throw new HttpsError(
          "internal",
          `Failed to upload to Strava: ${response.status}`
        );
      }

      const uploadResponse: StravaUploadResponse = await response.json();
      console.log(
        "Upload initiated:",
        uploadResponse.id,
        "status:", uploadResponse.status
      );

      // Poll for completion
      const result = await pollUploadStatus(uploadResponse.id, accessToken);

      if (result.error === "duplicate") {
        console.log("Activity already exists for:", externalId);
        return {
          success: true,
          alreadyExists: true,
          message: "Activity already synced to Strava",
        };
      }

      if (result.error) {
        console.error("Upload processing error:", result.error);
        throw new HttpsError("internal", `Upload failed: ${result.error}`);
      }

      if (!result.activityId) {
        throw new HttpsError("internal", "Upload completed but no activity ID");
      }

      console.log(
        "Strava activity created:",
        result.activityId,
        "for user:", userId,
        "external_id:", externalId
      );

      return {
        success: true,
        stravaActivityId: result.activityId,
      };
    } catch (err) {
      if (err instanceof HttpsError) {
        throw err;
      }
      console.error("Create activity error:", err);
      throw new HttpsError("internal", "Failed to create Strava activity");
    }
  }
);

// ============================================
// CALLABLE: Disconnect
// ============================================

export const stravaDisconnect = onCall(
  {
    secrets: ["STRAVA_CLIENT_ID", "STRAVA_CLIENT_SECRET"],
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    const db = admin.firestore();
    const docRef = db.doc(`users/${userId}/integrations/strava`);
    const doc = await docRef.get();

    if (!doc.exists) {
      // Already disconnected
      return {success: true};
    }

    const data = doc.data();

    try {
      // Revoke access on Strava
      if (data?.accessToken) {
        const response = await fetch(STRAVA_DEAUTHORIZE_URL, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${data.accessToken}`,
            "Content-Type": "application/json",
          },
        });

        if (!response.ok) {
          console.warn(
            "Strava deauthorize failed:",
            response.status,
            "- continuing with local cleanup"
          );
        }
      }
    } catch (err) {
      // Log but continue - we still want to clean up locally
      console.warn("Strava deauthorize error:", err);
    }

    // Delete tokens from Firestore
    await docRef.delete();

    console.log("Strava disconnected for user:", userId);

    return {success: true};
  }
);
