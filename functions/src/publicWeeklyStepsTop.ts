/**
 * The signed-out onboarding's weekly board: the three climbers on top of this
 * week's Steps board, readable before anyone has an account.
 *
 * `leaderboard_stats` is paid-reader content, so a climber still choosing
 * whether to sign in cannot read it, and should not be able to: it holds every
 * climber's totals. This projection is the deliberate, small exception - one
 * document, `public_weekly_steps_top/current`, carrying only the top three
 * rows' rank, public name, public photo and step total. No uid, no
 * demographics, no per-climb detail.
 *
 * It is derived here from the same rows the nightly finalizer ranks, with the
 * same de-duplication and the same competition ranking, so the board a visitor
 * sees is the board a member sees. A row whose public identity is not
 * `published` (still pending, or deleted with the account) is left out rather
 * than shown as "Anonymous Climber": the first screen a stranger sees of the
 * board is not where an unresolved handle belongs. Fewer than three eligible
 * climbers is fewer rows, never a placeholder.
 *
 * The client never writes it (`allow write: if false`), and the document is
 * rewritten on a short clock, so a climber who renames themselves or deletes
 * their account leaves it within minutes without a propagation job of its own.
 *
 * There is no Remote Config switch in front of this write on purpose: a Cloud
 * Function is redeployable, so the premise a kill switch exists for - an iOS
 * binary that cannot be rolled back - does not hold here
 * (docs/remote-config-kill-switches.md).
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {LeaderboardPeriod, currentPeriod} from "./leaderboardPeriod.js";
import {
  RankedStanding,
  StandingRow,
  dedupeStandings,
  rankStandings,
  standingRowFromData,
} from "./leaderboardResults.js";
import {PUBLIC_IDENTITY_STATE_PUBLISHED} from "./publicIdentity.js";

export const PUBLIC_WEEKLY_STEPS_TOP_COLLECTION = "public_weekly_steps_top";
export const PUBLIC_WEEKLY_STEPS_TOP_DOCUMENT_ID = "current";
export const PUBLIC_WEEKLY_STEPS_TOP_SCHEMA_VERSION = 1;
/** Rows the board shows. The design draws the podium, so three. */
export const PUBLIC_WEEKLY_STEPS_TOP_ROW_LIMIT = 3;
/**
 * How many rows are read to find the three that qualify. Rows that cannot be
 * shown (an unresolved identity, a duplicate legacy document) are skipped, so
 * the read is wider than the board; bounded so a week with thousands of
 * climbers is still one small query.
 */
export const PUBLIC_WEEKLY_STEPS_TOP_READ_LIMIT = 25;

const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";

/** One row of the public board. */
export interface PublicWeeklyStepsTopRow {
  rank: number;
  displayName: string;
  /** Empty when the climber has no photo. */
  photoURL: string;
  totalSteps: number;
}

/** The whole document, before timestamps are applied. */
export interface PublicWeeklyStepsTop {
  periodKey: string;
  periodStartAt: Date;
  periodEndAt: Date;
  rows: PublicWeeklyStepsTopRow[];
}

/**
 * Picks and ranks the rows the signed-out board shows.
 * @param {StandingRow[]} candidates The week's top rows in query order.
 * @param {LeaderboardPeriod} period The open weekly window.
 * @return {PublicWeeklyStepsTop} The document to publish.
 */
export function buildPublicWeeklyStepsTop(
  candidates: StandingRow[],
  period: LeaderboardPeriod
): PublicWeeklyStepsTop {
  // Rank before filtering: a climber hidden from this board still stands
  // between the others and the top, so hiding one never promotes anybody.
  const ranked = rankStandings(dedupeStandings(candidates));
  const rows = ranked
    .filter(isShowable)
    .slice(0, PUBLIC_WEEKLY_STEPS_TOP_ROW_LIMIT)
    .map((standing) => ({
      rank: standing.rank,
      displayName: standing.identity.displayName,
      photoURL: standing.identity.photoURL,
      totalSteps: standing.totalSteps,
    }));

  return {
    periodKey: period.key,
    periodStartAt: period.startAt,
    periodEndAt: period.endAt ?? period.startAt,
    rows,
  };
}

/**
 * Whether a standing may appear on the public board.
 * @param {RankedStanding} standing A ranked row.
 * @return {boolean} True when its public identity is published.
 */
function isShowable(standing: RankedStanding): boolean {
  return standing.identity.identityState === PUBLIC_IDENTITY_STATE_PUBLISHED &&
    standing.identity.displayName.trim().length > 0;
}

/** What the refresh needs from the database. */
export interface PublicWeeklyStepsTopStore {
  readTopRows(period: LeaderboardPeriod, limit: number):
    Promise<Array<{id: string; data: Record<string, unknown>}>>;
  readCurrent(): Promise<Record<string, unknown> | undefined>;
  write(projection: PublicWeeklyStepsTop, now: Date): Promise<void>;
}

/**
 * Rebuilds the document for the week `now` falls in, writing only when what a
 * visitor would see has changed.
 * @param {PublicWeeklyStepsTopStore} store Database access.
 * @param {Date} now The run instant.
 * @return {Promise<boolean>} True when the document was written.
 */
export async function refreshPublicWeeklyStepsTop(
  store: PublicWeeklyStepsTopStore,
  now: Date
): Promise<boolean> {
  const period = currentPeriod("weekly", now);
  const documents = await store.readTopRows(
    period,
    PUBLIC_WEEKLY_STEPS_TOP_READ_LIMIT
  );
  const candidates: StandingRow[] = [];
  for (const document of documents) {
    const row = standingRowFromData(document.id, document.data);
    if (row !== null) {
      candidates.push(row);
    }
  }

  const projection = buildPublicWeeklyStepsTop(candidates, period);
  const existing = await store.readCurrent();
  if (existing !== undefined && sameBoard(existing, projection)) {
    return false;
  }

  await store.write(projection, now);
  return true;
}

/**
 * Whether the stored document already says what `projection` would.
 * @param {Record<string, unknown>} stored The stored document.
 * @param {PublicWeeklyStepsTop} projection The document just derived.
 * @return {boolean} True when nothing a visitor sees would change.
 */
export function sameBoard(
  stored: Record<string, unknown>,
  projection: PublicWeeklyStepsTop
): boolean {
  if (stored.schemaVersion !== PUBLIC_WEEKLY_STEPS_TOP_SCHEMA_VERSION) {
    return false;
  }
  if (stored.periodKey !== projection.periodKey) {
    return false;
  }
  return JSON.stringify(stored.rows) === JSON.stringify(projection.rows);
}

/**
 * The document's stored shape.
 * @param {PublicWeeklyStepsTop} projection The derived board.
 * @param {Date} now The write instant.
 * @return {Record<string, unknown>} Firestore data.
 */
export function publicWeeklyStepsTopData(
  projection: PublicWeeklyStepsTop,
  now: Date
): Record<string, unknown> {
  return {
    schemaVersion: PUBLIC_WEEKLY_STEPS_TOP_SCHEMA_VERSION,
    periodKey: projection.periodKey,
    periodStartAt: admin.firestore.Timestamp.fromDate(projection.periodStartAt),
    periodEndAt: admin.firestore.Timestamp.fromDate(projection.periodEndAt),
    rows: projection.rows,
    updatedAt: admin.firestore.Timestamp.fromDate(now),
  };
}

/**
 * Database access over the Admin SDK.
 * @return {PublicWeeklyStepsTopStore} The store.
 */
export function makeAdminPublicWeeklyStepsTopStore():
PublicWeeklyStepsTopStore {
  const db = admin.firestore();
  const target = db
    .collection(PUBLIC_WEEKLY_STEPS_TOP_COLLECTION)
    .doc(PUBLIC_WEEKLY_STEPS_TOP_DOCUMENT_ID);

  return {
    async readTopRows(period, limit) {
      const snapshot = await db
        .collection(LEADERBOARD_STATS_COLLECTION)
        .where("timeFrame", "==", period.timeFrame)
        .where(
          "periodStartAt",
          "==",
          admin.firestore.Timestamp.fromDate(period.startAt)
        )
        .orderBy("totalSteps", "desc")
        .limit(limit)
        .get();
      return snapshot.docs.map((document) => ({
        id: document.id,
        data: document.data(),
      }));
    },

    async readCurrent() {
      const snapshot = await target.get();
      return snapshot.exists ? snapshot.data() : undefined;
    },

    async write(projection, now) {
      await target.set(publicWeeklyStepsTopData(projection, now));
    },
  };
}

/**
 * Keeps the signed-out board current. Ten minutes is the freshness a stranger
 * deciding whether to sign up can use; the read is one bounded query.
 */
export const refreshPublicWeeklyStepsTopBoard = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Etc/UTC",
    timeoutSeconds: 60,
  },
  async () => {
    try {
      const wrote = await refreshPublicWeeklyStepsTop(
        makeAdminPublicWeeklyStepsTopStore(),
        new Date()
      );
      logger.info("publicWeeklyStepsTop.refreshed", {wrote});
    } catch (error) {
      logger.error("publicWeeklyStepsTop.failed", {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }
);
