import Foundation
import Testing
@testable import AscendApp

struct PostAuthOnboardingCoordinatorTests {
    @Test
    func postAuthStagesStartWithTheFirstSurveyQuestion() {
        #expect(PostAuthOnboardingStage.allCases == [
            .stairStepperBaseline,
            .exerciseLevel,
            .goal,
            .motivation,
            .plan,
            .features,
            .gender,
            .age,
            .weight,
            .location,
            .notifications,
            .planLoading,
            .firstClimb
        ])
        #expect(PostAuthOnboardingStage.first == .stairStepperBaseline)
        #expect(PostAuthOnboardingStage.segmentID == "post_auth_onboarding")
        #expect(PostAuthOnboardingStage.plannedStepCount == 13)

        // The name step is gone, not hidden: App Review rejected 1.0 for asking a
        // Sign in with Apple climber to type a name the framework already
        // supplies, and `SuppliedNameAdoption` now always resolves one.
        #expect(!PostAuthOnboardingStage.allCases.contains { $0.rawValue == "displayName" })
    }

    @MainActor
    @Test
    func completingTheFirstStageAdvancesToTheSecond() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-1"

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        coordinator.completeCurrentStage()

        #expect(coordinator.phase == .onboarding(.exerciseLevel))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == [.stairStepperBaseline])
    }

    @MainActor
    @Test
    func completingAllStagesCompletesPostAuthOnboarding() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-complete"

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        for _ in PostAuthOnboardingStage.allCases {
            coordinator.completeCurrentStage()
        }

        #expect(coordinator.phase == .complete)
        #expect(store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == Set(PostAuthOnboardingStage.allCases))
    }

    @MainActor
    @Test
    func legacyRemovedStageSnapshotStartsAtDisplayName() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-2"

        defaults.set(
            Data(
                """
                {
                  "currentStage": "ratingSentiment",
                  "completedStages": ["valueScreens"],
                  "isComplete": false,
                  "startedAt": 1000
                }
                """.utf8
            ),
            forKey: "postAuthOnboarding.v1.\(userId)"
        )

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
    }

    @MainActor
    @Test
    func legacyRemovedStageSnapshotResumesAtFirstSurveyQuestion() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-3"

        defaults.set(
            Data(
                """
                {
                  "currentStage": "paywall",
                  "completedStages": ["displayName", "ratingSentiment", "userSurvey", "paywallPriming"],
                  "isComplete": false,
                  "startedAt": 1000
                }
                """.utf8
            ),
            forKey: "postAuthOnboarding.v1.\(userId)"
        )

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages.isEmpty)
    }

    @MainActor
    @Test
    func snapshotWithCurrentStageAfterNewRequiredQuestionsReopensAtFirstMissingQuestion() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-4"

        let snapshot = PostAuthOnboardingSnapshot(
            currentStage: .gender,
            completedStages: [],
            isComplete: false,
            startedAt: Date(timeIntervalSince1970: 1000)
        )
        store.save(snapshot, for: userId)

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages.isEmpty)
    }

    @MainActor
    @Test
    func resolvingIntoOnboardingDoesNotCompeteForFlowOwnership() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-flow-start"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.isEmpty)
        #expect(sink.records.filter { $0.name == "onboarding_flow_completed" }.isEmpty)
    }

    @MainActor
    @Test
    func resumingMidFlowDoesNotEmitASecondFlowStart() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-interrupted"

        let firstLaunch = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        firstLaunch.resolve(userId: userId)
        firstLaunch.completeCurrentStage()

        // A relaunch mid-flow must not restart the funnel, or starts outnumber completions.
        let relaunch = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        relaunch.resolve(userId: userId)

        #expect(relaunch.phase == .onboarding(.exerciseLevel))
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.isEmpty)
    }

    @MainActor
    @Test
    func returningCompleteUserNeverStartsTheFunnel() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-complete"
        store.markComplete(for: userId)

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .complete)
        #expect(sink.records.isEmpty)
    }

    @MainActor
    @Test
    func completingTheLastStageDoesNotCompleteTheUserLevelFlow() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-full-run"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)
        for _ in PostAuthOnboardingStage.allCases {
            coordinator.completeCurrentStage()
        }

        #expect(coordinator.phase == .complete)
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.isEmpty)
        #expect(sink.records.filter { $0.name == "onboarding_flow_completed" }.isEmpty)
    }

    @MainActor
    @Test
    func remoteProfileCompletionDoesNotCompleteTheUserLevelFlow() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-remote-profile"

        // A reinstall/second-device user resolves into onboarding (starting the funnel) and is
        // then flipped straight to complete once the remote profile loads.
        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)
        coordinator.markCurrentUserComplete()

        #expect(coordinator.phase == .complete)
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.isEmpty)
        #expect(sink.records.filter { $0.name == "onboarding_flow_completed" }.isEmpty)
    }

    @MainActor
    @Test
    func returningCompleteUserNeverClosesAFunnelItNeverStarted() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-already-complete"
        store.markComplete(for: userId)

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)
        coordinator.markCurrentUserComplete()

        #expect(coordinator.phase == .complete)
        #expect(sink.records.filter { $0.name == "onboarding_flow_completed" }.isEmpty)
    }

    @MainActor
    @Test
    func markingCompleteAfterFinishingStagesStillEmitsNoFlowCompletion() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-complete-then-profile-check"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)
        for _ in PostAuthOnboardingStage.allCases {
            coordinator.completeCurrentStage()
        }

        coordinator.markCurrentUserComplete()

        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.isEmpty)
        #expect(sink.records.filter { $0.name == "onboarding_flow_completed" }.isEmpty)
    }

    @MainActor
    @Test
    func bothPostAuthCompletionPathsEmitNoUserLevelCompletion() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)

        let fullRunStore = PostAuthOnboardingStore(userDefaults: makeDefaults())
        let fullRun = PostAuthOnboardingCoordinator(store: fullRunStore, telemetry: telemetry)
        fullRun.resolve(userId: "user-full-run")
        for _ in PostAuthOnboardingStage.allCases {
            fullRun.completeCurrentStage()
        }

        let remoteStore = PostAuthOnboardingStore(userDefaults: makeDefaults())
        let remote = PostAuthOnboardingCoordinator(store: remoteStore, telemetry: telemetry)
        remote.resolve(userId: "user-remote")
        remote.markCurrentUserComplete()

        let completed = sink.records.filter { $0.name == "onboarding_flow_completed" }
        #expect(completed.isEmpty)
    }

    @MainActor
    @Test
    func movingBackReportsTheStageBeingLeft() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-back"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)
        coordinator.completeCurrentStage()
        coordinator.moveBack()

        let back = sink.records.filter { $0.name == "onboarding_back_tapped" }
        #expect(back.count == 1)
        #expect(back.first?.parameters["from_step"] == .string("exercise_level"))
    }

    /// The guide sub-screen the user tapped back on reports that tap itself, and it reports the
    /// same `step_id` the container would, so a second event here is indistinguishable noise.
    @MainActor
    @Test
    func movingBackOffTheContainerStageReportsNothingOfItsOwn() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-back-features"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)
        for _ in PostAuthOnboardingStage.allCases where coordinator.phase != .onboarding(.features) {
            coordinator.completeCurrentStage()
        }
        coordinator.moveBack()

        #expect(coordinator.phase == .onboarding(.plan))
        #expect(sink.records.filter { $0.name == "onboarding_back_tapped" }.isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PostAuthOnboardingCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
