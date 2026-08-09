import Foundation
import Testing
@testable import AscendApp

@MainActor
struct ProfileCollectionSummaryTests {
    @Test
    func emptyCollectionShowsThreeEasiestAvailableRecommendations() {
        let snapshot = snapshot(
            attempts: [],
            climbs: [
                climb(id: "gold-low-steps", tier: .gold, steps: 300),
                climb(id: "common-high-steps", tier: .common, steps: 900),
                climb(id: "common-low-steps", tier: .common, steps: 500),
                climb(id: "bronze-low-steps", tier: .bronze, steps: 250),
                climb(id: "coming-soon", tier: .common, steps: 100, releaseState: .comingSoon)
            ]
        )

        #expect(snapshot.collection.catalogCount == 4)
        #expect(snapshot.collection.collectedCount == 0)
        #expect(snapshot.collection.comingSoonClimbs.map(\.id) == ["coming-soon"])
        #expect(snapshot.collection.previewCards.map(\.climb.id) == [
            "common-low-steps",
            "common-high-steps",
            "bronze-low-steps"
        ])
        #expect(snapshot.collection.launchedCards.map(\.climb.id) == [
            "common-low-steps",
            "common-high-steps",
            "bronze-low-steps",
            "gold-low-steps"
        ])
    }

    @Test
    func previewShowsRecentClaimsThenRecommendations() {
        let olderClaimDate = Date(timeIntervalSince1970: 1_000)
        let recentClaimDate = Date(timeIntervalSince1970: 3_000)
        let snapshot = snapshot(
            attempts: [
                attempt(climbId: "gold-claimed", completedAt: olderClaimDate),
                attempt(climbId: "silver-claimed", completedAt: recentClaimDate)
            ],
            climbs: [
                climb(id: "common-recommendation", tier: .common, steps: 600),
                climb(id: "gold-claimed", tier: .gold, steps: 500),
                climb(id: "silver-claimed", tier: .silver, steps: 700),
                climb(id: "bronze-recommendation", tier: .bronze, steps: 400)
            ]
        )

        #expect(snapshot.collection.collectedCount == 2)
        #expect(snapshot.collection.previewCards.map(\.climb.id) == [
            "silver-claimed",
            "gold-claimed",
            "common-recommendation"
        ])
        #expect(snapshot.collection.previewCards.compactMap(\.claimedAt) == [
            recentClaimDate,
            olderClaimDate
        ])
        #expect(snapshot.collection.launchedCards.map(\.climb.id) == [
            "common-recommendation",
            "bronze-recommendation",
            "silver-claimed",
            "gold-claimed"
        ])
        #expect(snapshot.collection.launchedCards.compactMap(\.claimedAt) == [
            recentClaimDate,
            olderClaimDate
        ])
    }

    @Test
    func launchedCollectionUsesProductOrderForKnownLaunchClimbs() {
        let snapshot = snapshot(
            attempts: [
                attempt(climbId: "taipei-101", completedAt: Date(timeIntervalSince1970: 1_000))
            ],
            climbs: [
                climb(id: "mount-everest", tier: .mythic, steps: 48_664),
                climb(id: "statue-of-liberty", tier: .bronze, steps: 377),
                climb(id: "taipei-101", tier: .gold, steps: 2_046),
                climb(id: "sydney-tower", tier: .gold, steps: 1_504),
                climb(id: "space-needle", tier: .silver, steps: 832),
                climb(id: "empire-state-building", tier: .gold, steps: 1_576),
                climb(id: "eiffel-tower", tier: .gold, steps: 1_665),
                climb(id: "burj-khalifa", tier: .diamond, steps: 2_909),
                climb(id: "table-mountain", tier: .legendary, steps: 6_023),
                climb(id: "machu-picchu", tier: .mythic, steps: 13_365)
            ]
        )

        #expect(snapshot.collection.launchedCards.map(\.climb.id) == [
            "taipei-101",
            "statue-of-liberty",
            "space-needle",
            "empire-state-building",
            "eiffel-tower",
            "burj-khalifa",
            "table-mountain",
            "machu-picchu",
            "mount-everest",
            "sydney-tower"
        ])
        #expect(snapshot.collection.launchedCards.first?.claimedAt != nil)
    }

    private func snapshot(attempts: [ClimbAttempt], climbs: [Climb]) -> ProfileSnapshot {
        ProfileSnapshotBuilder.makeOwnSnapshot(
            demographics: ProfileDemographicsSnapshot(userId: "test-user"),
            workouts: [],
            climbAttempts: attempts,
            bestEffortCacheEntries: [],
            achievements: .zero,
            standings: [],
            climbs: climbs,
            fitnessLevel: .beginner
        )
    }

    private func attempt(climbId: String, completedAt: Date) -> ClimbAttempt {
        ClimbAttempt(
            climbId: climbId,
            status: .completed,
            startedAt: completedAt.addingTimeInterval(-600),
            endedAt: completedAt,
            completedAt: completedAt,
            accumulatedSteps: 1_000,
            accumulatedDurationSeconds: 600,
            sessionsCount: 1
        )
    }

    private func climb(
        id: String,
        tier: ClimbTier,
        steps: Int,
        releaseState: ClimbReleaseState = .available
    ) -> Climb {
        Climb(
            id: id,
            name: id,
            city: "City",
            country: "Country",
            continent: "Continent",
            latitude: 0,
            longitude: 0,
            totalHeightMeters: Double(steps) * 0.25,
            totalHeightFeet: Double(steps) * 0.82,
            realClimbableHeightMeters: nil,
            realClimbableHeightFeet: nil,
            totalSteps: steps,
            realStairCount: nil,
            calculatedFloors: max(1, steps / 20),
            category: "tower",
            tier: tier,
            tags: [],
            funFact: "Test climb",
            sourceURL: "https://example.com",
            releaseState: releaseState
        )
    }
}
