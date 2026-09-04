/**
 * What the Ascend app would actually render, judged from stored documents.
 *
 * Every helper here mirrors one client parser, field for field, because a
 * document that exists and a row that renders are different claims. Six weeks of
 * "staging is ready" were claims of the first kind: the seed's own summary, the
 * fixture audit and hand-run database probes all confirm that documents were
 * written, and none of them confirm that a climber opening the app sees a
 * populated product. The Empire State board carried `completedCount: 85` on a
 * summary the app never renders while the collection it does render held four
 * rows.
 *
 * So this module is deliberately paranoid about the guards a parser applies
 * *after* the read succeeds - the `identityPolicyVersion` a leaderboard row must
 * carry, the `earnedAt` an achievement must carry, the display name a missing
 * profile resolves into. Those guards are why a full collection renders as an
 * empty board.
 *
 * Pure, so `scripts/test/app-render-contract.test.mjs` can pin every rule
 * without a network. The Swift authorities each helper mirrors are named on it.
 */

import {createHash} from "node:crypto";

import {isAllowedPublicPhotoURL} from "../seed/lib/public-identity-contract.mjs";

/** Mirrors `PublicClimberIdentity.policyVersion`. */
export const IDENTITY_POLICY_VERSION = 1;

/** Mirrors `PublicClimberIdentity.anonymousDisplayName`. */
export const ANONYMOUS_DISPLAY_NAME = "Anonymous Climber";

/** Mirrors `PublicClimberIdentity.tokenAlphabet`. */
const TOKEN_ALPHABET = Array.from("2346789AEFJMNQRT");

/** Identity states `LeaderboardRepository.parseStat` will accept. */
const RENDERABLE_IDENTITY_STATES = new Set([
  "published",
  "pending_public_profile",
  "deleted",
]);

/** Mirrors `ProfileAchievementType`'s raw values. */
export const ACHIEVEMENT_TYPES = new Set([
  "first_ascent",
  "weekly_top_1",
  "weekly_top_3",
  "weekly_top_10",
  "weekly_top_100",
  "monthly_top_1",
  "monthly_top_3",
  "monthly_top_10",
  "monthly_top_100",
  "yearly_top_1",
  "yearly_top_3",
  "yearly_top_10",
  "yearly_top_100",
]);

/** Mirrors `WorkoutSource`'s raw values, including the two only old rows carry. */
export const WORKOUT_SOURCES = new Set([
  "manual",
  "apple_health",
  "garmin",
  "fitbit",
  "hevy",
  "headphone_motion",
]);

/** Mirrors `LeaderboardMetric.sortField`. */
export const LEADERBOARD_METRIC_SORT_FIELDS = Object.freeze({
  climb: "totalSteps",
  workouts: "totalWorkouts",
  duration: "totalDuration",
  pace: "stepsPerMinute",
});

/** Mirrors `LeaderboardTimeFrame`'s raw values. */
export const LEADERBOARD_TIME_FRAMES = Object.freeze([
  "daily",
  "weekly",
  "monthly",
  "yearly",
  "all_time",
]);

/** Mirrors `LiveReplayLeaderboardContextType.collapsesRepeatFinishers`. */
const CONTEXT_TYPES_COLLAPSING_REPEAT_FINISHERS = new Set([
  "live_climb",
  "routine_template",
]);

/**
 * Builds the document key the app reads a replay board from.
 *
 * Mirrors `LiveReplayLeaderboardContext.contextKey` including its sanitizer, so
 * a check can never read a board at a path the app would not have built.
 * @param {string} type Context type raw value, e.g. `live_climb`.
 * @param {string} id Context id, e.g. a climb id.
 * @return {string} Document id under `live_replay_leaderboards`.
 */
export function replayContextKey(type, id) {
  const sanitized = Array.from(String(id))
    .map((character) => (/[\p{L}\p{N}_-]/u.test(character) ? character : "_"))
    .join("");
  return `${type}__${sanitized}`;
}

/**
 * Whether a context's frozen standing collapses a climber's repeat runs.
 *
 * Deliberately NOT the live-race filter. Every context type now carries
 * `isBestForUser` and every live-race read filters on it, so a race panel over
 * any board shows one row per climber. This predicate decides only what the
 * server's frozen standing counts and which population a board's field-size
 * line names.
 * @param {string} type Context type raw value.
 * @return {boolean} Whether the frozen standing counts climbers.
 */
export function collapsesRepeatFinishers(type) {
  return CONTEXT_TYPES_COLLAPSING_REPEAT_FINISHERS.has(type);
}

/**
 * The handle the app invents for a climber who publishes no name.
 *
 * Mirrors `PublicClimberIdentity.systemHandle`. Reproduced rather than
 * approximated because "Climber 6J84R7" is what a row with no display name
 * actually renders as, and a check that reported the stored empty string would
 * describe a blank the product never shows.
 * @param {?string} userId Account id.
 * @return {string} The rendered handle.
 */
export function systemHandle(userId) {
  const normalized = normalizedUserId(userId);
  if (normalized === null) {
    return ANONYMOUS_DISPLAY_NAME;
  }

  const digest = createHash("sha256").update(normalized, "utf8").digest();
  const prefix = digest.readUInt32BE(0);
  const token = [];
  for (let shift = 20; shift >= 0; shift -= 4) {
    const character = TOKEN_ALPHABET[(prefix >>> shift) & 0x0f];
    token.push(
      token.at(-1) === character ? nextTokenCharacter(character) : character
    );
  }

  return `Climber ${token.join("")}`;
}

/**
 * Resolves one stored identity into what the app puts on screen.
 *
 * Mirrors `PublicClimberIdentity.resolve` for the cross-user path every public
 * surface takes. The current-user branch is deliberately absent: no check here
 * runs as a signed-in climber, and pretending otherwise would hide exactly the
 * blank the account's own row shows to everybody else.
 * @param {object} options Stored identity fields.
 * @return {{displayName: string, photoURL: ?string, usesGenericAvatar: boolean}} Rendered identity.
 */
export function resolvedIdentity({
  userId = null,
  displayName = null,
  photoURL = null,
  avatarToken = null,
  isSynthetic = false,
} = {}) {
  const storedName = stringValue(displayName);
  const storedPhoto = stringValue(photoURL);

  if (typeof displayName === "string" && displayName.trim() === ANONYMOUS_DISPLAY_NAME) {
    return {
      displayName: ANONYMOUS_DISPLAY_NAME,
      photoURL: null,
      usesGenericAvatar: true,
    };
  }

  if (isSynthetic) {
    return {
      displayName: storedName ?? systemHandle(userId),
      photoURL: storedPhoto,
      usesGenericAvatar: storedPhoto === null && stringValue(avatarToken) === null,
    };
  }

  return {
    displayName: storedName ?? systemHandle(userId),
    photoURL: storedPhoto,
    usesGenericAvatar: storedPhoto === null,
  };
}

/**
 * Mirrors `isTrustedSyntheticRecord` in the replay repository.
 * @param {object} data Stored entry fields.
 * @return {boolean} Whether the row renders as a seeded climber.
 */
export function isTrustedSyntheticRecord(data) {
  return data?.isSynthetic === true || data?.source === "synthetic";
}

/**
 * Renders one `leaderboard_stats` document the way the app would, or explains
 * why the app drops it.
 *
 * Mirrors `LeaderboardRepository.parseStat` and the caller's period guard. Every
 * rejection carries a reason, because "the board has 60 documents and shows
 * nothing" is only actionable once the guard that ate them is named.
 * @param {object} data Stored document fields.
 * @param {object} options Query context.
 * @param {number} options.periodStartAtMs The period the board is showing.
 * @return {{renders: boolean, reason: ?string, row: ?object}} What the app does with it.
 */
export function renderedLeaderboardRow(data, {periodStartAtMs}) {
  const userId = stringValue(data?.userId);
  if (userId === null) {
    return dropped("carries no userId");
  }

  const policyVersion = numberValue(data?.identityPolicyVersion);
  if (policyVersion !== IDENTITY_POLICY_VERSION) {
    return dropped(
      `carries identityPolicyVersion ${JSON.stringify(data?.identityPolicyVersion)}, ` +
      `and the app renders only version ${IDENTITY_POLICY_VERSION}`
    );
  }

  const identityState = stringValue(data?.identityState);
  if (identityState === null || !RENDERABLE_IDENTITY_STATES.has(identityState)) {
    return dropped(`carries identityState ${JSON.stringify(data?.identityState)}`);
  }

  if (stringValue(data?.timeFrame) === null || stringValue(data?.periodKey) === null) {
    return dropped("is missing timeFrame or periodKey");
  }

  const periodStartAt = millisecondsValue(data?.periodStartAt);
  if (periodStartAt === null) {
    return dropped("is missing periodStartAt");
  }
  if (periodStartAt !== periodStartAtMs) {
    return dropped("belongs to a different period than the board being shown");
  }

  if (millisecondsValue(data?.lastUpdated) === null) {
    return dropped("is missing lastUpdated");
  }

  if (identityState === "published" && millisecondsValue(data?.identityChangedAt) === null) {
    return dropped(
      "claims a published identity with no identityChangedAt, which the app " +
      "reads as an unfinished identity write"
    );
  }

  const totals = {
    totalSteps: numberValue(data?.totalSteps) ?? 0,
    totalFloors: numberValue(data?.totalFloors) ?? 0,
    totalWorkouts: numberValue(data?.totalWorkouts) ?? 0,
    totalDuration: numberValue(data?.totalDuration) ?? 0,
  };
  if (Object.values(totals).every((value) => !(value > 0))) {
    return dropped("has nothing but zeroes to rank, so the app treats it as no standing");
  }

  const identity = identityState === "published" ?
    resolvedIdentity({
      userId,
      displayName: stringValue(data?.displayName),
      photoURL: stringValue(data?.photoURL),
    }) :
    resolvedIdentity({userId, displayName: ANONYMOUS_DISPLAY_NAME});

  return {
    renders: true,
    reason: null,
    row: {
      userId,
      displayName: identity.displayName,
      photoURL: identity.photoURL,
      usesGenericAvatar: identity.usesGenericAvatar,
      stepsPerMinute: numberValue(data?.stepsPerMinute) ?? 0,
      ...totals,
    },
  };
}

/**
 * Renders one replay completion row the way the static completion board would.
 *
 * Mirrors `parseCompletionRow` in `FirestoreLiveReplayLeaderboardRepository`,
 * including the `completionDurationSeconds` guard that silently removes a row
 * from a board whose count still includes it.
 * @param {string} id Entry document id.
 * @param {object} data Stored entry fields.
 * @return {{renders: boolean, reason: ?string, row: ?object}} What the app does with it.
 */
export function renderedCompletionRow(id, data) {
  const duration = numberValue(data?.completionDurationSeconds);
  if (duration === null) {
    return dropped("carries no completionDurationSeconds, so the board drops it");
  }

  const isSynthetic = isTrustedSyntheticRecord(data);
  const identity = resolvedIdentity({
    userId: stringValue(data?.userId),
    displayName: stringValue(data?.displayName),
    photoURL: httpPhotoURL(data?.photoURL),
    avatarToken: stringValue(data?.avatarToken),
    isSynthetic,
  });

  return {
    renders: true,
    reason: null,
    row: {
      id,
      userId: stringValue(data?.userId),
      displayName: identity.displayName,
      photoURL: identity.photoURL,
      usesGenericAvatar: identity.usesGenericAvatar,
      completionDurationSeconds: duration,
      finalSteps: numberValue(data?.finalSteps) ?? numberValue(data?.stepsAtBucket) ?? 0,
      isSynthetic,
    },
  };
}

/**
 * Renders one achievement the way the profile would.
 *
 * Mirrors `ProfileRepository.parseAchievement`. An unrecognized `type` is the
 * interesting rejection: it is what a server that awards a band the shipped app
 * does not know about produces, and the profile simply omits the row.
 * @param {string} id Achievement document id.
 * @param {object} data Stored fields.
 * @return {{renders: boolean, reason: ?string, row: ?object}} What the app does with it.
 */
export function renderedAchievement(id, data) {
  const type = stringValue(data?.type);
  if (type === null || !ACHIEVEMENT_TYPES.has(type)) {
    return dropped(`carries type ${JSON.stringify(data?.type)}, which this build cannot render`);
  }

  const earnedAt = millisecondsValue(data?.earnedAt);
  if (earnedAt === null) {
    return dropped("carries no earnedAt, so the profile drops it");
  }

  return {
    renders: true,
    reason: null,
    row: {
      id,
      type,
      earnedAtMs: earnedAt,
      climbId: stringValue(data?.climbId),
      rank: numberValue(data?.rank),
    },
  };
}

/**
 * Renders one profile workout summary the way the profile would.
 *
 * Mirrors `ProfileRepository.parseWorkoutSummary`, and note the collection: the
 * profile renders `users/{uid}/profile_workouts`, not `users/{uid}/workouts`. A
 * seed that fills the second and not the first leaves a full account with an
 * empty profile.
 * @param {string} id Summary document id.
 * @param {object} data Stored fields.
 * @return {{renders: boolean, reason: ?string, row: ?object}} What the app does with it.
 */
export function renderedProfileWorkout(id, data) {
  if (stringValue(data?.name) === null) {
    return dropped("carries no name");
  }

  const startedAt = millisecondsValue(data?.startedAt);
  if (startedAt === null) {
    return dropped("carries no startedAt");
  }

  const source = stringValue(data?.source);
  if (source === null || !WORKOUT_SOURCES.has(source)) {
    return dropped(`carries source ${JSON.stringify(data?.source)}, which this build cannot render`);
  }

  return {
    renders: true,
    reason: null,
    row: {
      id,
      startedAtMs: startedAt,
      steps: numberValue(data?.steps) ?? 0,
      climbId: stringValue(data?.climbId),
    },
  };
}

/**
 * Renders one routine template the way the Routines browse surfaces would.
 *
 * Mirrors `FirestoreRoutineTemplateRepository.parseTemplate`, `parseInterval`
 * and `isSupported`. `minAppVersion` is the guard worth stating: a template
 * published for a version the capture build predates is invisible on the device
 * doing the filming while being perfectly present in Firestore.
 * @param {string} id Template document id.
 * @param {object} data Stored fields.
 * @param {object} options Client context.
 * @param {string} options.appVersion The capture build's marketing version.
 * @return {{renders: boolean, reason: ?string, row: ?object}} What the app does with it.
 */
export function renderedRoutineTemplate(id, data, {appVersion}) {
  if (stringValue(data?.status) !== "published") {
    return dropped(`carries status ${JSON.stringify(data?.status)}, so the app never reads it`);
  }

  const name = stringValue(data?.name);
  if (name === null) {
    return dropped("carries no name");
  }

  const intervalRows = Array.isArray(data?.intervals) ? data.intervals : [];
  if (intervalRows.length === 0) {
    return dropped("carries no intervals");
  }

  const intervals = intervalRows.filter((row) => (numberValue(
    row?.durationSeconds ?? row?.duration_seconds ?? row?.duration
  ) ?? 0) > 0);
  if (intervals.length === 0) {
    return dropped("carries no interval with a positive duration");
  }

  const minAppVersion = stringValue(data?.minAppVersion) ?? stringValue(data?.min_app_version);
  if (minAppVersion !== null && compareVersions(appVersion, minAppVersion) < 0) {
    return dropped(
      `requires app version ${minAppVersion} and the capture build is ${appVersion}, ` +
      "so it is invisible on the device doing the filming"
    );
  }

  return {
    renders: true,
    reason: null,
    row: {
      id: stringValue(data?.templateId) ?? id,
      name,
      intervalCount: intervals.length,
    },
  };
}

/**
 * Renders the account's own public profile the way another climber sees it.
 *
 * Mirrors `ProfileRepository.parseIdentity`, whose two guards are the ones that
 * make an account with a perfectly good name render as `Climber 6J84R7` on
 * everybody else's screen.
 * @param {string} userId Account id.
 * @param {?object} data Stored `public_profile/current` fields.
 * @return {{renders: boolean, reason: ?string, row: ?object}} What the app does with it.
 */
export function renderedPublicProfile(userId, data) {
  if (data === null || data === undefined) {
    return dropped("has no public profile document at all");
  }

  if (numberValue(data.identityPolicyVersion) !== IDENTITY_POLICY_VERSION) {
    return dropped(
      `publishes identityPolicyVersion ${JSON.stringify(data.identityPolicyVersion)}, ` +
      `and the app renders only version ${IDENTITY_POLICY_VERSION}`
    );
  }

  if (millisecondsValue(data.identityChangedAt) === null) {
    return dropped("publishes no identityChangedAt, so the app drops the whole identity");
  }

  const identity = resolvedIdentity({
    userId: stringValue(data.userId) ?? userId,
    displayName: stringValue(data.displayName),
    photoURL: stringValue(data.photoURL),
  });

  return {renders: true, reason: null, row: identity};
}

/**
 * Whether a rendered photo URL will actually load an image.
 *
 * A row can carry a URL, render a non-generic avatar, and still show nothing:
 * the identity projection only republishes a Firebase Storage download URL, so
 * anything else is a photo the server would have dropped on its way to a public
 * surface.
 * @param {?string} photoURL Rendered photo URL.
 * @return {boolean} Whether the avatar is a picture rather than initials.
 */
export function rendersPhotoAvatar(photoURL) {
  return typeof photoURL === "string" &&
    photoURL.length > 0 &&
    isAllowedPublicPhotoURL(photoURL);
}

/**
 * Compares two dotted version strings the way the routine repository does.
 * @param {string} lhs Left version.
 * @param {string} rhs Right version.
 * @return {number} Negative, zero or positive.
 */
export function compareVersions(lhs, rhs) {
  const left = String(lhs).split(".").map((part) => Number.parseInt(part, 10) || 0);
  const right = String(rhs).split(".").map((part) => Number.parseInt(part, 10) || 0);
  const count = Math.max(left.length, right.length);

  for (let index = 0; index < count; index += 1) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) {
      return difference < 0 ? -1 : 1;
    }
  }
  return 0;
}

/**
 * Reads a Firestore timestamp, a Date, or a millisecond number as milliseconds.
 * @param {unknown} value Stored value.
 * @return {?number} Epoch milliseconds, or null.
 */
export function millisecondsValue(value) {
  if (value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

/**
 * @param {unknown} value Stored value.
 * @return {?number} A finite number, or null.
 */
export function numberValue(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * @param {unknown} value Stored value.
 * @return {?string} A non-empty trimmed string, or null.
 */
export function stringValue(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function httpPhotoURL(value) {
  const trimmed = stringValue(value);
  if (trimmed === null) {
    return null;
  }
  return /^https?:\/\//iu.test(trimmed) ? trimmed : null;
}

function normalizedUserId(userId) {
  if (typeof userId !== "string") {
    return null;
  }
  const trimmed = userId.trim();
  if (trimmed.length === 0 || Buffer.byteLength(trimmed, "utf8") > 128) {
    return null;
  }
  return CONTROL_CHARACTERS.test(trimmed) ? null : trimmed;
}

/** Mirrors `CharacterSet.controlCharacters`, which is C0 plus DEL and C1. */
const CONTROL_CHARACTERS = /[\u0000-\u001F\u007F-\u009F]/u;

function nextTokenCharacter(character) {
  const index = TOKEN_ALPHABET.indexOf(character);
  return index === -1 ? character : TOKEN_ALPHABET[(index + 1) % TOKEN_ALPHABET.length];
}

function dropped(reason) {
  return {renders: false, reason, row: null};
}
