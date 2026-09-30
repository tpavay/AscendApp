import Foundation

struct ProfileHeadToHeadClimbResult: Identifiable, Equatable {
    enum Winner: Equatable {
        case viewer
        case otherUser
        case tie
    }

    /// What "best" means on this climb, straight from The rank model in `ascend-leaderboards` -
    /// never a definition of its own.
    enum Measure: Equatable {
        /// A fixed-height landmark: every finisher climbs the same steps, so only the clock
        /// separates them and the faster completion wins.
        case completionTime(viewerSeconds: TimeInterval, otherUserSeconds: TimeInterval)
        /// An open Just Climb: a climber's best is their most-steps run (settled 2026-09-22), so
        /// the longer climb wins however long it took.
        case mostSteps(viewerSteps: Int, otherUserSteps: Int)
    }

    /// The row id of the single Just Climb matchup. Landmark rows use their climb id.
    static let justClimbID = "just-climb"

    let id: String
    let climbName: String
    /// The landmark's step count, shown under its name. `nil` on the Just Climb row, which has
    /// no fixed height.
    let stepCount: Int?
    let measure: Measure
    let mostRecentAt: Date?

    var winner: Winner {
        switch measure {
        case let .completionTime(viewerSeconds, otherUserSeconds):
            return Self.winner(viewer: -viewerSeconds, otherUser: -otherUserSeconds)
        case let .mostSteps(viewerSteps, otherUserSteps):
            return Self.winner(viewer: Double(viewerSteps), otherUser: Double(otherUserSteps))
        }
    }

    private static func winner(viewer: Double, otherUser: Double) -> Winner {
        if viewer > otherUser { return .viewer }
        if otherUser > viewer { return .otherUser }
        return .tie
    }
}
