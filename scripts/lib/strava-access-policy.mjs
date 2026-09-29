/**
 * Pure decisions behind scripts/strava-access.mjs.
 *
 * `_strava_access/settings` is read by Cloud Functions on every Strava call:
 * `enabled` is the kill switch and `allowedUserIds` is who may start a
 * connection. The allowlist is also the capacity lever - Strava refuses to
 * authorize an athlete past the app's approved athlete capacity, and a
 * climber removed from the list keeps holding a seat until their connection
 * ends, so allowed and connected climbers together must never exceed the
 * seats Strava has granted.
 */

export const STRAVA_ACCESS_PATH = Object.freeze({
  collection: "_strava_access",
  document: "settings",
});

/**
 * Strava's self-serve athlete capacity. Anything above it needs Strava's
 * Developer Program review, and `--capacity` records what Strava approved.
 */
export const DEFAULT_STRAVA_CAPACITY = 10;

/**
 * Normalizes whatever is stored, failing closed exactly as the functions do.
 * @param {unknown} data Stored document data, or undefined.
 * @return {{enabled: boolean, allowedUserIds: string[]}} Settings.
 */
export function normalizeStravaAccess(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return {enabled: false, allowedUserIds: []};
  }
  const allowed = Array.isArray(data.allowedUserIds) ?
    data.allowedUserIds.filter((value) => typeof value === "string" && value !== "") :
    [];
  return {
    enabled: data.enabled === true,
    allowedUserIds: [...new Set(allowed)].sort(),
  };
}

/**
 * Plans one change to the settings.
 * @param {{enabled: boolean, allowedUserIds: string[]}} current Settings now.
 * @param {{command: string, userId?: string, capacity?: number, connectedUserIds?: string[]}} request What to do.
 * @return {{next: {enabled: boolean, allowedUserIds: string[]}, changed: boolean, summary: string}} Plan.
 */
export function planStravaAccessChange(current, request) {
  const capacity = request.capacity ?? DEFAULT_STRAVA_CAPACITY;
  if (!Number.isInteger(capacity) || capacity < 1) {
    throw new Error(`--capacity must be a positive integer, got ${request.capacity}.`);
  }
  const allowed = new Set(current.allowedUserIds);
  const seats = new Set([...allowed, ...(request.connectedUserIds ?? [])]);

  switch (request.command) {
  case "enable":
  case "disable": {
    const enabled = request.command === "enable";
    return {
      next: {...current, enabled},
      changed: current.enabled !== enabled,
      summary: `Strava is ${enabled ? "ON" : "OFF"} for this project.`,
    };
  }
  case "allow": {
    const userId = requireUserId(request.userId);
    if (allowed.has(userId)) {
      return {next: current, changed: false, summary: `${userId} is already allowed.`};
    }
    if (!seats.has(userId) && seats.size >= capacity) {
      throw new Error(
        `Allowed and connected climbers already hold ${seats.size} of ${capacity} seats. ` +
          "Strava refuses athletes past the app's approved capacity, so remove someone and have them disconnect first, " +
          "or pass --capacity with the number Strava has approved."
      );
    }
    allowed.add(userId);
    seats.add(userId);
    return {
      next: {...current, allowedUserIds: [...allowed].sort()},
      changed: true,
      summary: `${userId} may now connect Strava (${seats.size} of ${capacity} seats).`,
    };
  }
  case "remove": {
    const userId = requireUserId(request.userId);
    if (!allowed.has(userId)) {
      return {next: current, changed: false, summary: `${userId} was not allowed.`};
    }
    allowed.delete(userId);
    return {
      next: {...current, allowedUserIds: [...allowed].sort()},
      changed: true,
      summary:
        `${userId} may no longer start a Strava connection. ` +
        "A connection they already made stays until they disconnect it.",
    };
  }
  default:
    throw new Error(`Unknown command "${request.command}".`);
  }
}

/**
 * @param {unknown} userId Candidate uid.
 * @return {string} The uid.
 */
function requireUserId(userId) {
  if (typeof userId !== "string" || !/^[A-Za-z0-9_-]{6,128}$/.test(userId)) {
    throw new Error("Name the climber by Firebase uid, or by --email.");
  }
  return userId;
}
