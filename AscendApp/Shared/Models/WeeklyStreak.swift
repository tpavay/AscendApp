import Foundation

/// A climber's streak of consecutive weeks with at least one climb.
///
/// Weeks are the app-wide Monday weeks in the climber's own time zone, never the device
/// locale's week: an en_US calendar starts on Sunday, which made a Sunday climb open a new
/// week and counted the Monday week that had just been climbed as the one before it.
struct WeeklyStreak: Equatable {
    /// Consecutive weeks with a climb, counting this week once it holds one.
    let weeks: Int
    /// Whether this week already holds a climb, so the streak cannot break before Monday.
    let isCurrentWeekSecured: Bool

    static let none = WeeklyStreak(weeks: 0, isCurrentWeekSecured: false)

    /// The streak standing at `referenceDate`. A week without a climb yet does not break the
    /// streak until it ends, so the count then runs through last week and waits on this one.
    static func current(
        climbDates: some Sequence<Date>,
        referenceDate: Date = .now,
        calendar: Calendar = WeekConfiguration.calendar()
    ) -> WeeklyStreak {
        let activeWeeks = weekStarts(of: climbDates, calendar: calendar)
        guard let currentWeek = weekStart(of: referenceDate, calendar: calendar) else { return .none }

        let isCurrentWeekSecured = activeWeeks.contains(currentWeek)
        var cursor = isCurrentWeekSecured ? currentWeek : weekBefore(currentWeek, calendar: calendar)
        var weeks = 0
        while let week = cursor, activeWeeks.contains(week) {
            weeks += 1
            cursor = weekBefore(week, calendar: calendar)
        }

        return WeeklyStreak(weeks: weeks, isCurrentWeekSecured: isCurrentWeekSecured)
    }

    /// The longest run of consecutive weeks with a climb, ever.
    static func longest(
        climbDates: some Sequence<Date>,
        calendar: Calendar = WeekConfiguration.calendar()
    ) -> Int {
        let activeWeeks = weekStarts(of: climbDates, calendar: calendar)
        var longest = 0
        for week in activeWeeks {
            // Count only from the first week of each run, so every run is walked once.
            if let previous = weekBefore(week, calendar: calendar), activeWeeks.contains(previous) {
                continue
            }
            var length = 1
            var cursor = week
            while let next = weekAfter(cursor, calendar: calendar), activeWeeks.contains(next) {
                length += 1
                cursor = next
            }
            longest = max(longest, length)
        }
        return longest
    }

    private static func weekStarts(of dates: some Sequence<Date>, calendar: Calendar) -> Set<Date> {
        Set(dates.compactMap { weekStart(of: $0, calendar: calendar) })
    }

    private static func weekStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    /// Stepped by a day from the week boundary rather than by seven days, so a daylight
    /// saving change inside a week can never land the cursor off a week start.
    private static func weekBefore(_ weekStart: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: weekStart)
            .flatMap { self.weekStart(of: $0, calendar: calendar) }
    }

    private static func weekAfter(_ weekStart: Date, calendar: Calendar) -> Date? {
        guard let end = calendar.dateInterval(of: .weekOfYear, for: weekStart)?.end else { return nil }
        return self.weekStart(of: end, calendar: calendar)
    }
}
