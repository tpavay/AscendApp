const HEADPHONE_MOTION_SOURCE = "headphone_motion";
const MAX_CLIMB_ID_LENGTH = 160;

/**
 * Derives the indexed climb key from the canonical source metadata.
 * @param {Record<string, unknown>} data Raw workout document.
 * @return {string|null} Promoted climb id, or null when not a climb workout.
 */
export function promotedWorkoutClimbId(data) {
  if (data.source !== HEADPHONE_MOTION_SOURCE) {
    return null;
  }

  const metadata = parseMetadata(data.sourceMetadata);
  const climbId = nonEmptyString(metadata?.climbId);
  if (!climbId || climbId.length > MAX_CLIMB_ID_LENGTH) {
    return null;
  }
  return climbId;
}

/** @param {unknown} value Raw source metadata. */
function parseMetadata(value) {
  if (typeof value !== "string") {
    return null;
  }
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

/** @param {unknown} value Candidate string. */
function nonEmptyString(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
