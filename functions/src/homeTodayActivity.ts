/**
 * Home's ON THE GLOBE TODAY projection.
 *
 * One server-owned document, `home_today_activity/global`, holding the most
 * recent uploaded climbs across every session kind - Live Climb completions,
 * Just Climbs and routine sessions - newest first. Home reads it through one
 * listener and shows the first three rows; SEE ALL shows the rest.
 *
 * Every row is derived here from the canonical private workout, the same way
 * `landmarkResults` and the replay boards are: the client never writes this
 * document (`allow write: if false`), and the eligibility of a row is decided
 * from the workout's evidence fields, never from a client-asserted flag. The
 * identity on a row is the climber's current public snapshot, read inside the
 * same transaction that writes the row, and it is refreshed when the public
 * profile changes and removed when the account is deleted.
 *
 * There is no Remote Config switch in front of this write on purpose: a Cloud
 * Function is redeployable, so the premise a kill switch exists for - an iOS
 * binary that cannot be rolled back - does not hold here
 * (docs/remote-config-kill-switches.md). The choke point that can defer the
 * evidence, and therefore the row, is the existing
 * `workout_cloud_backup_writes_enabled` switch on the workout backup itself.
 */

import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  HEADPHONE_MOTION_SOURCE,
  TARGET_REACHED_STOP_REASON,
  isRecoverableLegacyCompletion,
} from "./legacyClimbCompletion.js";
import {
  PublicUserSnapshot,
  currentPublicUserSnapshotFromData,
} from "./liveReplayLeaderboard.js";
import {publicIdentitySourceChanged} from "./publicIdentityPropagation.js";

export const HOME_TODAY_ACTIVITY_COLLECTION = "home_today_activity";
export const HOME_TODAY_ACTIVITY_DOCUMENT_ID = "global";
export const HOME_TODAY_ACTIVITY_SCHEMA_VERSION = 1;
/**
 * How many rows the document keeps. Home shows three; SEE ALL shows all of
 * them. Bounded so the document stays one small read on every Home entry.
 */
export const HOME_TODAY_ACTIVITY_MAX_ROWS = 24;

const USERS_COLLECTION = "users";
const PUBLIC_PROFILE_COLLECTION = "public_profile";
const PUBLIC_PROFILE_DOCUMENT_ID = "current";
const TRANSACTION_MAX_ATTEMPTS = 5;

const LIVE_CLIMB_TRACKING_MODE = "live_climb";
const JUST_CLIMB_TRACKING_MODE = "just_climb";
const ROUTINE_TRACKING_MODE = "routine";
const USER_STOPPED_REASON = "user_stopped";

export type HomeTodayActivityKind =
  "live_climb" |
  "just_climb" |
  "routine_template" |
  "routine";

export type HomeTodayJustClimbGoalKind = "open" | "duration" | "steps";

const HOME_TODAY_ACTIVITY_KINDS: HomeTodayActivityKind[] = [
  "live_climb",
  "just_climb",
  "routine_template",
  "routine",
];

const JUST_CLIMB_GOAL_KINDS: HomeTodayJustClimbGoalKind[] = [
  "open",
  "duration",
  "steps",
];

/**
 * One uploaded session reduced to what the feed needs, before identity.
 * Everything here comes from the workout's own evidence fields.
 */
export interface HomeTodayActivityCandidate {
  workoutId: string;
  userId: string;
  kind: HomeTodayActivityKind;
  /** The landmark climbed; only on `live_climb`. */
  climbId: string | null;
  /** The catalog template run; only on `routine_template`. */
  routineTemplateId: string | null;
  steps: number;
  durationSeconds: number;
  completedAtMillis: number;
  /** The goal a Just Climb was set to, so its row can re-open the same one. */
  justClimbGoalKind: HomeTodayJustClimbGoalKind | null;
  /** Minutes for a duration goal, steps for a step goal, null when open. */
  justClimbGoalValue: number | null;
}

/** A candidate plus when it first landed and who climbed it. */
export interface HomeTodayActivityRow extends HomeTodayActivityCandidate {
  /**
   * When the server first saw this workout. The feed orders on it because the
   * captain's word was "uploaded": a climb backed up after a day offline is
   * news when it lands, not when it happened.
   */
  publishedAtMillis: number;
  displayName: string;
  avatarToken: string;
  photoURL: string | null;
  identityState: string;
  isSynthetic: boolean;
}

export interface HomeTodayActivityProjection {
  schemaVersion: number;
  rows: HomeTodayActivityRow[];
}

/**
 * The operations one projection transaction can perform. The Admin SDK
 * adapter is the only production writer; tests inject an in-memory store.
 */
export interface HomeTodayActivityTransaction {
  readProjection(): Promise<HomeTodayActivityProjection | null>;
  readPublicUser(userId: string): Promise<PublicUserSnapshot>;
  writeProjection(projection: HomeTodayActivityProjection): Promise<void>;
}

export interface HomeTodayActivityStore {
  runTransaction<T>(
    operation: (transaction: HomeTodayActivityTransaction) => Promise<T>
  ): Promise<T>;
}

export type HomeTodayActivityOutcome = "written" | "skipped";

/**
 * Reduces a raw workout document to a feed candidate, or null when the
 * session is not one the feed shows.
 *
 * The gates mirror the publication rules the replay boards already apply,
 * re-derived from evidence rather than read off `leaderboardEligible`:
 * a Live Climb must be a completion under the shared legacy-completion
 * contract, a Just Climb must have ended by target or by the climber, and a
 * routine must have reached its target (a skipped interval ends a routine as
 * `skipped`). A personal routine is kept as `routine` with no template id: its
 * row opens nothing, because a private routine is not shareable.
 * @param {string} userId Owning user id.
 * @param {string} workoutId Workout document id.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @return {HomeTodayActivityCandidate | null} The candidate, or null.
 */
export function parseHomeTodayActivityCandidate(
  userId: string,
  workoutId: string,
  data: Record<string, unknown> | undefined
): HomeTodayActivityCandidate | null {
  if (!data || data.source !== HEADPHONE_MOTION_SOURCE) {
    return null;
  }

  const sourceMetadata = data.sourceMetadata;
  if (typeof sourceMetadata !== "string") {
    return null;
  }

  let metadata: Record<string, unknown>;
  try {
    metadata = JSON.parse(sourceMetadata) as Record<string, unknown>;
  } catch {
    return null;
  }

  const steps = nonNegativeIntegerValue(data.steps);
  const durationSeconds = nonNegativeNumberValue(data.durationSeconds);
  if (steps === null || durationSeconds === null) {
    return null;
  }

  const trackingMode = stringValue(metadata.trackingMode);
  const stopReason = stringValue(metadata.stopReason) ?? "";
  const targetStepCount = positiveIntegerValue(metadata.climbTargetStepCount) ??
    positiveIntegerValue(metadata.targetStepCount);
  const targetDurationSeconds = positiveNumberValue(
    metadata.targetDurationSeconds
  );
  const climbId = stringValue(metadata.climbId);

  const base = {
    workoutId,
    userId,
    climbId: null,
    routineTemplateId: null,
    steps,
    durationSeconds: Math.round(durationSeconds),
    completedAtMillis: completedAtMillis(data.startedAt, durationSeconds),
    justClimbGoalKind: null,
    justClimbGoalValue: null,
  };

  if (trackingMode === LIVE_CLIMB_TRACKING_MODE) {
    if (!climbId) {
      return null;
    }
    const completed = isRecoverableLegacyCompletion({
      source: HEADPHONE_MOTION_SOURCE,
      climbId,
      stopReason,
      steps,
      targetStepCount,
    });
    if (!completed) {
      return null;
    }
    return {...base, kind: "live_climb", climbId};
  }

  if (steps === 0 || durationSeconds <= 0) {
    return null;
  }

  if (trackingMode === JUST_CLIMB_TRACKING_MODE) {
    if (
      stopReason !== TARGET_REACHED_STOP_REASON &&
      stopReason !== USER_STOPPED_REASON
    ) {
      return null;
    }
    if (targetDurationSeconds !== null) {
      return {
        ...base,
        kind: "just_climb",
        justClimbGoalKind: "duration",
        justClimbGoalValue: Math.max(1, Math.round(targetDurationSeconds / 60)),
      };
    }
    if (targetStepCount !== null) {
      return {
        ...base,
        kind: "just_climb",
        justClimbGoalKind: "steps",
        justClimbGoalValue: targetStepCount,
      };
    }
    return {...base, kind: "just_climb", justClimbGoalKind: "open"};
  }

  if (trackingMode === ROUTINE_TRACKING_MODE) {
    if (stopReason !== TARGET_REACHED_STOP_REASON) {
      return null;
    }
    const routineTemplateId = stringValue(metadata.routineTemplateId);
    if (routineTemplateId) {
      return {...base, kind: "routine_template", routineTemplateId};
    }
    return {...base, kind: "routine"};
  }

  return null;
}

/**
 * Whether two candidates carry the same feed-facing facts. A workout update
 * that changes nothing the feed shows (a photo finishing its upload, a note)
 * must not cost a transaction.
 * @param {HomeTodayActivityCandidate | null} lhs One candidate.
 * @param {HomeTodayActivityCandidate | null} rhs The other.
 * @return {boolean} True when the feed would read the same either way.
 */
export function candidatesEqual(
  lhs: HomeTodayActivityCandidate | null,
  rhs: HomeTodayActivityCandidate | null
): boolean {
  if (lhs === null || rhs === null) {
    return lhs === rhs;
  }
  return lhs.workoutId === rhs.workoutId &&
    lhs.userId === rhs.userId &&
    lhs.kind === rhs.kind &&
    lhs.climbId === rhs.climbId &&
    lhs.routineTemplateId === rhs.routineTemplateId &&
    lhs.steps === rhs.steps &&
    lhs.durationSeconds === rhs.durationSeconds &&
    lhs.completedAtMillis === rhs.completedAtMillis &&
    lhs.justClimbGoalKind === rhs.justClimbGoalKind &&
    lhs.justClimbGoalValue === rhs.justClimbGoalValue;
}

/**
 * Newest first: by when the server first saw the workout, then by when the
 * climb finished, then by id so two rows never swap between derivations.
 * @param {HomeTodayActivityRow} lhs One row.
 * @param {HomeTodayActivityRow} rhs The other.
 * @return {number} Sort order.
 */
export function compareHomeTodayActivityRows(
  lhs: HomeTodayActivityRow,
  rhs: HomeTodayActivityRow
): number {
  if (lhs.publishedAtMillis !== rhs.publishedAtMillis) {
    return rhs.publishedAtMillis - lhs.publishedAtMillis;
  }
  if (lhs.completedAtMillis !== rhs.completedAtMillis) {
    return rhs.completedAtMillis - lhs.completedAtMillis;
  }
  return lhs.workoutId < rhs.workoutId ? -1 : lhs.workoutId > rhs.workoutId ?
    1 :
    0;
}

/**
 * Replaces one workout's row in the ordered, bounded row list.
 * Pure, so the trigger, the tests and any rebuild converge on the same list.
 * @param {HomeTodayActivityRow[]} existing Rows currently stored.
 * @param {string} workoutId The workout being reconciled.
 * @param {HomeTodayActivityRow | null} next Its row now, or null to remove.
 * @return {HomeTodayActivityRow[]} The next stored list.
 */
export function mergeHomeTodayActivityRows(
  existing: HomeTodayActivityRow[],
  workoutId: string,
  next: HomeTodayActivityRow | null
): HomeTodayActivityRow[] {
  const rows = existing.filter((row) => row.workoutId !== workoutId);
  if (next) {
    rows.push(next);
  }
  rows.sort(compareHomeTodayActivityRows);
  return rows.slice(0, HOME_TODAY_ACTIVITY_MAX_ROWS);
}

/**
 * Reconciles one workout write into the projection.
 * @param {HomeTodayActivityStore} store Persistence boundary.
 * @param {object} input The write to reconcile.
 * @param {string} input.workoutId The workout document id.
 * @param {HomeTodayActivityCandidate | null} input.candidate The workout's
 *   candidate after the write, or null when it no longer qualifies.
 * @param {number} input.nowMillis The event time, used as `publishedAt` for a
 *   workout the feed has not seen before.
 * @return {Promise<HomeTodayActivityOutcome>} Whether a write happened.
 */
export async function reconcileHomeTodayActivity(
  store: HomeTodayActivityStore,
  input: {
    workoutId: string;
    candidate: HomeTodayActivityCandidate | null;
    nowMillis: number;
  }
): Promise<HomeTodayActivityOutcome> {
  return store.runTransaction(async (transaction) => {
    // Every read precedes the write: Firestore retries the whole callback.
    const stored = await transaction.readProjection();
    const existingRows = stored?.rows ?? [];
    const existingRow = existingRows.find(
      (row) => row.workoutId === input.workoutId
    );

    let nextRow: HomeTodayActivityRow | null = null;
    if (input.candidate) {
      const publishedAtMillis = existingRow?.publishedAtMillis ??
        input.nowMillis;
      // A row that would fall off the end of a full list is not worth an
      // identity read or a write.
      if (
        existingRow === undefined &&
        existingRows.length >= HOME_TODAY_ACTIVITY_MAX_ROWS &&
        wouldFallOffTheEnd(existingRows, input.candidate, publishedAtMillis)
      ) {
        return "skipped";
      }
      const publicUser = await transaction.readPublicUser(
        input.candidate.userId
      );
      nextRow = rowFrom(input.candidate, publishedAtMillis, publicUser);
    } else if (existingRow === undefined) {
      return "skipped";
    }

    const nextRows = mergeHomeTodayActivityRows(
      existingRows,
      input.workoutId,
      nextRow
    );
    if (stored && rowListsEqual(stored.rows, nextRows)) {
      return "skipped";
    }

    await transaction.writeProjection({
      schemaVersion: HOME_TODAY_ACTIVITY_SCHEMA_VERSION,
      rows: nextRows,
    });
    return "written";
  });
}

/**
 * Rewrites the identity on every row one climber owns from their current
 * public snapshot. Runs when the public profile changes, so a renamed or
 * de-identified climber reads the same on Home as on every other board.
 * @param {HomeTodayActivityStore} store Persistence boundary.
 * @param {string} userId The climber whose rows to refresh.
 * @return {Promise<number>} How many rows changed.
 */
export async function refreshHomeTodayActivityIdentity(
  store: HomeTodayActivityStore,
  userId: string
): Promise<number> {
  return store.runTransaction(async (transaction) => {
    const stored = await transaction.readProjection();
    if (!stored || !stored.rows.some((row) => row.userId === userId)) {
      return 0;
    }
    const publicUser = await transaction.readPublicUser(userId);
    let changed = 0;
    const rows = stored.rows.map((row) => {
      if (row.userId !== userId) {
        return row;
      }
      const next = {...row, ...identityFields(publicUser)};
      if (!rowsEqual(row, next)) {
        changed += 1;
      }
      return next;
    });
    if (changed === 0) {
      return 0;
    }
    await transaction.writeProjection({
      schemaVersion: HOME_TODAY_ACTIVITY_SCHEMA_VERSION,
      rows,
    });
    return changed;
  });
}

/**
 * Drops every row a deleted account owns. Called from the account cleanup
 * sweep, which is the one path that can reach server-owned data once the
 * auth user is gone.
 * @param {HomeTodayActivityStore} store Persistence boundary.
 * @param {string} userId The deleted account.
 * @return {Promise<number>} How many rows were removed.
 */
export async function removeHomeTodayActivityRows(
  store: HomeTodayActivityStore,
  userId: string
): Promise<number> {
  return store.runTransaction(async (transaction) => {
    const stored = await transaction.readProjection();
    if (!stored) {
      return 0;
    }
    const rows = stored.rows.filter((row) => row.userId !== userId);
    const removed = stored.rows.length - rows.length;
    if (removed === 0) {
      return 0;
    }
    await transaction.writeProjection({
      schemaVersion: HOME_TODAY_ACTIVITY_SCHEMA_VERSION,
      rows,
    });
    return removed;
  });
}

/**
 * Derives the feed from the canonical private workout on every write. A
 * sibling of `onWorkoutWritten` and `onWorkoutReplaySplitsWritten` on the same
 * document, so one backup fans out to every projection it feeds.
 */
export const onWorkoutWrittenHomeTodayActivity = onDocumentWritten(
  {
    document: "users/{userId}/workouts/{workoutId}",
    retry: true,
  },
  async (event) => {
    const userId = event.params.userId;
    const workoutId = event.params.workoutId;
    const before = parseHomeTodayActivityCandidate(
      userId,
      workoutId,
      event.data?.before.data() as Record<string, unknown> | undefined
    );
    const after = parseHomeTodayActivityCandidate(
      userId,
      workoutId,
      event.data?.after.data() as Record<string, unknown> | undefined
    );
    if (candidatesEqual(before, after)) {
      return;
    }

    const nowMillis = Date.parse(event.time);
    await reconcileHomeTodayActivity(makeAdminStore(), {
      workoutId,
      candidate: after,
      nowMillis: Number.isFinite(nowMillis) ? nowMillis : Date.now(),
    });
  }
);

/**
 * Keeps a climber's rows current with their public profile. The paged
 * identity-propagation jobs rewrite one document per row; this projection
 * keeps its rows inside one document, so it refreshes them in one transaction
 * instead of joining that queue.
 */
export const onPublicProfileWrittenHomeTodayActivity = onDocumentWritten(
  {
    document: "users/{userId}/public_profile/current",
    retry: true,
  },
  async (event) => {
    if (
      !publicIdentitySourceChanged(
        event.data?.before.data(),
        event.data?.after.data()
      )
    ) {
      return;
    }
    await refreshHomeTodayActivityIdentity(
      makeAdminStore(),
      event.params.userId
    );
  }
);

/**
 * The production store, backed by the Admin SDK.
 * @param {admin.firestore.Firestore} db Firestore instance.
 * @return {HomeTodayActivityStore} Admin-backed store.
 */
export function makeAdminStore(
  db: admin.firestore.Firestore = admin.firestore()
): HomeTodayActivityStore {
  const projectionRef = db
    .collection(HOME_TODAY_ACTIVITY_COLLECTION)
    .doc(HOME_TODAY_ACTIVITY_DOCUMENT_ID);

  return {
    async runTransaction<T>(operation: (
      transaction: HomeTodayActivityTransaction
    ) => Promise<T>): Promise<T> {
      let attempts = 0;
      try {
        const outcome = await db.runTransaction(
          async (firestoreTransaction) => {
            attempts += 1;
            return operation({
              async readProjection() {
                const snapshot = await firestoreTransaction.get(projectionRef);
                if (!snapshot.exists) {
                  return null;
                }
                return projectionFromData(
                  snapshot.data() as Record<string, unknown>
                );
              },

              async readPublicUser(userId) {
                const userRef = db.collection(USERS_COLLECTION).doc(userId);
                const publicProfileRef = userRef
                  .collection(PUBLIC_PROFILE_COLLECTION)
                  .doc(PUBLIC_PROFILE_DOCUMENT_ID);
                const [publicProfile, user] = await firestoreTransaction.getAll(
                  publicProfileRef,
                  userRef
                );
                return currentPublicUserSnapshotFromData(
                  publicProfile.data(),
                  user.exists ? user.data() : undefined,
                  userId
                );
              },

              async writeProjection(projection) {
                firestoreTransaction.set(
                  projectionRef,
                  projectionToData(projection)
                );
              },
            });
          },
          {maxAttempts: TRANSACTION_MAX_ATTEMPTS}
        );
        if (attempts > 1) {
          logger.warn("homeTodayActivity.transaction.contention", {
            attempts,
            maxAttempts: TRANSACTION_MAX_ATTEMPTS,
          });
        }
        return outcome;
      } catch (error) {
        logger.error("homeTodayActivity.transaction.failed", {
          attempts,
          maxAttempts: TRANSACTION_MAX_ATTEMPTS,
          attemptsExhausted: attempts >= TRANSACTION_MAX_ATTEMPTS,
          errorMessage: String(
            (error as {message?: unknown})?.message ?? error
          ),
        });
        throw error;
      }
    },
  };
}

/**
 * Serializes the projection to its stored shape. Optional fields are omitted
 * rather than stored null, so a client reading a missing field and a client
 * reading an absent one see the same document.
 * @param {HomeTodayActivityProjection} projection In-memory projection.
 * @return {Record<string, unknown>} Firestore document data.
 */
export function projectionToData(
  projection: HomeTodayActivityProjection
): Record<string, unknown> {
  return {
    schemaVersion: projection.schemaVersion,
    rowCount: projection.rows.length,
    rows: projection.rows.map(rowToData),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Parses a stored projection, dropping any row it cannot read. A malformed
 * row is a fact about that row, not a reason to refuse the feed.
 * @param {Record<string, unknown>} data Stored document data.
 * @return {HomeTodayActivityProjection} The parsed projection.
 */
export function projectionFromData(
  data: Record<string, unknown>
): HomeTodayActivityProjection {
  const rows: HomeTodayActivityRow[] = [];
  if (Array.isArray(data.rows)) {
    for (const item of data.rows) {
      const row = rowFromData(item);
      if (row) {
        rows.push(row);
      }
    }
  }
  return {
    schemaVersion: positiveIntegerValue(data.schemaVersion) ??
      HOME_TODAY_ACTIVITY_SCHEMA_VERSION,
    rows,
  };
}

/**
 * @param {HomeTodayActivityRow} row One row.
 * @return {Record<string, unknown>} Its stored shape.
 */
function rowToData(row: HomeTodayActivityRow): Record<string, unknown> {
  const data: Record<string, unknown> = {
    workoutId: row.workoutId,
    userId: row.userId,
    kind: row.kind,
    steps: row.steps,
    durationSeconds: row.durationSeconds,
    completedAt: admin.firestore.Timestamp.fromMillis(row.completedAtMillis),
    publishedAt: admin.firestore.Timestamp.fromMillis(row.publishedAtMillis),
    displayName: row.displayName,
    avatarToken: row.avatarToken,
    photoURL: row.photoURL ?? "",
    identityState: row.identityState,
    isSynthetic: row.isSynthetic,
  };
  if (row.climbId !== null) {
    data.climbId = row.climbId;
  }
  if (row.routineTemplateId !== null) {
    data.routineTemplateId = row.routineTemplateId;
  }
  if (row.justClimbGoalKind !== null) {
    data.justClimbGoalKind = row.justClimbGoalKind;
  }
  if (row.justClimbGoalValue !== null) {
    data.justClimbGoalValue = row.justClimbGoalValue;
  }
  return data;
}

/**
 * @param {unknown} value One stored row.
 * @return {HomeTodayActivityRow | null} The row, or null when unreadable.
 */
function rowFromData(value: unknown): HomeTodayActivityRow | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const data = value as Record<string, unknown>;
  const workoutId = stringValue(data.workoutId);
  const userId = stringValue(data.userId);
  const kind = stringValue(data.kind);
  const steps = nonNegativeIntegerValue(data.steps);
  const durationSeconds = nonNegativeNumberValue(data.durationSeconds);
  const completedAt = timestampMillis(data.completedAt);
  const publishedAt = timestampMillis(data.publishedAt);
  const displayName = typeof data.displayName === "string" ?
    data.displayName :
    null;
  const identityState = stringValue(data.identityState);
  if (
    !workoutId || !userId || !kind ||
    !HOME_TODAY_ACTIVITY_KINDS.includes(kind as HomeTodayActivityKind) ||
    steps === null || durationSeconds === null ||
    completedAt === null || publishedAt === null ||
    displayName === null || !identityState
  ) {
    return null;
  }
  const goalKind = stringValue(data.justClimbGoalKind);
  const photoURL = stringValue(data.photoURL);
  return {
    workoutId,
    userId,
    kind: kind as HomeTodayActivityKind,
    climbId: stringValue(data.climbId),
    routineTemplateId: stringValue(data.routineTemplateId),
    steps,
    durationSeconds,
    completedAtMillis: completedAt,
    publishedAtMillis: publishedAt,
    justClimbGoalKind: goalKind &&
      JUST_CLIMB_GOAL_KINDS.includes(goalKind as HomeTodayJustClimbGoalKind) ?
      goalKind as HomeTodayJustClimbGoalKind :
      null,
    justClimbGoalValue: positiveIntegerValue(data.justClimbGoalValue),
    displayName,
    avatarToken: typeof data.avatarToken === "string" ? data.avatarToken : "",
    photoURL,
    identityState,
    isSynthetic: data.isSynthetic === true,
  };
}

/**
 * @param {HomeTodayActivityCandidate} candidate Parsed workout.
 * @param {number} publishedAtMillis When the feed first saw it.
 * @param {PublicUserSnapshot} publicUser The climber's public snapshot.
 * @return {HomeTodayActivityRow} The row to store.
 */
function rowFrom(
  candidate: HomeTodayActivityCandidate,
  publishedAtMillis: number,
  publicUser: PublicUserSnapshot
): HomeTodayActivityRow {
  return {
    ...candidate,
    publishedAtMillis,
    ...identityFields(publicUser),
  };
}

/**
 * The identity a row carries. Always the climber's current public snapshot,
 * which is already anonymous for a pending or deleted identity; a real account
 * is never synthetic, that marker belongs to seeded rows alone.
 * @param {PublicUserSnapshot} publicUser The climber's public snapshot.
 * @return {object} Identity fields.
 */
function identityFields(publicUser: PublicUserSnapshot): {
  displayName: string;
  avatarToken: string;
  photoURL: string | null;
  identityState: string;
  isSynthetic: boolean;
} {
  return {
    displayName: publicUser.displayName,
    avatarToken: publicUser.avatarToken,
    photoURL: publicUser.photoURL,
    identityState: publicUser.identityState,
    isSynthetic: false,
  };
}

/**
 * Whether a brand-new candidate would sort behind every row of a full list.
 * @param {HomeTodayActivityRow[]} rows The full stored list.
 * @param {HomeTodayActivityCandidate} candidate The new candidate.
 * @param {number} publishedAtMillis Its publish time.
 * @return {boolean} True when merging could not keep it.
 */
function wouldFallOffTheEnd(
  rows: HomeTodayActivityRow[],
  candidate: HomeTodayActivityCandidate,
  publishedAtMillis: number
): boolean {
  const last = rows[rows.length - 1];
  const probe: HomeTodayActivityRow = {
    ...candidate,
    publishedAtMillis,
    displayName: "",
    avatarToken: "",
    photoURL: null,
    identityState: "",
    isSynthetic: false,
  };
  return compareHomeTodayActivityRows(probe, last) > 0;
}

/**
 * @param {HomeTodayActivityRow[]} lhs One list.
 * @param {HomeTodayActivityRow[]} rhs The other.
 * @return {boolean} True when every row matches in order.
 */
function rowListsEqual(
  lhs: HomeTodayActivityRow[],
  rhs: HomeTodayActivityRow[]
): boolean {
  return lhs.length === rhs.length &&
    lhs.every((row, index) => rowsEqual(row, rhs[index]));
}

/**
 * @param {HomeTodayActivityRow} lhs One row.
 * @param {HomeTodayActivityRow} rhs The other.
 * @return {boolean} True when every stored field matches.
 */
function rowsEqual(
  lhs: HomeTodayActivityRow,
  rhs: HomeTodayActivityRow
): boolean {
  return candidatesEqual(lhs, rhs) &&
    lhs.publishedAtMillis === rhs.publishedAtMillis &&
    lhs.displayName === rhs.displayName &&
    lhs.avatarToken === rhs.avatarToken &&
    lhs.photoURL === rhs.photoURL &&
    lhs.identityState === rhs.identityState &&
    lhs.isSynthetic === rhs.isSynthetic;
}

/**
 * When the climb finished: its start plus its duration, or the duration alone
 * when no start was recorded, mirroring `parseCompletedLandmarkWorkout`.
 * @param {unknown} startedAt Raw start timestamp.
 * @param {number} durationSeconds Session length.
 * @return {number} Epoch millis.
 */
function completedAtMillis(
  startedAt: unknown,
  durationSeconds: number
): number {
  const startedAtMillis = timestampMillis(startedAt);
  const elapsedMillis = Math.round(durationSeconds * 1000);
  return startedAtMillis === null ?
    elapsedMillis :
    startedAtMillis + elapsedMillis;
}

/**
 * Reads epoch millis from a Firestore Timestamp, a Date, or a number.
 * @param {unknown} value Raw value.
 * @return {number | null} Epoch millis.
 */
function timestampMillis(value: unknown): number | null {
  if (value && typeof value === "object") {
    const candidate = value as {
      toMillis?: () => number;
      toDate?: () => Date;
      getTime?: () => number;
    };
    if (typeof candidate.toMillis === "function") {
      return candidate.toMillis();
    }
    if (typeof candidate.toDate === "function") {
      return candidate.toDate().getTime();
    }
    if (typeof candidate.getTime === "function") {
      return candidate.getTime();
    }
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

/**
 * @param {unknown} value Raw value.
 * @return {string | null} Trimmed non-empty string.
 */
function stringValue(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * @param {unknown} value Raw value.
 * @return {number | null} Non-negative number.
 */
function nonNegativeNumberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ?
    value :
    null;
}

/**
 * @param {unknown} value Raw value.
 * @return {number | null} Positive number.
 */
function positiveNumberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ?
    value :
    null;
}

/**
 * @param {unknown} value Raw value.
 * @return {number | null} Non-negative integer.
 */
function nonNegativeIntegerValue(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ?
    value :
    null;
}

/**
 * @param {unknown} value Raw value.
 * @return {number | null} Positive integer.
 */
function positiveIntegerValue(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ?
    value :
    null;
}
