/**
 * Canonical UTC leaderboard period derivation for the seeding scripts.
 *
 * The same keys are derived independently by the client
 * (LeaderboardTimeFrame.currentPeriod) and by the finalizer (previousPeriod in
 * functions/src/leaderboardAchievements.ts). All of them are pinned against
 * SharedTestVectors/leaderboard-period-key-vector.json, because a document written
 * under one spelling is invisible to a reader using another and the board just looks
 * empty. Add a case there rather than editing one derivation in isolation.
 *
 * Weeks start Monday in UTC, and week 1 is the week containing Jan 1 - so a week key
 * can carry the next calendar year (2025-12-29 is 2026-W01).
 */

export function utcDate(year, month, day) {
  return new Date(Date.UTC(year, month, day));
}

export function startOfUTCDay(date) {
  return utcDate(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

export function startOfWeekUTC(date) {
  const start = startOfUTCDay(date);
  const daysSinceMonday = (start.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - daysSinceMonday);
  return start;
}

export function weekInfoUTC(date) {
  const normalizedDate = startOfUTCDay(date);
  const weekStart = startOfWeekUTC(normalizedDate);
  const calendarYear = normalizedDate.getUTCFullYear();
  const firstWeekStart = startOfWeekUTC(utcDate(calendarYear, 0, 1));

  if (weekStart < firstWeekStart) {
    return weekInfoUTC(utcDate(calendarYear - 1, 11, 31));
  }

  const nextYearFirstWeekStart = startOfWeekUTC(utcDate(calendarYear + 1, 0, 1));
  if (weekStart >= nextYearFirstWeekStart) {
    return {year: calendarYear + 1, week: 1, startAt: weekStart};
  }

  const diffDays = Math.round(
    (weekStart.getTime() - firstWeekStart.getTime()) / (1000 * 60 * 60 * 24)
  );
  return {
    year: calendarYear,
    week: Math.floor(diffDays / 7) + 1,
    startAt: weekStart,
  };
}

export function currentPeriod(timeFrame, date = new Date()) {
  switch (timeFrame) {
    case "daily": {
      const startAt = startOfUTCDay(date);
      const year = startAt.getUTCFullYear();
      const month = String(startAt.getUTCMonth() + 1).padStart(2, "0");
      const day = String(startAt.getUTCDate()).padStart(2, "0");
      return {key: `${year}-${month}-${day}`, startAt};
    }
    case "weekly": {
      const {year, week, startAt} = weekInfoUTC(date);
      return {key: `${year}-W${String(week).padStart(2, "0")}`, startAt};
    }
    case "monthly": {
      const startAt = utcDate(date.getUTCFullYear(), date.getUTCMonth(), 1);
      const month = String(startAt.getUTCMonth() + 1).padStart(2, "0");
      return {key: `${startAt.getUTCFullYear()}-M${month}`, startAt};
    }
    case "yearly": {
      const startAt = utcDate(date.getUTCFullYear(), 0, 1);
      return {key: `${startAt.getUTCFullYear()}`, startAt};
    }
    case "all_time":
      return {key: "all", startAt: new Date(0)};
    default:
      throw new Error(`Unsupported time frame ${timeFrame}`);
  }
}
