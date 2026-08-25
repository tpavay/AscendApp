/**
 * How one seed pack's avatar images are divided between the synthetic field and
 * the account being seeded.
 *
 * The account appears on the same leaderboards as the competitors, so it cannot
 * share a face with one of them - a repeated portrait on one board reads as the
 * same climber posting twice, which is the rule seeded names already follow.
 *
 * The division is by position and lives here because two scripts have to agree
 * on it: `seed-live-replay-leaderboards.mjs` dresses the competitors, and
 * `seed-demo-user.mjs` dresses the account, and neither can see the other's run.
 */

/**
 * Storage prefix holding one seed pack's avatar objects.
 * @param {string} seedPackPath Sanitized seed pack id.
 * @return {string} Object prefix, with a trailing slash.
 */
export function seedAvatarPrefix(seedPackPath) {
  return `live-replay-avatars/${seedPackPath}/`;
}

/**
 * The avatars the synthetic competitors may use.
 *
 * Everything except the last, which the account takes. Ordered, because a
 * climber's face is resolved by their position in the name list and has to stay
 * the same across re-seeds.
 * @param {Array} avatars Avatar objects or URLs, ordered by object name.
 * @return {Array} Avatars available to synthetic climbers.
 */
export function competitorAvatars(avatars) {
  return avatars.slice(0, Math.max(avatars.length - 1, 0));
}

/**
 * The avatar reserved for the account being seeded, or null when there is none.
 * @param {Array} avatars Avatar objects or URLs, ordered by object name.
 * @return {*} The reserved avatar, or null.
 */
export function reservedAccountAvatar(avatars) {
  return avatars.length > 0 ? avatars[avatars.length - 1] : null;
}
