/**
 * Server-derived completed-climb projection (Phase 1 · Slice 1).
 *
 * The canonical record of a completed climb is the private `Workout` (1:1 with
 * the completion - see data/verify-workout-climb-cardinality-m2/report.md).
 * This function is the SINGLE site that derives the completed-climb projection
 * FROM that canonical workout: on any write to
 * `users/{uid}/workouts/{workoutId}` it
 * recomputes the affected `users/{uid}/landmarkResults/{climbId}` document from
 * the user's completed landmark workouts.
 *
 * One Projection Builder, three triggers (CANONICAL §1): this live trigger, a
 * rebuild of a corrupted projection, and the migration backfill
 * (scripts/backfill-landmark-results.mjs) all go through the same derivation
 * and the same validate-before-write guard. Never fork per-trigger logic.
 *
 * It writes ONLY the private `landmarkResults` projection. It never publishes a
 * replay row and never assigns a First Ascent - that stays owned by the
 * live-session-gated replay path (liveReplayLeaderboard.ts), which forces
 * `firstAscentEligible=false` for legacy/typed data. A typed or recovered-draft
 * completion can populate `landmarkResults` (private restore visibility) but
 * can never claim a First Ascent; the two paths never cross.
 */

import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {createHash} from "crypto";
import {
  HEADPHONE_MOTION_SOURCE,
  isRecoverableLegacyCompletion,
} from "./legacyClimbCompletion.js";

const LANDMARK_RESULTS_COLLECTION = "landmarkResults";
const WORKOUTS_COLLECTION = "workouts";
const USERS_COLLECTION = "users";
export const LANDMARK_RESULT_SCHEMA_VERSION = 1;

/** A completed landmark workout, reduced to the fields the projection needs. */
export interface CompletedLandmarkWorkout {
  workoutId: string;
  climbId: string;
  steps: number;
  elapsedSeconds: number;
  completedAtMillis: number;
}

/** The derived per-landmark projection, in comparable (millis) form. */
export interface LandmarkResultProjection {
  climbId: string;
  completed: true;
  firstCompletedAtMillis: number;
  latestCompletedAtMillis: number;
  attemptCount: number;
  bestWorkoutId: string;
  bestElapsedSeconds: number;
  schemaVersion: number;
  computedThroughEvent: string;
}

/**
 * The persistence boundary. The Admin SDK bypasses security rules, so this is
 * the only writer of `landmarkResults`; tests inject an in-memory store.
 */
export interface LandmarkResultStore {
  listUserWorkouts(
    userId: string
  ): Promise<{id: string; data: Record<string, unknown>}[]>;
  getLandmarkResult(
    userId: string,
    climbId: string
  ): Promise<LandmarkResultProjection | null>;
  writeLandmarkResult(
    userId: string,
    climbId: string,
    projection: LandmarkResultProjection
  ): Promise<void>;
  deleteLandmarkResult(userId: string, climbId: string): Promise<void>;
}

/**
 * Reduces a raw workout document to a completed landmark workout, or null when
 * it is not a completed landmark climb (a Just Climb, a non-climb workout, or a
 * short attempt). Completion is decided by the shared, vector-pinned
 * `isRecoverableLegacyCompletion` contract, which is the single definition of
 * "finished a landmark" across Swift, this function, and the backfill: it
 * covers both modern completions (a step target recorded, steps >= target)
 * and legacy ones (no target recorded, stopReason target_reached).
 * @param {string} workoutId The workout document id.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @return {CompletedLandmarkWorkout | null} The completion, or null.
 */
export function parseCompletedLandmarkWorkout(
  workoutId: string,
  data: Record<string, unknown> | undefined
): CompletedLandmarkWorkout | null {
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

  const climbId = stringValue(metadata.climbId);
  if (!climbId) {
    return null;
  }

  const steps = nonNegativeIntegerValue(data.steps) ?? 0;
  const elapsedSeconds = Math.round(
    nonNegativeNumberValue(data.durationSeconds) ?? 0
  );
  const targetStepCount = positiveIntegerValue(metadata.climbTargetStepCount) ??
    positiveIntegerValue(metadata.targetStepCount);
  const stopReason = stringValue(metadata.stopReason) ?? "";

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

  const startedAtMillis = timestampMillis(data.startedAt);
  const completedAtMillis = startedAtMillis === null ?
    elapsedSeconds * 1000 :
    startedAtMillis + elapsedSeconds * 1000;

  return {
    workoutId,
    climbId,
    steps,
    elapsedSeconds,
    completedAtMillis,
  };
}

/**
 * Derives the per-landmark projection from a landmark's completed workouts.
 * Deterministic in the completion set, so the live trigger, a rebuild, and the
 * migration backfill converge on byte-identical output (serves I2).
 * @param {string} climbId The landmark id (== climbId).
 * @param {CompletedLandmarkWorkout[]} completions Completions for the landmark.
 * @return {LandmarkResultProjection | null} The projection, or null when empty.
 */
export function deriveLandmarkResult(
  climbId: string,
  completions: CompletedLandmarkWorkout[]
): LandmarkResultProjection | null {
  if (completions.length === 0) {
    return null;
  }

  // Stable ordering so the digest and best-attempt pick never depend on read
  // order: fastest first, then earliest, then by id.
  const ordered = [...completions].sort(compareCompletions);
  const best = ordered[0];

  let firstCompletedAtMillis = completions[0].completedAtMillis;
  let latestCompletedAtMillis = completions[0].completedAtMillis;
  for (const completion of completions) {
    firstCompletedAtMillis = Math.min(
      firstCompletedAtMillis,
      completion.completedAtMillis
    );
    latestCompletedAtMillis = Math.max(
      latestCompletedAtMillis,
      completion.completedAtMillis
    );
  }

  return {
    climbId,
    completed: true,
    firstCompletedAtMillis,
    latestCompletedAtMillis,
    attemptCount: completions.length,
    bestWorkoutId: best.workoutId,
    bestElapsedSeconds: best.elapsedSeconds,
    schemaVersion: LANDMARK_RESULT_SCHEMA_VERSION,
    computedThroughEvent: computedThroughEvent(ordered),
  };
}

/**
 * Whether a recompute may return success WITHOUT writing, because the canonical
 * event is already reflected in the stored projection. This is the required
 * validate-the-invariant-before-writing guard (not deterministic-ID-only): it
 * makes re-delivery, concurrent triggers, and backfill re-runs converge on "the
 * projection already exists -> success, no duplicate write".
 * @param {LandmarkResultProjection | null} existing Stored projection.
 * @param {LandmarkResultProjection} next Newly derived projection.
 * @return {boolean} True when the write can be skipped.
 */
export function shouldSkipLandmarkResultWrite(
  existing: LandmarkResultProjection | null,
  next: LandmarkResultProjection
): boolean {
  if (!existing) {
    return false;
  }
  return existing.computedThroughEvent === next.computedThroughEvent &&
    landmarkResultsEqual(existing, next);
}

/**
 * Recomputes and reconciles one landmark's projection from the user's workouts.
 * Reads all the user's completed landmark workouts for this climb, derives the
 * projection, validates the invariant, and writes (or skips, or deletes when no
 * completion remains). The single derivation callable by all three triggers.
 * @param {LandmarkResultStore} store Persistence boundary.
 * @param {string} userId The owning user id.
 * @param {string} climbId The landmark id to recompute.
 * @return {Promise<"written" | "skipped" | "deleted">} The outcome.
 */
export async function recomputeLandmarkResult(
  store: LandmarkResultStore,
  userId: string,
  climbId: string
): Promise<"written" | "skipped" | "deleted"> {
  const workouts = await store.listUserWorkouts(userId);
  const completions: CompletedLandmarkWorkout[] = [];
  for (const workout of workouts) {
    const parsed = parseCompletedLandmarkWorkout(workout.id, workout.data);
    if (parsed && parsed.climbId === climbId) {
      completions.push(parsed);
    }
  }

  const next = deriveLandmarkResult(climbId, completions);
  if (!next) {
    // No completed workout remains for this landmark (deleted or edited below
    // target). The projection is disposable; remove it so the set stays honest.
    await store.deleteLandmarkResult(userId, climbId);
    return "deleted";
  }

  const existing = await store.getLandmarkResult(userId, climbId);
  if (shouldSkipLandmarkResultWrite(existing, next)) {
    return "skipped";
  }

  await store.writeLandmarkResult(userId, climbId, next);
  return "written";
}

/**
 * Derives `landmarkResults` from the canonical private workout on every write.
 */
export const onWorkoutWritten = onDocumentWritten(
  {
    document: "users/{userId}/workouts/{workoutId}",
    retry: true,
  },
  async (event) => {
    const userId = event.params.userId;
    const workoutId = event.params.workoutId;
    const beforeData = event.data?.before.data() as
      Record<string, unknown> | undefined;
    const afterData = event.data?.after.data() as
      Record<string, unknown> | undefined;

    // A write can add a completion, remove one (delete / edit below target), or
    // move it between landmarks. Recompute every landmark either side touched.
    const affected = new Set<string>();
    const before = parseCompletedLandmarkWorkout(workoutId, beforeData);
    if (before) {
      affected.add(before.climbId);
    }
    const after = parseCompletedLandmarkWorkout(workoutId, afterData);
    if (after) {
      affected.add(after.climbId);
    }
    if (affected.size === 0) {
      return;
    }

    const store = makeAdminStore();
    for (const climbId of affected) {
      await recomputeLandmarkResult(store, userId, climbId);
    }
  }
);

/**
 * The production store, backed by the Admin SDK.
 * @return {LandmarkResultStore} Admin-backed store.
 */
export function makeAdminStore(): LandmarkResultStore {
  const db = admin.firestore();

  return {
    async listUserWorkouts(userId) {
      const snapshot = await db
        .collection(USERS_COLLECTION)
        .doc(userId)
        .collection(WORKOUTS_COLLECTION)
        .get();
      return snapshot.docs.map((doc) => ({
        id: doc.id,
        data: doc.data() as Record<string, unknown>,
      }));
    },

    async getLandmarkResult(userId, climbId) {
      const snapshot = await landmarkResultRef(db, userId, climbId).get();
      if (!snapshot.exists) {
        return null;
      }
      return normalizeStoredProjection(
        climbId,
        snapshot.data() as Record<string, unknown>
      );
    },

    async writeLandmarkResult(userId, climbId, projection) {
      await landmarkResultRef(db, userId, climbId).set(
        toFirestoreProjection(projection)
      );
    },

    async deleteLandmarkResult(userId, climbId) {
      await landmarkResultRef(db, userId, climbId).delete();
    },
  };
}

/**
 * Builds the landmark-result document reference.
 * @param {admin.firestore.Firestore} db Firestore instance.
 * @param {string} userId Owning user id.
 * @param {string} climbId Landmark id.
 * @return {admin.firestore.DocumentReference} The document reference.
 */
function landmarkResultRef(
  db: admin.firestore.Firestore,
  userId: string,
  climbId: string
): admin.firestore.DocumentReference {
  return db
    .collection(USERS_COLLECTION)
    .doc(userId)
    .collection(LANDMARK_RESULTS_COLLECTION)
    .doc(climbId);
}

/**
 * Converts the comparable (millis) projection into the stored Firestore shape.
 * @param {LandmarkResultProjection} projection Derived projection.
 * @return {Record<string, unknown>} Firestore document data.
 */
function toFirestoreProjection(
  projection: LandmarkResultProjection
): Record<string, unknown> {
  return {
    climbId: projection.climbId,
    completed: projection.completed,
    firstCompletedAt: admin.firestore.Timestamp.fromMillis(
      projection.firstCompletedAtMillis
    ),
    latestCompletedAt: admin.firestore.Timestamp.fromMillis(
      projection.latestCompletedAtMillis
    ),
    attemptCount: projection.attemptCount,
    bestWorkoutId: projection.bestWorkoutId,
    bestElapsedSeconds: projection.bestElapsedSeconds,
    schemaVersion: projection.schemaVersion,
    computedThroughEvent: projection.computedThroughEvent,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Normalizes a stored Firestore document back into the comparable projection so
 * the validate-before-write guard compares like with like.
 * @param {string} climbId Landmark id (the document id).
 * @param {Record<string, unknown>} data Stored document data.
 * @return {LandmarkResultProjection | null} Comparable projection.
 */
function normalizeStoredProjection(
  climbId: string,
  data: Record<string, unknown>
): LandmarkResultProjection | null {
  const computed = stringValue(data.computedThroughEvent);
  const bestWorkoutId = stringValue(data.bestWorkoutId);
  const firstCompletedAtMillis = timestampMillis(data.firstCompletedAt);
  const latestCompletedAtMillis = timestampMillis(data.latestCompletedAt);
  const attemptCount = positiveIntegerValue(data.attemptCount);
  const bestElapsedSeconds = nonNegativeIntegerValue(data.bestElapsedSeconds);
  const schemaVersion = nonNegativeIntegerValue(data.schemaVersion);

  if (
    !computed ||
    !bestWorkoutId ||
    firstCompletedAtMillis === null ||
    latestCompletedAtMillis === null ||
    attemptCount === null ||
    bestElapsedSeconds === null ||
    schemaVersion === null
  ) {
    return null;
  }

  return {
    climbId,
    completed: true,
    firstCompletedAtMillis,
    latestCompletedAtMillis,
    attemptCount,
    bestWorkoutId,
    bestElapsedSeconds,
    schemaVersion,
    computedThroughEvent: computed,
  };
}

/**
 * Orders completions: fastest, then earliest, then by workout id. Stable.
 * @param {CompletedLandmarkWorkout} lhs Left completion.
 * @param {CompletedLandmarkWorkout} rhs Right completion.
 * @return {number} Comparison result.
 */
function compareCompletions(
  lhs: CompletedLandmarkWorkout,
  rhs: CompletedLandmarkWorkout
): number {
  if (lhs.elapsedSeconds !== rhs.elapsedSeconds) {
    return lhs.elapsedSeconds - rhs.elapsedSeconds;
  }
  if (lhs.completedAtMillis !== rhs.completedAtMillis) {
    return lhs.completedAtMillis - rhs.completedAtMillis;
  }
  return lhs.workoutId.localeCompare(rhs.workoutId);
}

/**
 * A deterministic digest of the completion set. Identical input completions
 * always yield the same digest; any new or changed completion changes it, so it
 * doubles as the "have we already incorporated this event" marker.
 * @param {CompletedLandmarkWorkout[]} ordered Completions in stable order.
 * @return {string} Hex digest.
 */
function computedThroughEvent(ordered: CompletedLandmarkWorkout[]): string {
  const canonical = ordered
    .map((completion) => [
      completion.workoutId,
      completion.steps,
      completion.elapsedSeconds,
      completion.completedAtMillis,
    ].join(":"))
    .join("|");
  return createHash("sha256").update(canonical).digest("hex");
}

/**
 * Field-by-field equality on the comparable projection (excludes server times).
 * @param {LandmarkResultProjection} lhs Left projection.
 * @param {LandmarkResultProjection} rhs Right projection.
 * @return {boolean} True when byte-identical in the derived fields.
 */
function landmarkResultsEqual(
  lhs: LandmarkResultProjection,
  rhs: LandmarkResultProjection
): boolean {
  return lhs.climbId === rhs.climbId &&
    lhs.completed === rhs.completed &&
    lhs.firstCompletedAtMillis === rhs.firstCompletedAtMillis &&
    lhs.latestCompletedAtMillis === rhs.latestCompletedAtMillis &&
    lhs.attemptCount === rhs.attemptCount &&
    lhs.bestWorkoutId === rhs.bestWorkoutId &&
    lhs.bestElapsedSeconds === rhs.bestElapsedSeconds &&
    lhs.schemaVersion === rhs.schemaVersion;
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
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

/**
 * Parses a trimmed non-empty string.
 * @param {unknown} value Raw value.
 * @return {string | null} Parsed string.
 */
function stringValue(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Parses a non-negative number.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed number.
 */
function nonNegativeNumberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ?
    value :
    null;
}

/**
 * Parses a non-negative integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer.
 */
function nonNegativeIntegerValue(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ?
    value :
    null;
}

/**
 * Parses a positive integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer.
 */
function positiveIntegerValue(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ?
    value :
    null;
}

export const climbCompletionsTestHooks = {
  parseCompletedLandmarkWorkout,
  deriveLandmarkResult,
  shouldSkipLandmarkResultWrite,
  recomputeLandmarkResult,
};
