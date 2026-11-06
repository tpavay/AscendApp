import Foundation

/// Every line screen 11 draws, resolved from the version it shows and what the climber answered.
/// Pure, so the copy table in the build spec is a test and not a reading of a view.
struct ThisMonthEventContent: Equatable {
    struct Tile: Equatable {
        let value: String
        let label: String
    }

    let kicker: String
    let headlineLines: [String]
    let subline: String
    let pieces: [OnboardingMonthlyEvent.Piece]
    let tiles: [Tile]
    let fineLine: String?

    init(
        presentation: OnboardingMonthlyEvent,
        landmarkCount: Int?,
        usualClimbSteps: Int?,
        usualClimbMinutes: Int?,
        weeklyTarget: WeeklyTarget?,
        calendar: Calendar = .current
    ) {
        let targetTile = weeklyTarget.map { Tile(value: "\($0.days)×", label: "A WEEK") }

        switch presentation {
        case .running(let running):
            let event = running.event
            kicker = "THIS MONTH"
            headlineLines = [event.title, "is on."]
            subline = "Climb this \(event.monthName) and earn gear for your athlete. Everyone can earn every piece."
            pieces = running.pieces
            tiles = [
                Tile(value: running.piecesToEarn.formatted(), label: "PIECES TO EARN"),
                Tile(value: running.daysLeft.formatted(), label: running.daysLeft == 1 ? "DAY LEFT" : "DAYS LEFT"),
                targetTile
            ].compactMap { $0 }
            fineLine = running.lastDay.map {
                "Ends \(OnboardingMonthlyEvent.shortDate($0, calendar: calendar)). A new event opens every month."
            }

        case .comingSoon(let upcoming):
            let opens = OnboardingMonthlyEvent.shortDate(upcoming.startsOn, calendar: calendar)
            kicker = "COMING \(opens.uppercased())"
            headlineLines = [upcoming.event.title, "starts soon."]
            subline = "Gear for your athlete opens on \(opens). Climb now and you're ready for it."
            pieces = upcoming.pieces
            tiles = [targetTile].compactMap { $0 }
            fineLine = nil

        case .neutral:
            kicker = "EVERY CLIMB COUNTS"
            headlineLines = ["You're ready", "to climb."]
            subline = landmarkCount.map {
                "Pick any of \($0.formatted()) real landmarks. Every climb lands on its board and counts toward your records."
            } ?? "Pick any real landmark. Every climb lands on its board and counts toward your records."
            pieces = []
            tiles = [
                usualClimbSteps.map { Tile(value: $0.formatted(), label: "STEPS A CLIMB") },
                usualClimbMinutes.map { Tile(value: "\($0)m", label: "EACH CLIMB") },
                targetTile
            ].compactMap { $0 }
            fineLine = nil
        }
    }
}
