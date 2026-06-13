import Foundation

struct ProfileStatsSnapshot: Equatable {
    var totalClimbsCompleted: Int
    var totalFirstAscents: Int
    var lifetimeTotalSteps: Int
    var lifetimeDurationSeconds: Int
    var totalClimbs: Int
    var averageStepsPerMinute: Double
    var achievementCounts: ProfileAchievementCounts
    var mostCompletedClimbId: String?
    var currentStreakWeeks: Int
    var bestStreakWeeks: Int
    var prMostSteps: Int
    var prLongestClimbSeconds: Int
    var prHighestSPM: Double

    init(
        totalClimbsCompleted: Int,
        totalFirstAscents: Int,
        achievementCounts: ProfileAchievementCounts,
        mostCompletedClimbId: String?,
        currentStreakWeeks: Int,
        bestStreakWeeks: Int,
        prMostSteps: Int,
        prLongestClimbSeconds: Int,
        prHighestSPM: Double,
        lifetimeTotalSteps: Int = 0,
        lifetimeDurationSeconds: Int = 0,
        totalClimbs: Int = 0,
        averageStepsPerMinute: Double = 0
    ) {
        self.totalClimbsCompleted = totalClimbsCompleted
        self.totalFirstAscents = totalFirstAscents
        self.lifetimeTotalSteps = lifetimeTotalSteps
        self.lifetimeDurationSeconds = lifetimeDurationSeconds
        self.totalClimbs = totalClimbs
        self.averageStepsPerMinute = averageStepsPerMinute
        self.achievementCounts = achievementCounts
        self.mostCompletedClimbId = mostCompletedClimbId
        self.currentStreakWeeks = currentStreakWeeks
        self.bestStreakWeeks = bestStreakWeeks
        self.prMostSteps = prMostSteps
        self.prLongestClimbSeconds = prLongestClimbSeconds
        self.prHighestSPM = prHighestSPM
    }

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
