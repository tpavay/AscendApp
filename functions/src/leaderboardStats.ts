/**
 * Server-derived global leaderboard standings (issue #307).
 *
 * `leaderboard_stats` is what the world ranks on and what the nightly finalizer
 * freezes into permanent achievements. It used to be written by the device from
 * its own SwiftData aggregate, and the rules validated only its shape and its
 * identity - never its evidence. One ordinary HTTPS request carrying
 * `totalSteps: 2000000000` therefore bought first place on every board and a
 * permanent award to go with it.
 *
 * This file is the SINGLE site that derives a standing. It reads the canonical
 * private workouts at `users/{uid}/workouts`, applies the competition
 * eligibility and plausibility policy below, and writes the rows through the
 * Admin SDK. `firestore.rules` denies every client write to the collection, so
 * the derivation here is the only author.
 *
 * One projection builder, three triggers (the shape climbCompletions.ts
 * established): the workout trigger, the demographics trigger, and the
 * backfill script (scripts/backfill-leaderboard-stats.mjs) all call
 * `reconcileLeaderboardStats`. Never fork per-trigger logic.
 *
 * WHAT THIS DOES NOT DO. Every workout document is still authored by the
 * device: there is no App Check attestation and no server-side sensor
 * ingestion, so the server holds no evidence a determined client could not
 * manufacture. What it does hold is a physical envelope - a session cannot
 * exceed 220 steps per minute, cannot run longer than a day, and a period's
 * sessions cannot total more wall clock than the period contains - so a forged
 * standing is now bounded by what a human could conceivably have climbed
 * instead of by the range of a 64-bit integer. Closing the remainder means
 * building the evidence path (attestation and per-workout provenance), which
 * is a separate piece of work.
 *
 * WHERE THE ENVELOPE DOES NOT REACH. The wall-clock bound is real for daily,
 * weekly, monthly and yearly, whose windows are fixed calendar spans the
 * client cannot move. It is NOT a meaningful bound on all-time: that window
 * has no start, so the budget is anchored at the climber's own earliest
 * workout, and one backdated workout moves the anchor and buys years of
 * headroom. Anchoring it at account creation would add precision the evidence
 * does not support, since the workouts themselves are client-authored either
 * way. The exposure is a visible all-time ranking rather than a frozen award:
 * finalizeLeaderboardAchievements mints permanent achievements from weekly,
 * monthly and yearly only (FINALIZED_TIME_FRAMES), never from all-time.
 */

import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  FINALIZED_TIME_FRAMES,
  LEADERBOARD_TIME_FRAMES,
  LeaderboardPeriod,
  LeaderboardTimeFrame,
  currentPeriod,
  leaderboardDocumentId,
} from "./leaderboardPeriod.js";
import {
  currentPublicIdentity,
  desiredIdentityFields,
} from "./publicIdentityPropagation.js";

const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";
const USERS_COLLECTION = "users";
const WORKOUTS_COLLECTION = "workouts";
const PUBLIC_PROFILE_COLLECTION = "public_profile";
const LEADERBOARD_PERIODS_COLLECTION = "leaderboard_periods";
const CURRENT_PUBLIC_PROFILE_ID = "current";

export const LEADERBOARD_STATS_SCHEMA_VERSION = 2;
const TRANSACTION_MAX_ATTEMPTS = 5;

/**
 * Which workout origins count toward a competitive standing.
 *
 * This is today's behaviour written down, not a new policy: the device counted
 * every workout it owned, so narrowing the set here would silently empty most
 * standings. The captain's competitive-eligibility decision of 2026-07-27 -
 * only Ascend-controlled live sensor sessions count - is a product change that
 * belongs in its own slice, and lands as an edit to this one constant plus its
 * test.
 *
 * `garmin` and `fitbit` are absent because `isValidWorkoutSource` in
 * `firestore.rules` refuses them, so no document reaching this function can
 * carry either. They named integrations that were never built - no build ever
 * set them. Keeping them listed here stated a second, looser policy that
 * nothing could exercise; one policy, stated once, is the point.
 */
export const COMPETITION_ELIGIBLE_SOURCES = new Set([
  "manual",
  "apple_health",
  "hevy",
  "headphone_motion",
]);

/**
 * The physical envelope a single session must fall inside to be counted.
 * `MAX_AVERAGE_STEPS_PER_MINUTE` mirrors
 * `WorkoutPlausibilityPolicy.maximumAverageStepsPerMinute` on the device; the
 * server applies it again because it cannot know the device applied it.
 */
export const MAX_AVERAGE_STEPS_PER_MINUTE = 220;
export const MAX_WORKOUT_DURATION_SECONDS = 24 * 60 * 60;

/** A workout reduced to the fields a standing is derived from. */
export interface EligibleWorkout {
  workoutId: string;
  startedAtMillis: number;
  durationSeconds: number;
  steps: number;
  floors: number;
}

/** The competitive totals for one board window. */
export interface LeaderboardAggregate {
  totalSteps: number;
  totalFloors: number;
  totalWorkouts: number;
  totalDuration: number;
  stepsPerMinute: number;
}

/** One derived row, keyed by the document it belongs in. */
export interface DerivedLeaderboardRow {
  documentId: string;
  timeFrame: LeaderboardTimeFrame;
  periodKey: string;
  periodStartAt: Date;
  aggregate: LeaderboardAggregate;
}

/** The optional demographics the board filters on. */
export interface LeaderboardDemographics {
  age: number | null;
  weightKg: number | null;
  locationCity: string | null;
  locationCountry: string | null;
  locationRegion: string | null;
}

/**
 * An existing row for this climber. `isSynthetic` marks a seeded competitor
 * (scripts/seed-leaderboard.mjs), whose standing has no canonical workouts
 * behind it by design - the same exemption identity propagation already makes
 * for seeded projections. The derivation neither rewrites nor removes one.
 *
 * `timeFrame` and `periodStartAtMillis` are read off the stored document rather
 * than parsed back out of the document id: the id is a formatting of those
 * fields, and re-deriving the window from a string would become a second period
 * derivation the moment the id format moves. Both are null when the stored row
 * predates them or carries something unrecognised, and a row whose window
 * cannot be established is never removed.
 */
export interface ExistingLeaderboardRow {
  documentId: string;
  isSynthetic: boolean;
  timeFrame: LeaderboardTimeFrame | null;
  periodStartAtMillis: number | null;
}

/**
 * How much of a climber's board history one reconciliation is allowed to own.
 *
 * `openPeriodsOnly` is what the Cloud Function triggers pass, and the reason is
 * that nobody is watching a trigger: finalizeLeaderboardAchievements can be
 * running concurrently, so a trigger that rewrote or removed a closed window
 * would race the job that freezes permanent awards from it.
 *
 * `openAndStoredPeriods` is the operator's tool (scripts/backfill-leaderboard-
 * stats.mjs, behind an explicit flag). It additionally owns every period a
 * stored row already names, so the rows this issue exists to clean - the
 * client-authored ones sitting in the window the finalizer is about to read -
 * are actually reachable. It is opt-in because it is a supervised,
 * dry-run-first operation, not something that should ever fire unattended.
 */
export type LeaderboardOwnership = "openPeriodsOnly" | "openAndStoredPeriods";

export interface ReconcileOptions {
  ownership: LeaderboardOwnership;
}

/** Everything one reconciliation reads. */
export interface LeaderboardStatsSnapshot {
  workouts: {id: string; data: Record<string, unknown>}[];
  publicProfile: Record<string, unknown> | undefined;
  user: Record<string, unknown> | undefined;
  existingRows: ExistingLeaderboardRow[];
}

/**
 * Why a stored row is being removed.
 *
 * The reason travels with the removal because only the derivation knows it, and
 * a caller that has to guess will guess wrong: "no eligible workouts" and "this
 * window was never examined" produce the same empty result and mean opposite
 * things about the row.
 *
 * - `noEvidence`: the window WAS derived and no eligible workout fell in it.
 * - `prunedClosedWindow`: the window was not derived at all. It closed, nothing
 *   reads it again, and the row is housekeeping rather than a finding.
 * - `unresolvableWindow`: the row's identifier encodes no period this
 *   derivation can name, so there is nothing to re-derive it from.
 */
export type LeaderboardRemovalReason =
  | "noEvidence"
  | "prunedClosedWindow"
  | "unresolvableWindow";

/**
 * What `leaderboard_periods/{timeFrame}_{periodKey}` says about one window.
 *
 * `exists` and `status` are kept apart on purpose. A period the finalizer has
 * never touched has no document at all, which is a different statement from a
 * document that exists carrying a status this code does not recognise, and only
 * the first is safe to act on.
 */
export interface PeriodFinalization {
  exists: boolean;
  status: string | null;
}

/**
 * The operations available inside one reconciliation.
 *
 * `readPeriodFinalization` is here rather than in the caller because a decision
 * about whether a removal is safe has to be made from a read INSIDE the
 * transaction that performs it. Reading the status separately leaves a window
 * where finalizeLeaderboardAchievements can take its lock between the check and
 * the delete; reading it here makes a concurrent finalizer abort and retry this
 * transaction so the decision is re-made against the new status. Firestore
 * requires reads before writes, so call it during the read phase.
 */
export interface LeaderboardStatsTransaction {
  read(userId: string): Promise<LeaderboardStatsSnapshot>;
  readPeriodFinalization(
    periodDocumentId: string
  ): Promise<PeriodFinalization>;
  write(documentId: string, data: Record<string, unknown>): Promise<void>;
  delete(
    documentId: string,
    reason: LeaderboardRemovalReason
  ): Promise<void>;
}

/**
 * The persistence boundary, with Firestore retry semantics.
 *
 * A reconciliation must be atomic in the workout set it read. Two workouts
 * saved back to back fire two reconciliations; without transaction isolation
 * the one that read the older set can commit last, and the board sits at the
 * earlier total until something else touches a workout. Reading inside a
 * transaction makes that case retry instead. Tests inject a store whose
 * runTransaction simply runs the operation.
 */
export interface LeaderboardStatsStore {
  runTransaction<T>(
    operation: (transaction: LeaderboardStatsTransaction) => Promise<T>
  ): Promise<T>;
}

export interface ReconcileOutcome {
  written: string[];
  deleted: string[];
  skippedSynthetic: string[];
  /**
   * Rows whose window this derivation cannot name - in practice the legacy
   * `{uid}_{timeFrame}` documents the device used to write.
   *
   * Reported whether or not they were removed, because they are not inert.
   * Deleting the client write path in this branch also deleted
   * `LeaderboardRepository.deleteLegacyStats`, which was the ONLY sweeper for
   * them, and `leaderboardRowsForPeriod` in finalizeLeaderboardAchievements
   * matches on `timeFrame` + `periodStartAt` with no constraint on document id,
   * resolving duplicates by newest `lastUpdated`. A legacy client-authored row
   * can therefore still win a permanent award, and nothing sweeps it now. That
   * is a partial reopening of the hole this change exists to close, introduced
   * by this change, and an operator has to be able to see it.
   */
  unresolvableRows: string[];
}

/**
 * Reduces a raw workout document to the fields a standing counts, or null when
 * the workout is not competition-eligible.
 *
 * Every check re-derives from the stored document. A device-asserted verdict -
 * `integrityLevel`, or any future `leaderboardEligible` flag - is a record of
 * what the device concluded, never an instruction this function obeys.
 * @param {string} workoutId The workout document id.
 * @param {Record<string, unknown> | undefined} data Raw workout data.
 * @return {EligibleWorkout | null} The eligible workout, or null.
 */
export function parseEligibleWorkout(
  workoutId: string,
  data: Record<string, unknown> | undefined
): EligibleWorkout | null {
  if (!data) {
    return null;
  }
  if (typeof data.source !== "string" ||
    !COMPETITION_ELIGIBLE_SOURCES.has(data.source)) {
    return null;
  }

  const startedAtMillis = timestampMillis(data.startedAt);
  const durationSeconds = finiteNumber(data.durationSeconds);
  const steps = nonNegativeInteger(data.steps);
  const floors = nonNegativeInteger(data.floors);
  if (
    startedAtMillis === null ||
    durationSeconds === null ||
    steps === null ||
    floors === null
  ) {
    return null;
  }

  if (
    durationSeconds <= 0 ||
    durationSeconds > MAX_WORKOUT_DURATION_SECONDS
  ) {
    return null;
  }

  if (steps / (durationSeconds / 60) > MAX_AVERAGE_STEPS_PER_MINUTE) {
    return null;
  }

  return {workoutId, startedAtMillis, durationSeconds, steps, floors};
}

/**
 * Sums the eligible workouts of one period.
 *
 * Takes the already-windowed list rather than re-filtering, so the totals and
 * the budget they are checked against agree on the window by construction
 * instead of by two copies of the same comparison.
 * @param {EligibleWorkout[]} workouts Eligible workouts inside the window.
 * @return {LeaderboardAggregate} The period's totals.
 */
export function aggregateForPeriod(
  workouts: EligibleWorkout[]
): LeaderboardAggregate {
  let totalSteps = 0;
  let totalFloors = 0;
  let totalWorkouts = 0;
  let totalDuration = 0;

  for (const workout of workouts) {
    totalSteps += workout.steps;
    totalFloors += workout.floors;
    totalWorkouts += 1;
    totalDuration += workout.durationSeconds;
  }

  const minutes = totalDuration / 60;
  return {
    totalSteps,
    totalFloors,
    totalWorkouts,
    totalDuration,
    stepsPerMinute: minutes > 0 ? totalSteps / minutes : 0,
  };
}

/**
 * The seconds of wall clock a period can honestly account for.
 *
 * A climber cannot have spent more time on the machine than the window
 * contains, so a closed window's budget is its FULL length - not the part of it
 * that has elapsed. Measuring elapsed time instead drops honest climbers: two
 * connected sources recording the same 45-minute climb (a Hevy record and its
 * Apple Health twin carry different identifiers, so they survive per-source
 * dedupe) at 00:05 and 00:10 UTC total 90 minutes against a 20-minute elapsed
 * budget, and the whole daily row vanishes. Where bounding an abuser and
 * protecting a real climber pull apart, protect the climber: the full-period
 * bound still caps a forger at human scale, and no honest total can exceed it.
 *
 * The floor at the longest single session keeps a legitimate workout that
 * straddles a boundary, or lands under a little clock skew, from tripping the
 * check.
 * @param {LeaderboardPeriod} period The board window.
 * @param {EligibleWorkout[]} workouts Eligible workouts in the period.
 * @param {Date} now The reconciliation instant.
 * @return {number} The budget in seconds.
 */
export function periodBudgetSeconds(
  period: LeaderboardPeriod,
  workouts: EligibleWorkout[],
  now: Date
): number {
  if (workouts.length === 0) {
    return 0;
  }

  const longestWorkout = workouts.reduce(
    (longest, workout) => Math.max(longest, workout.durationSeconds),
    0
  );
  const earliestStartMillis = workouts.reduce(
    (earliest, workout) => Math.min(earliest, workout.startedAtMillis),
    Number.POSITIVE_INFINITY
  );

  // All-time never opens at the epoch in practice - it opens when this climber
  // first climbed, which is the only span available to measure them against.
  // See the file comment: that anchor is client-authored, so all-time is the
  // one window this budget does not meaningfully bound.
  const startMillis = period.endAt === null ?
    earliestStartMillis :
    period.startAt.getTime();
  const endMillis = period.endAt === null ?
    now.getTime() :
    period.endAt.getTime();

  return Math.max((endMillis - startMillis) / 1000, longestWorkout);
}

/**
 * Derives every board row for one climber from their canonical workouts.
 *
 * Deterministic in the workout set and the instant, so the workout trigger, the
 * demographics trigger, and the backfill converge on identical output. A period
 * whose totals exceed its wall-clock budget yields no row at all: a standing
 * that violates physics is not a standing, and dropping it is the honest
 * outcome where clamping it would publish a number nobody climbed.
 * @param {string} userId Firebase Auth uid.
 * @param {EligibleWorkout[]} workouts Every eligible workout for the climber.
 * @param {Date} now The reconciliation instant.
 * @param {LeaderboardPeriod[]} periods The windows to derive, defaulting to the
 *   five currently open ones.
 * @return {DerivedLeaderboardRow[]} Rows with activity, one per window.
 */
export function deriveLeaderboardRows(
  userId: string,
  workouts: EligibleWorkout[],
  now: Date,
  periods: LeaderboardPeriod[] = openPeriods(now)
): DerivedLeaderboardRow[] {
  const rows: DerivedLeaderboardRow[] = [];

  for (const period of periods) {
    const timeFrame = period.timeFrame;
    const inPeriod = workoutsInPeriod(workouts, period);
    const aggregate = aggregateForPeriod(inPeriod);
    if (aggregate.totalWorkouts === 0) {
      continue;
    }

    const budget = periodBudgetSeconds(period, inPeriod, now);
    if (aggregate.totalDuration > budget) {
      logger.warn("leaderboardStats.implausiblePeriod", {
        userId,
        timeFrame,
        periodKey: period.key,
        totalDurationSeconds: aggregate.totalDuration,
        budgetSeconds: budget,
        workoutCount: aggregate.totalWorkouts,
      });
      continue;
    }

    rows.push({
      documentId: leaderboardDocumentId(userId, timeFrame, period.key),
      timeFrame,
      periodKey: period.key,
      periodStartAt: period.startAt,
      aggregate,
    });
  }

  return rows;
}

/**
 * Resolves the identity fields a standing renders under.
 *
 * Deliberately routed through publicIdentityPropagation.ts rather than
 * reimplemented: that module owns these same five fields on every existing row
 * and reaches every projection, not just this one. Two definitions of "what
 * identity does this profile currently publish" would become two answers, and
 * a leaderboard row is exactly where that shows up in public.
 * @param {string} userId Firebase Auth uid.
 * @param {Record<string, unknown> | undefined} data The public profile mirror.
 * @return {Record<string, unknown>} The identity fields for the row.
 */
export function leaderboardIdentityFields(
  userId: string,
  data: Record<string, unknown> | undefined
): Record<string, unknown> {
  return desiredIdentityFields("leaderboard", currentPublicIdentity(
    userId,
    data
  ));
}

/**
 * Copies the board's filter demographics off the private user document.
 *
 * Age is derived from the private `birth_date` rather than read as a stored
 * number, so the board ages a climber with the calendar instead of freezing
 * whatever they typed once. The stored `age` is consulted only for the legacy
 * climbers who never recorded a birthday; `birth_date` itself never leaves this
 * function.
 * @param {Record<string, unknown> | undefined} data The user document.
 * @param {Date} now The reconciliation instant.
 * @return {LeaderboardDemographics} Present values only.
 */
export function leaderboardDemographics(
  data: Record<string, unknown> | undefined,
  now: Date
): LeaderboardDemographics {
  return {
    age: data === undefined ?
      null :
      boundedInteger(
        ageFromBirthDate(data.birth_date, now) ?? data.age,
        13,
        120
      ),
    weightKg: data === undefined ?
      null :
      boundedNumber(data.weight_kg, 0, 400),
    locationCity: data === undefined ? null : profileText(data.location_city),
    locationCountry: data === undefined ?
      null :
      countryCode(data.location_country),
    locationRegion: data === undefined ?
      null :
      profileText(data.location_region),
  };
}

/**
 * The five currently open windows.
 * @param {Date} now The reconciliation instant.
 * @return {LeaderboardPeriod[]} One open period per time frame.
 */
export function openPeriods(now: Date): LeaderboardPeriod[] {
  return LEADERBOARD_TIME_FRAMES.map(
    (timeFrame) => currentPeriod(timeFrame, now)
  );
}

/**
 * The document ids of the five currently open periods.
 * @param {string} userId Firebase Auth uid.
 * @param {Date} now The reconciliation instant.
 * @return {Set<string>} The open-period document ids.
 */
export function openPeriodDocumentIds(
  userId: string,
  now: Date
): Set<string> {
  return new Set(
    openPeriods(now).map(
      (period) => leaderboardDocumentId(userId, period.timeFrame, period.key)
    )
  );
}

/**
 * Every window one reconciliation may derive and write under a given ownership.
 *
 * A stored row contributes its own window only when re-deriving that window
 * from the row's `timeFrame` and `periodStartAt` lands back on the same
 * document id. That round-trip is the check that the stored fields and the id
 * agree; a row where they do not is malformed, and rewriting it under a window
 * it does not claim would move a standing rather than repair it.
 * @param {string} userId Firebase Auth uid.
 * @param {Date} now The reconciliation instant.
 * @param {ExistingLeaderboardRow[]} existingRows The climber's stored rows.
 * @param {LeaderboardOwnership} ownership How much history to own.
 * @return {LeaderboardPeriod[]} The owned windows, deduplicated.
 */
export function ownedPeriods(
  userId: string,
  now: Date,
  existingRows: ExistingLeaderboardRow[],
  ownership: LeaderboardOwnership
): LeaderboardPeriod[] {
  const periods = openPeriods(now);
  if (ownership === "openPeriodsOnly") {
    return periods;
  }

  const seen = new Set(
    periods.map(
      (period) => leaderboardDocumentId(userId, period.timeFrame, period.key)
    )
  );
  for (const row of existingRows) {
    const period = resolvedPeriodForRow(userId, row);
    if (period === null) {
      continue;
    }
    const documentId = leaderboardDocumentId(
      userId,
      period.timeFrame,
      period.key
    );
    if (seen.has(documentId)) {
      continue;
    }
    seen.add(documentId);
    periods.push(period);
  }
  return periods;
}

/**
 * The window a stored row belongs to, or null when it names none.
 *
 * Null is the legacy `{uid}_{timeFrame}` case. Such a row can NEVER be
 * re-derived: its identifier encodes no period, so there is no window to sum
 * workouts over and nothing to rebuild it from. It is still live evidence as
 * far as the finalizer is concerned - see `ReconcileOutcome.unresolvableRows`.
 * @param {string} userId Firebase Auth uid.
 * @param {ExistingLeaderboardRow} row The stored row.
 * @return {LeaderboardPeriod | null} The window, or null.
 */
export function resolvedPeriodForRow(
  userId: string,
  row: ExistingLeaderboardRow
): LeaderboardPeriod | null {
  if (row.timeFrame === null || row.periodStartAtMillis === null) {
    return null;
  }
  const period = currentPeriod(
    row.timeFrame,
    new Date(row.periodStartAtMillis)
  );
  const documentId = leaderboardDocumentId(
    userId,
    period.timeFrame,
    period.key
  );
  return documentId === row.documentId ? period : null;
}

/**
 * Recomputes every board row for one climber and removes the ones that no
 * longer have evidence behind them.
 * @param {LeaderboardStatsStore} store Persistence boundary.
 * @param {string} userId Firebase Auth uid.
 * @param {Date} now The reconciliation instant.
 * @param {ReconcileOptions} options Ownership, defaulting to open periods only.
 * @return {Promise<ReconcileOutcome>} The document ids written and deleted.
 */
export async function reconcileLeaderboardStats(
  store: LeaderboardStatsStore,
  userId: string,
  now: Date,
  options: ReconcileOptions = {ownership: "openPeriodsOnly"}
): Promise<ReconcileOutcome> {
  return store.runTransaction(async (transaction) => {
    // Every read happens before the first write, so Firestore can retry the
    // whole callback and re-derive from the workouts as they stand.
    const snapshot = await transaction.read(userId);
    const eligible: EligibleWorkout[] = [];
    for (const workout of snapshot.workouts) {
      const parsed = parseEligibleWorkout(workout.id, workout.data);
      if (parsed) {
        eligible.push(parsed);
      }
    }

    const periods = ownedPeriods(
      userId,
      now,
      snapshot.existingRows,
      options.ownership
    );
    const rows = deriveLeaderboardRows(userId, eligible, now, periods);
    const identity = leaderboardIdentityFields(userId, snapshot.publicProfile);
    const demographics = leaderboardDemographics(snapshot.user, now);
    const synthetic = new Set(
      snapshot.existingRows
        .filter((row) => row.isSynthetic)
        .map((row) => row.documentId)
    );

    const written: string[] = [];
    const skippedSyntheticIds = new Set<string>();
    for (const row of rows) {
      if (synthetic.has(row.documentId)) {
        skippedSyntheticIds.add(row.documentId);
        continue;
      }
      await transaction.write(
        row.documentId,
        leaderboardDocumentData(userId, row, identity, demographics)
      );
      written.push(row.documentId);
    }

    const open = openPeriodDocumentIds(userId, now);
    const owned = new Set(
      periods.map(
        (period) => leaderboardDocumentId(userId, period.timeFrame, period.key)
      )
    );
    const keep = new Set(written);
    const deleted: string[] = [];
    const unresolvableRows: string[] = [];
    for (const row of snapshot.existingRows) {
      if (row.isSynthetic) {
        // Reported, not silently passed over: an operator reading a backfill
        // needs to see that a standing survived because it was seeded, not
        // because the derivation agreed with it.
        skippedSyntheticIds.add(row.documentId);
        continue;
      }
      if (!open.has(row.documentId) &&
        resolvedPeriodForRow(userId, row) === null) {
        unresolvableRows.push(row.documentId);
      }
      if (keep.has(row.documentId)) {
        continue;
      }
      const reason = removalReasonFor(row, {
        userId,
        open,
        owned,
        ownership: options.ownership,
      });
      if (reason === null) {
        continue;
      }
      await transaction.delete(row.documentId, reason);
      deleted.push(row.documentId);
    }

    return {
      written,
      deleted,
      skippedSynthetic: [...skippedSyntheticIds],
      unresolvableRows,
    };
  });
}

const FINALIZED_TIME_FRAME_SET: ReadonlySet<string> = new Set(
  FINALIZED_TIME_FRAMES
);

/**
 * Why a stored row the derivation did not just write may be removed, or null
 * when it must stay.
 *
 * Retention follows what still READS the row, not whether its period closed:
 *
 * - An OPEN period with no evidence left is dead weight and goes, whatever the
 *   time frame. That window was derived, so the emptiness is a finding.
 * - A row whose window cannot be named is left alone under the trigger
 *   ownership. Removing it is final - there is nothing to re-derive it from -
 *   so that call belongs to a supervised operator run, never to a trigger.
 * - A closed WEEKLY, MONTHLY or YEARLY row stays under the trigger ownership
 *   for two separate reasons. finalizeLeaderboardAchievements reads the
 *   previous period's rows at 00:15 UTC to freeze permanent achievements, so
 *   removing one in that window destroys an earned award. And the achievement
 *   it writes stores `leaderboardStatsId` pointing back at the row as the
 *   award's provenance, so removing it later orphans a permanent record.
 *   Neither reason expires; do not "clean this up".
 * - A closed DAILY row is never finalized and the client only ever queries the
 *   current period, so nothing reads it again. Left immortal it would add one
 *   dead document per active climber per day to an unpaginated per-user read.
 *   The trigger never derives that window, so this is housekeeping and must
 *   never be reported as an evidence failure.
 * - ALL_TIME never closes, so it is always in the open set.
 *
 * Under the operator ownership every owned window is removable, because that
 * run is supervised, dry-run first, and exists precisely to reach the closed
 * rows that were authored by a client and never checked against evidence.
 * @param {ExistingLeaderboardRow} row The stored row.
 * @param {object} scope The uid, open ids, owned ids, and ownership in force.
 * @return {LeaderboardRemovalReason | null} The reason, or null to keep it.
 */
function removalReasonFor(
  row: ExistingLeaderboardRow,
  scope: {
    userId: string;
    open: Set<string>;
    owned: Set<string>;
    ownership: LeaderboardOwnership;
  }
): LeaderboardRemovalReason | null {
  if (scope.open.has(row.documentId)) {
    return "noEvidence";
  }
  if (resolvedPeriodForRow(scope.userId, row) === null) {
    return scope.ownership === "openAndStoredPeriods" ?
      "unresolvableWindow" :
      null;
  }
  if (scope.ownership === "openAndStoredPeriods") {
    return scope.owned.has(row.documentId) ? "noEvidence" : null;
  }
  return row.timeFrame !== null &&
    !FINALIZED_TIME_FRAME_SET.has(row.timeFrame) ?
    "prunedClosedWindow" :
    null;
}

/**
 * Builds the stored document for one derived row.
 * @param {string} userId Firebase Auth uid.
 * @param {DerivedLeaderboardRow} row The derived row.
 * @param {Record<string, unknown>} identity Resolved public identity fields.
 * @param {LeaderboardDemographics} demographics Resolved filter demographics.
 * @return {Record<string, unknown>} Firestore document data.
 */
export function leaderboardDocumentData(
  userId: string,
  row: DerivedLeaderboardRow,
  identity: Record<string, unknown>,
  demographics: LeaderboardDemographics
): Record<string, unknown> {
  const data: Record<string, unknown> = {
    ...identity,
    userId,
    isSynthetic: false,
    timeFrame: row.timeFrame,
    schemaVersion: LEADERBOARD_STATS_SCHEMA_VERSION,
    periodKey: row.periodKey,
    periodStartAt: admin.firestore.Timestamp.fromDate(row.periodStartAt),
    totalSteps: row.aggregate.totalSteps,
    totalFloors: row.aggregate.totalFloors,
    totalWorkouts: row.aggregate.totalWorkouts,
    totalDuration: row.aggregate.totalDuration,
    stepsPerMinute: row.aggregate.stepsPerMinute,
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Absent demographics are deleted rather than written as null, so a row a
  // client wrote before this derivation owned it cannot keep a stale filter
  // value alive through a merge.
  data.age = demographics.age ?? admin.firestore.FieldValue.delete();
  data.weight_kg = demographics.weightKg ??
    admin.firestore.FieldValue.delete();
  data.location_city = demographics.locationCity ??
    admin.firestore.FieldValue.delete();
  data.location_country = demographics.locationCountry ??
    admin.firestore.FieldValue.delete();
  data.location_region = demographics.locationRegion ??
    admin.firestore.FieldValue.delete();
  return data;
}

/**
 * Rederives a climber's standings when the evidence a standing is derived from
 * changes. A photo finishing its upload, a note, a heart-rate sidecar reference
 * or a calorie estimate changes no total, and re-reading the whole workout
 * collection to rewrite five identical documents for one is pure fan-out.
 */
export const onWorkoutWrittenLeaderboardStats = onDocumentWritten(
  {
    document: "users/{userId}/workouts/{workoutId}",
    retry: true,
  },
  async (event) => {
    if (!leaderboardEvidenceChanged(
      event.data?.before.data(),
      event.data?.after.data()
    )) {
      return;
    }
    await reconcileLeaderboardStats(
      makeAdminLeaderboardStatsStore(),
      event.params.userId,
      new Date()
    );
  }
);

/**
 * The workout fields a standing is derived from - exactly the set
 * `parseEligibleWorkout` reads, and exactly the set the store projects.
 */
const LEADERBOARD_EVIDENCE_FIELDS = [
  "durationSeconds",
  "steps",
  "floors",
  "source",
] as const;

/**
 * Whether a workout write touched a field a standing is derived from.
 *
 * `startedAt` is compared as epoch millis rather than by value: the before and
 * after images can carry the same instant as a Timestamp and as a Date, and a
 * structural comparison would call that a change.
 * @param {Record<string, unknown> | undefined} before Before image.
 * @param {Record<string, unknown> | undefined} after After image.
 * @return {boolean} True when leaderboard evidence changed.
 */
export function leaderboardEvidenceChanged(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined
): boolean {
  if (before === undefined || after === undefined) {
    // A create or a delete always changes the evidence set.
    return before !== after;
  }
  if (timestampMillis(before.startedAt) !== timestampMillis(after.startedAt)) {
    return true;
  }
  return LEADERBOARD_EVIDENCE_FIELDS.some(
    (field) => (before[field] ?? null) !== (after[field] ?? null)
  );
}

/**
 * Rederives a climber's standings when the demographics the board filters on
 * change. Identity is not read here - publicIdentityPropagation.ts owns those
 * fields on existing rows and reaches every projection, not just this one.
 */
export const onUserDemographicsWrittenLeaderboardStats = onDocumentWritten(
  {
    document: "users/{userId}",
    retry: true,
  },
  async (event) => {
    if (!demographicsChanged(
      event.data?.before.data(),
      event.data?.after.data()
    )) {
      return;
    }
    if (event.data?.after.exists !== true) {
      // Account deletion sweeps the rows itself (accountCleanup.ts). Rebuilding
      // them from a half-deleted subtree would race that sweep.
      return;
    }
    await reconcileLeaderboardStats(
      makeAdminLeaderboardStatsStore(),
      event.params.userId,
      new Date()
    );
  }
);

const DEMOGRAPHIC_FIELDS = [
  "age",
  "birth_date",
  "weight_kg",
  "location_city",
  "location_country",
  "location_region",
] as const;

/**
 * Whether a user document write touched a field the board filters on.
 * @param {Record<string, unknown> | undefined} before Before image.
 * @param {Record<string, unknown> | undefined} after After image.
 * @return {boolean} True when a filter demographic changed.
 */
export function demographicsChanged(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined
): boolean {
  if (before === undefined || after === undefined) {
    return before !== after;
  }
  return DEMOGRAPHIC_FIELDS.some(
    (field) => JSON.stringify(before[field] ?? null) !==
      JSON.stringify(after[field] ?? null)
  );
}

/**
 * The production store, backed by the Admin SDK.
 * @return {LeaderboardStatsStore} Admin-backed store.
 */
export function makeAdminLeaderboardStatsStore(): LeaderboardStatsStore {
  const db = admin.firestore();

  return {
    async runTransaction<T>(operation: (
      transaction: LeaderboardStatsTransaction
    ) => Promise<T>): Promise<T> {
      let attempts = 0;
      try {
        const outcome = await db.runTransaction(
          async (firestoreTransaction) => {
            attempts += 1;
            return operation({
              async read(userId) {
                const userRef = db.collection(USERS_COLLECTION).doc(userId);
                const [workouts, publicProfile, user, existing] =
                  await Promise.all([
                    // Project to the derivation's fields: a workout carries
                    // its heart-rate series inline, so reading whole documents
                    // would move megabytes to add five integers.
                    firestoreTransaction.get(
                      userRef
                        .collection(WORKOUTS_COLLECTION)
                        .select(
                          "startedAt",
                          "durationSeconds",
                          "steps",
                          "floors",
                          "source"
                        )
                    ),
                    firestoreTransaction.get(
                      userRef
                        .collection(PUBLIC_PROFILE_COLLECTION)
                        .doc(CURRENT_PUBLIC_PROFILE_ID)
                    ),
                    firestoreTransaction.get(userRef),
                    firestoreTransaction.get(
                      db
                        .collection(LEADERBOARD_STATS_COLLECTION)
                        .where("userId", "==", userId)
                        .select(
                          "isSynthetic",
                          "timeFrame",
                          "periodStartAt"
                        )
                    ),
                  ]);

                return {
                  workouts: workouts.docs.map((document) => ({
                    id: document.id,
                    data: document.data() as Record<string, unknown>,
                  })),
                  publicProfile: publicProfile.exists ?
                    publicProfile.data() as Record<string, unknown> :
                    undefined,
                  user: user.exists ?
                    user.data() as Record<string, unknown> :
                    undefined,
                  existingRows: existing.docs.map((document) => ({
                    documentId: document.id,
                    isSynthetic: document.get("isSynthetic") === true,
                    timeFrame: parseTimeFrame(document.get("timeFrame")),
                    periodStartAtMillis: timestampMillis(
                      document.get("periodStartAt")
                    ),
                  })),
                };
              },

              async readPeriodFinalization(periodDocumentId) {
                const snapshot = await firestoreTransaction.get(
                  db
                    .collection(LEADERBOARD_PERIODS_COLLECTION)
                    .doc(periodDocumentId)
                );
                const status = snapshot.get("status");
                return {
                  exists: snapshot.exists,
                  status: typeof status === "string" ? status : null,
                };
              },

              async write(documentId, data) {
                firestoreTransaction.set(
                  db.collection(LEADERBOARD_STATS_COLLECTION).doc(documentId),
                  data,
                  {merge: true}
                );
              },

              async delete(documentId) {
                firestoreTransaction.delete(
                  db.collection(LEADERBOARD_STATS_COLLECTION).doc(documentId)
                );
              },
            });
          },
          {maxAttempts: TRANSACTION_MAX_ATTEMPTS}
        );
        if (attempts > 1) {
          logger.warn("leaderboardStats.transaction.contention", {
            attempts,
            maxAttempts: TRANSACTION_MAX_ATTEMPTS,
          });
        }
        return outcome;
      } catch (error) {
        logger.error("leaderboardStats.transaction.failed", {
          attempts,
          maxAttempts: TRANSACTION_MAX_ATTEMPTS,
          attemptsExhausted: attempts >= TRANSACTION_MAX_ATTEMPTS,
          errorMessage: String(
            (error as {message?: unknown})?.message ?? error
          ),
        });
        throw error;
      }
    },
  };
}

/**
 * Filters eligible workouts down to one period.
 * @param {EligibleWorkout[]} workouts Eligible workouts, any order.
 * @param {LeaderboardPeriod} period The board window.
 * @return {EligibleWorkout[]} Workouts that opened inside the window.
 */
function workoutsInPeriod(
  workouts: EligibleWorkout[],
  period: LeaderboardPeriod
): EligibleWorkout[] {
  const startMillis = period.startAt.getTime();
  const endMillis = period.endAt === null ?
    Number.POSITIVE_INFINITY :
    period.endAt.getTime();
  return workouts.filter(
    (workout) => workout.startedAtMillis >= startMillis &&
      workout.startedAtMillis < endMillis
  );
}

/**
 * Parses a stored time frame, or null when it is absent or unrecognised.
 * @param {unknown} value Raw value.
 * @return {LeaderboardTimeFrame | null} The time frame.
 */
export function parseTimeFrame(value: unknown): LeaderboardTimeFrame | null {
  return LEADERBOARD_TIME_FRAMES.find(
    (timeFrame) => timeFrame === value
  ) ?? null;
}

/**
 * Reads epoch millis from a Firestore Timestamp, a Date, or a number.
 * @param {unknown} value Raw value.
 * @return {number | null} Epoch millis.
 */
function timestampMillis(value: unknown): number | null {
  if (value && typeof value === "object") {
    const candidate = value as {
      toMillis?: () => number;
      toDate?: () => Date;
      getTime?: () => number;
    };
    if (typeof candidate.toMillis === "function") {
      return candidate.toMillis();
    }
    if (typeof candidate.toDate === "function") {
      return candidate.toDate().getTime();
    }
    if (typeof candidate.getTime === "function") {
      return candidate.getTime();
    }
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

/**
 * Parses a finite number.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed number.
 */
function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/**
 * Parses a non-negative integer.
 * @param {unknown} value Raw value.
 * @return {number | null} Parsed integer.
 */
function nonNegativeInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ?
    value :
    null;
}

const BIRTH_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/u;

/**
 * Derives whole years of age from a stored `YYYY-MM-DD` calendar birthday.
 *
 * The birthday carries no time zone, so the comparison runs entirely on
 * calendar components in UTC: a climber's age must not flip because the
 * reconciliation ran from a different region.
 * @param {unknown} value The stored `birth_date`.
 * @param {Date} now The reconciliation instant.
 * @return {number | null} Age in years, or null when no usable birthday.
 */
function ageFromBirthDate(value: unknown, now: Date): number | null {
  if (typeof value !== "string") {
    return null;
  }
  const match = BIRTH_DATE_PATTERN.exec(value);
  if (match === null) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const roundTrip = new Date(Date.UTC(year, month - 1, day));
  if (roundTrip.getUTCFullYear() !== year ||
    roundTrip.getUTCMonth() + 1 !== month ||
    roundTrip.getUTCDate() !== day) {
    return null;
  }

  const currentMonth = now.getUTCMonth() + 1;
  const currentDay = now.getUTCDate();
  const birthdayHasOccurred = currentMonth > month ||
    (currentMonth === month && currentDay >= day);
  return now.getUTCFullYear() - year - (birthdayHasOccurred ? 0 : 1);
}

/**
 * Parses an integer inside an inclusive range.
 * @param {unknown} value Raw value.
 * @param {number} minimum Inclusive lower bound.
 * @param {number} maximum Inclusive upper bound.
 * @return {number | null} Parsed integer.
 */
function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number
): number | null {
  const parsed = finiteNumber(value);
  if (parsed === null || !Number.isInteger(parsed)) {
    return null;
  }
  return parsed >= minimum && parsed <= maximum ? parsed : null;
}

/**
 * Parses a number inside an inclusive range.
 * @param {unknown} value Raw value.
 * @param {number} minimum Inclusive lower bound.
 * @param {number} maximum Inclusive upper bound.
 * @return {number | null} Parsed number.
 */
function boundedNumber(
  value: unknown,
  minimum: number,
  maximum: number
): number | null {
  const parsed = finiteNumber(value);
  if (parsed === null) {
    return null;
  }
  return parsed >= minimum && parsed <= maximum ? parsed : null;
}

/**
 * Parses a bounded free-text profile value the rules already accept.
 * @param {unknown} value Raw value.
 * @return {string | null} Trimmed value.
 */
function profileText(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= 120 ? trimmed : null;
}

/**
 * Parses an ISO 3166-1 alpha-2 country code.
 * @param {unknown} value Raw value.
 * @return {string | null} The code.
 */
function countryCode(value: unknown): string | null {
  return typeof value === "string" && /^[A-Z]{2}$/u.test(value) ?
    value :
    null;
}

export const leaderboardStatsTestHooks = {
  ageFromBirthDate,
  aggregateForPeriod,
  demographicsChanged,
  deriveLeaderboardRows,
  leaderboardDemographics,
  leaderboardEvidenceChanged,
  leaderboardIdentityFields,
  openPeriodDocumentIds,
  openPeriods,
  ownedPeriods,
  parseEligibleWorkout,
  parseTimeFrame,
  resolvedPeriodForRow,
  periodBudgetSeconds,
  reconcileLeaderboardStats,
};
