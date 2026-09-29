/**
 * The public profile's heart-rate aggregates, derived from a climber's own climbs.
 *
 * The mirror of `ProfileHeartRateSummary.derive` in the iOS app, which publishes these at
 * publish time; this copy exists for the seeds and for
 * `scripts/backfill-profile-heart-rate.mjs`. Both are pinned to
 * `SharedTestVectors/profile-heart-rate-summary-vector.json`, so a climber's public numbers
 * never depend on which of the two wrote them.
 *
 * Only the two aggregates ever leave this module: no sample and no per-climb heart rate is
 * published to the cross-account `profile_stats` document.
 */

export const PROFILE_HEART_RATE_FIELDS = Object.freeze({
  averageBpm: "average_heart_rate_bpm",
  maxBpm: "max_heart_rate_bpm",
});

/**
 * The climber's "Show my heart rate on my profile" choice on the same document. Absent means
 * shown; false means no aggregate may be published, which `firestore.rules` also enforces.
 */
export const PROFILE_HEART_RATE_PUBLIC_FIELD = "heart_rate_public";

export function isProfileHeartRatePublic(stats) {
  return stats?.[PROFILE_HEART_RATE_PUBLIC_FIELD] !== false;
}

/** Wider than any human heart, narrower than a sensor fault. `firestore.rules` agrees. */
export const PLAUSIBLE_BPM = Object.freeze({min: 25, max: 250});

function plausibleBpm(value) {
  return Number.isInteger(value) && value >= PLAUSIBLE_BPM.min && value <= PLAUSIBLE_BPM.max
    ? value
    : null;
}

/**
 * @param {{durationSeconds: number, averageBpm: number|null, maxBpm: number|null}[]} climbs
 * @returns {{averageBpm: number|null, maxBpm: number|null}}
 *   averageBpm is the duration-weighted mean of each climb's own average over the climbs that
 *   carry one; maxBpm the highest per-climb max. null means the field is absent.
 */
export function deriveProfileHeartRate(climbs) {
  let weightedBeats = 0;
  let weightedSeconds = 0;
  let highest = null;

  for (const climb of climbs) {
    const average = plausibleBpm(climb.averageBpm);
    const duration = Number(climb.durationSeconds);
    if (average !== null && Number.isFinite(duration) && duration > 0) {
      weightedBeats += average * duration;
      weightedSeconds += duration;
    }
    const max = plausibleBpm(climb.maxBpm);
    if (max !== null) {
      highest = highest === null ? max : Math.max(highest, max);
    }
  }

  return {
    averageBpm: weightedSeconds > 0 ? Math.round(weightedBeats / weightedSeconds) : null,
    maxBpm: highest,
  };
}

/** Reads the private `users/{uid}/workouts` documents the iOS app syncs. */
export function deriveProfileHeartRateFromWorkoutDocuments(workouts) {
  return deriveProfileHeartRate(workouts.map((workout) => ({
    durationSeconds: workout.durationSeconds,
    averageBpm: integerOrNull(workout.avgHeartRateBpm),
    maxBpm: integerOrNull(workout.maxHeartRateBpm),
  })));
}

/** The `profile_stats` fields for a derived summary; an absent aggregate is an absent key. */
export function profileHeartRateFields(summary) {
  const fields = {};
  if (summary.averageBpm !== null) {
    fields[PROFILE_HEART_RATE_FIELDS.averageBpm] = summary.averageBpm;
  }
  if (summary.maxBpm !== null) {
    fields[PROFILE_HEART_RATE_FIELDS.maxBpm] = summary.maxBpm;
  }
  return fields;
}

function integerOrNull(value) {
  const number = Number(value);
  return value !== null && value !== undefined && Number.isInteger(number) ? number : null;
}
