#!/usr/bin/env node

/**
 * Is staging filmable?
 *
 * One command that answers that with a pass or a fail per surface, by reading
 * exactly what the app reads: the same collections, the same aggregates, the
 * same query shapes.
 *
 * It exists because nothing did. The seed's own summary, `audit-seed-data.mjs`
 * and every hand-run database probe confirm that documents were written, and
 * none of them confirm that a climber opening the app sees a populated product.
 * So "staging is ready" was repeatedly a claim about Firestore and repeatedly
 * not a claim about the screen: empty leaderboards, four rivals instead of a
 * field, and the whole bottom half of the Empire State Building with nobody in
 * it while its summary said 85 climbers had finished.
 *
 * Two rules make that impossible to repeat:
 *
 * 1. Where the app uses a Firestore `count()` aggregate, this uses the same
 *    aggregate over the same path. The Empire State discrepancy was exactly a
 *    counter field being trusted in place of the aggregate the app renders.
 * 2. A read that failed is never rendered as a read that came back empty. Both
 *    print nothing, and reporting the first as the second is how a leaderboard
 *    holding 13 entries was once reported as holding none.
 *
 * Every network call carries a deadline, and the whole run carries one too, so
 * a wedged read is named rather than waited on.
 *
 * Usage:
 *   node scripts/verify-filmable.mjs --project staging --email you@example.com
 *   node scripts/verify-filmable.mjs --project staging --user <uid> --json
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login
 */

import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {applicationDefault, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {runPool, withRetry} from "./lib/firestore-bulk.mjs";
import {currentPeriod} from "./lib/leaderboard-period.mjs";
import {
  LEADERBOARD_METRIC_SORT_FIELDS,
  LEADERBOARD_TIME_FRAMES,
  collapsesRepeatFinishers,
  millisecondsValue,
  numberValue,
  renderedAchievement,
  renderedCompletionRow,
  renderedLeaderboardRow,
  renderedProfileWorkout,
  renderedPublicProfile,
  renderedRoutineTemplate,
  replayContextKey,
  stringValue,
} from "./lib/app-render-contract.mjs";
import {filmableChecks, renderFilmableReport} from "./lib/filmable-report.mjs";
import {
  RACEABLE_RELEASE_STATE,
  contestedClimbIds,
} from "./seed/lib/live-replay-climb-tiers.mjs";
import {
  PRODUCTION_PROJECT_ID,
  resolveProjectId,
  seedEnvironmentName,
} from "./seed/lib/environments.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");

/** The bootstrap catalog the app ships with, used only when hosting cannot answer. */
const CLIMB_CATALOG_PATH = resolve(REPO_ROOT, "AscendApp/Features/Climbs/Resources/climbs.json");

/** Mirrors `LiveReplayLeaderboardContextType.liveClimb`. */
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";

/** Rows one page of the completion board reads. Mirrors `completionLeaderboardPageSize`. */
const COMPLETION_PAGE_SIZE = 25;

/** Rows the leaderboard screen reads. Mirrors `LeaderboardRepository.fetchLeaderboard`. */
const LEADERBOARD_PAGE_SIZE = 100;

/** Sessions the profile reads. Mirrors `ProfileRepository.fetchRemoteBundle`. */
const PROFILE_WORKOUT_PAGE_SIZE = 60;

/** Achievements the profile reads. Mirrors `ProfileRepository.fetchAchievements`. */
const ACHIEVEMENT_PAGE_SIZE = 200;

/**
 * Split buckets counted per contested board.
 *
 * The live race reads one bucket at a time - `bucketIndex = elapsedSeconds /
 * bucketIntervalSeconds` - so a board can be complete at the summit and empty at
 * the base, which is exactly what Empire State was. Nine evenly spaced probes
 * bound the gap at an eighth of a climb, which for a 45 minute tower is close
 * enough to name the stretch a climber races alone.
 */
const DEFAULT_BUCKET_SAMPLES = 9;

/** Reads in flight at once. The backend, not the client, is the limit past this. */
const READ_CONCURRENCY = 48;

/** Deadline for any single Firestore call. */
const CALL_TIMEOUT_MS = 15_000;

/** Deadline for a hosted catalog fetch. Mirrors the app's own `timeoutInterval`. */
const CATALOG_TIMEOUT_MS = 15_000;

/** Attempts per call. Enough for a transient ABORTED, short enough to stay a check. */
const CALL_ATTEMPTS = 3;

/** Deadline for the whole run. A check that hangs is worse than no check. */
const DEFAULT_DEADLINE_SECONDS = 120;

function parseArgs(argv) {
  const first = argv[2];
  const args = {
    command: first && !first.startsWith("-") ? first : "check",
    project: "staging",
    email: null,
    userId: null,
    json: false,
    confirmProduction: false,
    bucketSamples: DEFAULT_BUCKET_SAMPLES,
    deadlineSeconds: DEFAULT_DEADLINE_SECONDS,
    appVersion: null,
  };
  const start = first && !first.startsWith("-") ? 3 : 2;

  for (let index = start; index < argv.length; index += 1) {
    const flag = argv[index];
    switch (flag) {
      case "--project":
        args.project = requireValue(argv, ++index, flag);
        break;
      case "--email":
        args.email = requireValue(argv, ++index, flag);
        break;
      case "--user":
      case "--uid":
        args.userId = requireValue(argv, ++index, flag);
        break;
      case "--app-version":
        args.appVersion = requireValue(argv, ++index, flag);
        break;
      case "--bucket-samples":
        args.bucketSamples = Math.max(2, Number.parseInt(requireValue(argv, ++index, flag), 10));
        break;
      case "--deadline-seconds":
        args.deadlineSeconds = Math.max(10, Number.parseInt(requireValue(argv, ++index, flag), 10));
        break;
      case "--json":
        args.json = true;
        break;
      case "--confirm-production":
        args.confirmProduction = true;
        break;
      case "--help":
      case "-h":
        args.command = "help";
        break;
      default:
        throw new Error(`Unknown argument: ${flag}`);
    }
  }

  if (!["check", "help"].includes(args.command)) {
    throw new Error(`Unknown command "${args.command}". Use check or help.`);
  }

  return args;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (value === undefined || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function printHelp() {
  console.log(`
Answers "is this environment filmable" with a pass or a fail per surface, by
reading exactly what the app reads.

Usage:
  node scripts/verify-filmable.mjs --project staging --email you@example.com
  node scripts/verify-filmable.mjs --project staging --user <uid> --json

Options:
  --project <name>  staging (default), dev, or production. Read-only either way,
                    but production needs --confirm-production, and the resolved
                    project is named on every line of the report.
  --confirm-production
                    Required before this reads ascend-prod-9c8f2.
  --email <email>   The capture account. Required, or pass --user.
  --user <uid>      A Firebase Auth uid instead of an email.
  --app-version <v> The capture build's marketing version, which decides whether
                    a routine template with a minAppVersion is visible on it.
                    Defaults to MARKETING_VERSION in the Xcode project.
  --bucket-samples <n>
                    Split buckets counted per contested board (default ${DEFAULT_BUCKET_SAMPLES}).
  --deadline-seconds <n>
                    Give up and say so (default ${DEFAULT_DEADLINE_SECONDS}).
  --json            Emit the measurements and verdicts as JSON.

Exit codes:
  0  every surface renders what it claims to hold
  1  a surface would not film
  2  a read did not complete, so nothing about that surface is known
`);
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.command === "help") {
    printHelp();
    return;
  }

  if (!args.email && !args.userId) {
    throw new Error("verify-filmable requires --email <email> or --user <uid>");
  }

  const projectId = resolveProjectId(args.project, REPO_ROOT);
  // Read-only, and still gated: naming production out loud is what keeps an
  // answer about staging from being reported as an answer about customers.
  if (projectId === PRODUCTION_PROJECT_ID && !args.confirmProduction) {
    throw new Error(
      `Reading ${PRODUCTION_PROJECT_ID} (production) requires --confirm-production.`
    );
  }

  if (getApps().length === 0) {
    initializeApp({credential: applicationDefault(), projectId});
  }

  const account = await resolveAccount(args);
  const startedAt = Date.now();
  const observed = await withDeadline(
    () => observe(getFirestore(), {
      projectId,
      account,
      appVersion: args.appVersion ?? marketingVersion(),
      bucketSamples: args.bucketSamples,
    }),
    args.deadlineSeconds
  );

  const checks = filmableChecks(observed);
  const report = renderFilmableReport(checks, {
    projectId,
    environment: seedEnvironmentName(projectId),
    account: `${account.uid} <${account.email ?? "no email"}>`,
    elapsedSeconds: (Date.now() - startedAt) / 1000,
  });

  if (args.json) {
    console.log(JSON.stringify({observed, checks, ok: report.ok}, null, 2));
  } else {
    console.log(report.text);
  }

  process.exitCode = report.errored.length > 0 ? 2 : (report.ok ? 0 : 1);
}

/**
 * Resolves the capture account before anything is read.
 *
 * Looked up rather than assumed, so a typo fails the command instead of
 * producing a confident report about an account that does not exist.
 * @param {object} args Parsed arguments.
 * @return {Promise<object>} Firebase Auth user record.
 */
async function resolveAccount(args) {
  const auth = getAuth();
  try {
    return args.userId ?
      await auth.getUser(args.userId) :
      await auth.getUserByEmail(args.email);
  } catch {
    const lookup = args.userId ? `uid ${args.userId}` : `email ${args.email}`;
    throw new Error(
      `No Firebase Auth user for ${lookup} in this environment. ` +
      "Sign into the app once with that account, then rerun."
    );
  }
}

/**
 * Runs the whole measurement under one wall clock.
 *
 * The seeder once printed nothing for eighteen minutes, and working could not be
 * told from dead from outside. A check has to be worse at hanging than the thing
 * it checks, so this one refuses to.
 * @param {() => Promise<T>} start Starts the work.
 * @param {number} deadlineSeconds Wall clock.
 * @return {Promise<T>} The work's result.
 * @template T
 */
async function withDeadline(start, deadlineSeconds) {
  let timer;
  try {
    return await Promise.race([
      start(),
      new Promise((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(
          `The environment did not answer within ${deadlineSeconds}s. Nothing ` +
          "here is known - this is not a report that staging is empty."
        )), deadlineSeconds * 1000);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Reads every surface the way the app reads it.
 *
 * Returns measurements only. Nothing here decides whether a number is good
 * enough - `filmable-report.mjs` owns that, and keeping the two apart is what
 * lets the judgment be tested without a network.
 * @param {object} db Firestore instance.
 * @param {object} options Run context.
 * @return {Promise<object>} Measurements.
 */
export async function observe(db, {projectId, account, appVersion, bucketSamples}) {
  const readFailures = [];
  const catalog = await loadClimbCatalog(projectId, readFailures);
  const contested = contestedClimbIds();

  const [accountState, leaderboards, routineTemplates, boards] = await Promise.all([
    observeAccount(db, account.uid, readFailures),
    observeLeaderboards(db),
    observeRoutineTemplates(db, appVersion, readFailures),
    observeBoards(db, {
      climbs: catalog.climbs,
      contested,
      accountUid: account.uid,
      bucketSamples,
      readFailures,
    }),
  ]);

  return {
    projectId,
    environment: seedEnvironmentName(projectId),
    accountUid: account.uid,
    accountEmail: account.email ?? null,
    appVersion,
    catalog,
    account: accountState,
    leaderboards,
    routineTemplates,
    boards,
    readFailures,
  };
}

/**
 * Reads the four documents and two collections the profile renders from.
 *
 * `profile_workouts` rather than `workouts` is deliberate and is the kind of
 * thing this whole command exists to catch: the profile renders the first, the
 * device syncs the second, and a seed that fills only one leaves a busy account
 * with an empty profile.
 * @param {object} db Firestore instance.
 * @param {string} uid Capture account.
 * @param {object[]} readFailures Accumulator for reads that did not complete.
 * @return {Promise<object>} Measurements.
 */
async function observeAccount(db, uid, readFailures) {
  const userRef = db.collection("users").doc(uid);

  const publicProfile = await attempt(readFailures, "account.publicProfile", async () => {
    const snapshot = await call(
      () => userRef.collection("public_profile").doc("current").get(),
      `get(users/${uid}/public_profile/current)`
    );
    return renderedPublicProfile(uid, snapshot.exists ? snapshot.data() : null);
  });

  const profileStats = await attempt(readFailures, "account.profileStats", async () => {
    const snapshot = await call(
      () => userRef.collection("profile_stats").doc("current").get(),
      `get(users/${uid}/profile_stats/current)`
    );
    const data = snapshot.data() ?? {};
    return {
      exists: snapshot.exists,
      totalClimbsCompleted: numberValue(data.total_climbs_completed) ?? 0,
      totalFirstAscents: numberValue(data.total_first_ascents) ?? 0,
    };
  });

  const profileWorkouts = await attempt(readFailures, "account.profileWorkouts", async () => {
    const snapshot = await call(
      () => userRef.collection("profile_workouts")
        .orderBy("startedAt", "desc")
        .limit(PROFILE_WORKOUT_PAGE_SIZE)
        .get(),
      `query(users/${uid}/profile_workouts)`
    );
    const judged = snapshot.docs.map((document) =>
      renderedProfileWorkout(document.id, document.data()));
    const rendered = judged.filter((entry) => entry.renders).map((entry) => entry.row);
    const startedAt = rendered.map((row) => row.startedAtMs);
    const now = Date.now();
    return {
      read: snapshot.size,
      rendered,
      dropped: judged.filter((entry) => !entry.renders)
        .map((entry) => ({reason: entry.reason})),
      daysSinceNewest: startedAt.length > 0 ?
        daysBetween(Math.max(...startedAt), now) :
        null,
      historyDepthDays: startedAt.length > 0 ?
        daysBetween(Math.min(...startedAt), now) :
        null,
    };
  });

  const achievements = await attempt(readFailures, "account.achievements", async () => {
    const snapshot = await call(
      () => userRef.collection("achievements")
        .orderBy("earnedAt", "desc")
        .limit(ACHIEVEMENT_PAGE_SIZE)
        .get(),
      `query(users/${uid}/achievements)`
    );
    const judged = snapshot.docs.map((document) =>
      renderedAchievement(document.id, document.data()));
    return {
      read: snapshot.size,
      rendered: judged.filter((entry) => entry.renders).map((entry) => entry.row),
      dropped: judged.filter((entry) => !entry.renders)
        .map((entry) => ({reason: entry.reason})),
    };
  });

  return {publicProfile, profileStats, profileWorkouts, achievements};
}

/**
 * Runs the leaderboard screen's own query for every tab a climber can reach.
 *
 * Every time frame crossed with every metric, because each pairing is a
 * different `order by` and therefore a different composite index: one missing
 * index leaves exactly one tab empty while the other nineteen look fine, and a
 * check that only reads the default tab would call that filmable.
 * @param {object} db Firestore instance.
 * @return {Promise<object[]>} One measurement per board.
 */
async function observeLeaderboards(db) {
  const combinations = LEADERBOARD_TIME_FRAMES.flatMap((timeFrame) =>
    Object.keys(LEADERBOARD_METRIC_SORT_FIELDS).map((metric) => ({timeFrame, metric})));
  const results = new Array(combinations.length);

  await runPool(combinations, READ_CONCURRENCY, async ({timeFrame, metric}, index) => {
    const period = currentPeriod(timeFrame);
    const base = {
      timeFrame,
      metric,
      periodKey: period.key,
      read: 0,
      rendered: [],
      dropped: [],
      periodsWithStandings: [],
      failure: null,
    };

    try {
      const snapshot = await call(
        () => db.collection("leaderboard_stats")
          .where("timeFrame", "==", timeFrame)
          .where("periodStartAt", "==", Timestamp.fromDate(period.startAt))
          .orderBy(LEADERBOARD_METRIC_SORT_FIELDS[metric], "desc")
          .limit(LEADERBOARD_PAGE_SIZE)
          .get(),
        `query(leaderboard_stats ${timeFrame}/${metric})`
      );
      const judged = snapshot.docs.map((document) => ({
        id: document.id,
        ...renderedLeaderboardRow(document.data(), {periodStartAtMs: period.startAt.getTime()}),
      }));
      results[index] = {
        ...base,
        read: snapshot.size,
        rendered: rankedRows(
          judged.filter((entry) => entry.renders).map((entry) => entry.row),
          metric
        ),
        dropped: judged.filter((entry) => !entry.renders)
          .map((entry) => ({id: entry.id, reason: entry.reason})),
        periodsWithStandings: snapshot.empty ?
          await periodsWithStandings(db, timeFrame) :
          [],
      };
    } catch (error) {
      results[index] = {...base, failure: error.message};
    }
  });

  return results;
}

/**
 * Which periods of one time frame hold standings at all.
 *
 * Only read when a board came back empty, and only to make the emptiness
 * legible: "no standing exists for today, the newest daily standings are for
 * yesterday" is a fixable finding, and a bare zero is not. Equality on one field
 * needs no composite index, so this cannot itself be the read that fails.
 * @param {object} db Firestore instance.
 * @param {string} timeFrame Time frame raw value.
 * @return {Promise<string[]>} Distinct period keys, newest-looking last.
 */
async function periodsWithStandings(db, timeFrame) {
  try {
    const snapshot = await call(
      () => db.collection("leaderboard_stats")
        .where("timeFrame", "==", timeFrame)
        .limit(50)
        .get(),
      `query(leaderboard_stats ${timeFrame}, any period)`
    );
    return Array.from(new Set(
      snapshot.docs.map((document) => document.data().periodKey).filter(Boolean)
    )).sort();
  } catch {
    return [];
  }
}

/**
 * Collapses a user's duplicate rows and orders them the way the screen does.
 *
 * `LeaderboardRepository` keeps one row per userId and re-sorts on the metric,
 * breaking ties on userId, so a board of fifty documents belonging to twelve
 * climbers renders twelve rows. Counting the documents would report that board
 * as four times fuller than it looks, and reading the podium off query order
 * would name the wrong three faces.
 * @param {object[]} rows Rendered rows in query order.
 * @param {string} metric The metric the board is ranking on.
 * @return {object[]} One row per climber, in the order the app shows them.
 */
export function rankedRows(rows, metric) {
  const byUser = new Map();
  for (const row of rows) {
    if (!byUser.has(row.userId)) {
      byUser.set(row.userId, row);
    }
  }

  const field = LEADERBOARD_METRIC_SORT_FIELDS[metric] ?? "totalSteps";
  return Array.from(byUser.values()).sort((lhs, rhs) => {
    const difference = (rhs[field] ?? 0) - (lhs[field] ?? 0);
    if (difference !== 0) {
      return difference;
    }
    return lhs.userId < rhs.userId ? -1 : (lhs.userId > rhs.userId ? 1 : 0);
  });
}

async function observeRoutineTemplates(db, appVersion, readFailures) {
  return attempt(readFailures, "routineTemplates", async () => {
    const snapshot = await call(
      () => db.collection("routine_templates").where("status", "==", "published").get(),
      "query(routine_templates)"
    );
    const judged = snapshot.docs.map((document) =>
      renderedRoutineTemplate(document.id, document.data(), {appVersion}));
    return {
      read: snapshot.size,
      rendered: judged.filter((entry) => entry.renders).map((entry) => entry.row),
      dropped: judged.filter((entry) => !entry.renders)
        .map((entry) => ({reason: entry.reason})),
    };
  });
}

/**
 * Measures every raceable climb's board the way its three surfaces read it.
 *
 * Contested boards get the full treatment - the aggregate climb detail renders,
 * the finisher collection behind it, the live race's field at several points up
 * the climb, and the first page of the completion board. Uncontested boards only
 * need to prove their First Ascent is still open and visibly so.
 * @param {object} db Firestore instance.
 * @param {object} options Run context.
 * @return {Promise<object[]>} One measurement per board.
 */
async function observeBoards(db, {climbs, contested, accountUid, bucketSamples, readFailures}) {
  const raceable = climbs.filter((climb) => climb.releaseState === RACEABLE_RELEASE_STATE);
  const boards = raceable.map((climb) => ({
    climbId: climb.id,
    contextKey: replayContextKey(LIVE_CLIMB_CONTEXT_TYPE, climb.id),
    contested: contested.has(climb.id),
  }));

  const summaries = await attempt(readFailures, "boards", async () => {
    const refs = boards.map((board) =>
      db.collection("live_replay_leaderboards").doc(board.contextKey));
    const snapshots = [];
    for (let index = 0; index < refs.length; index += 100) {
      const chunk = refs.slice(index, index + 100);
      const read = await call(
        () => db.getAll(...chunk),
        `getAll(${chunk.length} replay summaries)`
      );
      snapshots.push(...read);
    }
    return new Map(snapshots.map((snapshot) => [snapshot.ref.id, snapshot]));
  });

  if (summaries === null) {
    return boards.map((board) => ({
      ...board,
      failure: "the board summaries could not be read",
      summary: emptySummary(),
      finisherCount: null,
      entryCountAtBucketZero: null,
      liveField: null,
      bucketIds: null,
      completionPage: null,
      heldByAccount: false,
      accountFinisherOrder: null,
    }));
  }

  await runPool(boards, READ_CONCURRENCY, async (board) => {
    const snapshot = summaries.get(board.contextKey);
    board.summary = summaryOf(snapshot);
    board.heldByAccount = board.summary.firstAscentUserId === accountUid;
    board.failure = null;
    board.finisherCount = null;
    board.entryCountAtBucketZero = null;
    board.liveField = null;
    board.bucketIds = null;
    board.completionPage = null;
    board.accountFinisherOrder = null;

    const document = db.collection("live_replay_leaderboards").doc(board.contextKey);

    try {
      const [finisherCount, entryCount] = await Promise.all([
        countOf(document.collection("finishers"), `count(${board.contextKey}/finishers)`),
        countOf(
          entriesCollection(document, 0),
          `count(${board.contextKey}/splitBuckets/0/entries)`
        ),
      ]);
      board.finisherCount = finisherCount;
      board.entryCountAtBucketZero = entryCount;
    } catch (error) {
      board.failure = error.message;
      return;
    }

    if (board.heldByAccount) {
      try {
        const finisher = await call(
          () => document.collection("finishers").doc(accountUid).get(),
          `get(${board.contextKey}/finishers/${accountUid})`
        );
        board.accountFinisherOrder = numberValue(finisher.data()?.globalCompletionOrder);
      } catch (error) {
        board.failure = error.message;
        return;
      }
    }

    if (!board.contested) {
      return;
    }

    try {
      board.bucketIds = await bucketCensus(document);
      board.liveField = await liveFieldSamples(document, board, bucketSamples);
      board.completionPage = await completionPage(document);
    } catch (error) {
      board.failure = error.message;
    }
  });

  return boards;
}

/**
 * Which split buckets exist at all, and which do not.
 *
 * `listDocuments` on `splitBuckets` returns a reference for every bucket holding
 * entries, so a gap in the numeric range is a stretch of the climb with nobody
 * in it - the cheapest possible proof of the failure that cost two days, and one
 * RPC per board.
 * @param {object} document Board summary reference.
 * @return {Promise<object>} Present count, range, and the first gap.
 */
async function bucketCensus(document) {
  const refs = await call(
    () => document.collection("splitBuckets").listDocuments(),
    `listDocuments(${document.id}/splitBuckets)`
  );
  const indices = refs
    .map((ref) => Number.parseInt(ref.id, 10))
    .filter((index) => Number.isInteger(index) && index >= 0)
    .sort((lhs, rhs) => lhs - rhs);

  if (indices.length === 0) {
    return {present: 0, maxIndex: -1, missingCount: 0, firstMissing: null};
  }

  const present = new Set(indices);
  const maxIndex = indices.at(-1);
  let firstMissing = null;
  let missingCount = 0;
  for (let index = 0; index <= maxIndex; index += 1) {
    if (!present.has(index)) {
      missingCount += 1;
      if (firstMissing === null) {
        firstMissing = index;
      }
    }
  }

  return {present: indices.length, maxIndex, missingCount, firstMissing};
}

/**
 * Counts the live race field at several points up the climb.
 *
 * The same aggregate the app runs - `countLiveRaceRows` - over the same path,
 * with the same `isBestForUser` filter on the contexts that collapse repeat
 * finishers and no filter on the ones that do not. Bucket 0 is always sampled
 * first because it is the field a climber meets on their first stride.
 * @param {object} document Board summary reference.
 * @param {object} board The board being measured.
 * @param {number} sampleCount How many buckets to count.
 * @return {Promise<object[]>} `{bucketIndex, count}`, lowest bucket first.
 */
async function liveFieldSamples(document, board, sampleCount) {
  const maxIndex = Math.max(
    board.bucketIds?.maxIndex ?? -1,
    (board.summary.seedBucketCount ?? 0) - 1,
    0
  );
  const indices = bucketSampleIndices(maxIndex, sampleCount);
  const samples = new Array(indices.length);

  await runPool(indices, READ_CONCURRENCY, async (bucketIndex, position) => {
    // Mirrored from `liveRaceEntries` rather than hard-coded: a per-climb board
    // races a field of climbers on their best attempt, and a context that does
    // not collapse repeat finishers carries no flag, so filtering there would
    // count zero rivals on a board that has plenty.
    let query = entriesCollection(document, bucketIndex);
    if (collapsesRepeatFinishers(LIVE_CLIMB_CONTEXT_TYPE)) {
      query = query.where("isBestForUser", "==", true);
    }
    samples[position] = {
      bucketIndex,
      count: await countOf(query, `count(${document.id}/splitBuckets/${bucketIndex}/entries)`),
    };
  });

  return samples;
}

/**
 * Evenly spaced bucket indices, always including the base and the summit.
 * @param {number} maxIndex Highest bucket the board publishes.
 * @param {number} sampleCount How many to take.
 * @return {number[]} Ascending, distinct indices.
 */
export function bucketSampleIndices(maxIndex, sampleCount) {
  if (maxIndex <= 0) {
    return [0];
  }
  const steps = Math.max(2, sampleCount);
  const indices = new Set();
  for (let step = 0; step < steps; step += 1) {
    indices.add(Math.round((maxIndex * step) / (steps - 1)));
  }
  return Array.from(indices).sort((lhs, rhs) => lhs - rhs);
}

/**
 * Reads the first page of the static completion board.
 *
 * Same ordering and same page size as `fetchCompletionLeaderboard`, so a row the
 * app would drop for a missing `completionDurationSeconds` is dropped here too.
 * @param {object} document Board summary reference.
 * @return {Promise<object>} Read count, rendered rows and drop reasons.
 */
async function completionPage(document) {
  try {
    const snapshot = await call(
      () => entriesCollection(document, 0)
        .orderBy("completionDurationSeconds", "asc")
        .orderBy("__name__", "asc")
        .limit(COMPLETION_PAGE_SIZE)
        .get(),
      `query(${document.id}/splitBuckets/0/entries)`
    );
    const judged = snapshot.docs.map((row) => renderedCompletionRow(row.id, row.data()));
    return {
      read: snapshot.size,
      rendered: judged.filter((entry) => entry.renders).map((entry) => entry.row),
      dropped: judged.filter((entry) => !entry.renders).map((entry) => ({reason: entry.reason})),
      failure: null,
    };
  } catch (error) {
    return {read: 0, rendered: [], dropped: [], failure: error.message};
  }
}

function entriesCollection(document, bucketIndex) {
  return document
    .collection("splitBuckets")
    .doc(String(Math.max(bucketIndex, 0)))
    .collection("entries");
}

/**
 * Runs the same `count()` aggregate the app runs, under a deadline.
 *
 * The aggregate rather than a stored field is the whole point: climb detail's
 * "N completed" is `count(splitBuckets/0/entries)` at runtime, and reading the
 * summary's `completedCount` instead is precisely the discrepancy that cost the
 * captain two days.
 * @param {object} query Collection or query to count.
 * @param {string} description What the call is doing.
 * @return {Promise<number>} The match count.
 */
async function countOf(query, description) {
  const snapshot = await call(() => query.count().get(), description);
  const count = snapshot.data()?.count;
  if (!Number.isInteger(count) && typeof count !== "number") {
    throw new Error(`${description} returned no usable count`);
  }
  return Number(count);
}

function call(start, description) {
  return withRetry(start, {
    description,
    timeoutMs: CALL_TIMEOUT_MS,
    attempts: CALL_ATTEMPTS,
  });
}

/**
 * Runs one measurement, recording a failure rather than letting it read as zero.
 * @param {object[]} readFailures Accumulator.
 * @param {string} what Which measurement.
 * @param {() => Promise<T>} read The measurement.
 * @return {Promise<?T>} The measurement, or null when it did not complete.
 * @template T
 */
async function attempt(readFailures, what, read) {
  try {
    return await read();
  } catch (error) {
    readFailures.push({what, message: error.message});
    return null;
  }
}

function summaryOf(snapshot) {
  if (!snapshot || !snapshot.exists) {
    return emptySummary();
  }
  const data = snapshot.data() ?? {};
  return {
    exists: true,
    completedCount: numberValue(data.completedCount),
    totalClimbers: numberValue(data.totalClimbers),
    bucketIntervalSeconds: numberValue(data.bucketIntervalSeconds) ?? 10,
    seedBucketCount: numberValue(data.seedBucketCount),
    seededAttemptCount: numberValue(data.seededAttemptCount),
    source: stringValue(data.source),
    firstAscentUserId: stringValue(data.firstAscentUserId),
    updatedAt: millisecondsValue(data.updatedAt),
  };
}

function emptySummary() {
  return {
    exists: false,
    completedCount: null,
    totalClimbers: null,
    bucketIntervalSeconds: 10,
    seedBucketCount: null,
    seededAttemptCount: null,
    source: null,
    firstAscentUserId: null,
    updatedAt: null,
  };
}

/**
 * Loads the climb catalog the way a device on this project would.
 *
 * `HostedClimbCatalogRepository` fetches `https://<projectId>.web.app/climbs/
 * manifest.json` and then whatever `catalogPath` names, and only falls back to
 * the bundled `climbs.json` when it has neither a cache nor a network answer. So
 * the hosted pair is what decides which climbs exist on the globe for this
 * environment, and reading the committed file instead would check a catalog no
 * device is looking at.
 *
 * A failed fetch is recorded and the bundled bootstrap is used, so the rest of
 * the run still reports - but `catalog.source` says `bootstrap`, and the catalog
 * check fails on it rather than quietly grading a different climb list.
 * @param {string} projectId Firebase project whose hosting the app would read.
 * @param {object[]} readFailures Accumulator for reads that did not complete.
 * @return {Promise<object>} The catalog and where it came from.
 */
async function loadClimbCatalog(projectId, readFailures) {
  const baseURL = `https://${projectId}.web.app`;
  try {
    const manifest = await fetchJSON(`${baseURL}/climbs/manifest.json`);
    const catalogPath = String(manifest.catalogPath ?? "").replace(/^\/+/u, "");
    if (catalogPath.length === 0) {
      throw new Error("the hosted manifest names no catalogPath");
    }
    const climbs = await fetchJSON(`${baseURL}/${catalogPath}`);
    if (!Array.isArray(climbs)) {
      throw new Error(`${catalogPath} does not hold a climb array`);
    }
    return {
      source: "hosted",
      url: `${baseURL}/${catalogPath}`,
      catalogVersion: manifest.catalogVersion ?? null,
      featuredClimbId: manifest.featuredClimbId ?? null,
      climbs,
      failure: null,
    };
  } catch (error) {
    readFailures.push({what: "catalog", message: `${baseURL}: ${error.message}`});
    return {
      source: "bootstrap",
      url: CLIMB_CATALOG_PATH,
      catalogVersion: 0,
      featuredClimbId: "empire-state-building",
      climbs: readBundledClimbCatalog(),
      failure: error.message,
    };
  }
}

function readBundledClimbCatalog() {
  const parsed = JSON.parse(readFileSync(CLIMB_CATALOG_PATH, "utf-8"));
  const climbs = Array.isArray(parsed) ? parsed : parsed.climbs;
  if (!Array.isArray(climbs)) {
    throw new Error(`${CLIMB_CATALOG_PATH} does not hold a climb array.`);
  }
  return climbs;
}

/**
 * Fetches one JSON document under the same deadline the app gives it.
 *
 * `HostedClimbCatalogRepository` sets `timeoutInterval = 15` and ignores the
 * local cache; both matter, because a check answering from a cache is a check
 * about this machine rather than about the environment.
 * @param {string} url Absolute URL.
 * @return {Promise<any>} Parsed JSON.
 */
async function fetchJSON(url) {
  const response = await fetch(url, {
    cache: "no-store",
    signal: AbortSignal.timeout(CATALOG_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new Error(`${url} answered ${response.status}`);
  }
  return response.json();
}

/**
 * The capture build's marketing version, read from the Xcode project.
 *
 * A routine template published with a `minAppVersion` above it is invisible on
 * the device doing the filming while being perfectly present in Firestore, so
 * the check needs the same number the device would compare against.
 * @return {string} Marketing version, or "0" when it cannot be read.
 */
function marketingVersion() {
  try {
    const project = readFileSync(
      resolve(REPO_ROOT, "AscendApp.xcodeproj/project.pbxproj"),
      "utf-8"
    );
    return /MARKETING_VERSION = ([0-9.]+);/u.exec(project)?.[1] ?? "0";
  } catch {
    return "0";
  }
}

function daysBetween(earlierMs, laterMs) {
  return Math.floor((laterMs - earlierMs) / 86_400_000);
}

if (isEntrypoint(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    console.error(
      "\nThis is a failed read, not an empty environment. Nothing has been " +
      "established about what this project holds."
    );
    process.exit(2);
  });
}
