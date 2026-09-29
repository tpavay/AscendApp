import Foundation

/// How a Just Climb is shown on the live screen.
///
/// Both run the identical session - steps, time, pace, heart rate, goals, saving and the
/// leaderboard all come from `LiveClimbSessionViewModel` - so this is a presentation choice and
/// is never stored on the workout. Ascend Mountain renders that same session as an avatar
/// climbing an endless staircase.
enum JustClimbExperience: String, CaseIterable, Identifiable, Sendable {
    case classic
    case mountain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            return "Classic"
        case .mountain:
            return "Mountain"
        }
    }
}
