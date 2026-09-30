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
        #expect(comparison.ties == 0)
    }

    // The settled rule (2026-09-22): a climber's Just Climb best is their most-steps run, so a
    // short fast session must never beat a long one because it took less time.
    @Test
    func theJustClimbMatchupIsWonOnMostStepsNotTime() {
        let viewer = snapshot(
            userId: "viewer",
            workouts: [justClimb(id: "viewer-quick", steps: 149, duration: 60)],
            mostSteps: 149
        )
        let otherUser = snapshot(
            userId: "other",
            workouts: [justClimb(id: "other-long", steps: 1_776, duration: 1_800)],
            mostSteps: 1_776
        )

        let results = ProfileSnapshotBuilder.headToHeadResults(
            viewer: viewer,
            otherUser: otherUser,
            climbs: []
        )
        let comparison = ProfileSnapshotBuilder.comparison(viewer: viewer, otherUser: otherUser)

        #expect(results.map(\.id) == [ProfileHeadToHeadClimbResult.justClimbID])
        #expect(results.first?.measure == .mostSteps(viewerSteps: 149, otherUserSteps: 1_776))
        #expect(results.first?.winner == .otherUser)
        #expect(comparison.state == .shared)
        #expect(comparison.viewerWins == 0)
        #expect(comparison.otherUserWins == 1)
    }

    @Test
    func landmarksKeepFastestTimeBesideTheJustClimbMatchup() {
        let viewer = snapshot(
            userId: "viewer",
            workouts: [workout(id: "viewer-needle", climbId: "space-needle", duration: 700, steps: 848)],
            mostSteps: 2_400
        )
        let otherUser = snapshot(
            userId: "other",
            workouts: [workout(id: "other-needle", climbId: "space-needle", duration: 900, steps: 848)],
            mostSteps: 1_200
        )

        let results = ProfileSnapshotBuilder.headToHeadResults(
            viewer: viewer,
            otherUser: otherUser,
            climbs: []
        )
        let comparison = ProfileSnapshotBuilder.comparison(viewer: viewer, otherUser: otherUser)

        #expect(results.map(\.id) == [ProfileHeadToHeadClimbResult.justClimbID, "space-needle"])
        #expect(results.last?.measure == .completionTime(viewerSeconds: 700, otherUserSeconds: 900))
        #expect(results.allSatisfy { $0.winner == .viewer })
        #expect(comparison.sharedClimbCount == 2)
        #expect(comparison.viewerWins == 2)
    }

    @Test
    func equalMostStepsIsATie() {
        let viewer = snapshot(userId: "viewer", workouts: [justClimb(id: "a", steps: 900, duration: 600)], mostSteps: 900)
        let otherUser = snapshot(userId: "other", workouts: [justClimb(id: "b", steps: 900, duration: 300)], mostSteps: 900)

        let comparison = ProfileSnapshotBuilder.comparison(viewer: viewer, otherUser: otherUser)

        #expect(comparison.ties == 1)
        #expect(comparison.viewerWins == 0)
        #expect(comparison.otherUserWins == 0)
    }

    @Test
    func aViewerWithNoClimbsHasNothingToCompare() {
        let viewer = snapshot(userId: "viewer", workouts: [], mostSteps: 0)
        let otherUser = snapshot(
            userId: "other",
            workouts: [justClimb(id: "other", steps: 1_000, duration: 600)],
            mostSteps: 1_000
        )

        let comparison = ProfileSnapshotBuilder.comparison(viewer: viewer, otherUser: otherUser)

        #expect(comparison.state == .viewerEmpty)
        #expect(ProfileSnapshotBuilder.headToHeadResults(viewer: viewer, otherUser: otherUser, climbs: []).isEmpty)
    }

    private func snapshot(
        userId: String,
        workouts: [ProfileWorkoutSummary],
        mostSteps: Int = 0
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            demographics: ProfileDemographicsSnapshot(userId: userId),
            stats: ProfileStatsSnapshot(
                totalClimbsCompleted: workouts.count,
                totalFirstAscents: 0,
                achievementCounts: .zero,
                mostCompletedClimbId: nil,
                currentStreakWeeks: 0,
                bestStreakWeeks: 0,
            prMostSteps: mostSteps,
            prLongestClimbSeconds: 0,
            prHighestSPM: 0,
            lifetimeTotalSteps: workouts.reduce(0) { $0 + $1.steps },
            lifetimeDurationSeconds: Int(workouts.reduce(0.0) { $0 + $1.durationSeconds }),
            totalClimbs: workouts.count,
            averageStepsPerMinute: 0
            ),
            standings: [],
            activityWorkouts: workouts,
            collection: ProfileCollectionSummary(
                collectedCount: Set(workouts.compactMap(\.climbId)).count,
                catalogCount: 0,
                previewCards: [],
                launchedCards: [],
                comingSoonClimbs: []
            ),
            achievements: .empty,
            firstAscentsHeld: [],
            openFirstAscents: [],
            records: ProfileRecordSummary(personalRecords: [], featuredBestEffort: nil),
            trends: ProfileTrendSummary(currentSteps: 0, previousSteps: 0, daysWithData: 0),
            recentWorkouts: workouts
        )
    }

    private func justClimb(id: String, steps: Int, duration: TimeInterval) -> ProfileWorkoutSummary {
        ProfileWorkoutSummary(
            id: id,
            name: "Just Climb",
            startedAt: Date(),
            durationSeconds: duration,
            steps: steps,
            source: .headphoneMotion,
            climbId: nil,
            climbTier: nil,
            climbCompletionStatus: nil,
            climbCompletionDurationSeconds: nil
        )
    }

    private func workout(
        id: String,
        climbId: String,
        duration: TimeInterval,
        steps: Int = 1_000
    ) -> ProfileWorkoutSummary {
        ProfileWorkoutSummary(
            id: id,
            name: climbId,
            startedAt: Date(),
            durationSeconds: duration,
            steps: steps,
            source: .headphoneMotion,
            climbId: climbId,
            climbTier: .common,
            climbCompletionStatus: .completed,
            climbCompletionDurationSeconds: Int(duration)
        )
    }
}
