import Foundation

enum HomeStartAction: CaseIterable, Hashable {
    case justClimb
    case browseClimbs
    case routines

    var title: String {
        switch self {
        case .justClimb:
            return "Just Climb"
        case .browseClimbs:
            return "Race a Landmark"
        case .routines:
            return "Run a Routine"
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
        }
    }
}
