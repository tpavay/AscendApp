import Foundation

extension AppTab {
    /// The screen this tab root reports each time it becomes the mounted tab.
    ///
    /// Exhaustive on purpose: a fifth tab cannot ship uninstrumented, because this switch
    /// stops compiling until it is named.
    var telemetryScreenName: TelemetryScreenName {
        switch self {
        case .home: .home
        case .training: .routines
        case .leaderboard: .leaderboard
        case .profile: .profile
        }
    }
}
