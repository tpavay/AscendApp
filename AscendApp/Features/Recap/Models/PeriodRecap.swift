import Foundation

/// One climber's recap of one closed week or month
/// (`users/{uid}/recaps/{cadence}_{periodKey}`), composed by the server at 00:30 UTC.
///
/// The recap email sends from the same stored document, so the app and the email can
/// never tell a climber two different stories about the same week.
struct PeriodRecap: Identifiable, Equatable, Sendable {
    enum Variant: String, Sendable {
        case active
        case inactive
        case neverClimbed = "never_climbed"
    }

    struct FirstAscent: Equatable, Sendable {
        let climbId: String
        /// Nil when the server's catalogue could not name the climb; the app names it from
        /// its own catalogue instead of dropping a badge the climber earned.
        let name: String?
    }

    struct Active: Equatable, Sendable {
        /// Only present when the period had enough climbers for a rank to mean something.
        let rank: Int?
        let climberCount: Int?
        let percentileBand: String?
        let climbs: Int
        let steps: Int
        let floors: Int
        let previousClimbs: Int?
        let previousSteps: Int?
        /// The exact rank the period's achievement record froze, when one was awarded.
        let awardRank: Int?
        let firstAscents: [FirstAscent]
        let landmarksFinished: [String]
    }

    struct Inactive: Equatable, Sendable {
        let gapCount: Int
        let lastClimbAt: Date?
        let suggestedClimbId: String?
        let suggestedClimbName: String?
    }

    let id: String
    let period: LeaderboardPeriod
    let variant: Variant
    let active: Active?
    let inactive: Inactive?
    let seenAt: Date?

    var cadence: LeaderboardTimeFrame {
        period.timeFrame
    }

    var resultID: String {
        LeaderboardResult.documentID(timeFrame: period.timeFrame, periodKey: period.key)
    }

    static func documentID(cadence: LeaderboardTimeFrame, periodKey: String) -> String {
        "\(cadence.rawValue)_\(periodKey)"
    }
}
