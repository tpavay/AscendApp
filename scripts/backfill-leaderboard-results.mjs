#!/usr/bin/env node

/**
 * Rebuilds `leaderboard_results` for periods finalized before results existed.
 *
 * finalizeLeaderboardAchievements writes `leaderboard_results/{id}` and its
 * `placings` in the same commit as a period's awards, but every period it
 * finalized before champion recognition shipped has awards and no result - so
 * no past board, and nobody reigning. This rebuilds those results from the
 * closed-period `leaderboard_stats` rows that retention keeps for exactly this
 * kind of reason (`ascend-leaderboards`, Publication & sync).
 *
 * It ranks with the finalizer's own code, imported from the compiled function
 * bundle rather than reimplemented: the award query, the per-climber dedupe,
 * the competition ranking, the period summary and the result composition are
 * all `functions/src/leaderboardResults.ts`. Build it first:
 *   cd functions && npm run build
 *
 * A rebuilt board is only as good as the rows still standing, and a row can
 * have moved since the period was frozen - a backfill repaired it, or its owner
 * deleted their account and took the row and the award with them. The awards
 * are the permanent record of who finished where, so every climber in the
 * period is checked against
 * `users/{uid}/achievements/global_steps_{timeFrame}_{periodKey}` and the
 * award decides: an awarded climber is placed at the AWARDED rank, and a
 * climber the recomputed board ranks 1-100 who holds no award is not placed.
 * Every disagreement is printed. A champion whose account is gone cannot be
 * rebuilt at all - their row and their award are both deleted - so that period
 * is reported with nobody at #1 rather than promoting the runner-up.
 *
 * Every rebuilt result says so: `source: "backfill"`, `reconstructed: true`.
 * The champion push never fires for one.
 *
 * Dry run is the default and writes nothing. `--commit` writes, placings
 * first and the result document last, so a result that exists always has its
 * placings behind it. It is idempotent: a period that already has a result is
 * skipped, whoever wrote it.
 *
 * Usage:
 *   node scripts/backfill-leaderboard-results.mjs --env dev
 *   node scripts/backfill-leaderboard-results.mjs --env dev --commit
 *   node scripts/backfill-leaderboard-results.mjs --env staging --period weekly_2026-W38
 *   node scripts/backfill-leaderboard-results.mjs --env prod --confirm-production ascend-prod-9c8f2
 *   node scripts/backfill-leaderboard-results.mjs --env prod --confirm-production ascend-prod-9c8f2 --commit
 *
 * Prerequisites:
 *   cd functions && npm run build
 *   cd scripts && npm install
 *   gcloud auth application-default login
 *
 * The planning half is exported so scripts/test can run it against fixtures
 * without a Firestore or a functions build; the run itself starts only when
 * this file is the entrypoint.
 */

import {createRequire} from "node:module";
import {existsSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {
  createBatchWriter,
  createProgressReporter,
  runPool,
  withRetry,
} from "./lib/firestore-bulk.mjs";
import {isEntrypoint} from "./lib/is-entrypoint.mjs";

export const PRODUCTION_PROJECT_ID = "ascend-prod-9c8f2";
export const ENVIRONMENTS = Object.freeze({
  dev: "ascend-f2e4f",
  staging: "ascend-staging-fa7d5",
  prod: PRODUCTION_PROJECT_ID,
});
export const FINALIZED_TIME_FRAMES = Object.freeze([
  "weekly",
  "monthly",
  "yearly",
]);

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const FUNCTIONS_DIR = resolve(SCRIPT_DIR, "..", "functions");
const RESULTS_MODULE_PATH = resolve(
  FUNCTIONS_DIR,
  "lib/src/leaderboardResults.js"
);
const PERIOD_MODULE_PATH = resolve(
  FUNCTIONS_DIR,
  "lib/src/leaderboardPeriod.js"
);
const ACHIEVEMENT_READ_CONCURRENCY = 16;

if (isEntrypoint(import.meta.url)) {
  try {
    await main();
  } catch (error) {
    console.error(error?.message ?? error);
    process.exitCode = 1;
  }
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printUsage();
    return;
  }

  const target = resolveTarget(args);
  const {admin, periodModule, results} = loadFinalizerModules();
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: target.projectId,
  });
  const db = admin.firestore();

  console.log(`Target: ${target.label}`);
  console.log(`Mode: ${args.commit ? "COMMIT" : "dry run (pass --commit to write)"}`);

  const periods = await readFinalizedPeriods(db, args.period);
  console.log(`Finalized periods: ${periods.length}`);

  const outcomes = [];
  for (const {id, data} of periods) {
    try {
      outcomes.push(await backfillPeriod({
        db,
        id,
        data,
        periodModule,
        results,
        commit: args.commit,
      }));
    } catch (error) {
      outcomes.push({resultId: id, status: "failed", error: error.message});
      console.error(`  ${id}: FAILED - ${error.message}`);
    }
  }

  console.log("");
  console.log(renderSummary(outcomes, {commit: args.commit}));
  if (outcomes.some((outcome) => outcome.status === "failed")) {
    process.exitCode = 1;
  }
}

/**
 * Parses command-line arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Parsed arguments.
 */
export function parseArgs(argv) {
  const parsed = {
    env: null,
    confirmProduction: null,
    commit: false,
    period: null,
    help: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--env":
        parsed.env = requireValue(argv, ++index, "--env");
        break;
      case "--confirm-production":
        parsed.confirmProduction = requireValue(argv, ++index, "--confirm-production");
        break;
      case "--period":
        parsed.period = requireValue(argv, ++index, "--period");
        break;
      case "--commit":
        parsed.commit = true;
        break;
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  return parsed;
}

/**
 * The environment a run targets. `--env` is required, and production also
 * needs `--confirm-production` spelling out its project id - for a dry run too,
 * because a dry run still reads real climbers' standings.
 * @param {{env: string | null, confirmProduction: string | null}} args Parsed
 *   arguments.
 * @return {{projectId: string, env: string, label: string}} Resolved target.
 */
export function resolveTarget({env = null, confirmProduction = null} = {}) {
  if (env === null) {
    throw new Error(
      "No target. Pass --env dev, --env staging, or --env prod " +
        `--confirm-production ${PRODUCTION_PROJECT_ID}.`
    );
  }
  if (!Object.hasOwn(ENVIRONMENTS, env)) {
    throw new Error(
      `Unknown environment "${env}". Use one of: ${Object.keys(ENVIRONMENTS).join(", ")}.`
    );
  }

  const projectId = ENVIRONMENTS[env];
  if (projectId === PRODUCTION_PROJECT_ID && confirmProduction !== projectId) {
    throw new Error(
      `Production requires --confirm-production ${PRODUCTION_PROJECT_ID}.`
    );
  }

  return {projectId, env, label: `${projectId} (${env})`};
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function printUsage() {
  console.log(`
Usage:
  node scripts/backfill-leaderboard-results.mjs --env dev
  node scripts/backfill-leaderboard-results.mjs --env dev --commit
  node scripts/backfill-leaderboard-results.mjs --env staging --period weekly_2026-W38
  node scripts/backfill-leaderboard-results.mjs --env prod --confirm-production ${PRODUCTION_PROJECT_ID}
  node scripts/backfill-leaderboard-results.mjs --env prod --confirm-production ${PRODUCTION_PROJECT_ID} --commit

Flags:
  --env <dev|staging|prod>     Required.
  --confirm-production <id>    Required with --env prod, dry run included.
  --commit                     Write. Without it nothing is written.
  --period <timeFrame_key>     Only this period, e.g. weekly_2026-W38.

Rebuilds leaderboard_results/{timeFrame}_{periodKey} and its placings for every
leaderboard_periods document with status "finalized" and no result yet, ranked
by the finalizer's own compiled code (cd functions && npm run build first).
Every climber is checked against their award for the period and the award
decides: an awarded climber is placed at the awarded rank, and a climber with
no award is not placed. Every disagreement is printed. Results are marked
source "backfill", reconstructed true, and never send a champion push.
`);
}

/**
 * Loads the finalizer's compiled modules and the firebase-admin instance they
 * call. The bundle resolves firebase-admin inside functions/, so the app has to
 * be initialized on that module instance or the first read fails.
 * @return {{admin: object, periodModule: object, results: object}} Modules.
 */
function loadFinalizerModules() {
  if (!existsSync(RESULTS_MODULE_PATH)) {
    throw new Error("functions/lib is not built. Run: cd functions && npm run build");
  }
  const requireFromFunctions = createRequire(resolve(FUNCTIONS_DIR, "package.json"));
  return {
    admin: requireFromFunctions("firebase-admin"),
    periodModule: requireFromFunctions(PERIOD_MODULE_PATH),
    results: requireFromFunctions(RESULTS_MODULE_PATH),
  };
}

/**
 * Every finalized period document, optionally narrowed to one id.
 * @param {object} db Firestore instance.
 * @param {string | null} onlyId A single period id, or null for all.
 * @return {Promise<{id: string, data: object}[]>} Period documents, sorted.
 */
async function readFinalizedPeriods(db, onlyId) {
  const snapshot = await withRetry(
    () => db.collection("leaderboard_periods").where("status", "==", "finalized").get(),
    {description: "read finalized leaderboard_periods"}
  );
  return snapshot.docs
    .map((document) => ({id: document.id, data: document.data()}))
    .filter(({id}) => onlyId === null || id === onlyId)
    .sort((lhs, rhs) => lhs.id.localeCompare(rhs.id));
}

/**
 * Plans, prints and (with --commit) writes one period's result.
 * @param {object} options Run context.
 * @return {Promise<object>} What happened to the period.
 */
async function backfillPeriod({db, id, data, periodModule, results, commit}) {
  const resolved = closedPeriodFromDocument(id, data, periodModule);
  if (resolved.error) {
    console.log(`  ${id}: SKIPPED - ${resolved.error}`);
    return {resultId: id, status: "skipped", reason: resolved.error};
  }
  const period = resolved.period;
  const resultRef = db.collection(results.LEADERBOARD_RESULTS_COLLECTION).doc(id);

  const existing = await withRetry(() => resultRef.get(), {
    description: `read leaderboard_results/${id}`,
  });
  if (existing.exists) {
    console.log(`  ${id}: already has a result (source ${existing.get("source") ?? "unknown"})`);
    return {resultId: id, status: "exists"};
  }

  const awardRows = await withRetry(() => results.readAwardStandings(db, period), {
    description: `award query for ${id}`,
  });
  const periodRows = await withRetry(() => results.readPeriodStandings(db, period), {
    description: `period read for ${id}`,
  });
  const computed = results.rankStandings(awardRows, results.TOP_RANK_LIMIT);
  const everyone = results.rankStandings(periodRows);
  const awards = await readAwards(db, period, everyone.map((row) => row.userId));
  const {placed, mismatches} = reconcileWithAwards({computed, everyone, awards});
  const summary = results.summarizePeriodStandings(periodRows);
  const outcome = results.buildLeaderboardResult({
    period,
    placed,
    summary,
    source: "backfill",
  });

  const plan = describePeriodPlan({
    resultId: id,
    climberCount: summary.climberCount,
    championUserIds: outcome.result.championUserIds,
    podiumUserIds: outcome.result.podiumUserIds,
    placingCount: outcome.placings.length,
    mostClimbs: summary.mostClimbs,
    mismatches,
  });
  for (const line of plan) {
    console.log(line);
  }

  if (!commit) {
    return {resultId: id, status: "planned", mismatches: mismatches.length};
  }

  await writeResult({db, resultRef, outcome, results});
  return {resultId: id, status: "written", mismatches: mismatches.length};
}

/**
 * Names the closed window a finalized period document describes, refusing one
 * whose stored fields do not round-trip through the finalizer's own period
 * derivation - rebuilding a result under a window the document does not claim
 * would crown the wrong board.
 * @param {string} id Period document id.
 * @param {object} data Period document fields.
 * @param {object} periodModule Compiled leaderboardPeriod module.
 * @return {{period?: object, error?: string}} The period, or why not.
 */
export function closedPeriodFromDocument(id, data, periodModule) {
  const timeFrame = data?.timeFrame;
  if (!FINALIZED_TIME_FRAMES.includes(timeFrame)) {
    return {error: `unrecognised timeFrame ${JSON.stringify(timeFrame)}`};
  }
  const startAt = dateValue(data.periodStartAt);
  const endAt = dateValue(data.periodEndAt);
  if (startAt === null || endAt === null) {
    return {error: "missing periodStartAt or periodEndAt"};
  }

  const derived = periodModule.currentPeriod(timeFrame, startAt);
  if (
    derived.key !== data.periodKey ||
    derived.startAt.getTime() !== startAt.getTime() ||
    derived.endAt?.getTime() !== endAt.getTime() ||
    id !== `${timeFrame}_${derived.key}`
  ) {
    return {error: `stored window does not match its id (derived ${timeFrame}_${derived.key})`};
  }

  return {period: {timeFrame, key: derived.key, startAt, endAt}};
}

/**
 * The award rank each climber holds for the period, or null for no award.
 * @param {object} db Firestore instance.
 * @param {object} period The closed window.
 * @param {string[]} userIds Every climber in the period.
 * @return {Promise<Map<string, number | null>>} uid to awarded rank.
 */
async function readAwards(db, period, userIds) {
  const achievementId = `global_steps_${period.timeFrame}_${period.key}`;
  const awards = new Map();
  const progress = createProgressReporter({
    label: `awards ${period.timeFrame}_${period.key}`,
    total: userIds.length,
    unit: "climbers",
    quiet: userIds.length < 500,
  });
  try {
    await runPool(userIds, ACHIEVEMENT_READ_CONCURRENCY, async (userId) => {
      progress.assertAlive();
      const snapshot = await withRetry(
        () => db.doc(`users/${userId}/achievements/${achievementId}`).get(),
        {
          description: `read ${userId}'s ${achievementId}`,
          onRetry: () => progress.retried(),
        }
      );
      awards.set(userId, snapshot.exists ? awardedRank(snapshot.get("rank")) : null);
      progress.advance();
    });
  } finally {
    progress.finish();
  }
  return awards;
}

function awardedRank(value) {
  return Number.isInteger(value) && value >= 1 ? value : null;
}

/**
 * Decides who is placed and at what rank, deferring to the awards minted when
 * the period was frozen.
 *
 * - A climber the finalizer's ranking places in the top 100 whose award agrees
 *   is placed as ranked.
 * - Where their award names a different rank, the award's rank is used.
 * - Where they hold no award, they are NOT placed: the finalizer did not rank
 *   them in the top 100 when it froze the period, so a rebuilt board that
 *   placed them would slot an unawarded finish in among awarded ones - which
 *   is exactly what deleting an account ahead of them would otherwise do.
 * - A climber ranked outside the top 100 who DOES hold an award is placed at
 *   the awarded rank: their row moved after the period was frozen.
 *
 * Every one of those except the first is reported.
 * @param {object} input Ranked rows and awards.
 * @param {object[]} input.computed Rows the finalizer's ranking places 1-100.
 * @param {object[]} input.everyone Every row in the period, ranked.
 * @param {Map<string, number | null>} input.awards uid to awarded rank.
 * @return {{placed: object[], mismatches: object[]}} Placed rows, disagreements.
 */
export function reconcileWithAwards({computed, everyone, awards}) {
  const placed = [];
  const mismatches = [];
  const placedUserIds = new Set();

  for (const row of computed) {
    placedUserIds.add(row.userId);
    const awarded = awards.get(row.userId) ?? null;
    if (awarded === null) {
      mismatches.push({userId: row.userId, computedRank: row.rank, awardedRank: null});
    } else if (awarded !== row.rank) {
      mismatches.push({userId: row.userId, computedRank: row.rank, awardedRank: awarded});
      placed.push({...row, rank: awarded});
    } else {
      placed.push(row);
    }
  }

  for (const row of everyone) {
    if (placedUserIds.has(row.userId)) continue;
    const awarded = awards.get(row.userId) ?? null;
    if (awarded === null) continue;
    placedUserIds.add(row.userId);
    mismatches.push({userId: row.userId, computedRank: row.rank, awardedRank: awarded});
    placed.push({...row, rank: awarded});
  }

  return {placed, mismatches};
}

/**
 * A uid shortened for a console line: enough to tell climbers apart, not
 * enough to paste anywhere.
 * @param {string} userId Firebase Auth uid.
 * @return {string} The first four characters.
 */
export function uidPrefix(userId) {
  return String(userId).slice(0, 4);
}

/**
 * The dry-run lines for one period.
 * @param {object} plan What would be written.
 * @return {string[]} Lines to print.
 */
export function describePeriodPlan({
  resultId,
  climberCount,
  championUserIds,
  podiumUserIds,
  placingCount,
  mostClimbs,
  mismatches,
}) {
  const champions = championUserIds.length === 0 ?
    "none" :
    championUserIds.map(uidPrefix).join(", ");
  const lines = [
    `  ${resultId}: ${climberCount} climber(s), champion(s) [${champions}], ` +
      `podium ${podiumUserIds.length}, ${placingCount} placing(s), ` +
      `most climbs ${mostClimbs === null ? "none" : `${mostClimbs.count} [${mostClimbs.userIds.map(uidPrefix).join(", ")}]`}, ` +
      `award ranks ${mismatches.length === 0 ? "agree" : `DISAGREE (${mismatches.length})`}`,
  ];
  for (const mismatch of mismatches) {
    lines.push(
      mismatch.awardedRank === null ?
        `    ${uidPrefix(mismatch.userId)}: recomputed #${mismatch.computedRank}, no award record - not placed` :
        `    ${uidPrefix(mismatch.userId)}: recomputed #${mismatch.computedRank}, awarded #${mismatch.awardedRank} - using #${mismatch.awardedRank}`
    );
  }
  if (championUserIds.length === 0 && climberCount > 0) {
    lines.push("    nobody holds #1 - the champion's row and award are gone (deleted account?)");
  }
  return lines;
}

/**
 * The run's closing summary.
 * @param {object[]} outcomes One per period.
 * @param {{commit: boolean}} options Run mode.
 * @return {string} Summary text.
 */
export function renderSummary(outcomes, {commit}) {
  const count = (status) => outcomes.filter((outcome) => outcome.status === status).length;
  const disagreeing = outcomes.filter((outcome) => (outcome.mismatches ?? 0) > 0).length;
  return [
    `Periods already holding a result: ${count("exists")}`,
    commit ?
      `Results written: ${count("written")}` :
      `Results that would be written: ${count("planned")}`,
    `Periods whose award ranks disagree with the recomputed board: ${disagreeing}`,
    `Skipped (malformed period document): ${count("skipped")}`,
    `Failed: ${count("failed")}`,
    commit ? "" : "Dry run: nothing was written. Pass --commit to write.",
  ].filter((line) => line !== "").join("\n");
}

/**
 * Writes the placings, then the result - never the other way round.
 * @param {object} options Write context.
 * @return {Promise<void>} Resolves once both phases have committed.
 */
async function writeResult({db, resultRef, outcome, results}) {
  const progress = createProgressReporter({
    label: `write ${outcome.resultId}`,
    total: outcome.placings.length + 1,
    unit: "docs",
  });
  try {
    const writer = createBatchWriter(db, {progress});
    for (const placing of outcome.placings) {
      writer.set(
        resultRef.collection(results.LEADERBOARD_PLACINGS_COLLECTION).doc(placing.userId),
        placing.data
      );
    }
    await writer.flush();

    // Re-checked immediately before the one write that makes the result
    // visible, so a result that appeared while this ran is never replaced.
    const existing = await withRetry(() => resultRef.get(), {
      description: `re-read ${resultRef.path}`,
    });
    if (existing.exists) {
      throw new Error(`${resultRef.path} appeared during the run; left untouched`);
    }
    writer.set(resultRef, outcome.result);
    await writer.drain();
  } finally {
    progress.finish();
  }
}

function dateValue(value) {
  if (value instanceof Date) return value;
  if (value && typeof value.toDate === "function") return value.toDate();
  return null;
}
