import Foundation

struct ProfileStatsSnapshot: Equatable {
    var totalClimbsCompleted: Int
    var totalFirstAscents: Int
    var achievementCounts: ProfileAchievementCounts
    var mostCompletedClimbId: String?
    var currentStreakWeeks: Int
    var bestStreakWeeks: Int
    var prMostSteps: Int
    var prLongestClimbSeconds: Int
    var prHighestSPM: Double

    static let empty = ProfileStatsSnapshot(
        totalClimbsCompleted: 0,
        totalFirstAscents: 0,
        achievementCounts: .zero,
        mostCompletedClimbId: nil,
        currentStreakWeeks: 0,
        bestStreakWeeks: 0,
        prMostSteps: 0,
        prLongestClimbSeconds: 0,
        prHighestSPM: 0
    )
}
