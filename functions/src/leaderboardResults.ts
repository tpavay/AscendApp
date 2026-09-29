/**
 * The frozen final result of a closed weekly, monthly or yearly Steps board.
 *
 * `docs/champion-recognition.md` owns the data contract this file writes:
 * `leaderboard_results/{timeFrame}_{periodKey}` and its `placings/{uid}`
 * subcollection. The rank model itself - what a rank counts and how ties
 * resolve - stays owned by `ascend-leaderboards`.
 *
 * This is the one place a closed board is read, ranked and composed into a
 * result. finalizeLeaderboardAchievements calls it in the same batch that mints
 * the period's achievements, and scripts/backfill-leaderboard-results.mjs
 * imports the compiled module to rebuild results for periods finalized before
 * it existed. Two copies of "who won that week" would become two answers.
 *
 * Two reads, on purpose:
 *
 * - `readAwardStandings` is the award query exactly as the finalizer has always
 *   run it: the top 250 rows by steps, deduplicated per climber. Ranks 1-100
 *   are awarded from it, so the placings frozen beside those awards have to
 *   come from the same rows or the frozen board and the achievement records
 *   could disagree.
 * - `readPeriodStandings` pages every row in the period, because the climber
 *   count, the community totals and the most-climbs leader describe everybody
 *   who climbed, not the 250 the award query happens to read.
 */

import * as admin from "firebase-admin";
import {
  ClosedLeaderboardPeriod,
  FinalizedTimeFrame,
} from "./leaderboardPeriod.js";
import {
  ANONYMOUS_CLIMBER_NAME,
  PUBLIC_IDENTITY_POLICY_VERSION,
  PUBLIC_IDENTITY_STATE_DELETED,
  PUBLIC_IDENTITY_STATE_PENDING,
  PUBLIC_IDENTITY_STATE_PUBLISHED,
} from "./publicIdentity.js";

export const LEADERBOARD_RESULTS_COLLECTION = "leaderboard_results";
export const LEADERBOARD_PLACINGS_COLLECTION = "placings";
export const LEADERBOARD_RESULT_SCHEMA_VERSION = 1;
export const LEADERBOARD_PLACING_SCHEMA_VERSION = 1;

/** Ranks at or above this are awarded, and frozen as placings. */
export const TOP_RANK_LIMIT = 100;
/** Rows the award query reads. Unchanged since awards were first minted. */
export const AWARD_QUERY_LIMIT = 250;
/** The most-climbs leaders a result names when several share the count. */
export const MOST_CLIMBS_USER_LIMIT = 10;
/** Rows per page when every row of a period is read. */
export const PERIOD_STANDINGS_PAGE_SIZE = 500;
/**
 * Pages before a period read gives up. 100,000 climbers in one period is far
 * past anything Ascend holds; reaching it throws rather than freezing a
 * community total that silently stopped counting.
 */
export const PERIOD_STANDINGS_MAX_PAGES = 200;

const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";

/**
 * The stats-row fields a period read needs: the ranking inputs, the community
 * totals, and the identity a most-climbs leader's placing is written with.
 */
const PERIOD_STANDING_FIELDS = [
  "userId",
  "totalSteps",
  "totalWorkouts",
  "totalFloors",
  "lastUpdated",
  "displayName",
  "photoURL",
  "identityPolicyVersion",
  "identityState",
  "identityChangedAt",
  "isSynthetic",
] as const;

export type LeaderboardResultSource = "leaderboard_finalizer" | "backfill";

/** The identity fields a placing carries, as a stats row carries them. */
export interface PlacingIdentity {
  displayName: string;
  photoURL: string;
  identityPolicyVersion: number;
  identityState: string;
  identityChangedAt: admin.firestore.Timestamp | null;
  isSynthetic: boolean;
}

/** One climber's row on a closed board. */
export interface StandingRow {
  documentId: string;
  userId: string;
  totalSteps: number;
  totalWorkouts: number;
  totalFloors: number;
  lastUpdated: Date;
  identity: PlacingIdentity;
}

export interface RankedStanding extends StandingRow {
  rank: number;
}

export interface CommunityTotals {
  climbers: number;
  climbs: number;
  steps: number;
  floors: number;
}

export interface MostClimbs {
  count: number;
  userIds: string[];
}

/** What every row of a period adds up to. */
export interface PeriodStandingSummary {
  climberCount: number;
  community: CommunityTotals;
  mostClimbs: MostClimbs | null;
  /** The rows behind `mostClimbs.userIds`, carrying their full-board rank. */
  mostClimbsLeaders: RankedStanding[];
}

export interface LeaderboardResultWrite {
  resultId: string;
  result: Record<string, unknown>;
  placings: {userId: string; data: Record<string, unknown>}[];
}

/**
 * The result document id, which is also the period document id.
 * @param {FinalizedTimeFrame} timeFrame The board's window.
 * @param {string} periodKey The closed period's key.
 * @return {string} `{timeFrame}_{periodKey}`.
 */
export function leaderboardResultId(
  timeFrame: FinalizedTimeFrame,
  periodKey: string
): string {
  return `${timeFrame}_${periodKey}`;
}

/**
 * Parses one stats row, or null when it cannot stand on the Steps board.
 *
 * A row with no owner or no steps is not ranked, so it is not counted anywhere
 * in a result either: the climber count, the community totals and the
 * most-climbs leader all describe the same population the board ranks.
 * @param {string} documentId The leaderboard_stats document id.
 * @param {Record<string, unknown>} data Stored fields.
 * @return {StandingRow | null} The row, or null.
 */
export function standingRowFromData(
  documentId: string,
  data: Record<string, unknown>
): StandingRow | null {
  const userId = stringValue(data.userId);
  const totalSteps = numberValue(data.totalSteps);
  if (!userId || totalSteps <= 0) {
    return null;
  }

  return {
    documentId,
    userId,
    totalSteps,
    totalWorkouts: numberValue(data.totalWorkouts),
    totalFloors: numberValue(data.totalFloors),
    lastUpdated: timestampDate(data.lastUpdated) ?? new Date(0),
    identity: placingIdentity(data),
  };
}

/**
 * Keeps `row` as its climber's row unless one already kept is at least as
 * recently updated - the one rule every reader of a window's rows resolves a
 * climber's duplicate rows by, so the recap and the frozen result agree.
 * @param {Map<string, T>} byUser Rows kept so far, by climber.
 * @param {T} row The row just read.
 * @template T
 */
export function keepNewestRow<T extends {userId: string; lastUpdated: Date}>(
  byUser: Map<string, T>,
  row: T
): void {
  const existing = byUser.get(row.userId);
  if (!existing || row.lastUpdated > existing.lastUpdated) {
    byUser.set(row.userId, row);
  }
}

/**
 * Keeps one row per climber - the most recently updated - in board order.
 *
 * A climber can hold two rows for one window (a legacy `{uid}_{timeFrame}`
 * document beside the canonical one), and the award query has always resolved
 * that by newest `lastUpdated`, keeping the first row read on a tie. Board
 * order is steps descending with the uid as a stable tiebreak; the uid never
 * influences a rank (`rankStandings`).
 * @param {StandingRow[]} rows Rows in query order.
 * @return {StandingRow[]} One row per climber, in board order.
 */
export function dedupeStandings(rows: StandingRow[]): StandingRow[] {
  const byUser = new Map<string, StandingRow>();
  for (const row of rows) {
    keepNewestRow(byUser, row);
  }

  return [...byUser.values()].sort((lhs, rhs) => {
    if (lhs.totalSteps !== rhs.totalSteps) {
      return rhs.totalSteps - lhs.totalSteps;
    }
    return lhs.userId.localeCompare(rhs.userId);
  });
}

/**
 * Standard competition ranking over steps ("1, 2, 2, 4").
 * @param {StandingRow[]} rows Deduplicated rows in board order.
 * @param {number} rankLimit Highest rank to keep.
 * @return {RankedStanding[]} Rows ranked at or above the limit, board order.
 */
export function rankStandings(
  rows: StandingRow[],
  rankLimit = Number.POSITIVE_INFINITY
): RankedStanding[] {
  const ranked: RankedStanding[] = [];
  let previousSteps: number | null = null;
  let currentRank = 0;

  rows.forEach((row, index) => {
    if (previousSteps !== row.totalSteps) {
      currentRank = index + 1;
      previousSteps = row.totalSteps;
    }

    if (currentRank <= rankLimit) {
      ranked.push({...row, rank: currentRank});
    }
  });

  return ranked;
}

/**
 * Sums every climber in a period and names the most-climbs leaders.
 * @param {StandingRow[]} rows Every deduplicated row in the period.
 * @return {PeriodStandingSummary} Counts, totals, and leaders.
 */
export function summarizePeriodStandings(
  rows: StandingRow[]
): PeriodStandingSummary {
  const community: CommunityTotals = {
    climbers: rows.length,
    climbs: 0,
    steps: 0,
    floors: 0,
  };
  let mostClimbsCount = 0;
  for (const row of rows) {
    community.climbs += row.totalWorkouts;
    community.steps += row.totalSteps;
    community.floors += row.totalFloors;
    mostClimbsCount = Math.max(mostClimbsCount, row.totalWorkouts);
  }

  if (mostClimbsCount <= 0) {
    return {
      climberCount: rows.length,
      community,
      mostClimbs: null,
      mostClimbsLeaders: [],
    };
  }

  const leaders = rankStandings(rows)
    .filter((row) => row.totalWorkouts === mostClimbsCount)
    .slice(0, MOST_CLIMBS_USER_LIMIT);
  return {
    climberCount: rows.length,
    community,
    mostClimbs: {
      count: mostClimbsCount,
      userIds: leaders.map((row) => row.userId),
    },
    mostClimbsLeaders: leaders,
  };
}

/**
 * Orders ranked rows the way a board draws them: rank, then steps, then uid.
 * @param {RankedStanding[]} rows Ranked rows in any order.
 * @return {RankedStanding[]} A new array in board order.
 */
export function boardOrder(rows: RankedStanding[]): RankedStanding[] {
  return [...rows].sort((lhs, rhs) => {
    if (lhs.rank !== rhs.rank) {
      return lhs.rank - rhs.rank;
    }
    if (lhs.totalSteps !== rhs.totalSteps) {
      return rhs.totalSteps - lhs.totalSteps;
    }
    return lhs.userId.localeCompare(rhs.userId);
  });
}

/**
 * Composes the result document and its placings.
 *
 * `placed` is the awarded set: every climber ranked 1-100, with the rank their
 * achievement carries. Champions and the podium are read off those ranks, so a
 * backfill that corrects a rank to the one already awarded moves the crown with
 * it. A most-climbs leader outside that set is placed too, at their full-board
 * rank, because a past board names them.
 * @param {object} input What the result is built from.
 * @param {ClosedLeaderboardPeriod} input.period The closed window.
 * @param {RankedStanding[]} input.placed The awarded rows.
 * @param {PeriodStandingSummary} input.summary Every row's totals.
 * @param {LeaderboardResultSource} input.source Who wrote it.
 * @return {LeaderboardResultWrite} The documents to write.
 */
export function buildLeaderboardResult(input: {
  period: ClosedLeaderboardPeriod;
  placed: RankedStanding[];
  summary: PeriodStandingSummary;
  source: LeaderboardResultSource;
}): LeaderboardResultWrite {
  const {period, summary, source} = input;
  const placed = boardOrder(input.placed);
  const placedUserIds = new Set(placed.map((row) => row.userId));
  const extraLeaders = summary.mostClimbsLeaders.filter(
    (row) => !placedUserIds.has(row.userId)
  );
  const periodStartAt = admin.firestore.Timestamp.fromDate(period.startAt);

  const result: Record<string, unknown> = {
    schemaVersion: LEADERBOARD_RESULT_SCHEMA_VERSION,
    timeFrame: period.timeFrame,
    periodKey: period.key,
    periodStartAt,
    periodEndAt: admin.firestore.Timestamp.fromDate(period.endAt),
    metric: "steps",
    climberCount: summary.climberCount,
    championUserIds: placed
      .filter((row) => row.rank === 1)
      .map((row) => row.userId),
    podiumUserIds: placed
      .filter((row) => row.rank <= 3)
      .map((row) => row.userId),
    mostClimbs: summary.mostClimbs === null ? null : {
      count: summary.mostClimbs.count,
      userIds: [...summary.mostClimbs.userIds],
    },
    community: {...summary.community},
    finalizedAt: admin.firestore.FieldValue.serverTimestamp(),
    source,
    reconstructed: source === "backfill",
  };

  const placings = [...placed, ...extraLeaders].map((row) => ({
    userId: row.userId,
    data: {
      schemaVersion: LEADERBOARD_PLACING_SCHEMA_VERSION,
      userId: row.userId,
      timeFrame: period.timeFrame,
      periodKey: period.key,
      periodStartAt,
      rank: row.rank,
      totalSteps: row.totalSteps,
      totalWorkouts: row.totalWorkouts,
      displayName: row.identity.displayName,
      photoURL: row.identity.photoURL,
      identityPolicyVersion: row.identity.identityPolicyVersion,
      identityState: row.identity.identityState,
      identityChangedAt: row.identity.identityChangedAt,
      isSynthetic: row.identity.isSynthetic,
    },
  }));

  return {
    resultId: leaderboardResultId(period.timeFrame, period.key),
    result,
    placings,
  };
}

/**
 * The identity a placing is frozen with, copied from the stats row.
 *
 * Copied only when it is a whole identity the client will render - the current
 * policy version, a known state, and a change stamp behind a published name -
 * because a placing that fails the client's parse is a missing row on a past
 * board. Anything else is written as the pending anonymous identity, which is
 * exactly what identity propagation is allowed to overwrite the next time the
 * climber's public profile changes.
 * @param {Record<string, unknown>} data Stats row fields.
 * @return {PlacingIdentity} The placing's identity.
 */
export function placingIdentity(
  data: Record<string, unknown>
): PlacingIdentity {
  const isSynthetic = data.isSynthetic === true;
  const state = data.identityState;
  const changedAt = data.identityChangedAt instanceof
    admin.firestore.Timestamp ?
    data.identityChangedAt :
    null;
  const knownState = state === PUBLIC_IDENTITY_STATE_PUBLISHED ||
    state === PUBLIC_IDENTITY_STATE_PENDING ||
    state === PUBLIC_IDENTITY_STATE_DELETED;

  if (
    data.identityPolicyVersion !== PUBLIC_IDENTITY_POLICY_VERSION ||
    !knownState ||
    (state === PUBLIC_IDENTITY_STATE_PUBLISHED && changedAt === null)
  ) {
    return {
      displayName: ANONYMOUS_CLIMBER_NAME,
      photoURL: "",
      identityPolicyVersion: PUBLIC_IDENTITY_POLICY_VERSION,
      identityState: PUBLIC_IDENTITY_STATE_PENDING,
      identityChangedAt: null,
      isSynthetic,
    };
  }

  return {
    displayName: typeof data.displayName === "string" ?
      data.displayName :
      ANONYMOUS_CLIMBER_NAME,
    photoURL: typeof data.photoURL === "string" ? data.photoURL : "",
    identityPolicyVersion: PUBLIC_IDENTITY_POLICY_VERSION,
    identityState: state as string,
    identityChangedAt: changedAt,
    isSynthetic,
  };
}

/**
 * The award query, exactly as the finalizer has always run it.
 * @param {admin.firestore.Firestore} db Firestore instance.
 * @param {ClosedLeaderboardPeriod} period The closed window.
 * @return {Promise<StandingRow[]>} Deduplicated rows in board order.
 */
export async function readAwardStandings(
  db: admin.firestore.Firestore,
  period: ClosedLeaderboardPeriod
): Promise<StandingRow[]> {
  const snapshot = await periodStandingsQuery(db, period)
    .limit(AWARD_QUERY_LIMIT)
    .get();

  return dedupeStandings(parsedRows(snapshot.docs));
}

/**
 * A period too large for the bounded standings scan. Deterministic - the
 * same period fails the same way on every run - unlike a transient read
 * failure, which a later run can simply retry.
 */
export class PeriodStandingsTruncatedError extends Error {
  /**
   * @param {string} message What was cut short.
   */
  constructor(message: string) {
    super(message);
    this.name = "PeriodStandingsTruncatedError";
  }
}

/**
 * Every row in a period, a bounded page at a time.
 *
 * Pages on the award query's own ordering and composite index, so the read
 * needs nothing new deployed, and projects to the fields a summary uses.
 * @param {admin.firestore.Firestore} db Firestore instance.
 * @param {ClosedLeaderboardPeriod} period The closed window.
 * @param {object} options Paging bounds.
 * @param {number} options.pageSize Rows per page.
 * @param {number} options.maxPages Pages before giving up.
 * @param {Function} options.readPage Reads one page; a caller that needs a
 *   deadline on every read (a local script) wraps each page, not the scan.
 * @return {Promise<StandingRow[]>} Deduplicated rows in board order.
 */
export async function readPeriodStandings(
  db: admin.firestore.Firestore,
  period: ClosedLeaderboardPeriod,
  options: {
    pageSize?: number;
    maxPages?: number;
    readPage?: (
      query: admin.firestore.Query
    ) => Promise<admin.firestore.QuerySnapshot>;
  } = {}
): Promise<StandingRow[]> {
  const pageSize = options.pageSize ?? PERIOD_STANDINGS_PAGE_SIZE;
  const maxPages = options.maxPages ?? PERIOD_STANDINGS_MAX_PAGES;
  const readPage = options.readPage ??
    ((query: admin.firestore.Query) => query.get());
  const query = periodStandingsQuery(db, period)
    .select(...PERIOD_STANDING_FIELDS)
    .limit(pageSize);

  const rows: StandingRow[] = [];
  let cursor: admin.firestore.QueryDocumentSnapshot | null = null;
  for (let page = 0; ; page += 1) {
    if (page >= maxPages) {
      throw new PeriodStandingsTruncatedError(
        `leaderboard_stats for ${period.timeFrame} ${period.key} exceeded ` +
          `${maxPages} pages of ${pageSize}; refusing to freeze a partial count`
      );
    }

    const snapshot: admin.firestore.QuerySnapshot = await readPage(
      cursor === null ? query : query.startAfter(cursor)
    );
    for (const row of parsedRows(snapshot.docs)) {
      rows.push(row);
    }
    if (snapshot.docs.length < pageSize) {
      break;
    }
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }

  return dedupeStandings(rows);
}

/**
 * The rows of one closed window, ordered as the award query orders them.
 * @param {admin.firestore.Firestore} db Firestore instance.
 * @param {ClosedLeaderboardPeriod} period The closed window.
 * @return {admin.firestore.Query} The ordered query.
 */
function periodStandingsQuery(
  db: admin.firestore.Firestore,
  period: ClosedLeaderboardPeriod
): admin.firestore.Query {
  return db
    .collection(LEADERBOARD_STATS_COLLECTION)
    .where("timeFrame", "==", period.timeFrame)
    .where(
      "periodStartAt",
      "==",
      admin.firestore.Timestamp.fromDate(period.startAt)
    )
    .orderBy("totalSteps", "desc");
}

/**
 * Parses query documents in query order, dropping rows that cannot rank.
 * @param {admin.firestore.QueryDocumentSnapshot[]} documents Query results.
 * @return {StandingRow[]} Parsed rows.
 */
function parsedRows(
  documents: admin.firestore.QueryDocumentSnapshot[]
): StandingRow[] {
  const rows: StandingRow[] = [];
  for (const document of documents) {
    const row = standingRowFromData(document.id, document.data());
    if (row !== null) {
      rows.push(row);
    }
  }
  return rows;
}

function timestampDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  return null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value :
    null;
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.trunc(value) :
    0;
}
