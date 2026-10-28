import Foundation

/// Builds the Totals stickers' numbers from a bounded list of workout samples.
///
/// Pure over its inputs so every figure is testable without a store. Weeks start on Monday, like
/// every week in the app, and floors are steps divided by 16.
enum ShareTotalsBuilder {
    struct Sample: Equatable, Sendable {
        let date: Date
        let steps: Int
        let duration: TimeInterval
    }

    /// The earliest date any figure needs: the start of the year, the six weekly bars and the
    /// 30-day pace window. A query for samples never needs to reach further back than this.
    static func earliestNeededDate(now: Date, calendar: Calendar) -> Date {
        let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let sixWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -5, to: weekStart) ?? weekStart
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        return min(yearStart, sixWeeksAgo, thirtyDaysAgo)
    }

    static func make(
        samples: [Sample],
        period: SharePeriod,
        now: Date,
        calendar: Calendar,
        weekStanding: ShareTotalsSnapshot.Standing? = nil,
        monthStanding: ShareTotalsSnapshot.Standing? = nil,
        yearStanding: ShareTotalsSnapshot.Standing? = nil
    ) -> ShareTotalsSnapshot {
        let interval = periodInterval(period, now: now, calendar: calendar)
        let inPeriod = samples.filter { interval.contains($0.date) }
        let steps = inPeriod.reduce(0) { $0 + $1.steps }
        let duration = inPeriod.reduce(0.0) { $0 + $1.duration }

        let month = calendar.dateInterval(of: .month, for: now) ?? interval
        let monthSamples = samples.filter { month.contains($0.date) }
        let climbDays = Set(monthSamples.map { calendar.component(.day, from: $0.date) })

        return ShareTotalsSnapshot(
            period: period,
            periodCaption: caption(for: period),
            steps: steps,
            durationSeconds: Int(duration.rounded()),
            floors: FloorsClimbed.count(forSteps: steps),
            climbs: inPeriod.count,
            calendarMonthName: monthName(for: now, calendar: calendar),
            calendarLeadingBlanks: leadingBlanks(for: month.start, calendar: calendar),
            calendarDayCount: calendar.range(of: .day, in: .month, for: now)?.count ?? 30,
            calendarClimbDays: climbDays,
            calendarClimbCount: monthSamples.count,
            weeklySteps: weeklySteps(samples: samples, now: now, calendar: calendar),
            averagePace30Days: averagePace(samples: samples, now: now, calendar: calendar),
            weekDays: weekDays(samples: samples, now: now, calendar: calendar),
            weekStanding: weekStanding,
            monthStanding: monthStanding,
            yearStanding: yearStanding
        )
    }

    static func periodInterval(_ period: SharePeriod, now: Date, calendar: Calendar) -> DateInterval {
        let component: Calendar.Component
        switch period {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.dateInterval(of: component, for: now) ?? DateInterval(start: now, duration: 1)
    }

    static func caption(for period: SharePeriod) -> String {
        switch period {
        case .week: return "THIS WEEK"
        case .month: return "THIS MONTH"
        case .year: return "THIS YEAR"
        }
    }

    /// Empty cells before day 1 in a Monday-first month grid.
    static func leadingBlanks(for monthStart: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    static func monthName(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date).uppercased()
    }

    /// Steps for each of the last six weeks, oldest first, ending with the current week.
    static func weeklySteps(samples: [Sample], now: Date, calendar: Calendar) -> [Int] {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return Array(repeating: 0, count: 6)
        }
        return (0..<6).map { offset in
            let back = 5 - offset
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: weekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return 0 }
            return samples.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.steps }
        }
    }

    /// Total steps over total minutes across the last 30 days, or nil when nothing was climbed.
    static func averagePace(samples: [Sample], now: Date, calendar: Calendar) -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
        let recent = samples.filter { $0.date >= start && $0.date <= now }
        let minutes = recent.reduce(0.0) { $0 + $1.duration } / 60
        guard minutes > 0 else { return nil }
        let steps = recent.reduce(0) { $0 + $1.steps }
        return Double(steps) / minutes
    }

    /// Monday to Sunday: whether a climb happened on that day of the current week.
    static func weekDays(samples: [Sample], now: Date, calendar: Calendar) -> [Bool] {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return Array(repeating: false, count: 7)
        }
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return samples.contains { calendar.isDate($0.date, inSameDayAs: day) }
        }
    }
}
