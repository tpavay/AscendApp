import Foundation

/// How many days a week a climber chose to climb: one to seven, or nothing at all.
///
/// A target is optional and belongs to the climber who set it. Everyone has the week streak
/// (`WeeklyStreak`, a week with any climb) whether or not they set one; the weekly ring on Home
/// exists only for a climber who did.
struct WeeklyTarget: Equatable, Hashable, Codable, Sendable {
    static let validDays = 1...7

    let days: Int

    init?(days: Int) {
        guard Self.validDays.contains(days) else { return nil }
        self.days = days
    }

    /// What the number says about the climber, as onboarding's big label and Settings read it.
    enum Tier: Equatable, Sendable {
        case easeIn, steadyClimber, serious, allIn

        var title: String {
            switch self {
            case .easeIn: "EASE IN"
            case .steadyClimber: "STEADY CLIMBER"
            case .serious: "SERIOUS"
            case .allIn: "ALL IN"
            }
        }
    }

    var tier: Tier {
        switch days {
        case ...2: .easeIn
        case 3...4: .steadyClimber
        case 5: .serious
        default: .allIn
        }
    }

    /// "3 days a week", "1 day a week".
    var summary: String {
        days == 1 ? "1 day a week" : "\(days) days a week"
    }
}

/// How far through this week's target a climber is: the distinct days they climbed in the app's
/// Monday week, against the days they chose.
///
/// There is no progress without a target, which is how the ring stays away from a climber who
/// skipped it.
struct WeeklyTargetProgress: Equatable, Sendable {
    let target: WeeklyTarget
    /// Different calendar days this week with a climb. Two climbs on one Monday are one day.
    let daysClimbed: Int

    /// Whether the week's days are all climbed, so the ring closes.
    var isMet: Bool { daysClimbed >= target.days }

    var daysRemaining: Int { max(target.days - daysClimbed, 0) }

    /// The ring's fill, 0 through 1.
    var fraction: Double {
        min(Double(daysClimbed) / Double(target.days), 1)
    }

    /// The progress at `referenceDate`, or nil for a climber with no target.
    static func current(
        target: WeeklyTarget?,
        climbDates: some Sequence<Date>,
        referenceDate: Date = .now,
        calendar: Calendar = WeekConfiguration.calendar()
    ) -> WeeklyTargetProgress? {
        guard let target,
              let week = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return nil }

        let days = Set(
            climbDates
                .filter { week.contains($0) }
                .map { calendar.startOfDay(for: $0) }
        )
        return WeeklyTargetProgress(target: target, daysClimbed: days.count)
    }
}
