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
    /// `nil` when no climb carries heart rate, which is how the comparison knows to leave the
    /// row out rather than print a zero. Derivation: `ProfileHeartRateSummary`.
    var heartRate: ProfileHeartRateSummary?

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
        averageStepsPerMinute: Double = 0,
        heartRate: ProfileHeartRateSummary? = nil
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
        self.heartRate = heartRate
    }

    /// Averaged over every recorded climb - completed or not - so it is exactly the ALL-TIME
    /// `Steps` total divided by the `Climbs` count drawn beside it on the same screen. Both
    /// totals are already public, which is why this needs no field of its own.
    var averageStepsPerClimb: Double? {
        guard totalClimbs > 0, lifetimeTotalSteps > 0 else { return nil }
        return Double(lifetimeTotalSteps) / Double(totalClimbs)
    }

    /// Same population as `averageStepsPerClimb`: the ALL-TIME `Duration` over `Climbs`.
    var averageClimbDurationSeconds: TimeInterval? {
        guard totalClimbs > 0, lifetimeDurationSeconds > 0 else { return nil }
        return TimeInterval(lifetimeDurationSeconds) / TimeInterval(totalClimbs)
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
