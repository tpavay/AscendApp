import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {
  STRAVA_CONNECTIONS_COLLECTION,
  STRAVA_OAUTH_STATES_COLLECTION,
  STRAVA_UPLOAD_JOBS_COLLECTION,
} from "./access";
import type {StravaClient, StravaTokenGrant} from "./api";

/**
 * One climber's Strava connection, stored at `_strava_connections/{uid}`.
 *
 * This is the only place a Strava token lives. The athlete's name is kept
 * because the climber is shown who they connected as, and Strava's API
 * Policy allows a user's own Strava data to be shown to that user.
 */
export interface StravaConnection {
  userId: string;
  athleteId: string;
  athleteDisplayName: string;
  accessToken: string;
  refreshToken: string;
  expiresAtMillis: number;
  scopes: string[];
  connectedAtMillis: number;
}

// Strava hands back the current access token until it is within an hour of
// expiring, so refreshing inside that hour is what actually rotates it.
const REFRESH_WITHIN_MS = 60 * 60 * 1000;

/**
 * "First L." - what the climber is shown as the connected Strava athlete.
 * @param {string} firstName Athlete first name.
 * @param {string} lastName Athlete last name.
 * @return {string} Display name, possibly empty.
 */
export function athleteDisplayName(
  firstName: string,
  lastName: string
): string {
  const initial = lastName.trim().charAt(0);
  return [firstName.trim(), initial ? `${initial}.` : ""]
    .filter((part) => part.length > 0)
    .join(" ");
}

/**
 * Whether an access token must be refreshed before use.
 * @param {number} expiresAtMillis Token expiry.
 * @param {number} nowMillis Current time.
 * @return {boolean} True when it expires within the refresh window.
 */
export function needsRefresh(
  expiresAtMillis: number,
  nowMillis: number
): boolean {
  return expiresAtMillis - nowMillis <= REFRESH_WITHIN_MS;
}

/**
 * Parses a stored connection, or null when the document is unusable.
 * @param {string} userId Owner uid.
 * @param {admin.firestore.DocumentData | undefined} data Stored data.
 * @return {StravaConnection | null} The connection.
 */
export function parseStravaConnection(
  userId: string,
  data: admin.firestore.DocumentData | undefined
): StravaConnection | null {
  if (!data) {
    return null;
  }
  const expiresAt = data.expiresAt;
  const connectedAt = data.connectedAt;
  if (typeof data.athleteId !== "string" ||
    typeof data.accessToken !== "string" ||
    typeof data.refreshToken !== "string" ||
    !(expiresAt instanceof admin.firestore.Timestamp) ||
    !(connectedAt instanceof admin.firestore.Timestamp)) {
    return null;
  }
  return {
    userId,
    athleteId: data.athleteId,
    athleteDisplayName: typeof data.athleteDisplayName === "string" ?
      data.athleteDisplayName :
      "",
    accessToken: data.accessToken,
    refreshToken: data.refreshToken,
    expiresAtMillis: expiresAt.toMillis(),
    scopes: Array.isArray(data.scopes) ?
      data.scopes.filter((scope): scope is string =>
        typeof scope === "string") :
      [],
    connectedAtMillis: connectedAt.toMillis(),
  };
}

/**
 * Firestore access for Strava connections.
 */
export class StravaConnectionStore {
  constructor(private readonly firestore: admin.firestore.Firestore) {}

  async read(userId: string): Promise<StravaConnection | null> {
    const snapshot = await this.reference(userId).get();
    return parseStravaConnection(userId, snapshot.data());
  }

  async save(connection: StravaConnection): Promise<void> {
    await this.reference(connection.userId).set({
      userId: connection.userId,
      athleteId: connection.athleteId,
      athleteDisplayName: connection.athleteDisplayName,
      accessToken: connection.accessToken,
      refreshToken: connection.refreshToken,
      expiresAt: admin.firestore.Timestamp.fromMillis(
        connection.expiresAtMillis
      ),
      scopes: connection.scopes,
      connectedAt: admin.firestore.Timestamp.fromMillis(
        connection.connectedAtMillis
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  /**
   * Returns a usable access token, refreshing it first when needed.
   *
   * Strava rotates the refresh token on every refresh and invalidates the old
   * one immediately, so two concurrent refreshes would leave one caller
   * holding a dead token. The write is therefore conditional on the refresh
   * token being the one this call refreshed from; a caller that loses the
   * race re-reads and uses the winner's token.
   * @param {string} userId Owner uid.
   * @param {StravaClient} client Strava client.
   * @param {number} nowMillis Current time.
   * @return {Promise<string | null>} Access token, or null if not connected.
   */
  async validAccessToken(
    userId: string,
    client: StravaClient,
    nowMillis: number
  ): Promise<string | null> {
    const connection = await this.read(userId);
    if (!connection) {
      return null;
    }
    if (!needsRefresh(connection.expiresAtMillis, nowMillis)) {
      return connection.accessToken;
    }
    let grant: StravaTokenGrant;
    try {
      grant = await client.refresh(connection.refreshToken);
    } catch (error) {
      // A refresh token another caller already rotated is refused exactly
      // like a revoked one. Only a token that is still the stored one proves
      // the athlete revoked Ascend.
      const current = await this.read(userId);
      if (current && current.refreshToken !== connection.refreshToken) {
        return current.accessToken;
      }
      throw error;
    }
    const stored = await this.storeRefreshedGrant(
      userId,
      connection.refreshToken,
      grant
    );
    if (stored) {
      return grant.accessToken;
    }
    const winner = await this.read(userId);
    return winner?.accessToken ?? null;
  }

  /**
   * Removes a connection and every record derived from it: the token, any
   * pending authorization, and the upload queue including completed rows,
   * which hold Strava activity ids. Strava's API Policy requires Strava data
   * to be deleted once a user revokes access.
   * @param {string} userId Owner uid.
   * @return {Promise<number>} How many documents were deleted.
   */
  async deleteAll(userId: string): Promise<number> {
    const [jobs, states] = await Promise.all([
      this.firestore.collection(STRAVA_UPLOAD_JOBS_COLLECTION)
        .where("userId", "==", userId)
        .get(),
      this.firestore.collection(STRAVA_OAUTH_STATES_COLLECTION)
        .where("userId", "==", userId)
        .get(),
    ]);
    const references = [
      this.reference(userId),
      ...jobs.docs.map((document) => document.ref),
      ...states.docs.map((document) => document.ref),
    ];
    for (let index = 0; index < references.length; index += 400) {
      const batch = this.firestore.batch();
      for (const reference of references.slice(index, index + 400)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
    return references.length;
  }

  /**
   * Revokes Ascend's access at Strava, then deletes everything local.
   *
   * Revocation is best-effort: a Strava outage must never leave a climber
   * unable to disconnect or delete their account, and the local token is
   * useless to anyone once deleted.
   * @param {string} userId Owner uid.
   * @param {StravaClient | null} client Strava client, or null when the
   *   project is not configured for Strava.
   * @return {Promise<{revoked: boolean, deleted: number}>} Outcome.
   */
  async disconnect(
    userId: string,
    client: StravaClient | null
  ): Promise<{revoked: boolean; deleted: number}> {
    const connection = await this.read(userId);
    let revoked = false;
    if (connection && client) {
      try {
        await client.revoke(connection.refreshToken);
        revoked = true;
      } catch (error) {
        logger.warn("Strava revoke failed; deleting the connection anyway", {
          userId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    const deleted = await this.deleteAll(userId);
    return {revoked, deleted};
  }

  /**
   * Every connection authorized by one Strava athlete. Normally at most one,
   * but nothing stops two Ascend accounts connecting the same athlete.
   * @param {string} athleteId Strava athlete id.
   * @return {Promise<Array<StravaConnection>>} Connections.
   */
  async findByAthlete(athleteId: string): Promise<StravaConnection[]> {
    const snapshot = await this.firestore
      .collection(STRAVA_CONNECTIONS_COLLECTION)
      .where("athleteId", "==", athleteId)
      .get();
    return snapshot.docs
      .map((document) => parseStravaConnection(document.id, document.data()))
      .filter((connection): connection is StravaConnection =>
        connection !== null);
  }

  private async storeRefreshedGrant(
    userId: string,
    previousRefreshToken: string,
    grant: StravaTokenGrant
  ): Promise<boolean> {
    const reference = this.reference(userId);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists ||
        snapshot.get("refreshToken") !== previousRefreshToken) {
        return false;
      }
      transaction.update(reference, {
        accessToken: grant.accessToken,
        refreshToken: grant.refreshToken,
        expiresAt: admin.firestore.Timestamp.fromMillis(grant.expiresAtMillis),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  private reference(userId: string): admin.firestore.DocumentReference {
    return this.firestore.collection(STRAVA_CONNECTIONS_COLLECTION).doc(userId);
  }
}
