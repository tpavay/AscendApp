import Foundation

struct ProfileRemoteBundle {
    var identity: ProfileUserIdentity?
    var stats: ProfileStatsSnapshot?
    var achievements: [ProfileAchievementRecord]
    var workoutSummaries: [ProfileWorkoutSummary]

    static let empty = ProfileRemoteBundle(
        identity: nil,
        stats: nil,
        achievements: [],
        workoutSummaries: []
    )
}
