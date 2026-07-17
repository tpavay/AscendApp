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

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTelemetry(sink: sink))
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

        let firstLaunch = PostAuthOnboardingCoordinator(store: store, telemetry: makeTelemetry(sink: sink))
        firstLaunch.resolve(userId: userId)
        firstLaunch.completeCurrentStage()

        // A relaunch mid-flow must not restart the funnel, or starts outnumber completions.
        let relaunch = PostAuthOnboardingCoordinator(store: store, telemetry: makeTelemetry(sink: sink))
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

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTelemetry(sink: sink))
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

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTelemetry(sink: sink))
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
    func movingBackReportsTheStageBeingLeft() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let userId = "user-back"

        let coordinator = PostAuthOnboardingCoordinator(store: store, telemetry: makeTelemetry(sink: sink))
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

    /// `configure()` is what applies the override; without it collection stays off and every
    /// emission assertion would pass vacuously against an empty sink.
    private func makeTelemetry(sink: InMemoryTelemetrySink) -> TelemetryManager {
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true
        )
        telemetry.configure()
        return telemetry
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PostAuthOnboardingCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct NoopCrashlyticsReporter: CrashlyticsReporting {
    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {}
}
