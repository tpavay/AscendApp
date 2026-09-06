import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence that the completion summary's splits card survives phone width.
///
/// The card is drawn by the shipping `LiveClimbCompletionSummaryView`, hosted through
/// `RenderedScreen` at the 393-point width of the phone Ascend ships against. Only the
/// height is opened up, so the whole scroll content lays out at once and every split
/// row can be read back off the pixels - the width, which is what the row's fixed pace
/// column has to fit inside, is the real one.
///
/// The PNG lands in `ASCEND_EVIDENCE_DIR` when set and is not taken otherwise.
@MainActor
@Suite(.hostsAWindow)
struct LiveClimbPaceSplitRowLayoutEvidenceTests {
    /// Every split row states its pace unit as one word. A pace column too narrow for
    /// the unit wraps `SPM` into `SP` and `M`, which is what the card looked like at
    /// phone width before the column was allowed to size to its own content.
    @Test
    func everySplitRowKeepsItsPaceUnitOnOneLine() async throws {
        let workout = Self.makeWorkout()
        let splits = LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: max(workout.steps, 1)
        )

        // Read by OCR, not off the tree: each split row publishes one combined label that
        // says "steps per minute", so the tree cannot see whether the visible SPM wrapped -
        // and wrapping is the whole contract. The capture keeps the 3x the test always used,
        // because an 8pt unit is what has to stay legible.
        let text = try await RenderedScreen.host(
            summary(for: workout, container: try summaryContainer()),
            size: Self.renderSize
        ) { screen in
            let text = try await screen.recognizedText(scale: 3)
            try screen.photograph(named: "live-climb-summary-pace-splits")
            return text
        }

        // The card's own average and the trend card each state the unit once more, so a
        // wrapped row column shows up as a shortfall against the row count.
        #expect(occurrenceCount(of: "spm", in: text) >= splits.count)
        #expect(!text.contains("sp m"))
    }

    // MARK: - Hosting the shipping screen

    /// The summary carries a `@Query`, so its host must be dropped before the store it observes
    /// is - `RenderedScreen.host` drops the root view controller on every path.
    private func summary(for workout: Workout, container: ModelContainer) -> some View {
        LiveClimbCompletionSummaryView(
            climb: nil,
            workout: workout,
            leaderboardRank: nil,
            leaderboardTotal: nil,
            leaderboardRankBasis: .current,
            leaderboardContext: nil,
            onDone: { _ in }
        )
        .modelContainer(container)
    }

    private func summaryContainer() throws -> ModelContainer {
        try #require(Self.container, "The evidence suite needs an in-memory model container")
    }

    /// The phone width Ascend ships against, with the height opened up so the scroll
    /// content below the fold lays out in the same pass.
    private static let renderSize = CGSize(width: 393, height: 2_400)

    // MARK: - Fixtures

    /// A session paced fast enough that every split's pace is three digits wide, which is
    /// the widest the column ever has to hold.
    private static func makeWorkout() -> Workout {
        Workout(
            name: "CN Tower Live Climb",
            duration: 1_908,
            steps: 4_100,
            floors: 144,
            caloriesBurned: 486,
            source: .headphoneMotion
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

    // MARK: - Reading the capture back

    private func occurrenceCount(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
