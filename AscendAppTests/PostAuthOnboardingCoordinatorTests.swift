import Foundation
import Testing
@testable import AscendApp

struct PostAuthOnboardingCoordinatorTests {
    @Test
    func postAuthStagesStartWithDisplayName() {
        #expect(PostAuthOnboardingStage.allCases == [
            .displayName,
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
        #expect(PostAuthOnboardingStage.first == .displayName)
        #expect(PostAuthOnboardingStage.flowID == "post_auth_onboarding")
        #expect(PostAuthOnboardingStage.plannedStepCount == 14)
    }

    @MainActor
    @Test
    func completingDisplayNameAdvancesToStairStepperBaseline() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-1"

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        coordinator.completeCurrentStage()

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
    }

    @MainActor
    @Test
    func existingDisplayNameCanAdvanceDirectlyToStairStepperBaseline() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-with-name"

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        coordinator.completeDisplayNameIfNeeded()

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
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

        #expect(coordinator.phase == .onboarding(.displayName))
    }

    @MainActor
    @Test
    func legacyRemovedStageSnapshotWithDisplayNameCompletedResumesAtFirstSurveyQuestion() {
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
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
    }

    @MainActor
    @Test
    func snapshotWithCurrentStageAfterNewRequiredQuestionsReopensAtFirstMissingQuestion() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-4"

        let snapshot = PostAuthOnboardingSnapshot(
            currentStage: .gender,
            completedStages: [.displayName],
            isComplete: false,
            startedAt: Date(timeIntervalSince1970: 1000)
        )
        store.save(snapshot, for: userId)

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
    }

    @MainActor
    @Test
    func resolvingIntoOnboardingStartsTheFunnelAtTheFirstStage() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-flow-start"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.displayName))
        #expect(store.hasRecordedFlowStart(for: userId))

        let started = sink.records.filter { $0.name == "onboarding_flow_started" }
        #expect(started.count == 1)
        #expect(started.first?.parameters["step_id"] == .string("displayName"))
        #expect(started.first?.parameters["flow_id"] == .string("post_auth_onboarding"))
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

        #expect(relaunch.phase == .onboarding(.stairStepperBaseline))
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.count == 1)
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
        #expect(!store.hasRecordedFlowStart(for: userId))
        #expect(sink.records.isEmpty)
    }

    @MainActor
    @Test
    func completingTheLastStageClosesTheFunnelThatWasStarted() {
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
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.count == 1)
        #expect(sink.records.filter { $0.name == "onboarding_flow_completed" }.count == 1)
    }

    @MainActor
    @Test
    func remoteProfileCompletionClosesTheFunnelThatWasStarted() {
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
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.count == 1)

        let completed = sink.records.filter { $0.name == "onboarding_flow_completed" }
        #expect(completed.count == 1)
        #expect(completed.first?.parameters["step_id"] == .string("first_climb"))
        #expect(completed.first?.parameters["flow_id"] == .string("post_auth_onboarding"))
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
    func markingCompleteAfterFinishingTheFlowDoesNotEmitASecondCompletion() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-complete-then-profile-check"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTestTelemetry(sink: sink))
        coordinator.resolve(userId: userId)
        for _ in PostAuthOnboardingStage.allCases {
            coordinator.completeCurrentStage()
        }

        // The remote profile check runs after a genuine finish; starts and completions stay 1:1.
        coordinator.markCurrentUserComplete()

        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.count == 1)
        #expect(sink.records.filter { $0.name == "onboarding_flow_completed" }.count == 1)
    }

    @MainActor
    @Test
    func bothCompletionPathsReportTheSameFinalStep() {
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
        #expect(completed.count == 2)
        #expect(completed[0].parameters == completed[1].parameters)
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
        #expect(back.first?.parameters["from_step"] == .string("stair_stepper_baseline"))
    }

    @Test
    func resetClearsFlowStartSoTheFunnelCanRestart() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-reset"

        store.markFlowStartRecorded(for: userId)
        #expect(store.hasRecordedFlowStart(for: userId))

        store.reset(for: userId)

        #expect(!store.hasRecordedFlowStart(for: userId))
    }

    @Test
    func flowStartFlagIsScopedPerUser() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)

        store.markFlowStartRecorded(for: "user-a")

        #expect(store.hasRecordedFlowStart(for: "user-a"))
        #expect(!store.hasRecordedFlowStart(for: "user-b"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PostAuthOnboardingCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
