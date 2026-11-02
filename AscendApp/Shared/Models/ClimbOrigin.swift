import Foundation

/// How a climb came to exist.
///
/// Shown to a climber in two places only: the Imports list, which is Apple Health's own, and the
/// footnote at the foot of a climb's detail. No row, board, record or history list draws it.
///
/// A reading of `WorkoutSource`, not a second column: that raw value is already stored, filterable
/// and synced under exactly these distinctions, and a parallel one would only be a second place to
/// disagree. The older provider cases (`garmin`, `fitbit`, `hevy`) were never produced and read as
/// imported.
enum ClimbOrigin: String, CaseIterable, Sendable {
    /// Recorded by Ascend's own sensor flow: a Live Climb, a routine, a recovered session.
    case live
    /// Brought in from Apple Health or another provider.
    case healthImport
    /// Typed in by hand.
    case manual

    /// The footnote on a climb's detail, or nil for a live climb, which says nothing.
    var detailFootnote: String? {
        switch self {
        case .live:
            return nil
        case .healthImport:
            return "Imported from Apple Health"
        case .manual:
            return "Logged by hand"
        }
    }
}

extension WorkoutSource {
    var climbOrigin: ClimbOrigin {
        switch self {
        case .headphoneMotion:
            return .live
        case .manual:
            return .manual
        case .appleHealth, .garmin, .fitbit, .hevy:
            return .healthImport
        }
    }
}
