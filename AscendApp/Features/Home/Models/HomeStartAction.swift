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
            return "Climb a Landmark"
        case .routines:
            return "Run a Routine"
        }
    }

    /// What the row says when it has no pick of its own to name: the first line for Just Climb, and
    /// the fallback for the other two while the catalog or a built-in routine is not in hand.
    var subtitle: String {
        switch self {
        case .justClimb:
            return "The mountain, with whoever you want."
        case .browseClimbs:
            return "Choose by step count, then chase the leaderboard."
        case .routines:
            return "Follow structured intervals on the stair stepper."
        }
    }

    var glyph: HomeStartGlyph {
        switch self {
        case .justClimb:
            return .stairs
        case .browseClimbs:
            return .tower
        case .routines:
            return .bars
        }
    }

    /// Only the two lists have somewhere to go besides the row itself.
    var offersSeeAll: Bool {
        self != .justClimb
    }
}
