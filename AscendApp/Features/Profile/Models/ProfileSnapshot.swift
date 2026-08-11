import Foundation

struct ProfileDemographicsSnapshot: Equatable, Sendable {
    let userId: String
    var age: Int?
    var gender: ProfileGender?
    var weightKg: Double?
    var heightCm: Double?
    var locationCity: String?
    var locationCountryCode: String?
    var locationRegionCode: String?
    var joinedAt: Date?

    init(
        userId: String,
        age: Int? = nil,
        gender: ProfileGender? = nil,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        locationCity: String? = nil,
        locationCountryCode: String? = nil,
        locationRegionCode: String? = nil,
        joinedAt: Date? = nil
    ) {
        self.userId = userId
        self.age = age
        self.gender = gender
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.locationCity = locationCity
        self.locationCountryCode = locationCountryCode
        self.locationRegionCode = locationRegionCode
        self.joinedAt = joinedAt
    }
}

struct ProfileSnapshot {
    var demographics: ProfileDemographicsSnapshot
    var stats: ProfileStatsSnapshot
    var standings: [ProfileStanding]
    var activityWorkouts: [ProfileWorkoutSummary]
    var collection: ProfileCollectionSummary
    var achievements: ProfileAchievementLadder
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

    var totalClimbsCollected: Int {
        collection.collectedCount
    }
}
