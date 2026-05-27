import Foundation
import Testing
@testable import AscendApp

@MainActor
struct ProfileComparisonSummaryTests {
    @Test
    func sharedClimbRecordUsesBestCompletionDuration() {
        let viewer = snapshot(
            userId: "viewer",
            workouts: [
                workout(id: "viewer-everest-fast", climbId: "everest", duration: 1_000),
                workout(id: "viewer-space-needle", climbId: "space-needle", duration: 900)
            ]
        )
        let otherUser = snapshot(
            userId: "other",
            workouts: [
                workout(id: "other-everest", climbId: "everest", duration: 1_200),
                workout(id: "other-space-needle", climbId: "space-needle", duration: 700)
            ]
        )

        let comparison = ProfileSnapshotBuilder.comparison(viewer: viewer, otherUser: otherUser)

        #expect(comparison.state == .shared)
        #expect(comparison.sharedClimbCount == 2)
        #expect(comparison.viewerWins == 1)
        #expect(comparison.otherUserWins == 1)
    }

    private func snapshot(userId: String, workouts: [ProfileWorkoutSummary]) -> ProfileSnapshot {
        ProfileSnapshot(
            identity: ProfileUserIdentity(userId: userId, displayName: userId),
            stats: ProfileStatsSnapshot(
                totalClimbsCompleted: workouts.count,
                totalFirstAscents: 0,
                achievementCounts: .zero,
                mostCompletedClimbId: nil,
                currentStreakWeeks: 0,
                bestStreakWeeks: 0,
                prMostSteps: 0,
                prLongestClimbSeconds: 0,
                prHighestSPM: 0
            ),
            standings: [],
            activityWorkouts: workouts,
            collection: ProfileCollectionSummary(
                collectedCount: Set(workouts.compactMap(\.climbId)).count,
                catalogCount: 0,
                previewCards: []
            ),
            achievements: .zero,
            firstAscentsHeld: [],
            openFirstAscents: [],
            records: ProfileRecordSummary(personalRecords: [], featuredBestEffort: nil),
            trends: ProfileTrendSummary(currentSteps: 0, previousSteps: 0, daysWithData: 0),
            recentWorkouts: workouts
        )
    }

    private func workout(id: String, climbId: String, duration: TimeInterval) -> ProfileWorkoutSummary {
        ProfileWorkoutSummary(
            id: id,
            name: climbId,
            startedAt: Date(),
            durationSeconds: duration,
            steps: 1_000,
            source: .headphoneMotion,
            climbId: climbId,
            climbTier: .common
        )
    }
}
