import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence that the App Store sentiment question survived the move and now lands
/// *after* the celebration instead of on top of it.
///
/// A climb is recorded and saved through the real `LiveClimbSessionViewModel`, the shipping
/// `LiveClimbSessionView` is hosted in a live window through `RenderedScreen`, and `DONE` is
/// pressed through the same accessibility action a climber's tap produces. The screen is read
/// off the accessibility tree at two moments: the summary as the climber earns it, and what the
/// screen holds once they dismiss it.
///
/// Both moments are photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbRatingPromptPlacementEvidenceTests {
    @Test("The rating question follows the completion summary instead of covering it")
    func ratingPromptFollowsTheCompletionSummary() async throws {
        AppStoreRatingManager.shared.resetPromptState()
        defer { AppStoreRatingManager.shared.resetPromptState() }

        let container = try RetainedModelContainer.inMemory(for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self, ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self)
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

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let summaryText = try await screen.copy { $0.contains("done") }
            try screen.photograph(named: "live-climb-rating-prompt-01-summary-as-earned")

            #expect(
                summaryText.contains("enjoying ascend") == false,
                "The summary must be readable on its own - nothing asking for a rating over it"
            )
            #expect(summaryText.contains("done"))

            _ = try await screen.elements()
            try activateAccessibilityElement(labelled: "DONE", in: screen.window)

            // The question is a presented controller, so waiting for it is a fact about the
            // screen rather than a guess at how long presentation takes on a busy host.
            let alert = try await presentedAlert(in: screen)
            let question = try #require(alert as? UIAlertController, "The question is a UIKit alert")
            #expect(question.title == "Enjoying Ascend?")
            #expect(question.message == "If Ascend made this climb better, leave a quick rating.")

            // The question is read off the alert rather than off the hosted screen: a live
            // `UIAlertController` is presented in its own window, outside the hierarchy this
            // test hosts, so what it holds proves what machine the suite ran on rather than
            // where Ascend asks. What the hosted window does own is the other half of this
            // claim - that the earned result is already gone by the time the question is asked
            // - and that is what it is read and photographed for.
            let elementsBehindTheQuestion = try await screen.elements { elements in
                elements.contains { element in element.accessibilityLabel == "DONE" } == false
            }
            #expect(
                elementsBehindTheQuestion.contains { $0.accessibilityLabel == "DONE" } == false,
                "The summary the climber just dismissed must not still be behind the question"
            )

            try await screen.settle(.turns(6))
            let promptText = try await screen.copy { _ in true }
            try screen.photograph(named: "live-climb-rating-prompt-02-after-done")

            #expect(
                promptText.contains("splits") == false,
                "The earned result must be off screen by the time the question is asked"
            )

            try await pressAnswer("No", presentedBy: alert, in: screen)
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

    // MARK: - The question

    /// Waits for the sentiment question to be really presented, rather than assuming a settle was
    /// long enough on a host that is running other suites at the same time.
    private func presentedAlert(in screen: HostedScreen) async throws -> UIViewController {
        for _ in 0..<120 {
            if let presented = screen.window.rootViewController?.presentedViewController,
               presented.isBeingPresented == false {
                return presented
            }

            try await screen.settle(.turns(1))
            try await Task.sleep(for: .milliseconds(20))
        }

        return try #require(
            screen.window.rootViewController?.presentedViewController,
            "Pressing DONE on a first completed climb has to present the sentiment question"
        )
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
        in screen: HostedScreen
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

        for _ in 0..<60 where screen.window.rootViewController?.presentedViewController != nil {
            try await screen.settle(.turns(1))
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(
            screen.window.rootViewController?.presentedViewController == nil,
            "Answering has to take the question away"
        )
    }
}
