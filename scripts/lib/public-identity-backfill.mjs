/**
 * Planning logic for the public-identity policy backfill.
 *
 * `leaderboard_stats` rows written before the identity policy landed carry no
 * `identityPolicyVersion`, `identityState`, or `identityChangedAt`, and the
 * client drops every row that is missing them. Those three fields are
 * server-owned: `firestore.rules` forbids a client from adding them to an
 * existing row, and `LeaderboardRepository.upsertStats` only stamps them on
 * create. The one writer that can repair an existing row is the deployed
 * `onPublicProfileIdentityWritten` trigger, which fires on a write to
 * `users/{uid}/public_profile/current` and fans out to every projection.
 *
 * So the repair starts at the source document and nowhere else. This module
 * decides, per user, whether a publishable identity can be derived from what
 * that document already holds - never inventing one it cannot derive.
 *
 * The screening is the shared contract in seed/lib/public-identity-contract.mjs,
 * which mirrors DisplayNamePolicy in Swift, isAllowedDisplayName in
 * functions/src/publicIdentity.ts, and isAllowedDisplayName in firestore.rules.
 * A reconciler that screened a name any looser would publish an identity the
 * live write path would have rejected.
 */

import {
  isAllowedDisplayName,
  isAllowedPublicPhotoURL,
} from "../seed/lib/public-identity-contract.mjs";

export const PUBLIC_IDENTITY_BACKFILL_VERSION = 1;
export const PUBLIC_IDENTITY_POLICY_VERSION = 1;

/**
 * What a plan entry asks the runner to do.
 *
 * `stamp`   - a publishable identity exists; add the missing policy fields.
 * `current` - already carries the current policy; nothing to write.
 * `skip`    - no publishable identity could be derived; leave it alone.
 */
export const BACKFILL_ACTIONS = Object.freeze({
  current: "current",
  skip: "skip",
  stamp: "stamp",
});

/**
 * Decides what one user's public profile mirror needs.
 * @param {object} input Planning input.
 * @param {string} input.userId Firebase Auth uid, from the users/{uid} id.
 * @param {boolean} input.profileExists Whether public_profile/current exists.
 * @param {object | undefined} input.profileData Current mirror fields.
 * @return {{userId: string, action: string, reason: string, warnings: string[]}}
 *   The planned action, why, and any non-blocking caveats to report.
 */
export function planPublicIdentityBackfill({
  userId,
  profileExists,
  profileData,
}) {
  const warnings = [];

  if (!profileExists || profileData === undefined) {
    return skip(
      userId,
      "no users/" + userId + "/public_profile/current to derive an identity " +
      "from. Only the account itself can publish one."
    );
  }

  if (profileData.userId !== userId) {
    return skip(
      userId,
      "public_profile/current has userId " +
      JSON.stringify(profileData.userId ?? null) +
      ", which does not match the document owner."
    );
  }

  const displayName = profileData.displayName;
  if (typeof displayName !== "string" || displayName.trim().length === 0) {
    return skip(userId, "public_profile/current has no display name.");
  }

  if (!isAllowedDisplayName(displayName)) {
    return skip(
      userId,
      "display name " + JSON.stringify(displayName) + " fails the shared " +
      "display-name screening, so the live write path would have rejected it."
    );
  }

  // The mirror's photo is account-authored and rules require the field to be
  // present. Absent, the identity is not in contract and there is no honest
  // value to derive - an empty string would be this script inventing "no photo"
  // on the account's behalf.
  const photoURL = profileData.photoURL;
  if (typeof photoURL !== "string") {
    return skip(
      userId,
      "public_profile/current has no photoURL field, so its identity is not " +
      "in contract. Republish the profile rather than guessing a value."
    );
  }

  // An off-contract photo does not block the name from publishing: the
  // propagation trigger validates the URL itself and projects an empty photo
  // when it fails. Worth saying out loud, not worth withholding the row for.
  if (!isAllowedPublicPhotoURL(photoURL)) {
    warnings.push(
      "photoURL " + JSON.stringify(photoURL) + " is not a Firebase Storage " +
      "download URL, so projections will publish this climber with no photo."
    );
  }

  if (hasCurrentIdentityPolicy(profileData)) {
    return {
      action: BACKFILL_ACTIONS.current,
      reason: "already carries identityPolicyVersion " +
        PUBLIC_IDENTITY_POLICY_VERSION + " and identityChangedAt.",
      userId,
      warnings,
    };
  }

  return {
    action: BACKFILL_ACTIONS.stamp,
    reason: "publishable identity " + JSON.stringify(displayName.trim()) +
      "; " + missingPolicyDescription(profileData) + ".",
    userId,
    warnings,
  };
}

/**
 * Returns whether a mirror already satisfies the current identity policy.
 * @param {object | undefined} profileData Current mirror fields.
 * @return {boolean} Whether both policy fields are present and current.
 */
export function hasCurrentIdentityPolicy(profileData) {
  return numberValue(profileData?.identityPolicyVersion) ===
      PUBLIC_IDENTITY_POLICY_VERSION &&
    profileData?.identityChangedAt !== undefined &&
    profileData?.identityChangedAt !== null;
}

/**
 * Returns every clause of the client's parse contract a leaderboard row fails.
 *
 * This is the JavaScript twin of the guard in LeaderboardRepository.parseStat.
 * A row that fails any clause is fetched, dropped, and never rendered, so the
 * twin has to reproduce all of them - a looser guard reports a green
 * leaderboard the client still empties out.
 * @param {object | undefined} data Leaderboard row fields.
 * @return {string[]} The unmet clauses, empty when the row would parse.
 */
export function rowGuardFailures(data) {
  const failures = [];

  if (typeof data?.userId !== "string") {
    failures.push("userId");
  }
  if (
    numberValue(data?.identityPolicyVersion) !== PUBLIC_IDENTITY_POLICY_VERSION
  ) {
    failures.push("identityPolicyVersion");
  }

  const state = data?.identityState;
  const stateIsKnown = typeof state === "string" &&
    ["published", "pending_public_profile", "deleted"].includes(state);
  if (!stateIsKnown) {
    failures.push("identityState");
  }

  if (typeof data?.timeFrame !== "string") {
    failures.push("timeFrame");
  }
  if (typeof data?.periodKey !== "string") {
    failures.push("periodKey");
  }
  if (!isTimestampValue(data?.periodStartAt)) {
    failures.push("periodStartAt");
  }
  if (!isTimestampValue(data?.lastUpdated)) {
    failures.push("lastUpdated");
  }
  if (state === "published" && !isTimestampValue(data?.identityChangedAt)) {
    failures.push("identityChangedAt");
  }

  const hasEffort = [
    data?.totalWorkouts,
    data?.totalSteps,
    data?.totalFloors,
    data?.totalDuration,
  ].some((value) => (numberValue(value) ?? 0) > 0);
  if (!hasEffort) {
    failures.push("totals are all zero");
  }

  return failures;
}

/**
 * Returns whether a leaderboard row carries everything the client requires.
 * @param {object | undefined} data Leaderboard row fields.
 * @return {boolean} Whether the row would survive parseStat.
 */
export function rowPassesIdentityGuard(data) {
  return rowGuardFailures(data).length === 0;
}

/**
 * Summarizes a plan for the run report.
 * @param {object[]} plans Planned actions.
 * @return {{current: number, skip: number, stamp: number, warnings: number}}
 *   Counts by action, plus how many entries carry a caveat.
 */
export function summarizeBackfillPlan(plans) {
  return {
    current: countAction(plans, BACKFILL_ACTIONS.current),
    skip: countAction(plans, BACKFILL_ACTIONS.skip),
    stamp: countAction(plans, BACKFILL_ACTIONS.stamp),
    warnings: plans.filter((plan) => plan.warnings.length > 0).length,
  };
}

function missingPolicyDescription(profileData) {
  const missing = [];
  if (
    numberValue(profileData?.identityPolicyVersion) !==
    PUBLIC_IDENTITY_POLICY_VERSION
  ) {
    missing.push("identityPolicyVersion");
  }
  if (
    profileData?.identityChangedAt === undefined ||
    profileData?.identityChangedAt === null
  ) {
    missing.push("identityChangedAt");
  }
  return "missing " + missing.join(" and ");
}

function countAction(plans, action) {
  return plans.filter((plan) => plan.action === action).length;
}

function skip(userId, reason) {
  return {
    action: BACKFILL_ACTIONS.skip,
    reason,
    userId,
    warnings: [],
  };
}

// Firestore integers arrive as numbers, but a mirror written by an older tool
// can hold the value as a string; neither should be treated as current unless
// it really is the current version.
function numberValue(value) {
  return typeof value === "number" ? value : null;
}

// The client reads these through timestampValue, which accepts only a Firestore
// Timestamp or a Date. A string or a number is not a timestamp there either.
function isTimestampValue(value) {
  if (value instanceof Date) {
    return true;
  }
  if (value === null || typeof value !== "object") {
    return false;
  }
  return typeof value.toDate === "function" ||
    (typeof value.seconds === "number" && typeof value.nanoseconds === "number");
}
