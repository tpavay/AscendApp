import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// The captain's 1:30:07 Just Climb, as the pre-fix sampler stored it, drawn by the shipping
/// completion summary and Workout Detail's splits.
///
/// On 1.1 this screen read 3,514 steps at 351 spm for 50:00-1:00:00, 0 steps for every segment
/// after it, and an SPM trend that spiked and fell to zero, `-83 SPM` start to finish. The recorder
/// kept nothing after 59:50 but the total, so the honest screen splits the first hour and shows
/// the rest as one row labelled as its average. Each surface is hosted through `RenderedScreen` at
/// phone width with the height opened up, and read back off the accessibility tree.
///
/// The PNG lands in `ASCEND_EVIDENCE_DIR` when set and is not taken otherwise.
@MainActor
@Suite(.hostsAWindow)
struct LiveClimbLongClimbSummaryEvidenceTests {
    @Test
    func theCaptainsNinetyMinuteClimbSummarisesEverySegmentItRan() async throws {
        let workout = try Self.captainsClimb()

        let copy = try await RenderedScreen.host(
            LiveClimbCompletionSummaryView(
                climb: nil,
                workout: workout,
                leaderboardRank: nil,
                leaderboardTotal: nil,
                leaderboardRankBasis: .current,
                leaderboardContext: nil,
                onDone: { _ in }
            )
            .modelContainer(try #require(Self.container)),
            size: CGSize(width: 393, height: 2_400)
        ) { screen in
            let copy = try await screen.copy { $0.contains("not split") }
            try screen.photograph(named: "live-climb-summary-ninety-minute-splits")
            return copy
        }

        #expect(copy.contains("7 segments"))
        #expect(copy.contains("7,708"))
        // The whole last half hour no longer lands in 50:00-1:00:00, and nothing reads as empty...
        #expect(!copy.contains("3,514 steps"))
        #expect(!copy.contains("351 steps per minute"))
        #expect(!copy.contains(", 0 steps"))
        #expect(!copy.contains("-83"))
        // ...and the stretch that was never split says so instead of passing for three segments.
        #expect(copy.contains("1:00:00-1:30:07"))
        #expect(copy.contains("not split"))
        #expect(copy.contains("recorded before splits ran past the hour"))
        #expect(copy.contains("pace through 1:00:00"))
    }

    @Test
    func workoutDetailLabelsTheUnsplitStretchTheSameWay() async throws {
        let workout = try Self.captainsClimb()
        let splits = LiveClimbWorkoutSummaryData.paceSplits(for: workout, targetSteps: workout.steps)

        let copy = try await RenderedScreen.host(
            WorkoutPaceSplitsSection(
                splits: splits,
                averageStepsPerMinute: workout.stepsPerMinute,
                effectiveColorScheme: .dark
            )
            .padding(20)
            .background(Color.black),
            size: CGSize(width: 393, height: 1_400)
        ) { screen in
            let copy = try await screen.copy { $0.contains("1:30:07") }
            try screen.photograph(named: "workout-detail-ninety-minute-splits")
            return copy
        }

        #expect(copy.contains("7 segments"))
        #expect(copy.contains("not split"))
        #expect(copy.contains("recorded before splits ran past the hour"))
        #expect(!copy.contains(", 0 steps"))
    }

    // MARK: - Fixture

    private struct PreFixSamplerClimbs: Decodable {
        struct Climb: Decodable {
            let name: String
            let steps: Int
            let durationSeconds: Double
            let splitIntervalSeconds: Int
            let splitSteps: [Int]
        }

        let climbs: [Climb]
    }

    private static func captainsClimb() throws -> Workout {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent() // AscendAppTests/
            .deletingLastPathComponent() // repo root
        let data = try Data(
            contentsOf: repoRoot.appending(path: "SharedTestVectors/pre-fix-sampler-long-climbs.json")
        )
        let climb = try #require(
            try JSONDecoder().decode(PreFixSamplerClimbs.self, from: data)
                .climbs.first { $0.name == "steady-84-spm-1h30m" }
        )
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: climb.splitSteps.count,
            trackingMode: .justClimb,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped,
            splitCurve: LiveReplaySplitCurve(
                intervalSeconds: climb.splitIntervalSeconds,
                steps: climb.splitSteps
            )
        )

        return Workout(
            name: "Just Climb",
            duration: climb.durationSeconds,
            steps: climb.steps,
            floors: Workout.stepsToFloors(climb.steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    /// Held for the process, not per render - see the note in `CompletedClimbRankSummaryEvidenceTests`.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}
