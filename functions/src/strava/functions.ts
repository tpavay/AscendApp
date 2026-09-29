/**
 * Strava: every climb a connected climber finishes is sent to their Strava.
 *
 * The app only ever connects and disconnects. Everything else happens here:
 * the OAuth code exchange (the client secret never leaves Secret Manager),
 * the upload queue fed by workout writes, the deauthorization webhook, and
 * the account-deletion sweep's revoke. docs/strava-integration.md is the
 * operator's guide.
 */

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {mayConnectStrava, readStravaAccessSettings} from "./access";
import {
  HttpStravaClient,
  StravaApiError,
  STRAVA_WRITE_SCOPE,
} from "./api";
import {
  getStravaServerConfig,
  STRAVA_REDIRECT_SCHEME,
  stravaServerConfig,
} from "./config";
import {athleteDisplayName, StravaConnectionStore} from "./connections";
import {
  buildStravaAuthorizeUrl,
  consumeStravaOAuthState,
  newStravaOAuthState,
  saveStravaOAuthState,
  sweepExpiredStravaOAuthStates,
} from "./oauth";
import {
  enqueueStravaUpload,
  FirestoreStravaUploadJobStore,
  FirestoreStravaWorkoutSource,
} from "./uploadJobStore";
import {
  isStravaUploadEligible,
  processStravaUploadQueue,
  STRAVA_UPLOAD_SETTLE_MS,
  stravaUploadJobId,
} from "./uploadProcessor";
import {
  handleStravaDeauthorization,
  parseStravaDeauthorization,
  stravaWebhookChallenge,
} from "./webhook";

/**
 * What the Integrations screen needs. `available` is whether this climber
 * may start a connection; a connected climber is always shown their
 * connection, so they can leave even after the switch is turned off.
 */
export interface StravaStatusResponse {
  available: boolean;
  connected: boolean;
  athleteName: string | null;
}

/**
 * Whether the Integrations screen should offer Strava to the caller.
 */
export const stravaGetStatus = onCall(
  {secrets: [stravaServerConfig]},
  async (request): Promise<StravaStatusResponse> => {
    const userId = requireUserId(request.auth?.uid);
    return statusFor(userId);
  }
);

/**
 * Starts a connection: records a pending state and returns the Strava
 * consent URL. Refused outright for anyone the access settings do not name,
 * so no climber outside the allowlist can begin a Strava authorization.
 */
export const stravaBeginConnect = onCall(
  {secrets: [stravaServerConfig]},
  async (request) => {
    const userId = requireUserId(request.auth?.uid);
    const firestore = admin.firestore();
    const config = getStravaServerConfig();
    if (!config ||
      !mayConnectStrava(await readStravaAccessSettings(firestore), userId)) {
      throw refusal("failed-precondition", "unavailable");
    }
    if (await new StravaConnectionStore(firestore).read(userId)) {
      throw refusal("already-exists", "already_connected");
    }
    const state = newStravaOAuthState();
    await saveStravaOAuthState(firestore, userId, state, new Date());
    return {
      authorizeUrl: buildStravaAuthorizeUrl(config, state),
      callbackScheme: STRAVA_REDIRECT_SCHEME,
    };
  }
);

/**
 * Finishes a connection from the code Strava redirected back with.
 */
export const stravaCompleteConnect = onCall(
  {secrets: [stravaServerConfig]},
  async (request): Promise<StravaStatusResponse> => {
    const userId = requireUserId(request.auth?.uid);
    const {code, state} = parseCompletePayload(request.data);
    const firestore = admin.firestore();
    const now = new Date();
    const stateCheck = await consumeStravaOAuthState(
      firestore,
      userId,
      state,
      now
    );
    if (stateCheck !== "valid") {
      logger.warn("Refused a Strava connection with a bad state", {
        userId,
        stateCheck,
      });
      throw refusal("permission-denied", "expired");
    }
    const config = getStravaServerConfig();
    if (!config ||
      !mayConnectStrava(await readStravaAccessSettings(firestore), userId)) {
      throw refusal("failed-precondition", "unavailable");
    }

    const client = new HttpStravaClient(config);
    const authorization = await callStrava(() => client.exchangeCode(code));
    if (!authorization.grantedScopes.includes(STRAVA_WRITE_SCOPE)) {
      // Without write access there is nothing to keep, and a grant left
      // behind would still count against the app's athlete capacity.
      await client.revoke(authorization.refreshToken).catch(() => undefined);
      throw refusal("failed-precondition", "missing_scope");
    }

    const store = new StravaConnectionStore(firestore);
    await store.save({
      userId,
      athleteId: authorization.athleteId,
      athleteDisplayName: athleteDisplayName(
        authorization.athleteFirstName,
        authorization.athleteLastName
      ),
      accessToken: authorization.accessToken,
      refreshToken: authorization.refreshToken,
      expiresAtMillis: authorization.expiresAtMillis,
      scopes: authorization.grantedScopes,
      connectedAtMillis: now.getTime(),
    });
    logger.info("Strava connected", {userId});
    return statusFor(userId);
  }
);

/**
 * Disconnects: revokes Ascend at Strava and deletes the token, pending
 * authorizations and the upload queue. Always allowed, whatever the access
 * settings say.
 */
export const stravaDisconnect = onCall(
  {secrets: [stravaServerConfig]},
  async (request): Promise<StravaStatusResponse> => {
    const userId = requireUserId(request.auth?.uid);
    const config = getStravaServerConfig();
    await new StravaConnectionStore(admin.firestore()).disconnect(
      userId,
      config ? new HttpStravaClient(config) : null
    );
    logger.info("Strava disconnected", {userId});
    return statusFor(userId);
  }
);

/**
 * Queues a freshly written climb for Strava when its climber is connected.
 */
export const onWorkoutWrittenStravaUpload = onDocumentWritten(
  "users/{userId}/workouts/{workoutId}",
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) {
      return;
    }
    const {userId, workoutId} = event.params;
    const firestore = admin.firestore();
    const connection = await new StravaConnectionStore(firestore).read(userId);
    if (!connection) {
      return;
    }
    const startedAt = after.get("startedAt");
    const now = Date.now();
    if (!isStravaUploadEligible({
      source: after.get("source"),
      steps: after.get("steps"),
      durationSeconds: after.get("durationSeconds"),
      startedAtMillis: startedAt instanceof admin.firestore.Timestamp ?
        startedAt.toMillis() :
        null,
      connectedAtMillis: connection.connectedAtMillis,
      nowMillis: now,
    })) {
      return;
    }
    const created = await enqueueStravaUpload(firestore, {
      jobId: stravaUploadJobId(userId, workoutId),
      userId,
      workoutId,
      readyAt: new Date(now + STRAVA_UPLOAD_SETTLE_MS),
    });
    if (created) {
      logger.info("Queued a climb for Strava", {userId, workoutId});
    }
  }
);

/**
 * Sends due climbs to Strava. A run does nothing at all while the
 * integration is switched off, which leaves every queued climb in place.
 */
export const processStravaUploads = onSchedule(
  {
    schedule: "*/5 * * * *",
    secrets: [stravaServerConfig],
    timeZone: "Etc/UTC",
    timeoutSeconds: 120,
  },
  async () => {
    const firestore = admin.firestore();
    const now = new Date();
    await sweepExpiredStravaOAuthStates(firestore, now);
    const config = getStravaServerConfig();
    if (!config || !(await readStravaAccessSettings(firestore)).enabled) {
      return;
    }
    const client = new HttpStravaClient(config);
    const connections = new StravaConnectionStore(firestore);
    const summary = await processStravaUploadQueue({
      store: new FirestoreStravaUploadJobStore(firestore),
      workouts: new FirestoreStravaWorkoutSource(firestore),
      connections: {
        accessToken: (userId, nowMillis) =>
          connections.validAccessToken(userId, client, nowMillis),
        disconnectRevoked: async (userId) => {
          await connections.deleteAll(userId);
        },
      },
      client,
      now: () => new Date(),
      sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    });
    if (summary.claimed > 0 || summary.reclaimed > 0) {
      logger.info("Strava upload run completed", summary);
    }
  }
);

/**
 * Strava's webhook: the subscription handshake on GET, and athlete
 * deauthorizations on POST. Every other event is acknowledged and ignored.
 */
export const stravaWebhook = onRequest(
  {secrets: [stravaServerConfig]},
  async (request, response) => {
    const config = getStravaServerConfig();
    if (!config) {
      response.status(404).json({error: "not_configured"});
      return;
    }
    if (request.method === "GET") {
      const answer = stravaWebhookChallenge(
        request.query as Record<string, unknown>,
        config.webhookVerifyToken
      );
      response.status(answer.status).json(answer.body);
      return;
    }
    if (request.method !== "POST") {
      response.status(405).json({error: "method_not_allowed"});
      return;
    }
    const athleteId = parseStravaDeauthorization(request.body);
    if (athleteId) {
      const removed = await handleStravaDeauthorization(
        athleteId,
        new StravaConnectionStore(admin.firestore()),
        new HttpStravaClient(config)
      );
      logger.info("Handled a Strava deauthorization", {removed});
    }
    response.status(200).json({ok: true});
  }
);

/**
 * Builds the status the Integrations screen renders.
 * @param {string} userId Caller uid.
 * @return {Promise<StravaStatusResponse>} Status.
 */
async function statusFor(userId: string): Promise<StravaStatusResponse> {
  const firestore = admin.firestore();
  const [settings, connection] = await Promise.all([
    readStravaAccessSettings(firestore),
    new StravaConnectionStore(firestore).read(userId),
  ]);
  const configured = getStravaServerConfig() !== null;
  return {
    available: configured && mayConnectStrava(settings, userId),
    connected: connection !== null,
    athleteName: connection?.athleteDisplayName || null,
  };
}

/**
 * Runs a Strava call, turning its failure into a callable error the app can
 * tell apart.
 * @param {Function} call The Strava call.
 * @return {Promise<T>} Its result.
 */
async function callStrava<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch (error) {
    if (error instanceof StravaApiError) {
      logger.warn("Strava call failed during connect", {
        kind: error.kind,
        status: error.status,
        error: error.message,
      });
      throw error.kind === "unauthorized" || error.kind === "rejected" ?
        refusal("permission-denied", "expired") :
        refusal("unavailable", "strava_unreachable");
    }
    throw error;
  }
}

/**
 * Validates the completion payload.
 * @param {unknown} data Callable payload.
 * @return {object} The code and state.
 */
function parseCompletePayload(data: unknown): {code: string; state: string} {
  const record = data as Record<string, unknown> | null;
  const code = record?.code;
  const state = record?.state;
  if (typeof code !== "string" || !/^[A-Za-z0-9]{1,200}$/.test(code) ||
    typeof state !== "string" || !/^[A-Za-z0-9_-]{16,100}$/.test(state)) {
    throw new HttpsError("invalid-argument", "code and state are required");
  }
  return {code, state};
}

/**
 * Narrows the caller's uid.
 * @param {string | undefined} uid Auth uid.
 * @return {string} The uid.
 */
function requireUserId(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in first");
  }
  return uid;
}

/**
 * A refusal the app maps onto copy through `details.reason`.
 * @param {string} code Callable error code.
 * @param {string} reason Stable machine-readable reason.
 * @return {HttpsError} The error.
 */
function refusal(
  code: "failed-precondition" | "already-exists" | "permission-denied" |
    "unavailable",
  reason: string
): HttpsError {
  return new HttpsError(code, reason, {reason});
}
