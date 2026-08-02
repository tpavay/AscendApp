/**
 * The one leaderboard period derivation inside Cloud Functions.
 *
 * The same keys are derived independently by the client
 * (LeaderboardTimeFrame.currentPeriod) and by the seeding scripts
 * (scripts/lib/leaderboard-period.mjs). All of them are pinned against
 * SharedTestVectors/leaderboard-period-key-vector.json, because a document
 * written under one spelling is invisible to a reader using another and the
 * board just looks empty. Add a case to that vector rather than editing one
 * derivation in isolation.
 *
 * Weeks start Monday in UTC, and week 1 is the week containing Jan 1 - so a
 * week key can carry the next calendar year (2025-12-29 is 2026-W01).
 */

/** Every time frame a leaderboard row exists for. */
export const LEADERBOARD_TIME_FRAMES = [
  "daily",
  "weekly",
  "monthly",
  "yearly",
  "all_time",
] as const;

export type LeaderboardTimeFrame = typeof LEADERBOARD_TIME_FRAMES[number];

/** The subset the nightly finalizer freezes into permanent achievements. */
export const FINALIZED_TIME_FRAMES = [
  "weekly",
  "monthly",
  "yearly",
] as const;

export type FinalizedTimeFrame = typeof FINALIZED_TIME_FRAMES[number];

export interface LeaderboardPeriod {
  timeFrame: LeaderboardTimeFrame;
  key: string;
  startAt: Date;
  /** Open-ended for all-time, which never closes. */
  endAt: Date | null;
}

export interface ClosedLeaderboardPeriod extends LeaderboardPeriod {
  timeFrame: FinalizedTimeFrame;
  endAt: Date;
}

/**
 * Returns the open period a workout on this instant would count toward.
 * @param {LeaderboardTimeFrame} timeFrame The board's window.
 * @param {Date} date The instant to place.
 * @return {LeaderboardPeriod} The open period.
 */
export function currentPeriod(
  timeFrame: LeaderboardTimeFrame,
  date: Date
): LeaderboardPeriod {
  switch (timeFrame) {
  case "daily": {
    const startAt = startOfDayUTC(date);
    return {
      timeFrame,
      key: `${startAt.getUTCFullYear()}-` +
        `${padded(startAt.getUTCMonth() + 1)}-` +
        `${padded(startAt.getUTCDate())}`,
      startAt,
      endAt: addDays(startAt, 1),
    };
  }
  case "weekly": {
    const startAt = startOfWeekUTC(date);
    const {year, week} = weekInfoUTC(startAt);
    return {
      timeFrame,
      key: `${year}-W${padded(week)}`,
      startAt,
      endAt: addDays(startAt, 7),
    };
  }
  case "monthly": {
    const startAt = utcDate(date.getUTCFullYear(), date.getUTCMonth(), 1);
    return {
      timeFrame,
      key: `${startAt.getUTCFullYear()}-M` +
        `${padded(startAt.getUTCMonth() + 1)}`,
      startAt,
      endAt: utcDate(startAt.getUTCFullYear(), startAt.getUTCMonth() + 1, 1),
    };
  }
  case "yearly": {
    const startAt = utcDate(date.getUTCFullYear(), 0, 1);
    return {
      timeFrame,
      key: `${startAt.getUTCFullYear()}`,
      startAt,
      endAt: utcDate(startAt.getUTCFullYear() + 1, 0, 1),
    };
  }
  case "all_time":
    return {
      timeFrame,
      key: "all",
      startAt: new Date(0),
      endAt: null,
    };
  }
}

/**
 * Returns the most recently closed period, which is what the finalizer freezes.
 * @param {FinalizedTimeFrame} timeFrame The board's window.
 * @param {Date} date The instant the finalizer ran.
 * @return {ClosedLeaderboardPeriod} The closed period.
 */
export function previousPeriod(
  timeFrame: FinalizedTimeFrame,
  date: Date
): ClosedLeaderboardPeriod {
  const open = currentPeriod(timeFrame, date);
  const endAt = open.startAt;

  switch (timeFrame) {
  case "weekly":
    return closedPeriod(timeFrame, addDays(endAt, -7), endAt);
  case "monthly":
    return closedPeriod(
      timeFrame,
      utcDate(endAt.getUTCFullYear(), endAt.getUTCMonth() - 1, 1),
      endAt
    );
  case "yearly":
    return closedPeriod(
      timeFrame,
      utcDate(endAt.getUTCFullYear() - 1, 0, 1),
      endAt
    );
  }
}

/**
 * Names a closed period by the key its own start instant falls inside.
 * @param {FinalizedTimeFrame} timeFrame The board's window.
 * @param {Date} startAt The closed period's first instant.
 * @param {Date} endAt The closed period's exclusive end.
 * @return {ClosedLeaderboardPeriod} The named closed period.
 */
function closedPeriod(
  timeFrame: FinalizedTimeFrame,
  startAt: Date,
  endAt: Date
): ClosedLeaderboardPeriod {
  return {
    timeFrame,
    key: currentPeriod(timeFrame, startAt).key,
    startAt,
    endAt,
  };
}

/**
 * Builds the one document id a user's row for a period may occupy.
 * @param {string} userId Firebase Auth uid.
 * @param {LeaderboardTimeFrame} timeFrame The board's window.
 * @param {string} periodKey The period key.
 * @return {string} The canonical leaderboard_stats document id.
 */
export function leaderboardDocumentId(
  userId: string,
  timeFrame: LeaderboardTimeFrame,
  periodKey: string
): string {
  return `${timeFrame}_${periodKey}_${userId}`;
}

/**
 * Builds a UTC midnight date.
 * @param {number} year Full year.
 * @param {number} month Zero-based month, may overflow.
 * @param {number} day Day of month, may overflow.
 * @return {Date} UTC midnight.
 */
export function utcDate(year: number, month: number, day: number): Date {
  return new Date(Date.UTC(year, month, day));
}

/**
 * Truncates an instant to UTC midnight.
 * @param {Date} date The instant.
 * @return {Date} UTC midnight of the same day.
 */
function startOfDayUTC(date: Date): Date {
  return utcDate(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate()
  );
}

/**
 * Shifts a date by whole days.
 * @param {Date} date The instant.
 * @param {number} days Days to add, may be negative.
 * @return {Date} The shifted instant.
 */
function addDays(date: Date, days: number): Date {
  const result = new Date(date.getTime());
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

/**
 * Truncates an instant to the Monday that opens its week, in UTC.
 * @param {Date} date The instant.
 * @return {Date} UTC midnight on that Monday.
 */
export function startOfWeekUTC(date: Date): Date {
  const start = startOfDayUTC(date);
  const daysSinceMonday = (start.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - daysSinceMonday);
  return start;
}

/**
 * Names the week a date falls in. Week 1 is the week containing Jan 1, so a
 * week opening in December can carry the next calendar year.
 * @param {Date} date The instant.
 * @return {{year: number, week: number}} The week's year and ordinal.
 */
function weekInfoUTC(date: Date): {year: number; week: number} {
  const normalizedDate = startOfDayUTC(date);
  const weekStart = startOfWeekUTC(normalizedDate);
  const calendarYear = normalizedDate.getUTCFullYear();
  const firstWeekStart = startOfWeekUTC(utcDate(calendarYear, 0, 1));

  if (weekStart < firstWeekStart) {
    return weekInfoUTC(utcDate(calendarYear - 1, 11, 31));
  }

  const nextYearFirstWeekStart = startOfWeekUTC(
    utcDate(calendarYear + 1, 0, 1)
  );
  if (weekStart >= nextYearFirstWeekStart) {
    return {year: calendarYear + 1, week: 1};
  }

  const diffDays = Math.round(
    (weekStart.getTime() - firstWeekStart.getTime()) /
      (1000 * 60 * 60 * 24)
  );
  return {
    year: calendarYear,
    week: Math.floor(diffDays / 7) + 1,
  };
}

/**
 * Zero-pads a period ordinal so keys keep sorting and keep matching.
 * @param {number} value The ordinal.
 * @return {string} Two-digit string.
 */
function padded(value: number): string {
  return String(value).padStart(2, "0");
}
