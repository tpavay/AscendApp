/**
 * What "content-ready" means, as numbers rather than taste.
 *
 * Capturing App Store screenshots, video and marketing from staging only works
 * if the environment looks like somebody has genuinely been using Ascend for
 * months. That is a judgement call until it is written down, and a judgement
 * call cannot be re-run. So the definition lives here, the seed asserts it, and
 * `seed-content-ready.mjs verify` re-checks it at any time without writing.
 *
 * `docs/staging-content-capture.md` explains why each number is what it is.
 * Changing one is a deliberate change to what the captured content shows.
 */

export const CONTENT_READY_THRESHOLDS = Object.freeze({
  /** Landmark climbs the account has finished. Six fills a Collection grid. */
  minimumClimbsCompleted: 6,

  /**
   * Sessions behind those climbs. Best Efforts ranks a history, and a record
   * book with six rows in it reads as a first week rather than a record.
   */
  minimumWorkouts: 10,

  /** First Ascents the account holds. The retention hook needs one on screen. */
  minimumFirstAscentsHeld: 1,

  /**
   * Days since the newest session. Anything older reads as an abandoned account
   * in a screenshot, and relative dates ("2 days ago") are what give it away.
   */
  maximumDaysSinceNewestClimb: 2,

  /**
   * Days from the oldest session to today. Progress trends and streaks need a
   * span behind them, and six weeks is the shortest one that renders as months
   * of use rather than a burst.
   */
  minimumHistoryDepthDays: 40,

  /** Global standing rows for the account, so a rank exists to point a camera at. */
  minimumAccountStandingRows: 3,

  /**
   * Climbers on a board before it counts as contested. Below this a leaderboard
   * screenshot shows a rank nobody had to earn.
   */
  minimumCompetitorsPerContestedBoard: 20,

  /**
   * Contested boards, so the globe looks populated wherever it is spun. The
   * live replay pack seeds fourteen boards past that competitor bar; the
   * headroom is deliberate, so trimming one climb from the pack does not fail a
   * capture session.
   */
  minimumContestedBoards: 12,

  /**
   * Boards left with an open First Ascent.
   *
   * The server only lets a finisher claim a slot on a board with no completions,
   * so every climb the seed fills with competitors spends its First Ascent
   * permanently. That rule is correct; what is not is spending the whole
   * catalogue on it. Staging offered four claimable climbs out of thirty-two,
   * which is not enough to demonstrate the hook, let alone film it twice. The
   * seed now leaves every raceable climb it does not contest genuinely open, so
   * the floor is high on purpose: falling under it means seeding has started
   * eating the feature again.
   */
  minimumOpenFirstAscentBoards: 20,

  /** Routine templates, so the routines surfaces are not empty. */
  minimumRoutineTemplates: 2,
});

/**
 * Display names that belong to tooling rather than to a climber.
 *
 * These reach a public leaderboard, so they end up in a screenshot. Matched
 * case-insensitively against the account's published name.
 */
export const PLACEHOLDER_DISPLAY_NAMES = Object.freeze([
  "content capture",
  "product tester",
  "qa tester",
  "test user",
  "change me",
  "climber",
]);

/**
 * Reports why a published display name is not fit to be photographed.
 *
 * A leaderboard row is the product's shop window, and the name on it has to read
 * as a person. Digits are the giveaway for a machine-shaped name - an
 * email-derived "Qa G4 Noname", or the "Climber 061" placeholder the seed used
 * past the end of its name list.
 * @param {unknown} displayName Published display name.
 * @return {string | null} Failure message, or null when the name is fine.
 */
export function unphotographableDisplayName(displayName) {
  if (typeof displayName !== "string" || displayName.trim().length === 0) {
    return "the account publishes no display name, so its leaderboard row is blank";
  }

  const name = displayName.trim();
  if (/\d/u.test(name)) {
    return `the account publishes "${name}", and a digit in a name reads as ` +
      "tooling rather than a climber";
  }

  if (PLACEHOLDER_DISPLAY_NAMES.includes(name.toLowerCase())) {
    return `the account publishes "${name}", which is a placeholder, not a climber`;
  }

  return null;
}

/**
 * Judges an observed environment against the contract.
 *
 * Returns every failure rather than the first, because the fix for a
 * content-ready run that fell short is usually "look at all of it and decide",
 * not "fix one number and run again".
 * @param {object} observed Measured state from `observeContentState`.
 * @return {string[]} Human-readable failures, empty when content-ready.
 */
export function contentReadinessFailures(observed) {
  const failures = [];
  const t = CONTENT_READY_THRESHOLDS;

  if (!observed.hasPublicProfile) {
    failures.push("the account has no public profile, so no other climber can see it");
  }
  if (!observed.hasProfileStats) {
    failures.push("the account has no profile stats, so every profile stat renders empty");
  }

  atLeast(failures, observed.climbsCompleted, t.minimumClimbsCompleted,
    "landmark climbs completed");
  atLeast(failures, observed.workoutCount, t.minimumWorkouts,
    "sessions in the account's history");
  atLeast(failures, observed.firstAscentsHeld, t.minimumFirstAscentsHeld,
    "First Ascents held by the account");
  atLeast(failures, observed.accountStandingRows, t.minimumAccountStandingRows,
    "global standing rows for the account");
  atLeast(failures, observed.contestedClimbBoards, t.minimumContestedBoards,
    `climb boards with at least ${t.minimumCompetitorsPerContestedBoard} climbers`);
  atLeast(failures, observed.openFirstAscentBoards, t.minimumOpenFirstAscentBoards,
    "climb boards with an open First Ascent");
  atLeast(failures, observed.routineTemplateCount, t.minimumRoutineTemplates,
    "routine templates");

  const nameFailure = unphotographableDisplayName(observed.accountDisplayName);
  if (nameFailure) {
    failures.push(nameFailure);
  }

  // Read back off the rows themselves rather than trusting the seed: the avatar
  // set lives in Storage and the rows only carry URLs into it, so a run that
  // could not resolve the images still writes a complete-looking board of
  // lettered circles.
  if (observed.seededRowsWithoutPhoto > 0) {
    failures.push(
      `${observed.seededRowsWithoutPhoto} of ${observed.seededRowsSampled} ` +
      "seeded leaderboard rows carry no photo, so they render as lettered circles"
    );
  }

  if (observed.seededRowsWithPlaceholderName > 0) {
    failures.push(
      `${observed.seededRowsWithPlaceholderName} seeded leaderboard rows carry a ` +
      "machine-shaped display name"
    );
  }

  if (observed.daysSinceNewestClimb === null) {
    failures.push("the account has no sessions at all");
  } else if (observed.daysSinceNewestClimb > t.maximumDaysSinceNewestClimb) {
    failures.push(
      `newest session is ${observed.daysSinceNewestClimb} days old, ` +
      `which reads as stale on screen (want <= ${t.maximumDaysSinceNewestClimb})`
    );
  }

  if (observed.historyDepthDays !== null) {
    atLeast(failures, observed.historyDepthDays, t.minimumHistoryDepthDays,
      "days of history behind the newest session");
  }

  // A First Ascent means first ever. A board where the account holds it while
  // other climbers already finished says the opposite on the one screen that
  // exists to say it, so the claim is checked against its own board rather than
  // just counted.
  for (const board of observed.firstAscentBoards ?? []) {
    if (board.completedCount !== 1) {
      failures.push(
        `${board.contextKey}: the account holds the First Ascent but the board ` +
        `reports ${board.completedCount} completions, so it reads as first ` +
        "ever beside climbers who finished before it"
      );
    }
  }

  // The seed and the Cloud Function both write these two, and they have to mean
  // the same population or a leaderboard shows a rank out of a denominator its
  // own board contradicts.
  for (const contextKey of observed.incoherentBoards ?? []) {
    failures.push(
      `${contextKey}: completedCount and totalClimbers disagree, so the board ` +
      "ranks against a population it does not have"
    );
  }

  return failures;
}

/**
 * @param {string[]} failures Accumulated failures.
 * @param {number} actual Observed value.
 * @param {number} minimum Required value.
 * @param {string} label What is being counted.
 */
function atLeast(failures, actual, minimum, label) {
  if (!(actual >= minimum)) {
    failures.push(`${actual} ${label}, want at least ${minimum}`);
  }
}
