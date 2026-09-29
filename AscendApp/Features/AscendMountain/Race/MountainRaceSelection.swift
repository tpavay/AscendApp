import Foundation

/// Who races the climber on the Mountain: the sheet's four switches.
///
/// Settled by the captain on 2026-09-29. Every climb starts with everyone's best on the stairs
/// and the rest off; your best and a pacer tap on and off beside them. Just you hides everyone
/// without touching the other switches, so turning it off brings back exactly what was on.
struct MountainRaceSelection: Equatable, Sendable {
    static let pacerRange = 40...200
    static let pacerIncrement = 5

    var everyone = true
    var yourBest = false
    var pacer = false
    var pacerStepsPerMinute = 90
    var justYou = false

    var showsEveryone: Bool { everyone && !justYou }
    var showsYourBest: Bool { yourBest && !justYou }
    var showsPacer: Bool { pacer && !justYou }

    mutating func stepPacer(by increments: Int) {
        pacerStepsPerMinute = min(
            max(pacerStepsPerMinute + increments * Self.pacerIncrement, Self.pacerRange.lowerBound),
            Self.pacerRange.upperBound
        )
    }
}
