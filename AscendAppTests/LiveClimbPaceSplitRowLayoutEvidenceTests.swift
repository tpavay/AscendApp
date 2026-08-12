import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence that the completion summary's splits card survives phone width.
///
/// The card is drawn by the shipping `LiveClimbCompletionSummaryView`, hosted at the
/// 393-point width of the phone Ascend ships against. Only the height is opened up,
/// so the whole scroll content lays out at once and every split row can be read back
/// off the pixels - the width, which is what the row's fixed pace column has to fit
/// inside, is the real one.
///
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set, the test host's temp dir otherwise.
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
        let image = try screenshot(of: summary(for: workout, container: try summaryContainer()))
        let text = try await recognizedText(in: image)

        // The card's own average and the trend card each state the unit once more, so a
        // wrapped row column shows up as a shortfall against the row count.
        #expect(occurrenceCount(of: "spm", in: text) >= splits.count)
        #expect(!text.contains("sp m"))

        try writeEvidence(image: image, named: "live-climb-summary-pace-splits.png")
    }

    // MARK: - Rendering the shipping screen

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

    private func screenshot(of view: some View) throws -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: Self.renderSize)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.renderSize))
        window.frame = CGRect(origin: .zero, size: Self.renderSize)
        window.overrideUserInterfaceStyle = .dark

        // The summary carries a `@Query`, so a host left mounted keeps observing SwiftData after
        // its container has gone, and then traps on the next save any other suite performs.
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.rootViewController = controller
        window.isHidden = false

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: Self.renderSize, format: format)
        return renderer.image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

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

    // MARK: - Reading the rendered pixels back

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func occurrenceCount(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: name)
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("Rendered pace-split evidence: \(url.path())")
    }
}
