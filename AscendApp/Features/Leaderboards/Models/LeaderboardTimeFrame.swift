import Foundation

enum LeaderboardTimeFrame: String, CaseIterable, Codable, Identifiable, Sendable {
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"
    case allTime = "all_time"

    static let canonicalTimeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        case .allTime:
            return "All Time"
        }
    }

    var shortName: String {
        switch self {
        case .weekly:
            return "Week"
        case .monthly:
            return "Month"
        case .yearly:
            return "Year"
        case .allTime:
            return "All"
        }
    }

    private var canonicalCalendar: Calendar {
        WeekConfiguration.calendar(timeZone: Self.canonicalTimeZone)
    }

    func currentPeriod(referenceDate: Date = Date()) -> LeaderboardPeriod {
        let calendar = canonicalCalendar

        switch self {
        case .weekly:
            let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) ??
                DateInterval(start: referenceDate, duration: 7 * 24 * 60 * 60)
            let year = calendar.component(.yearForWeekOfYear, from: interval.start)
            let week = calendar.component(.weekOfYear, from: interval.start)
            return LeaderboardPeriod(
                timeFrame: self,
                key: "\(year)-W\(week < 10 ? "0" : "")\(week)",
                startAt: interval.start,
                endAt: interval.end
            )
        case .monthly:
            let interval = calendar.dateInterval(of: .month, for: referenceDate) ??
                DateInterval(start: referenceDate, duration: 31 * 24 * 60 * 60)
            let year = calendar.component(.year, from: interval.start)
            let month = calendar.component(.month, from: interval.start)
            return LeaderboardPeriod(
                timeFrame: self,
                key: "\(year)-M\(month < 10 ? "0" : "")\(month)",
                startAt: interval.start,
                endAt: interval.end
            )
        case .yearly:
            let interval = calendar.dateInterval(of: .year, for: referenceDate) ??
                DateInterval(start: referenceDate, duration: 366 * 24 * 60 * 60)
            let year = calendar.component(.year, from: interval.start)
            return LeaderboardPeriod(
                timeFrame: self,
                key: "\(year)",
                startAt: interval.start,
                endAt: interval.end
            )
        case .allTime:
            return LeaderboardPeriod(
                timeFrame: self,
                key: "all",
                startAt: Date(timeIntervalSince1970: 0),
                endAt: nil
            )
        }
    }

    func contains(_ workoutDate: Date, referenceDate: Date = Date()) -> Bool {
        currentPeriod(referenceDate: referenceDate).contains(workoutDate, referenceDate: referenceDate)
    }

    func nextResetDate(from date: Date = Date()) -> Date? {
        currentPeriod(referenceDate: date).endAt
    }

    func resetDescription(from date: Date = Date(), displayTimeZone: TimeZone = .current) -> String {
        guard let resetDate = nextResetDate(from: date) else {
            return "This leaderboard never resets"
        }

        let formatter = DateFormatter()
        formatter.calendar = WeekConfiguration.calendar(timeZone: displayTimeZone)
        formatter.timeZone = displayTimeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE h:mm a")

        return "Resets \(formatter.string(from: resetDate))"
    }
}
