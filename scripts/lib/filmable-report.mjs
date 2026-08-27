/**
 * Is staging filmable? The judgment, as pure functions.
 *
 * Every check to date answered a question about Firestore: the seed's own
 * summary, `audit-seed-data.mjs`, and hand-run database probes all confirm that
 * documents were written. None of them confirmed that a climber opening the app
 * sees a populated product, which is why "staging is ready" kept turning out to
 * be a claim about a different thing than the screen - empty leaderboards, four
 * rivals instead of a field, and the bottom half of the Empire State Building
 * with nobody in it.
 *
 * So the rule here is that a check may only assert on a number the app itself
 * would produce. `scripts/verify-filmable.mjs` does the reading through the same
 * collections, the same aggregates and the same query shapes the client uses;
 * this module turns those measurements into named pass/fail lines and does not
 * get to see anything else.
 *
 * A read that FAILED is a third status, never a pass and never a fail: a query
 * that errored and a query that found nothing both print nothing, and reporting
 * the first as the second is how a production leaderboard holding 13 entries was
 * once reported as holding none.
 */

import {
  CONTENT_READY_THRESHOLDS,
  unphotographableDisplayName,
} from "../seed/lib/content-ready-contract.mjs";
import {rendersPhotoAvatar} from "./app-render-contract.mjs";

export const STATUS = Object.freeze({
  pass: "PASS",
  fail: "FAIL",
  error: "ERROR",
});

/**
 * What each surface has to measure before it is worth pointing a camera at.
 *
 * The numbers a screenshot already depends on are imported rather than
 * restated - `CONTENT_READY_THRESHOLDS` is the one home for "how contested is
 * contested", and two copies of that number become two different answers. What
 * is new here is the set below, which exists because these surfaces were never
 * measured as surfaces at all.
 */
export const FILMABLE_THRESHOLDS = Object.freeze({
  /** Rows a global leaderboard has to render before it fills a phone screen. */
  minimumRenderedLeaderboardRows: 10,

  /** How many rows deep the podium goes, and so how many faces have to be pictures. */
  podiumDepth: 3,

  /** Achievements on the account's profile, so the shelf is not one badge wide. */
  minimumRenderedAchievements: 3,
});

/**
 * Judges one observed environment, surface by surface.
 *
 * Order is fixed rather than sorted by status, so the same list appears in the
 * same order after every seed and the captain reads it by position instead of
 * hunting.
 * @param {object} observed Measurements from `verify-filmable.mjs`.
 * @return {object[]} One result per named check.
 */
export function filmableChecks(observed) {
  return [
    climbCatalogCheck(observed),
    accountProfileCheck(observed),
    accountHistoryCheck(observed),
    accountAchievementsCheck(observed),
    accountFirstAscentCheck(observed),
    leaderboardRowsCheck(observed),
    leaderboardNamesCheck(observed),
    leaderboardAvatarsCheck(observed),
    climbCompletedCountCheck(observed),
    climbCompletionBoardCheck(observed),
    liveClimbFieldCheck(observed),
    openFirstAscentCheck(observed),
    routineTemplateCheck(observed),
  ];
}

/**
 * Renders the judged checks for a human.
 *
 * One line per check with the measured number and the expectation beside it,
 * then the specifics indented under any check that did not pass, because
 * "FAILED" on its own is what made the captain need somebody to interpret the
 * output for him.
 * @param {object[]} checks Judged checks.
 * @param {object} context Where the reads were pointed.
 * @return {{text: string, ok: boolean, failed: object[], errored: object[]}} Rendered report.
 */
export function renderFilmableReport(checks, context = {}) {
  const lines = [];
  const {projectId, environment, account, elapsedSeconds} = context;

  lines.push("");
  lines.push(`Filmable check  ${projectId ?? "?"} (${environment ?? "?"})  account ${account ?? "?"}`);
  lines.push("Every number below is read the way the app reads it.");
  lines.push("");

  for (const check of checks) {
    lines.push(`${check.status.padEnd(5)} ${check.name}`);
    lines.push(`      ${check.measured}`);
    lines.push(`      want: ${check.expectation}`);
    for (const detail of check.detail ?? []) {
      for (const [index, line] of String(detail).split("\n").entries()) {
        lines.push(`      ${index === 0 ? "· " : "  "}${line}`);
      }
    }
    lines.push("");
  }

  const failed = checks.filter((check) => check.status === STATUS.fail);
  const errored = checks.filter((check) => check.status === STATUS.error);
  const ok = failed.length === 0 && errored.length === 0;

  if (elapsedSeconds !== undefined) {
    lines.push(`Read ${checks.length} surfaces in ${elapsedSeconds.toFixed(1)}s.`);
  }

  if (errored.length > 0) {
    lines.push(
      `${errored.length} check${errored.length === 1 ? "" : "s"} could not be read: ` +
      errored.map((check) => check.name).join(", ") + "."
    );
    lines.push(
      "A read that failed says nothing about what is there. This is not a pass " +
      "and it is not an empty result - fix the read and run again."
    );
  }

  if (failed.length > 0) {
    lines.push(
      `${failed.length} of ${checks.length} surfaces would not film: ` +
      failed.map((check) => check.name).join(", ") + "."
    );
  }

  lines.push(ok ?
    "Staging is filmable. Every surface above renders what it claims to hold." :
    "Staging is NOT filmable."
  );

  return {text: lines.join("\n"), ok, failed, errored};
}

/**
 * Whether the globe would be drawn from this environment's own catalog.
 *
 * `HostedClimbCatalogRepository` fetches the manifest and catalog from
 * `https://<projectId>.web.app` and only falls back to the bundled `climbs.json`
 * when it has neither a cache nor an answer. A device on the bootstrap catalog
 * is looking at a different climb list than the boards below were measured
 * against, so grading the rest without saying so would be grading two
 * environments at once.
 * @param {object} observed Measurements.
 * @return {object} The judged check.
 */
function climbCatalogCheck(observed) {
  const catalog = observed.catalog ?? {};
  const climbs = catalog.climbs ?? [];
  const raceable = climbs.filter((climb) => climb.releaseState === "available");

  if (catalog.source !== "hosted") {
    return {
      id: "catalog",
      name: "Globe · the climb catalog the device loads",
      status: STATUS.error,
      measured: "the hosted catalog did not answer, so the bundled bootstrap list was used",
      expectation: "the manifest and catalog this project hosts",
      detail: [
        `${catalog.url}: ${catalog.failure ?? "no answer"}`,
        "A device with no cached catalog falls back to the same bootstrap list, " +
        "so this is also what a fresh install would see - deploy hosting before " +
        "trusting anything below.",
      ],
    };
  }

  const detail = [];
  const featured = catalog.featuredClimbId;
  if (featured === null || featured === undefined) {
    detail.push("the manifest names no featuredClimbId, so the globe opens on nothing in particular");
  } else if (!raceable.some((climb) => climb.id === featured)) {
    detail.push(
      `the manifest features "${featured}", which is not an available climb in ` +
      "the catalog it points at, so the globe features a climb nobody can race"
    );
  }

  return {
    id: "catalog",
    name: "Globe · the climb catalog the device loads",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `catalog v${catalog.catalogVersion} holds ${raceable.length} raceable ` +
      `climbs of ${climbs.length}`,
    expectation: "a hosted catalog whose featured climb is raceable",
    detail,
  };
}

function accountProfileCheck(observed) {
  const profile = observed.account?.publicProfile;
  const failure = readFailure(observed, "account.publicProfile");
  if (failure) {
    return errored("account.profile", "Profile · the account's own identity", failure);
  }

  if (!profile?.renders) {
    return {
      id: "account.profile",
      name: "Profile · the account's own identity",
      status: STATUS.fail,
      measured: "the account's public profile does not render",
      expectation: "a name and a face every other climber can see",
      detail: [
        `the mirror at users/${observed.accountUid}/public_profile/current ` +
        `${profile?.reason ?? "could not be judged"}`,
      ],
    };
  }

  const detail = [];
  const nameFailure = unphotographableDisplayName(profile.row.displayName);
  if (nameFailure) {
    detail.push(nameFailure);
  }
  if (!rendersPhotoAvatar(profile.row.photoURL)) {
    detail.push(
      profile.row.photoURL === null ?
        "the account publishes no photo, so the row every screenshot centers on " +
          "renders as a lettered circle" :
        "the account's photo is not a Firebase Storage download URL, so the " +
          "identity projection drops it and the row renders as a lettered circle"
    );
  }

  return {
    id: "account.profile",
    name: "Profile · the account's own identity",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `renders as "${profile.row.displayName}"` +
      (rendersPhotoAvatar(profile.row.photoURL) ? " with a photo" : " with no photo"),
    expectation: "a climber's name and a photo",
    detail,
  };
}

function accountHistoryCheck(observed) {
  const failure = readFailure(observed, "account.profileWorkouts") ??
    readFailure(observed, "account.profileStats");
  if (failure) {
    return errored("account.history", "Profile · climbs and sessions", failure);
  }

  const workouts = observed.account?.profileWorkouts ?? {rendered: [], dropped: []};
  const stats = observed.account?.profileStats ?? {exists: false};
  const detail = [];
  const rendered = workouts.rendered.length;
  const climbs = stats.totalClimbsCompleted ?? 0;

  if (!stats.exists) {
    detail.push("the account has no profile_stats/current, so every profile stat renders as zero");
  }
  if (climbs < CONTENT_READY_THRESHOLDS.minimumClimbsCompleted) {
    detail.push(
      `profile stats report ${climbs} landmark climbs completed, and the ` +
      `Collection grid wants ${CONTENT_READY_THRESHOLDS.minimumClimbsCompleted}`
    );
  }
  if (rendered < CONTENT_READY_THRESHOLDS.minimumWorkouts) {
    detail.push(
      `the profile renders ${rendered} of ${workouts.read} documents in ` +
      `users/${observed.accountUid}/profile_workouts`
    );
  }
  if (workouts.dropped.length > 0) {
    detail.push(dropReasons(
      `${workouts.dropped.length} profile session${workouts.dropped.length === 1 ? "" : "s"} ` +
      "will not render",
      workouts.dropped
    ));
  }

  const newestDays = workouts.daysSinceNewest;
  if (newestDays === null || newestDays === undefined) {
    if (rendered > 0) {
      detail.push("no rendered session carries a startedAt, so the profile shows no dates");
    }
  } else if (newestDays > CONTENT_READY_THRESHOLDS.maximumDaysSinceNewestClimb) {
    detail.push(
      `the newest session the profile renders is ${newestDays} days old, which reads ` +
      `as an abandoned account (want <= ${CONTENT_READY_THRESHOLDS.maximumDaysSinceNewestClimb})`
    );
  }

  const depth = workouts.historyDepthDays;
  if (typeof depth === "number" && depth < CONTENT_READY_THRESHOLDS.minimumHistoryDepthDays) {
    detail.push(
      `the rendered history spans ${depth} days, and trends want ` +
      `${CONTENT_READY_THRESHOLDS.minimumHistoryDepthDays}`
    );
  }

  return {
    id: "account.history",
    name: "Profile · climbs and sessions",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${climbs} climbs completed, ${rendered} of ${workouts.read} sessions render`,
    expectation: `${CONTENT_READY_THRESHOLDS.minimumClimbsCompleted} climbs and ` +
      `${CONTENT_READY_THRESHOLDS.minimumWorkouts} rendered sessions`,
    detail,
  };
}

function accountAchievementsCheck(observed) {
  const failure = readFailure(observed, "account.achievements");
  if (failure) {
    return errored("account.achievements", "Profile · achievements", failure);
  }

  const achievements = observed.account?.achievements ?? {read: 0, rendered: [], dropped: []};
  const rendered = achievements.rendered.length;
  const detail = [];

  if (rendered < FILMABLE_THRESHOLDS.minimumRenderedAchievements) {
    detail.push(
      `the profile renders ${rendered} of ${achievements.read} documents in ` +
      `users/${observed.accountUid}/achievements`
    );
  }
  if (achievements.dropped.length > 0) {
    detail.push(dropReasons(
      `${achievements.dropped.length} achievement${achievements.dropped.length === 1 ? "" : "s"} ` +
      "will not render",
      achievements.dropped
    ));
  }

  return {
    id: "account.achievements",
    name: "Profile · achievements",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${rendered} of ${achievements.read} achievements render`,
    expectation: `at least ${FILMABLE_THRESHOLDS.minimumRenderedAchievements}`,
    detail,
  };
}

function accountFirstAscentCheck(observed) {
  const failure = readFailure(observed, "boards");
  if (failure) {
    return errored("account.firstAscent", "Profile · First Ascents", failure);
  }

  const held = (observed.boards ?? []).filter((board) => board.heldByAccount);
  const detail = [];

  for (const board of held) {
    if (board.accountFinisherOrder === null || board.accountFinisherOrder === undefined) {
      detail.push(
        `${board.climbId}: the account holds the First Ascent but has no finisher ` +
        "document on that board, so nothing records that it finished at all"
      );
    } else if (board.accountFinisherOrder !== 1) {
      detail.push(
        `${board.climbId}: the account holds the First Ascent but finished ` +
        `#${board.accountFinisherOrder}, so it reads as first ever beside climbers ` +
        "who finished before it"
      );
    }
  }

  if (held.length < CONTENT_READY_THRESHOLDS.minimumFirstAscentsHeld) {
    detail.unshift(
      "no board names the account as its First Ascent holder, so the retention " +
      "hook has nothing on screen"
    );
  }

  return {
    id: "account.firstAscent",
    name: "Profile · First Ascents",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${held.length} board${held.length === 1 ? "" : "s"} name the account as First Ascent holder`,
    expectation: `at least ${CONTENT_READY_THRESHOLDS.minimumFirstAscentsHeld}, each finished first`,
    detail,
  };
}

function leaderboardRowsCheck(observed) {
  const boards = observed.leaderboards ?? [];
  const broken = boards.filter((board) => board.failure);
  if (broken.length > 0) {
    return {
      id: "leaderboards.rows",
      name: "Leaderboards · rows on every board",
      status: STATUS.error,
      measured: `${broken.length} of ${boards.length} board queries did not complete`,
      expectation: "every board answers",
      detail: broken.map((board) =>
        `${board.timeFrame}/${board.metric}: ${board.failure}`),
    };
  }

  const thin = boards.filter((board) =>
    board.rendered.length < FILMABLE_THRESHOLDS.minimumRenderedLeaderboardRows);
  const detail = thin.map((board) => {
    const lines = [
      `${board.timeFrame}/${board.metric} (period ${board.periodKey}): ` +
      `${board.rendered.length} of ${board.read} documents render`,
    ];

    if (board.read === 0) {
      const elsewhere = board.periodsWithStandings ?? [];
      lines.push(
        elsewhere.length === 0 ?
          "no climber holds a standing in this time frame at all" :
          "no climber holds a standing in this period; the standings that do " +
          `exist are for ${sample(elsewhere, 5)}, so this tab renders its empty state`
      );
    }
    if (board.dropped.length > 0) {
      lines.push(dropReasons(`${board.dropped.length} row(s) the app drops`, board.dropped));
    }

    return lines.join("\n");
  });

  return {
    id: "leaderboards.rows",
    name: "Leaderboards · rows on every board",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${boards.length - thin.length} of ${boards.length} boards render ` +
      `${FILMABLE_THRESHOLDS.minimumRenderedLeaderboardRows}+ rows`,
    expectation: "every time frame and metric a climber can tap",
    detail,
  };
}

function leaderboardNamesCheck(observed) {
  const boards = (observed.leaderboards ?? []).filter((board) => !board.failure);
  if (boards.length === 0) {
    return errored(
      "leaderboards.names",
      "Leaderboards · names a camera can read",
      "no leaderboard query completed, so no name was seen"
    );
  }

  const accountName = observed.account?.publicProfile?.row?.displayName ?? null;
  const offenders = new Map();
  let inspected = 0;

  for (const board of boards) {
    for (const row of board.rendered) {
      inspected += 1;
      const key = `${row.userId}|${row.displayName}`;
      if (offenders.has(key)) {
        continue;
      }

      const nameFailure = unphotographableDisplayName(row.displayName);
      if (nameFailure) {
        offenders.set(key, `${board.timeFrame}/${board.metric}: ${nameFailure}`);
        continue;
      }

      if (accountName !== null &&
          row.userId !== observed.accountUid &&
          row.displayName.trim().toLowerCase() === accountName.trim().toLowerCase()) {
        offenders.set(key,
          `${board.timeFrame}/${board.metric}: ${row.userId} publishes ` +
          `"${row.displayName}", the same name as the capture account, so two ` +
          "rows on one board read as the same climber");
      }
    }
  }

  return {
    id: "leaderboards.names",
    name: "Leaderboards · names a camera can read",
    status: offenders.size === 0 ? STATUS.pass : STATUS.fail,
    measured: `${offenders.size} of ${inspected} rendered rows carry a name that cannot be filmed`,
    expectation: "no placeholder, no digits, no collision with the capture account",
    detail: Array.from(offenders.values()),
  };
}

function leaderboardAvatarsCheck(observed) {
  const boards = (observed.leaderboards ?? []).filter((board) => !board.failure);
  const climbBoards = (observed.boards ?? []).filter((board) => board.contested);
  if (boards.length === 0 && climbBoards.length === 0) {
    return errored(
      "leaderboards.avatars",
      "Podiums · faces rather than initials",
      "no board completed its read, so no podium was seen"
    );
  }

  const detail = [];
  let podiums = 0;
  let clean = 0;

  for (const board of boards) {
    podiums += 1;
    const missing = board.rendered
      .slice(0, FILMABLE_THRESHOLDS.podiumDepth)
      .filter((row) => !rendersPhotoAvatar(row.photoURL));
    if (missing.length === 0) {
      clean += 1;
      continue;
    }
    detail.push(
      `${board.timeFrame}/${board.metric}: ${missing.length} of the top ` +
      `${FILMABLE_THRESHOLDS.podiumDepth} render as lettered circles ` +
      `(${missing.map((row) => `"${row.displayName}"`).join(", ")})`
    );
  }

  for (const board of climbBoards) {
    if (board.completionPage?.failure) {
      continue;
    }
    podiums += 1;
    const missing = (board.completionPage?.rendered ?? [])
      .slice(0, FILMABLE_THRESHOLDS.podiumDepth)
      .filter((row) => !rendersPhotoAvatar(row.photoURL));
    if (missing.length === 0) {
      clean += 1;
      continue;
    }
    detail.push(
      `${board.climbId}: ${missing.length} of the top ${FILMABLE_THRESHOLDS.podiumDepth} ` +
      `render as lettered circles (${missing.map((row) => `"${row.displayName}"`).join(", ")})`
    );
  }

  return {
    id: "leaderboards.avatars",
    name: "Podiums · faces rather than initials",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${clean} of ${podiums} podiums show a photo in every one of their top ` +
      `${FILMABLE_THRESHOLDS.podiumDepth}`,
    expectation: "every podium",
    detail,
  };
}

function climbCompletedCountCheck(observed) {
  const boards = (observed.boards ?? []).filter((board) => board.contested);
  const failure = boardReadFailure(boards);
  if (failure) {
    return errored("climb.completedCount", "Climb detail · the completed count", failure);
  }
  if (boards.length === 0) {
    return errored(
      "climb.completedCount",
      "Climb detail · the completed count",
      "no contested board was read"
    );
  }

  const detail = [];
  let agree = 0;

  for (const board of boards) {
    const rendered = board.entryCountAtBucketZero;
    const finishers = board.finisherCount;
    const problems = [];

    if (rendered === 0) {
      problems.push(
        "climb detail renders \"0 completed\" on a board the seed pack contests, " +
        "so the climb reads as untouched"
      );
    }
    if (rendered < finishers) {
      problems.push(
        `climb detail renders ${rendered} completions over ${finishers} finishers - ` +
        "a board cannot hold more climbers than completions, so the rows behind " +
        "the count are missing"
      );
    }
    if (board.summary.completedCount !== null &&
        board.summary.completedCount !== finishers) {
      problems.push(
        `the summary counter says ${board.summary.completedCount} and the ` +
        `finishers collection holds ${finishers}, so the globe and climb detail ` +
        "disagree about the same climb"
      );
    }

    if (problems.length === 0) {
      agree += 1;
      continue;
    }
    detail.push(`${board.climbId}: ${problems.join("; ")}`);
  }

  // A board's own field size is the seed pack's decision, so the floor is not
  // applied per board - a warm climb is meant to hold a dozen. What has to hold
  // is that enough of them look genuinely contested to spin a globe past.
  const busy = boards.filter((board) =>
    board.entryCountAtBucketZero >= CONTENT_READY_THRESHOLDS.minimumCompetitorsPerContestedBoard);
  if (busy.length < CONTENT_READY_THRESHOLDS.minimumContestedBoards) {
    detail.push(
      `only ${busy.length} boards render ` +
      `${CONTENT_READY_THRESHOLDS.minimumCompetitorsPerContestedBoard}+ completions, ` +
      `and the globe wants ${CONTENT_READY_THRESHOLDS.minimumContestedBoards} that ` +
      "read as contested wherever it is spun"
    );
  }

  return {
    id: "climb.completedCount",
    name: "Climb detail · the completed count",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${agree} of ${boards.length} contested boards render a count that ` +
      `agrees with the finishers behind it, ${busy.length} of them ` +
      `${CONTENT_READY_THRESHOLDS.minimumCompetitorsPerContestedBoard}+ deep`,
    expectation: `every contested board, and at least ` +
      `${CONTENT_READY_THRESHOLDS.minimumContestedBoards} of them ` +
      `${CONTENT_READY_THRESHOLDS.minimumCompetitorsPerContestedBoard} deep`,
    detail,
  };
}

function climbCompletionBoardCheck(observed) {
  const boards = (observed.boards ?? []).filter((board) => board.contested);
  const broken = boards.filter((board) => board.completionPage?.failure);
  if (broken.length > 0) {
    return {
      id: "climb.board",
      name: "Climb detail · the completion board",
      status: STATUS.error,
      measured: `${broken.length} of ${boards.length} completion boards did not answer`,
      expectation: "every contested board answers",
      detail: broken.map((board) => `${board.climbId}: ${board.completionPage.failure}`),
    };
  }
  if (boards.length === 0) {
    return errored(
      "climb.board",
      "Climb detail · the completion board",
      "no contested board was read"
    );
  }

  const detail = [];
  let full = 0;

  for (const board of boards) {
    const page = board.completionPage;
    const problems = [];

    if (page.rendered.length === 0 && board.entryCountAtBucketZero > 0) {
      problems.push(
        `counts ${board.entryCountAtBucketZero} completions and renders none of them`
      );
    }
    if (page.dropped.length > 0) {
      problems.push(dropReasons(
        `${page.dropped.length} of the ${page.read} rows it read never reach the screen`,
        page.dropped
      ));
    }

    if (problems.length === 0) {
      full += 1;
      continue;
    }
    detail.push(`${board.climbId}: ${problems.join("; ")}`);
  }

  return {
    id: "climb.board",
    name: "Climb detail · the completion board",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${full} of ${boards.length} contested boards render every row they read`,
    expectation: "no row a board counts is dropped on its way to the screen",
    detail,
  };
}

function liveClimbFieldCheck(observed) {
  const boards = (observed.boards ?? []).filter((board) => board.contested);
  const failure = boardReadFailure(boards, "liveField");
  if (failure) {
    return errored("live.field", "Live climb · the field from the first bucket", failure);
  }
  if (boards.length === 0) {
    return errored(
      "live.field",
      "Live climb · the field from the first bucket",
      "no contested board was read"
    );
  }

  const detail = [];
  let whole = 0;

  for (const board of boards) {
    const problem = thinFieldReport(board);
    if (problem === null) {
      whole += 1;
      continue;
    }
    detail.push(problem);
  }

  return {
    id: "live.field",
    name: "Live climb · the field from the first bucket",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${whole} of ${boards.length} contested boards hold a field that only ever thins`,
    expectation: "a climber meets the whole field at the base; it may shrink as " +
      "rivals finish, never grow as they climb",
    detail,
  };
}

/**
 * Describes how one board's live race fails, or nothing when it does not.
 *
 * The rule is that a field may only ever thin. A climber can leave a race - they
 * finish, and the Cloud Function writes them into their own buckets only - but
 * nobody joins one part way up a building. So the counts across ascending split
 * buckets must be non-increasing, and any rise is rows missing from every bucket
 * below it.
 *
 * That distinction is the whole point. The Empire State board held all 81 of its
 * seeded rows in buckets 151 to 272 and four in bucket 0, so the climb started
 * against four rivals and the field appeared 25 minutes in. A board where the
 * field falls from 85 to 81 partway up is the opposite and is correct: four
 * climbers finished. Reading the second as a defect is how a check stops being
 * read at all.
 * @param {object} board One measured board.
 * @return {?string} The failure, ready to print.
 */
function thinFieldReport(board) {
  const samples = board.liveField ?? [];
  if (samples.length === 0) {
    return `${board.climbId}: no split bucket could be counted`;
  }

  const fullField = samples.reduce(
    (best, sample) => sample.count > best.count ? sample : best
  ).count;
  const problems = [];

  if (fullField === 0) {
    problems.push(
      "no rival at any sampled bucket, so a climber races this contested board alone"
    );
  }

  const risingAt = samples.findIndex(
    (sample, index) => index > 0 && sample.count > samples[index - 1].count
  );
  if (risingAt > 0) {
    const before = samples[risingAt - 1];
    const after = samples[risingAt];
    problems.push(
      `the field GROWS from ${before.count} rivals at bucket ${before.bucketIndex} ` +
      `(${elapsedLabel(before, board)}) to ${after.count} at bucket ` +
      `${after.bucketIndex} (${elapsedLabel(after, board)}). A climber can leave a ` +
      "race by finishing it but can never join one part way up, so " +
      `${after.count - before.count} rows are missing from every bucket below ` +
      `${after.bucketIndex} - the first ${elapsedLabel(after, board).replace(" in", "")} ` +
      "of this climb"
    );
  }

  const empty = samples.filter((sample) => sample.count === 0);
  if (empty.length > 0 && fullField > 0) {
    problems.push(
      `bucket${empty.length === 1 ? "" : "s"} ` +
      `${empty.map((sample) => sample.bucketIndex).join(", ")} ` +
      `hold${empty.length === 1 ? "s" : ""} nobody at all`
    );
  }

  if (board.bucketIds?.missingCount > 0) {
    problems.push(
      `${board.bucketIds.missingCount} of the ${board.bucketIds.maxIndex + 1} split ` +
      "buckets below the summit hold no entries at all (first missing: " +
      `${board.bucketIds.firstMissing})`
    );
  }

  if (problems.length === 0) {
    return null;
  }

  return `${board.climbId}: ${problems.join("; ")}\n` +
    `sampled buckets ${samples.map((sample) => sample.bucketIndex).join(", ")} ` +
    `hold ${samples.map((sample) => sample.count).join(", ")} rivals`;
}

function openFirstAscentCheck(observed) {
  const boards = (observed.boards ?? []).filter((board) => !board.contested);
  const failure = boardReadFailure(boards);
  if (failure) {
    return errored("climb.openFirstAscents", "Globe · climbs with an open First Ascent", failure);
  }

  const open = boards.filter((board) =>
    board.summary.exists &&
    board.summary.updatedAt !== null &&
    board.finisherCount === 0 &&
    board.entryCountAtBucketZero === 0 &&
    board.summary.firstAscentUserId === null);
  const spent = boards.filter((board) =>
    board.summary.exists && board.summary.firstAscentUserId !== null && !board.heldByAccount);
  const absent = boards.filter((board) => !board.summary.exists);

  const detail = [];
  const minimum = CONTENT_READY_THRESHOLDS.minimumOpenFirstAscentBoards;
  if (open.length < minimum) {
    if (absent.length > 0) {
      detail.push(
        `${absent.length} raceable climb${absent.length === 1 ? " has" : "s have"} ` +
        "no board document at all, and an open slot the app cannot see reads as " +
        `nothing (${sample(absent.map((board) => board.climbId))})`
      );
    }
    if (spent.length > 0) {
      detail.push(
        `${spent.length} uncontested climb${spent.length === 1 ? " has" : "s have"} ` +
        `already had the First Ascent claimed (${sample(spent.map((board) => board.climbId))})`
      );
    }
    if (detail.length === 0) {
      detail.push("the open slots are simply below the floor; re-seed the world targets");
    }
  }

  return {
    id: "climb.openFirstAscents",
    name: "Globe · climbs with an open First Ascent",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${open.length} raceable climbs show a claimable First Ascent`,
    expectation: `at least ${minimum}`,
    detail,
  };
}

function routineTemplateCheck(observed) {
  const failure = readFailure(observed, "routineTemplates");
  if (failure) {
    return errored("routines.templates", "Routines · remote templates", failure);
  }

  const templates = observed.routineTemplates ?? {read: 0, rendered: [], dropped: []};
  const detail = [];

  if (templates.rendered.length < CONTENT_READY_THRESHOLDS.minimumRoutineTemplates) {
    detail.push(
      `the app renders ${templates.rendered.length} of ${templates.read} published ` +
      "routine_templates, so the Routines browse surfaces show only the built-in ones"
    );
  }
  if (templates.dropped.length > 0) {
    detail.push(dropReasons(
      `${templates.dropped.length} published template${templates.dropped.length === 1 ? "" : "s"} ` +
      "will not render",
      templates.dropped
    ));
  }

  return {
    id: "routines.templates",
    name: "Routines · remote templates",
    status: detail.length === 0 ? STATUS.pass : STATUS.fail,
    measured: `${templates.rendered.length} of ${templates.read} published templates render ` +
      "beside the built-in routines",
    expectation: `at least ${CONTENT_READY_THRESHOLDS.minimumRoutineTemplates}`,
    detail,
  };
}

/**
 * How far into a climb one split bucket sits, in the app's own terms.
 *
 * A bucket index means nothing to a person watching a screen; "22:40 in" does.
 * `LiveReplayLeaderboardService` derives the index as
 * `elapsedSeconds / bucketIntervalSeconds`, so the inverse is exact.
 * @param {object} sample One measured bucket.
 * @param {object} board The board it belongs to.
 * @return {string} A human elapsed time.
 */
function elapsedLabel(sample, board) {
  const interval = board.summary?.bucketIntervalSeconds ?? 10;
  const seconds = sample.bucketIndex * interval;
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, "0")} in`;
}

function dropReasons(headline, dropped) {
  const byReason = new Map();
  for (const drop of dropped) {
    byReason.set(drop.reason, (byReason.get(drop.reason) ?? 0) + 1);
  }
  const reasons = Array.from(byReason.entries())
    .sort((lhs, rhs) => rhs[1] - lhs[1])
    .slice(0, 3)
    .map(([reason, count]) => `${count}x ${reason}`);
  return `${headline}: ${reasons.join("; ")}`;
}

function sample(values, limit = 4) {
  const shown = values.slice(0, limit).join(", ");
  return values.length > limit ? `${shown}, +${values.length - limit} more` : shown;
}

function readFailure(observed, key) {
  return (observed.readFailures ?? []).find((entry) => entry.what === key)?.message ?? null;
}

function boardReadFailure(boards, field = null) {
  const broken = boards.filter((board) =>
    board.failure || (field !== null && board[field] === null));
  if (broken.length === 0) {
    return null;
  }
  return `${broken.length} board read(s) did not complete: ` +
    broken.slice(0, 3).map((board) => `${board.climbId} (${board.failure ?? "no measurement"})`).join("; ");
}

function errored(id, name, message) {
  return {
    id,
    name,
    status: STATUS.error,
    measured: "the read did not complete, so nothing about this surface is known",
    expectation: "a completed read",
    detail: [message],
  };
}
