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
 * sessions cannot total more time than the period contains - so a forged
 * standing is now bounded by what a human could conceivably have climbed
 * instead of by the range of a 64-bit integer. Closing the remainder means
 * building the evidence path (attestation and per-workout provenance), which
 * is a separate piece of work.
 */

import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
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
 */
export const COMPETITION_ELIGIBLE_SOURCES = new Set([
  "manual",
  "apple_health",
  "garmin",
  "fitbit",
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
 */
export interface ExistingLeaderboardRow {
  documentId: string;
  isSynthetic: boolean;
}

/** Everything one reconciliation reads. */
export interface LeaderboardStatsSnapshot {
  workouts: {id: string; data: Record<string, unknown>}[];
  publicProfile: Record<string, unknown> | undefined;
  user: Record<string, unknown> | undefined;
  existingRows: ExistingLeaderboardRow[];
}

/** The operations available inside one reconciliation. */
export interface LeaderboardStatsTransaction {
  read(userId: string): Promise<LeaderboardStatsSnapshot>;
  write(documentId: string, data: Record<string, unknown>): Promise<void>;
  delete(documentId: string): Promise<void>;
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
 * Sums the eligible workouts that fall inside a period.
 * @param {EligibleWorkout[]} workouts Eligible workouts, any order.
 * @param {LeaderboardPeriod} period The board window.
 * @return {LeaderboardAggregate} The period's totals.
 */
export function aggregateForPeriod(
  workouts: EligibleWorkout[],
  period: LeaderboardPeriod
): LeaderboardAggregate {
  const startMillis = period.startAt.getTime();
  const endMillis = period.endAt === null ?
    Number.POSITIVE_INFINITY :
    period.endAt.getTime();

  let totalSteps = 0;
  let totalFloors = 0;
  let totalWorkouts = 0;
  let totalDuration = 0;

  for (const workout of workouts) {
    if (
      workout.startedAtMillis < startMillis ||
      workout.startedAtMillis >= endMillis
    ) {
      continue;
    }
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
 * contains. The floor at the longest single session keeps a legitimate workout
 * that straddles a boundary, or lands under a little clock skew, from tripping
 * the check.
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
  // first climbed, which is the only honest span to measure them against.
  const startMillis = period.endAt === null ?
    earliestStartMillis :
    period.startAt.getTime();
  const endMillis = period.endAt === null ?
    now.getTime() :
    Math.min(now.getTime(), period.endAt.getTime());

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
 * @return {DerivedLeaderboardRow[]} Rows with activity, one per time frame.
 */
export function deriveLeaderboardRows(
  userId: string,
  workouts: EligibleWorkout[],
  now: Date
): DerivedLeaderboardRow[] {
  const rows: DerivedLeaderboardRow[] = [];

  for (const timeFrame of LEADERBOARD_TIME_FRAMES) {
    const period = currentPeriod(timeFrame, now);
    const inPeriod = workoutsInPeriod(workouts, period);
    const aggregate = aggregateForPeriod(workouts, period);
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
 * @param {Record<string, unknown> | undefined} data The user document.
 * @return {LeaderboardDemographics} Present values only.
 */
export function leaderboardDemographics(
  data: Record<string, unknown> | undefined
): LeaderboardDemographics {
  return {
    age: data === undefined ? null : boundedInteger(data.age, 13, 120),
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
 * Recomputes every board row for one climber and removes the ones that no
 * longer have evidence behind them.
 * @param {LeaderboardStatsStore} store Persistence boundary.
 * @param {string} userId Firebase Auth uid.
 * @param {Date} now The reconciliation instant.
 * @return {Promise<ReconcileOutcome>} The document ids written and deleted.
 */
export async function reconcileLeaderboardStats(
  store: LeaderboardStatsStore,
  userId: string,
  now: Date
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

    const rows = deriveLeaderboardRows(userId, eligible, now);
    const identity = leaderboardIdentityFields(userId, snapshot.publicProfile);
    const demographics = leaderboardDemographics(snapshot.user);
    const synthetic = new Set(
      snapshot.existingRows
        .filter((row) => row.isSynthetic)
        .map((row) => row.documentId)
    );

    const written: string[] = [];
    const skippedSynthetic: string[] = [];
    for (const row of rows) {
      if (synthetic.has(row.documentId)) {
        skippedSynthetic.push(row.documentId);
        continue;
      }
      await transaction.write(
        row.documentId,
        leaderboardDocumentData(userId, row, identity, demographics)
      );
      written.push(row.documentId);
    }

    // A row for a period the climber no longer has evidence in - a deleted
    // workout, an edit that pushed it out of the window, a period that rolled -
    // is removed rather than left behind at its last value.
    const keep = new Set(written);
    const deleted: string[] = [];
    for (const row of snapshot.existingRows) {
      if (row.isSynthetic) {
        // Reported, not silently passed over: an operator reading a backfill
        // needs to see that a standing survived because it was seeded, not
        // because the derivation agreed with it.
        if (!skippedSynthetic.includes(row.documentId)) {
          skippedSynthetic.push(row.documentId);
        }
        continue;
      }
      if (keep.has(row.documentId)) {
        continue;
      }
      await transaction.delete(row.documentId);
      deleted.push(row.documentId);
    }

    return {written, deleted, skippedSynthetic};
  });
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
 * Rederives a climber's standings whenever their canonical workouts change.
 */
export const onWorkoutWrittenLeaderboardStats = onDocumentWritten(
  {
    document: "users/{userId}/workouts/{workoutId}",
    retry: true,
  },
  async (event) => {
    await reconcileLeaderboardStats(
      makeAdminLeaderboardStatsStore(),
      event.params.userId,
      new Date()
    );
  }
);

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
                        .select("isSynthetic")
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
                  })),
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
  aggregateForPeriod,
  demographicsChanged,
  deriveLeaderboardRows,
  leaderboardDemographics,
  leaderboardIdentityFields,
  parseEligibleWorkout,
  periodBudgetSeconds,
  reconcileLeaderboardStats,
};
