import Foundation

/// One completed landmark, as seen through `ClimbCompletionRepository`. It is
/// distinct per landmark (`climbId`): completing a climb three times is one entry
/// here, which is what ends the "globe 1, aggregate 3" divergence.
struct CompletedClimb: Equatable, Sendable {
    let climbId: String
    let firstCompletedAt: Date
    let latestCompletedAt: Date
    let attemptCount: Int
    let bestElapsedSeconds: Int?
}

/// The single definition of the completed-climb set. Every completion surface -
/// the globe numerator, Collection claimed state, and `totalClimbsCompleted` -
/// reads this one value so they agree by construction; nobody recomputes a
/// competing definition.
struct CompletedClimbSet: Equatable, Sendable {
    let climbs: [CompletedClimb]

    static let empty = CompletedClimbSet(climbs: [])

    /// The distinct set of completed landmark ids - the one distinct-climb
    /// definition every surface reads.
    var completedClimbIds: Set<String> {
        Set(climbs.map(\.climbId))
    }

    /// The distinct completed-climb count (== `completedClimbIds.count`).
    var completedCount: Int {
        completedClimbIds.count
    }
}
