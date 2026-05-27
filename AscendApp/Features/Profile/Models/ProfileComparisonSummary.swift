import Foundation

struct ProfileComparisonSummary: Equatable {
    enum State: Equatable {
        case hidden
        case viewerEmpty
        case noSharedClimbs
        case shared
    }

    let state: State
    let sharedClimbCount: Int
    let viewerWins: Int
    let otherUserWins: Int
    let viewerExclusiveCount: Int
    let otherExclusiveCount: Int
}
