import Foundation

enum DailyClimbRecommendationPolicy {
    static let rolloverHour = 4

    static func recommendation(
        from availableClimbs: [Climb],
        completedClimbIds: Set<String>,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Climb? {
        let uncompletedClimbs = sortedDailyClimbs(
            availableClimbs.filter { !completedClimbIds.contains($0.id) }
        )
        if let climb = dailyClimb(from: uncompletedClimbs, on: date, calendar: calendar) {
            return climb
        }

        return dailyClimb(
            from: sortedDailyClimbs(availableClimbs),
            on: date,
            calendar: calendar
        )
    }

    static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let effectiveDate = effectiveRecommendationDate(for: date, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: effectiveDate)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func nextRolloverDate(
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        var rolloverComponents = DateComponents()
        rolloverComponents.calendar = calendar
        rolloverComponents.timeZone = calendar.timeZone
        rolloverComponents.year = dateComponents.year
        rolloverComponents.month = dateComponents.month
        rolloverComponents.day = dateComponents.day
        rolloverComponents.hour = rolloverHour
        rolloverComponents.minute = 0
        rolloverComponents.second = 0

        guard let todayRollover = calendar.date(from: rolloverComponents) else {
            return nil
        }

        if date < todayRollover {
            return todayRollover
        }

        return calendar.date(byAdding: .day, value: 1, to: todayRollover)
    }

    static func rolloverDate(
        offsetByDays dayOffset: Int,
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let nextRollover = nextRolloverDate(after: date, calendar: calendar) else {
            return nil
        }

        return calendar.date(byAdding: .day, value: dayOffset, to: nextRollover)
    }

    private static func sortedDailyClimbs(_ climbs: [Climb]) -> [Climb] {
        climbs.sorted { lhs, rhs in
            if lhs.tier == rhs.tier {
                return lhs.id < rhs.id
            }
            return lhs.tier < rhs.tier
        }
    }

    private static func dailyClimb(
        from climbs: [Climb],
        on date: Date,
        calendar: Calendar
    ) -> Climb? {
        guard !climbs.isEmpty else { return nil }

        let effectiveDate = effectiveRecommendationDate(for: date, calendar: calendar)
        let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: effectiveDate) ?? 0
        return climbs[dayOrdinal % climbs.count]
    }

    private static func effectiveRecommendationDate(
        for date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.date(byAdding: .hour, value: -rolloverHour, to: date) ?? date
    }
}
