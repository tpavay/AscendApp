import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision

@testable import AscendApp

/// Product-level evidence that the App Store sentiment question survived the move and now lands
/// *after* the celebration instead of on top of it.
///
/// A climb is recorded and saved through the real `LiveClimbSessionViewModel`, the shipping
/// `LiveClimbSessionView` is hosted in a live window, and `DONE` is pressed through the same
/// accessibility action a climber's tap produces. Two frames are captured: the summary as the
/// climber earns it, and what the screen holds once they dismiss it.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's temporary directory
/// otherwise; the path is logged either way.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbRatingPromptPlacementEvidenceTests {
    @Test("The rating question follows the completion summary instead of covering it")
    func ratingPromptFollowsTheCompletionSummary() async throws {
        AppStoreRatingManager.shared.resetPromptState()
        defer { AppStoreRatingManager.shared.resetPromptState() }

        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let viewModel = try await recordAndSaveAClimb(in: context)
        #expect(
            viewModel.shouldShowRankedCompletionSummary,
            "The saved climb has to reach the ranked summary, or there is no handoff to test"
        )
        #expect(
            AppStoreRatingManager.shared.shouldAskEnjoymentQuestionAfterFirstLiveClimb(
                completedLiveClimbCount: 1
            ),
            "A first completed climb with no stored answer is exactly when Ascend asks"
        )

        try await withAccessibilityAutomation {
            let window = try makeHostedWindow(
                LiveClimbSessionView(viewModel: viewModel)
                    .environment(ModerationStore.shared)
                    .modelContainer(container)
            )
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            settle(window, for: 0.9)
            let summaryFrame = screenshot(window)
            let summaryText = try await recognizedText(in: summaryFrame)

            #expect(
                summaryText.contains("enjoying ascend") == false,
                "The summary must be readable on its own - nothing asking for a rating over it"
            )
            #expect(summaryText.contains("done"))

            _ = try await settledAccessibilityElements(under: window)
            try activateAccessibilityElement(labelled: "DONE", in: window)

            // The question is a presented controller, so waiting for it is a fact about the
            // screen rather than a guess at how long presentation takes on a busy host.
            let alert = try await presentedAlert(in: window)
            #expect(alert.title == "Enjoying Ascend?")

            let (promptFrame, promptText) = try await frameShowing("enjoying ascend", in: window)

            #expect(
                promptText.contains("enjoying ascend"),
                "Dismissing the summary is what asks the question. Read: \(promptText)"
            )
            #expect(
                promptText.contains("splits") == false,
                "The earned result must be off screen by the time the question is asked"
            )

            try writeProofSheet(
                [
                    ("1 · Summary as the climber earns it - no rating question over it", summaryFrame),
                    ("2 · DONE pressed - the question follows the celebration", promptFrame),
                ],
                named: "live-climb-rating-prompt-follows-summary.png"
            )

            try await pressAnswer("No", presentedBy: alert, in: window)
        }

        #expect(
            AppStoreRatingManager.shared.shouldAskEnjoymentQuestionAfterFirstLiveClimb(
                completedLiveClimbCount: 1
            ) == false,
            "Answering records the response, so the question is not asked again"
        )
    }

    // MARK: - The climb

    private func recordAndSaveAClimb(
        in context: ModelContext
    ) async throws -> LiveClimbSessionViewModel {
        let climb = Self.climb
        let startedAt = Date().addingTimeInterval(-1_908)
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_908),
            duration: 1_908,
            steps: climb.referenceStepCount,
            sampleCount: 2_400,
            stopReason: .targetReached
        )

        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [climb])
            ),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: context)
        await viewModel.finishAndSave(modelContext: context, reason: .targetReached)

        return viewModel
    }

    private static let climb = Climb(
        id: "rating-prompt-test-tower",
        name: "CN Tower",
        city: "Toronto",
        country: "Canada",
        continent: "North America",
        latitude: 43.6426,
        longitude: -79.3871,
        totalHeightMeters: 553,
        totalHeightFeet: 1_815,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 2_579,
        realStairCount: 2_579,
        calculatedFloors: 144,
        category: "tower",
        tier: .gold,
        tags: [],
        funFact: "Fact",
        sourceURL: "https://example.com",
        imageSetVersion: 1,
        releaseState: .available
    )

    // MARK: - Hosting

    private static let screenSize = CGSize(width: 402, height: 874)

    private func makeHostedWindow(_ content: some View) throws -> UIWindow {
        let controller = UIHostingController(rootView: content)
        controller.overrideUserInterfaceStyle = .dark

        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "The test host app should expose a live window scene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.screenSize)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()

        return window
    }

    private func settle(_ window: UIWindow, for duration: TimeInterval) {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
        window.layoutIfNeeded()
    }

    /// Waits for the sentiment question to be really presented, rather than assuming a settle was
    /// long enough on a host that is running other suites at the same time.
    private func presentedAlert(in window: UIWindow) async throws -> UIViewController {
        for _ in 0..<120 {
            if let presented = window.rootViewController?.presentedViewController,
               presented.isBeingPresented == false {
                return presented
            }

            settle(window, for: 0.05)
            try await Task.sleep(for: .milliseconds(20))
        }

        return try #require(
            window.rootViewController?.presentedViewController,
            "Pressing DONE on a first completed climb has to present the sentiment question"
        )
    }

    /// Captures until the frame actually contains `expected`. A window that lost key status
    /// mid-run draws a blank frame, which reads as the feature being wrong rather than the
    /// capture being early.
    private func frameShowing(
        _ expected: String,
        in window: UIWindow
    ) async throws -> (UIImage, String) {
        var lastFrame = screenshot(window)
        var lastText = ""

        for _ in 0..<10 {
            window.makeKeyAndVisible()
            settle(window, for: 0.3)
            lastFrame = screenshot(window)
            lastText = try await recognizedText(in: lastFrame)
            if lastText.contains(expected) {
                break
            }
        }

        return (lastFrame, lastText)
    }

    /// Answers the question and waits for it to go away.
    ///
    /// The rest of this test drives controls through `accessibilityActivate()`, but the question is
    /// a UIKit alert: its answers are `UIView`s that publish themselves as accessibility elements
    /// and then refuse activation in process, and UIKit exposes no public way to press one. So the
    /// answer is run the way a tap runs it - the `UIAlertAction` UIKit would invoke, which is the
    /// screen's own `Button` action.
    private func pressAnswer(
        _ label: String,
        presentedBy alert: UIViewController,
        in window: UIWindow
    ) async throws {
        let controller = try #require(alert as? UIAlertController, "The question is a UIKit alert")
        let titles = controller.actions.map { $0.title ?? "untitled" }
        #expect(titles == ["Yes", "No"], "The question offers both answers")

        let answer = try #require(
            controller.actions.first { $0.title == label },
            "The question has to offer \(label). Found: \(titles)"
        )
        let handler = try #require(
            answer.value(forKey: "handler") as AnyObject?,
            "\(label) has to carry the action the screen attached to it"
        )

        // A tap takes the alert away first and runs the answer second, so the order is kept.
        controller.dismiss(animated: false)

        typealias AlertActionHandler = @convention(block) (UIAlertAction) -> Void
        unsafeBitCast(handler, to: AlertActionHandler.self)(answer)

        for _ in 0..<60 where window.rootViewController?.presentedViewController != nil {
            settle(window, for: 0.05)
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(
            window.rootViewController?.presentedViewController == nil,
            "Answering has to take the question away"
        )
    }

    private func screenshot(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3

        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { context in
            if window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) == false {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "The screenshot should have a CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        return try await request.perform(on: cgImage)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: - Evidence

    private func writeProofSheet(
        _ frames: [(caption: String, image: UIImage)],
        named name: String
    ) throws {
        let sheet = ImageRenderer(content: ProofSheet(frames: frames))
        sheet.scale = 2
        let image = try #require(sheet.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: name)
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("Rendered rating-prompt placement evidence: \(url.path())")
    }
}

private struct ProofSheet: View {
    let frames: [(caption: String, image: UIImage)]

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                VStack(alignment: .leading, spacing: 10) {
                    Text(frame.caption)
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(Color.ascendAccent)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 402, alignment: .leading)

                    Image(uiImage: frame.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 402)
                }
            }
        }
        .padding(24)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

private struct StubClimbCatalogRepository: ClimbCatalogRepository {
    let climbs: [Climb]

    func loadInitialCatalog() throws -> ClimbCatalogSnapshot {
        ClimbCatalogSnapshot(
            climbs: climbs,
            source: .bootstrap,
            catalogVersion: 0,
            featuredClimbId: climbs.first?.id,
            updatedAt: nil
        )
    }

    func refreshCatalog() async throws -> ClimbCatalogSnapshot {
        try loadInitialCatalog()
    }
}

/// Keeps the recorded climb off the network: the placement being proven is local to the screen.
private struct StubLiveReplayLeaderboardService: LiveReplayLeaderboardServicing {
    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        .empty
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank {
        throw CancellationError()
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        nil
    }

    func fetchPublishStatus(workoutId: String) async throws -> LiveReplayPublishStatus? {
        nil
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        nil
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        nil
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard {
        throw CancellationError()
    }

    func refreshIfNeeded(
        context: LiveReplayLeaderboardContext,
        elapsedSeconds: Int,
        currentSteps: Int,
        force: Bool
    ) async throws -> LiveReplayLeaderboardWindow? {
        nil
    }
}
