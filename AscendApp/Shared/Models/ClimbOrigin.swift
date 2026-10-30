import Foundation

/// How a climb came to exist, in the three words a climber and a leaderboard row use for it.
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

    /// What a climb's source icon says, spoken.
    var accessibilityLabel: String {
        switch self {
        case .live:
            return "Recorded live"
        case .healthImport:
            return "Imported"
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
