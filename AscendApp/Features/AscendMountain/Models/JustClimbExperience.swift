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

    /// The climber's last choice on the setup sheet, Mountain until they have made one.
    static func remembered(in defaults: UserDefaults = .standard) -> JustClimbExperience {
        defaults.string(forKey: JustClimbSetupSheet.experienceKey).flatMap(Self.init(rawValue:)) ?? .mountain
    }

    var title: String {
        switch self {
        case .classic:
            return "Classic"
        case .mountain:
            return "Mountain"
        }
    }
}
