import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision

@testable import AscendApp

/// Product-level evidence that the completion summary stays focused on the earned result.
///
/// This hosts the shipping completion summary in a real phone-sized window with Health in the
/// never-connected state and a climb carrying no heart rate - the exact conditions the connect
/// offer used to appear under - so the screenshot proves the view says nothing about heart rate
/// rather than relying on test setup to hide it.
@MainActor
@Suite(.hostsAWindow)
struct LiveClimbCompletionSummaryHealthPromptEvidenceTests {
    @Test("A completed climb summary never asks for Apple Health")
    func hidesHeartRateAbsenceAndKeepsSummaryActions() async throws {
        let previousAuthorizationState = HealthKitSyncState.hasRequestedAuthorization
        HealthKitSyncState.hasRequestedAuthorization = false
        defer { HealthKitSyncState.hasRequestedAuthorization = previousAuthorizationState }

        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let workout = Workout(
            name: "CN Tower Live Climb",
            date: Date().addingTimeInterval(-1_908),
            duration: 1_908,
            steps: 2_579,
            floors: 144,
            source: .headphoneMotion
        )
        context.insert(workout)
        try context.save()

        #expect(workout.isInAppSensorWorkout, "the fixture has to be a climb enrichment tracks")
        #expect(workout.avgHeartRate == nil)
        #expect(workout.heartRateTimeSeries.isEmpty)

        let screen = LiveClimbCompletionSummaryView(
            climb: nil,
            workout: workout,
            leaderboardRank: 1,
            leaderboardTotal: 1,
            leaderboardRankBasis: .atCompletion,
            leaderboardContext: .justClimbGlobal(targetSteps: 2_579),
            onDone: { _ in }
        )
        .modelContainer(container)

        let image = try screenshot(of: screen)
        let recognized = try await recognizedText(in: image)

        #expect(recognized.contains("no heart rate on this climb") == false)
        #expect(recognized.contains("connect apple health") == false)
        #expect(recognized.contains("heart rate") == false)
        #expect(recognized.contains("share"))
        #expect(recognized.contains("done"))

        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory)
            .appending(path: "live-climb-completion-summary-without-heart-rate-prompt.png")
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("Rendered prompt-free completion summary evidence: \(url.path())")
    }

    private static let screenSize = CGSize(width: 393, height: 852)

    private func screenshot(of view: some View) throws -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: Self.screenSize)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
        window.frame = CGRect(origin: .zero, size: Self.screenSize)
        window.overrideUserInterfaceStyle = .dark

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
        return UIGraphicsImageRenderer(size: Self.screenSize, format: format).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        return try await request.perform(on: cgImage)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }
}
