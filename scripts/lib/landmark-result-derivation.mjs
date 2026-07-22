/**
 * The completed-climb projection derivation, in Node/ESM form.
 *
 * This mirrors functions/src/climbCompletions.ts exactly (same completion
 * predicate, same digest, same best-attempt pick), because CANONICAL §1
 * mandates one Projection Builder shared by all three triggers - the live
 * Firestore trigger (the CF), a rebuild, and the migration backfill. Swift, the
 * CF (TS), and this module can't share a binary, so the completion contract is
 * shared through the vector at
 * SharedTestVectors/legacy-recoverable-completion-vector.json and the derivation
 * is kept byte-equivalent and unit-tested here. Only the backfill
 * (scripts/backfill-landmark-results.mjs) imports this; the CF has its own copy.
 */

import {createHash} from "crypto";
import {
  isRecoverableLegacyCompletion,
  HEADPHONE_MOTION_SOURCE,
  nonEmptyString,
  nonNegativeInteger,
  positiveInteger,
} from "./legacy-climb-completion.mjs";

export const LANDMARK_RESULT_SCHEMA_VERSION = 1;

/**
 * Reduces a raw workout to a completed landmark workout, or null when it is not
 * a completed landmark climb. Completion uses the shared vector-pinned contract.
 * @param {string} workoutId Workout document id.
 * @param {Record<string, unknown>} data Raw workout data.
 * @return {object|null} The completion, or null.
 */
export function parseCompletedLandmarkWorkout(workoutId, data) {
  if (!data || data.source !== HEADPHONE_MOTION_SOURCE) {
    return null;
  }

  const metadata = parseMetadata(data.sourceMetadata);
  if (!metadata) {
    return null;
  }

  const climbId = nonEmptyString(metadata.climbId);
  if (!climbId) {
    return null;
  }

  const steps = nonNegativeInteger(data.steps) ?? 0;
  const elapsedSeconds = Math.round(numberOrZero(data.durationSeconds));
  const targetStepCount = positiveInteger(metadata.climbTargetStepCount) ??
    positiveInteger(metadata.targetStepCount);
  const stopReason = nonEmptyString(metadata.stopReason) ?? "";

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

  return {workoutId, climbId, steps, elapsedSeconds, completedAtMillis};
}

/**
 * Derives the per-landmark projection from its completed workouts.
 * @param {string} climbId Landmark id.
 * @param {object[]} completions Completions for this landmark.
 * @return {object|null} The projection (millis form), or null when empty.
 */
export function deriveLandmarkResult(climbId, completions) {
  if (completions.length === 0) {
    return null;
  }

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
 * Whether a write can be skipped because the stored projection already reflects
 * the derived event (validate-the-invariant-before-writing).
 * @param {object|null} existing Stored projection (millis form).
 * @param {object} next Newly derived projection.
 * @return {boolean} True when the write can be skipped.
 */
export function shouldSkipLandmarkResultWrite(existing, next) {
  if (!existing) {
    return false;
  }
  return existing.computedThroughEvent === next.computedThroughEvent &&
    existing.climbId === next.climbId &&
    existing.firstCompletedAtMillis === next.firstCompletedAtMillis &&
    existing.latestCompletedAtMillis === next.latestCompletedAtMillis &&
    existing.attemptCount === next.attemptCount &&
    existing.bestWorkoutId === next.bestWorkoutId &&
    existing.bestElapsedSeconds === next.bestElapsedSeconds &&
    existing.schemaVersion === next.schemaVersion;
}

/**
 * Recomputes one landmark projection atomically from its canonical workouts.
 * The store must retry the callback when any transactional read changes, which
 * prevents a stale workout snapshot from committing after a newer projection.
 * `getLandmarkResult` must return `{exists, projection}` so an unparseable
 * stored document stays distinguishable from an absent one.
 * @param {object} store Transactional persistence boundary.
 * @param {string} userId Owning user id.
 * @param {string} climbId Landmark id.
 * @return {Promise<"written"|"skipped"|"deleted">} Reconciliation outcome.
 */
export async function recomputeLandmarkResult(store, userId, climbId) {
  return store.runTransaction(async (transaction) => {
    const workouts = await transaction.listLandmarkWorkouts(userId, climbId);
    const completions = [];
    for (const workout of workouts) {
      const parsed = parseCompletedLandmarkWorkout(workout.id, workout.data);
      if (parsed && parsed.climbId === climbId) {
        completions.push(parsed);
      }
    }

    // Firestore requires every read before the first write. Changes to either
    // this document or the workout query cause the entire callback to retry.
    const stored = await transaction.getLandmarkResult(userId, climbId);
    const existing = stored.projection;
    const next = deriveLandmarkResult(climbId, completions);
    if (!next) {
      // Delete on existence, not on parseability: a stored document whose
      // canonical completions are gone is an orphan even when it is malformed.
      if (!stored.exists) {
        return "skipped";
      }
      await transaction.deleteLandmarkResult(userId, climbId);
      return "deleted";
    }

    if (shouldSkipLandmarkResultWrite(existing, next)) {
      return "skipped";
    }

    await transaction.writeLandmarkResult(userId, climbId, next);
    return "written";
  });
}

/**
 * Groups a flat list of raw workouts into completions keyed by user then climb.
 * @param {{userId: string, workoutId: string, data: Record<string, unknown>}[]} workouts
 *   Raw workouts with their owning user id.
 * @return {Map<string, Map<string, object[]>>} userId -> climbId -> completions.
 */
export function groupCompletions(workouts) {
  const byUser = new Map();
  for (const workout of workouts) {
    const parsed = parseCompletedLandmarkWorkout(workout.workoutId, workout.data);
    if (!parsed) {
      continue;
    }
    if (!byUser.has(workout.userId)) {
      byUser.set(workout.userId, new Map());
    }
    const byClimb = byUser.get(workout.userId);
    if (!byClimb.has(parsed.climbId)) {
      byClimb.set(parsed.climbId, []);
    }
    byClimb.get(parsed.climbId).push(parsed);
  }
  return byUser;
}

/**
 * Orders completions: fastest, then earliest, then by id. Stable.
 * @param {object} lhs Left completion.
 * @param {object} rhs Right completion.
 * @return {number} Comparison result.
 */
function compareCompletions(lhs, rhs) {
  if (lhs.elapsedSeconds !== rhs.elapsedSeconds) {
    return lhs.elapsedSeconds - rhs.elapsedSeconds;
  }
  if (lhs.completedAtMillis !== rhs.completedAtMillis) {
    return lhs.completedAtMillis - rhs.completedAtMillis;
  }
  return String(lhs.workoutId).localeCompare(String(rhs.workoutId));
}

/**
 * A deterministic digest of the completion set (matches the CF).
 * @param {object[]} ordered Completions in stable order.
 * @return {string} Hex digest.
 */
function computedThroughEvent(ordered) {
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
 * Parses source metadata JSON.
 * @param {unknown} value Raw sourceMetadata.
 * @return {Record<string, unknown>|null} Parsed metadata.
 */
function parseMetadata(value) {
  if (typeof value !== "string") {
    return null;
  }
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

/**
 * Reads epoch millis from a Firestore Timestamp, Date, or number.
 * @param {unknown} value Raw value.
 * @return {number|null} Epoch millis.
 */
function timestampMillis(value) {
  if (value && typeof value === "object") {
    if (typeof value.toMillis === "function") {
      return value.toMillis();
    }
    if (typeof value.toDate === "function") {
      return value.toDate().getTime();
    }
    if (typeof value.getTime === "function") {
      return value.getTime();
    }
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

/**
 * Reads a finite number, else 0.
 * @param {unknown} value Raw value.
 * @return {number} The number, or 0.
 */
function numberOrZero(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
