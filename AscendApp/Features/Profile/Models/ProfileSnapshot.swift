import Foundation

struct ProfileSnapshot {
    var identity: ProfileUserIdentity
    var stats: ProfileStatsSnapshot
    var standings: [ProfileStanding]
    var activityWorkouts: [ProfileWorkoutSummary]
    var collection: ProfileCollectionSummary
    var achievements: ProfileAchievementCounts
    var achievementRecords: [ProfileAchievementRecord]
    var firstAscentsHeld: [ProfileFirstAscentSummary]
    var openFirstAscents: [ProfileFirstAscentSummary]
    var records: ProfileRecordSummary
    var trends: ProfileTrendSummary
    var recentWorkouts: [ProfileWorkoutSummary]

    var hasActiveRank: Bool {
        standings.contains { $0.hasRank }
    }

    var totalClimbsCompleted: Int {
        stats.totalClimbsCompleted
    }

    var totalClimbs: Int {
        stats.totalClimbs
    }

    var totalFirstAscents: Int {
        stats.totalFirstAscents
    }

    var totalMedalWeeks: Int {
        achievements.total
    }

    var totalClimbsCollected: Int {
        collection.collectedCount
    }
}
