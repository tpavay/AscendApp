import {timingSafeEqual} from "node:crypto";
import * as logger from "firebase-functions/logger";
import {StravaApiError, type StravaClient} from "./api";
import type {StravaConnectionStore} from "./connections";

/**
 * Answers Strava's subscription handshake.
 *
 * Strava sends `hub.mode=subscribe`, the verify token chosen when the
 * subscription was created, and a challenge it expects echoed back as JSON.
 * @param {Record<string, unknown>} query Request query parameters.
 * @param {string} verifyToken The configured verify token.
 * @return {object} HTTP status and JSON body.
 */
export function stravaWebhookChallenge(
  query: Record<string, unknown>,
  verifyToken: string
): {status: number; body: Record<string, string>} {
  const mode = query["hub.mode"];
  const token = query["hub.verify_token"];
  const challenge = query["hub.challenge"];
  if (mode !== "subscribe" || typeof token !== "string" ||
    typeof challenge !== "string" || challenge.length === 0 ||
    !constantTimeEquals(token, verifyToken)) {
    return {status: 403, body: {error: "forbidden"}};
  }
  return {status: 200, body: {"hub.challenge": challenge}};
}

/**
 * Picks the athlete id out of a deauthorization event, or null for any other
 * event. Ascend asks for no read scope, so a revoke is the only event it
 * acts on.
 * @param {unknown} body The POSTed event.
 * @return {string | null} Strava athlete id.
 */
export function parseStravaDeauthorization(body: unknown): string | null {
  if (!body || typeof body !== "object") {
    return null;
  }
  const event = body as Record<string, unknown>;
  const updates = event.updates as Record<string, unknown> | undefined;
  if (event.object_type !== "athlete" ||
    event.aspect_type !== "update" ||
    updates?.authorized !== "false") {
    return null;
  }
  const ownerId = event.owner_id ?? event.object_id;
  if (typeof ownerId === "number" && Number.isSafeInteger(ownerId)) {
    return String(ownerId);
  }
  if (typeof ownerId === "string" && /^\d+$/.test(ownerId)) {
    return ownerId;
  }
  return null;
}

/**
 * Drops every connection a deauthorization event names, once Strava itself
 * confirms the grant is gone.
 *
 * Strava does not sign webhook events, so anybody who learns the callback URL
 * and an athlete id could post a fake revoke. Refreshing the stored token is
 * the proof: a revoked grant refuses it, a live one answers normally and the
 * event is ignored.
 * @param {string} athleteId Strava athlete id from the event.
 * @param {StravaConnectionStore} store Connection store.
 * @param {StravaClient} client Strava client.
 * @return {Promise<number>} How many connections were removed.
 */
export async function handleStravaDeauthorization(
  athleteId: string,
  store: StravaConnectionStore,
  client: StravaClient
): Promise<number> {
  const connections = await store.findByAthlete(athleteId);
  let removed = 0;
  for (const connection of connections) {
    try {
      // Force a refresh by treating the token as already expired.
      await store.validAccessToken(connection.userId, client, Number.MAX_VALUE);
      logger.warn("Ignored a Strava deauthorization the grant contradicts", {
        userId: connection.userId,
      });
    } catch (error) {
      if (error instanceof StravaApiError && error.kind === "unauthorized") {
        await store.deleteAll(connection.userId);
        removed += 1;
        continue;
      }
      throw error;
    }
  }
  return removed;
}

/**
 * Compares two secrets without leaking where they differ.
 * @param {string} a First value.
 * @param {string} b Second value.
 * @return {boolean} True when equal.
 */
function constantTimeEquals(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
