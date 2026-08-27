import assert from "node:assert/strict";
import {test} from "node:test";

import {CONTENT_READY_THRESHOLDS} from "../seed/lib/content-ready-contract.mjs";
import {
  STATUS,
  filmableChecks,
  renderFilmableReport,
} from "../lib/filmable-report.mjs";
import {
  LEADERBOARD_METRIC_SORT_FIELDS,
  LEADERBOARD_TIME_FRAMES,
} from "../lib/app-render-contract.mjs";

const ACCOUNT_UID = "captain-uid";
const STORAGE_PHOTO =
  "https://firebasestorage.googleapis.com/v0/b/ascend-staging-fa7d5.firebasestorage.app/" +
  "o/users%2Fu1%2Fprofile_pictures%2Fone.jpg?alt=media&token=abc";

function check(checks, id) {
  const found = checks.find((entry) => entry.id === id);
  assert.ok(found, `no check with id ${id}`);
  return found;
}

const GIVEN_NAMES = ["Morgan", "Bryce", "Georgia", "Julian", "Priya", "Noor"];
const FAMILY_NAMES = ["Hale", "Coleman", "Vance", "Estevez", "Raman", "Whitfield"];

/** A full name of the shape a real sign-in supplies, so the screening accepts it. */
function climberName(index) {
  return `${GIVEN_NAMES[index % GIVEN_NAMES.length]} ` +
    `${FAMILY_NAMES[Math.floor(index / GIVEN_NAMES.length) % FAMILY_NAMES.length]}`;
}

function leaderboardRow(index) {
  return {
    userId: `rival-${index}`,
    displayName: climberName(index),
    photoURL: STORAGE_PHOTO,
    usesGenericAvatar: false,
    totalSteps: 90_000 - index * 100,
    totalFloors: 500,
    totalWorkouts: 12,
    totalDuration: 20_000,
    stepsPerMinute: 60,
  };
}

function completionRow(index) {
  return {
    id: `seed-${index}`,
    userId: `rival-${index}`,
    displayName: climberName(index),
    photoURL: STORAGE_PHOTO,
    usesGenericAvatar: false,
    completionDurationSeconds: 900 + index,
    finalSteps: 1_576,
    isSynthetic: true,
  };
}

function contestedBoard(climbId, overrides = {}) {
  const field = overrides.field ?? 40;
  const maxIndex = overrides.maxIndex ?? 272;
  return {
    climbId,
    contextKey: `live_climb__${climbId}`,
    contested: true,
    failure: null,
    summary: {
      exists: true,
      completedCount: field,
      totalClimbers: field,
      bucketIntervalSeconds: 10,
      seedBucketCount: maxIndex + 1,
      seededAttemptCount: field,
      source: "seeded",
      firstAscentUserId: "seed-holder",
      updatedAt: Date.now(),
    },
    finisherCount: field,
    entryCountAtBucketZero: field,
    bucketIds: {present: maxIndex + 1, maxIndex, missingCount: 0, firstMissing: null},
    liveField: [0, 68, 136, 204, maxIndex].map((bucketIndex) => ({bucketIndex, count: field})),
    completionPage: {
      read: 25,
      rendered: Array.from({length: 25}, (_value, index) => completionRow(index)),
      dropped: [],
      failure: null,
    },
    heldByAccount: false,
    accountFinisherOrder: null,
    ...overrides,
  };
}

function openBoard(climbId) {
  return {
    climbId,
    contextKey: `live_climb__${climbId}`,
    contested: false,
    failure: null,
    summary: {
      exists: true,
      completedCount: 0,
      totalClimbers: 0,
      bucketIntervalSeconds: 10,
      seedBucketCount: null,
      seededAttemptCount: 0,
      source: "seeded",
      firstAscentUserId: null,
      updatedAt: Date.now(),
    },
    finisherCount: 0,
    entryCountAtBucketZero: 0,
    bucketIds: null,
    liveField: null,
    completionPage: null,
    heldByAccount: false,
    accountFinisherOrder: null,
  };
}

function heldBoard(climbId) {
  return {
    ...openBoard(climbId),
    summary: {...openBoard(climbId).summary, firstAscentUserId: ACCOUNT_UID, completedCount: 1},
    finisherCount: 1,
    entryCountAtBucketZero: 1,
    heldByAccount: true,
    accountFinisherOrder: 1,
  };
}

function filmableEnvironment(overrides = {}) {
  const day = 86_400_000;
  const now = Date.now();

  return {
    projectId: "ascend-staging-fa7d5",
    environment: "staging",
    accountUid: ACCOUNT_UID,
    appVersion: "1.0",
    catalog: {
      source: "hosted",
      url: "https://ascend-staging-fa7d5.web.app/climbs/catalog-v1.json",
      catalogVersion: 10,
      featuredClimbId: "empire-state-building",
      climbs: [
        {id: "empire-state-building", releaseState: "available"},
        {id: "eiffel-tower", releaseState: "available"},
      ],
      failure: null,
    },
    account: {
      publicProfile: {
        renders: true,
        reason: null,
        row: {displayName: "Tyler Pavay", photoURL: STORAGE_PHOTO, usesGenericAvatar: false},
      },
      profileStats: {exists: true, totalClimbsCompleted: 9, totalFirstAscents: 1},
      profileWorkouts: {
        read: 24,
        rendered: Array.from({length: 24}, (_value, index) => ({
          id: `w${index}`,
          startedAtMs: now - index * 2 * day,
          steps: 1_500,
          climbId: "eiffel-tower",
        })),
        dropped: [],
        daysSinceNewest: 0,
        historyDepthDays: 46,
      },
      achievements: {
        read: 5,
        rendered: Array.from({length: 5}, (_value, index) => ({
          id: `a${index}`,
          type: "weekly_top_3",
          earnedAtMs: now - index * day,
        })),
        dropped: [],
      },
    },
    leaderboards: LEADERBOARD_TIME_FRAMES.flatMap((timeFrame) =>
      Object.keys(LEADERBOARD_METRIC_SORT_FIELDS).map((metric) => ({
        timeFrame,
        metric,
        periodKey: "2026-W35",
        read: 30,
        rendered: Array.from({length: 30}, (_value, index) => leaderboardRow(index)),
        dropped: [],
        periodsWithStandings: [],
        failure: null,
      }))),
    routineTemplates: {
      read: 4,
      rendered: [
        {id: "t1", name: "Tower Intervals", intervalCount: 6},
        {id: "t2", name: "Base Builder", intervalCount: 5},
      ],
      dropped: [],
    },
    boards: [
      ...Array.from({length: 12}, (_value, index) => contestedBoard(`contested-${index}`)),
      heldBoard("open-held"),
      ...Array.from({length: 24}, (_value, index) => openBoard(`open-${index}`)),
    ],
    readFailures: [],
    ...overrides,
  };
}

test("a healthy environment passes every surface", () => {
  const checks = filmableChecks(filmableEnvironment());
  const notPassing = checks.filter((entry) => entry.status !== STATUS.pass);

  assert.deepEqual(
    notPassing.map((entry) => `${entry.id}: ${entry.measured} | ${entry.detail.join(" | ")}`),
    []
  );
  assert.equal(renderFilmableReport(checks, {}).ok, true);
});

test("every check names a measured number and an expectation", () => {
  for (const entry of filmableChecks(filmableEnvironment())) {
    assert.ok(entry.name.length > 0, `${entry.id} has no name`);
    assert.ok(entry.measured.length > 0, `${entry.id} reports no measurement`);
    assert.ok(entry.expectation.length > 0, `${entry.id} states no expectation`);
  }
});

test("the Empire State shape fails loudly, naming the base and the summit", () => {
  const broken = contestedBoard("empire-state-building", {
    field: 81,
    finisherCount: 85,
    entryCountAtBucketZero: 4,
    liveField: [
      {bucketIndex: 0, count: 4},
      {bucketIndex: 68, count: 4},
      {bucketIndex: 136, count: 0},
      {bucketIndex: 204, count: 81},
      {bucketIndex: 272, count: 81},
    ],
    bucketIds: {present: 232, maxIndex: 272, missingCount: 41, firstMissing: 102},
  });
  broken.summary.completedCount = 85;

  const environment = filmableEnvironment();
  environment.boards = [broken, ...environment.boards];
  const checks = filmableChecks(environment);

  const field = check(checks, "live.field");
  assert.equal(field.status, STATUS.fail);
  const detail = field.detail.join("\n");
  assert.match(detail, /empire-state-building/u);
  assert.match(detail, /the field GROWS from 0 rivals at bucket 136 \(22:40 in\) to 81 at bucket 204 \(34:00 in\)/u);
  assert.match(detail, /81 rows are missing from every bucket below 204/u);
  assert.match(detail, /the first 34:00 of this climb/u);
  assert.match(detail, /bucket 136 holds nobody at all/u);
  assert.match(detail, /41 of the 273 split buckets/u);
  assert.match(detail, /first missing: 102/u);
  assert.match(detail, /sampled buckets 0, 68, 136, 204, 272 hold 4, 4, 0, 81, 81 rivals/u);
});

test("a completed count below the finishers behind it fails, because rows are missing", () => {
  const broken = contestedBoard("empire-state-building", {
    finisherCount: 85,
    entryCountAtBucketZero: 4,
  });
  broken.summary.completedCount = 85;

  const environment = filmableEnvironment();
  environment.boards = [broken, ...environment.boards];
  const counted = check(filmableChecks(environment), "climb.completedCount");

  assert.equal(counted.status, STATUS.fail);
  assert.match(counted.detail.join("\n"), /renders 4 completions over 85 finishers/u);
});

test("a warm board seeded a dozen deep is not a failure, but too few busy boards is", () => {
  const environment = filmableEnvironment();
  environment.boards = environment.boards.map((board) => board.contested ?
    contestedBoard(board.climbId, {field: 12}) :
    board);

  const counted = check(filmableChecks(environment), "climb.completedCount");
  assert.equal(counted.status, STATUS.fail);
  assert.match(counted.detail.join("\n"), /only 0 boards render 20\+ completions/u);
  assert.equal(
    counted.detail.some((line) => /contested-0:/u.test(line)),
    false,
    "a twelve-deep warm board must not be failed on its own field size"
  );
});

test("a board whose field is the same the whole way up passes even when it is small", () => {
  const environment = filmableEnvironment();
  environment.boards = environment.boards.map((board) => board.contested ?
    contestedBoard(board.climbId, {field: 9}) :
    board);

  const field = check(filmableChecks(environment), "live.field");
  assert.equal(field.status, STATUS.pass);
});

test("a field that thins as rivals finish is correct, not a defect", () => {
  const board = contestedBoard("empire-state-building", {field: 85});
  board.liveField = [
    {bucketIndex: 0, count: 85},
    {bucketIndex: 102, count: 81},
    {bucketIndex: 272, count: 81},
  ];

  const environment = filmableEnvironment();
  environment.boards = [board, ...environment.boards];

  assert.equal(check(filmableChecks(environment), "live.field").status, STATUS.pass);
});

test("a field that dips and recovers fails, because nobody joins a race part way up", () => {
  const board = contestedBoard("taipei-101", {field: 14});
  board.liveField = [
    {bucketIndex: 0, count: 14},
    {bucketIndex: 165, count: 10},
    {bucketIndex: 330, count: 14},
  ];

  const environment = filmableEnvironment();
  environment.boards = [board, ...environment.boards];
  const field = check(filmableChecks(environment), "live.field");

  assert.equal(field.status, STATUS.fail);
  assert.match(
    field.detail.join("\n"),
    /GROWS from 10 rivals at bucket 165 \(27:30 in\) to 14 at bucket 330/u
  );
  assert.match(field.detail.join("\n"), /4 rows are missing from every bucket below 330/u);
});

test("a contested board with no rival at any bucket fails outright", () => {
  const board = contestedBoard("merdeka-118", {field: 0});
  board.liveField = board.liveField.map((sample) => ({...sample, count: 0}));

  const environment = filmableEnvironment();
  environment.boards = [board, ...environment.boards];
  const field = check(filmableChecks(environment), "live.field");

  assert.equal(field.status, STATUS.fail);
  assert.match(field.detail.join("\n"), /races this contested board alone/u);
});

test("an empty period says which periods do hold standings", () => {
  const environment = filmableEnvironment();
  environment.leaderboards[0].read = 0;
  environment.leaderboards[0].rendered = [];
  environment.leaderboards[0].periodsWithStandings = ["2026-08-25", "2026-08-26"];

  const rows = check(filmableChecks(environment), "leaderboards.rows");
  assert.equal(rows.status, STATUS.fail);
  assert.match(rows.detail.join("\n"), /no climber holds a standing in this period/u);
  assert.match(rows.detail.join("\n"), /2026-08-25, 2026-08-26/u);
});

test("a summary counter that disagrees with its finishers fails", () => {
  const board = contestedBoard("merdeka-118", {field: 40});
  board.summary.completedCount = 82;

  const environment = filmableEnvironment();
  environment.boards = [board, ...environment.boards];
  const counted = check(filmableChecks(environment), "climb.completedCount");

  assert.equal(counted.status, STATUS.fail);
  assert.match(counted.detail.join("\n"), /summary counter says 82 and the finishers collection holds 40/u);
});

test("a read that failed is an ERROR, never a pass and never an empty result", () => {
  const environment = filmableEnvironment({
    readFailures: [{what: "account.achievements", message: "DEADLINE_EXCEEDED"}],
  });
  environment.account.achievements = null;

  const checks = filmableChecks(environment);
  const achievements = check(checks, "account.achievements");
  assert.equal(achievements.status, STATUS.error);
  assert.match(achievements.detail.join(" "), /DEADLINE_EXCEEDED/u);

  const report = renderFilmableReport(checks, {});
  assert.equal(report.ok, false);
  assert.equal(report.errored.length, 1);
  assert.match(report.text, /A read that failed says nothing about what is there/u);
  assert.match(report.text, /NOT filmable/u);
});

test("a leaderboard query that did not complete errors rather than reading as an empty board", () => {
  const environment = filmableEnvironment();
  environment.leaderboards[3].failure = "FAILED_PRECONDITION: the query requires an index";

  const rows = check(filmableChecks(environment), "leaderboards.rows");
  assert.equal(rows.status, STATUS.error);
  assert.match(rows.detail.join(" "), /requires an index/u);
});

test("a thin leaderboard names the tab, the period and what the app dropped", () => {
  const environment = filmableEnvironment();
  environment.leaderboards[0].rendered = [leaderboardRow(0)];
  environment.leaderboards[0].read = 14;
  environment.leaderboards[0].dropped = Array.from({length: 13}, () => ({
    reason: "carries identityPolicyVersion 0, and the app renders only version 1",
  }));

  const rows = check(filmableChecks(environment), "leaderboards.rows");
  assert.equal(rows.status, STATUS.fail);
  assert.match(rows.detail.join("\n"), /1 of 14 documents render/u);
  assert.match(rows.detail.join("\n"), /13x carries identityPolicyVersion 0/u);
});

test("a placeholder name on a board fails, and so does a name colliding with the account", () => {
  const environment = filmableEnvironment();
  environment.leaderboards[0].rendered[0] = {
    ...leaderboardRow(0),
    userId: "qa-1",
    displayName: "CHANGE ME",
  };
  environment.leaderboards[1].rendered[0] = {
    ...leaderboardRow(0),
    userId: "qa-2",
    displayName: "tyler pavay",
  };

  const names = check(filmableChecks(environment), "leaderboards.names");
  assert.equal(names.status, STATUS.fail);
  assert.match(names.detail.join("\n"), /CHANGE ME/u);
  assert.match(names.detail.join("\n"), /same name as the capture account/u);
});

test("a podium of lettered circles fails and names the climbers", () => {
  const environment = filmableEnvironment();
  environment.leaderboards[0].rendered[1] = {
    ...leaderboardRow(1),
    displayName: "Jenny Whitfield",
    photoURL: null,
    usesGenericAvatar: true,
  };
  environment.boards[0].completionPage.rendered[0] = {
    ...completionRow(0),
    displayName: "Bryce Coleman",
    photoURL: "https://example.com/face.jpg",
  };

  const avatars = check(filmableChecks(environment), "leaderboards.avatars");
  assert.equal(avatars.status, STATUS.fail);
  assert.match(avatars.detail.join("\n"), /Jenny Whitfield/u);
  assert.match(avatars.detail.join("\n"), /Bryce Coleman/u);
});

test("routine templates the app cannot render fail even when the documents exist", () => {
  const environment = filmableEnvironment({
    routineTemplates: {
      read: 4,
      rendered: [],
      dropped: Array.from({length: 4}, () => ({
        reason: "requires app version 1.1 and the capture build is 1.0",
      })),
    },
  });

  const routines = check(filmableChecks(environment), "routines.templates");
  assert.equal(routines.status, STATUS.fail);
  assert.match(routines.detail.join("\n"), /0 of 4 published routine_templates/u);
  assert.match(routines.detail.join("\n"), /4x requires app version 1\.1/u);
});

test("a First Ascent the account did not finish first fails on the ordinal", () => {
  const environment = filmableEnvironment();
  const held = environment.boards.find((board) => board.heldByAccount);
  held.accountFinisherOrder = 4;

  const ascents = check(filmableChecks(environment), "account.firstAscent");
  assert.equal(ascents.status, STATUS.fail);
  assert.match(ascents.detail.join("\n"), /finished #4/u);
});

test("no First Ascent at all fails with the reason on the first line", () => {
  const environment = filmableEnvironment();
  environment.boards = environment.boards.filter((board) => !board.heldByAccount);

  const ascents = check(filmableChecks(environment), "account.firstAscent");
  assert.equal(ascents.status, STATUS.fail);
  assert.match(ascents.detail[0], /no board names the account/u);
});

test("a profile whose sessions live only in the workouts collection fails", () => {
  const environment = filmableEnvironment();
  environment.account.profileWorkouts = {
    read: 0,
    rendered: [],
    dropped: [],
    daysSinceNewest: null,
    historyDepthDays: null,
  };

  const history = check(filmableChecks(environment), "account.history");
  assert.equal(history.status, STATUS.fail);
  assert.match(history.detail.join("\n"), /profile_workouts/u);
  assert.equal(
    history.expectation,
    `${CONTENT_READY_THRESHOLDS.minimumClimbsCompleted} climbs and ` +
    `${CONTENT_READY_THRESHOLDS.minimumWorkouts} rendered sessions`
  );
});

test("an account with no publishable photo fails, because its own row is the shop window", () => {
  const environment = filmableEnvironment();
  environment.account.publicProfile.row.photoURL = null;

  const profile = check(filmableChecks(environment), "account.profile");
  assert.equal(profile.status, STATUS.fail);
  assert.match(profile.detail.join("\n"), /lettered circle/u);
});

test("open First Ascent slots with no board document are named as invisible, not merely few", () => {
  const environment = filmableEnvironment();
  environment.boards = environment.boards.map((board) => board.contested || board.heldByAccount ?
    board :
    {...board, summary: {...board.summary, exists: false, updatedAt: null}});

  const open = check(filmableChecks(environment), "climb.openFirstAscents");
  assert.equal(open.status, STATUS.fail);
  assert.match(open.detail.join("\n"), /no board document at all/u);
});

test("a bootstrap catalog is an ERROR, because the rest was graded against a different climb list", () => {
  const environment = filmableEnvironment({
    catalog: {
      source: "bootstrap",
      url: "AscendApp/Features/Climbs/Resources/climbs.json",
      catalogVersion: 0,
      featuredClimbId: "empire-state-building",
      climbs: [{id: "empire-state-building", releaseState: "available"}],
      failure: "https://ascend-staging-fa7d5.web.app answered 404",
    },
  });

  const catalog = check(filmableChecks(environment), "catalog");
  assert.equal(catalog.status, STATUS.error);
  assert.match(catalog.detail.join("\n"), /answered 404/u);
});

test("the rendered report shows every check with its measurement, and the verdict last", () => {
  const checks = filmableChecks(filmableEnvironment());
  const report = renderFilmableReport(checks, {
    projectId: "ascend-staging-fa7d5",
    environment: "staging",
    account: "captain-uid <you@example.com>",
    elapsedSeconds: 4.2,
  });

  assert.match(report.text, /ascend-staging-fa7d5 \(staging\)/u);
  for (const entry of checks) {
    assert.ok(report.text.includes(entry.name), `${entry.name} is missing from the report`);
  }
  assert.match(report.text, /want: /u);
  assert.match(report.text, /Read 13 surfaces in 4\.2s\./u);
  assert.ok(report.text.trimEnd().endsWith("Staging is filmable. Every surface above renders what it claims to hold."));
});

test("a board that counts completions it cannot render fails, and names the reason", () => {
  const environment = filmableEnvironment();
  environment.boards[0].completionPage = {
    read: 25,
    rendered: [],
    dropped: Array.from({length: 25}, () => ({
      reason: "carries no completionDurationSeconds, so the board drops it",
    })),
    failure: null,
  };

  const board = check(filmableChecks(environment), "climb.board");
  assert.equal(board.status, STATUS.fail);
  assert.match(board.detail.join("\n"), /counts 40 completions and renders none of them/u);
  assert.match(board.detail.join("\n"), /25x carries no completionDurationSeconds/u);
});

test("a full first page with nothing dropped passes", () => {
  const board = check(filmableChecks(filmableEnvironment()), "climb.board");
  assert.equal(board.status, STATUS.pass);
  assert.match(board.measured, /12 of 12 contested boards render every row they read/u);
});
