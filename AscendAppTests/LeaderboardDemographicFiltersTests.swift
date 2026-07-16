import Foundation
import Testing
@testable import AscendApp

struct LeaderboardDemographicFiltersTests {
    @Test
    func ageGroupMatchesOnlyItsRange() {
        #expect(LeaderboardAgeGroup.age25To29.contains(age: 25))
        #expect(LeaderboardAgeGroup.age25To29.contains(age: 29))
        #expect(!LeaderboardAgeGroup.age25To29.contains(age: 30))
        #expect(!LeaderboardAgeGroup.age25To29.contains(age: nil))
    }

    @Test
    func pounds200PlusUsesStoredMetricWeight() {
        let thresholdKg = MeasurementSystem.imperial.convertWeight(200, to: .metric)

        #expect(LeaderboardBodyWeightFilter.pounds200Plus.contains(weightKg: thresholdKg))
        #expect(LeaderboardBodyWeightFilter.pounds200Plus.contains(weightKg: thresholdKg + 0.1))
        #expect(!LeaderboardBodyWeightFilter.pounds200Plus.contains(weightKg: thresholdKg - 0.1))
        #expect(!LeaderboardBodyWeightFilter.pounds200Plus.contains(weightKg: nil))
    }

    @Test
    func locationFilterMatchesCurrentProfileLocation() {
        let currentProfile = LeaderboardProfileSnapshot(
            userId: "current",
            locationCity: "Austin",
            locationCountry: "US",
            locationRegion: "TX"
        )
        let matchingStats = stats(
            userId: "match",
            locationCity: "austin",
            locationCountry: "us",
            locationRegion: "tx"
        )
        let otherStats = stats(
            userId: "other",
            locationCity: "Dallas",
            locationCountry: "US",
            locationRegion: "TX"
        )

        #expect(LeaderboardLocationFilter.currentCity.contains(
            stats: matchingStats,
            currentUserProfile: currentProfile
        ))
        #expect(!LeaderboardLocationFilter.currentCity.contains(
            stats: otherStats,
            currentUserProfile: currentProfile
        ))
        #expect(LeaderboardLocationFilter.currentRegion.contains(
            stats: otherStats,
            currentUserProfile: currentProfile
        ))
    }

    private func stats(
        userId: String,
        locationCity: String?,
        locationCountry: String?,
        locationRegion: String?
    ) -> FirestoreLeaderboardStats {
        FirestoreLeaderboardStats(
            userId: userId,
            displayName: userId,
            timeFrame: LeaderboardTimeFrame.weekly.rawValue,
            schemaVersion: LeaderboardStats.currentSchemaVersion,
            periodKey: "2026-W24",
            periodStartAt: Date(timeIntervalSince1970: 0),
            totalSteps: 100,
            totalFloors: 10,
            totalWorkouts: 1,
            totalDuration: 100,
            stepsPerMinute: 60,
            lastUpdated: Date(timeIntervalSince1970: 0),
            locationCity: locationCity,
            locationCountry: locationCountry,
            locationRegion: locationRegion
        )
    }
}
