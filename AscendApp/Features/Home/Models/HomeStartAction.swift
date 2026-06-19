import Foundation

enum HomeStartAction: CaseIterable, Hashable {
    case justClimb
    case browseClimbs
    case routines
    case manualWorkout

    var title: String {
        switch self {
        case .justClimb:
            return "Just Climb"
        case .browseClimbs:
            return "Race a Landmark"
        case .routines:
            return "Run a Routine"
        case .manualWorkout:
            return "Log Manual Workout"
        }
    }

    var subtitle: String {
        switch self {
        case .justClimb:
            return "Start stepping now. Add a goal if you want one."
        case .browseClimbs:
            return "Choose by step count, then chase the leaderboard."
        case .routines:
            return "Follow structured intervals on the stair stepper."
        case .manualWorkout:
            return "Enter steps and time from a finished session."
        }
    }

    var iconToken: AppIconToken {
        switch self {
        case .justClimb:
            return .infinity
        case .browseClimbs:
            return .globeHemisphereWest
        case .routines:
            return .clipboardText
        case .manualWorkout:
            return .manualWorkout
        }
    }
}
