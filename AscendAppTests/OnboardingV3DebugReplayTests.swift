import Foundation
import Testing
@testable import AscendApp

/// Debug Tools' "Replay New Onboarding From Welcome": a finished v3 pass is kept across sign-out on
/// purpose, so the replay has to clear it, restart the live coordinator, and open the flow even
/// when `onboarding_v3_enabled` is off.
@MainActor
struct OnboardingV3DebugReplayTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "onboarding-v3-debug-replay-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func resetClearsAFinishedPassItsAnswersAndTheHandOffIntent() {
        let defaults = makeDefaults()
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        store.update {
            $0.weeklyTargetDays = 4
            $0.paywallStageUserID = "u1"
            $0.completedAt = Date()
        }
        OnboardingV3HandOffIntent(userDefaults: defaults).set()

        OnboardingV3DebugReplay(userDefaults: defaults).reset()

        #expect(store.answers() == PreAuthOnboardingAnswers())
        #expect(store.answers().completedAt == nil)
        #expect(!OnboardingV3HandOffIntent(userDefaults: defaults).isSet)
    }

    @Test
    func resetTurnsTheFlowOverrideOn() {
        let defaults = makeDefaults()
        let replay = OnboardingV3DebugReplay(userDefaults: defaults)
        #expect(!replay.forcesFlow)

        replay.reset()

        #expect(replay.forcesFlow)
    }

    @Test
    func aLiveCoordinatorReturnsToWelcomeUnfinishedAndUnanswered() {
        let defaults = makeDefaults()
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        let coordinator = OnboardingV3Coordinator(store: store)
        coordinator.advance()
        coordinator.update { $0.weeklyTargetDays = 5 }
        coordinator.completeSignIn(userID: "u1", showsPaywall: true)
        #expect(coordinator.isFinished)
        #expect(coordinator.step == .paywall)
        #expect(coordinator.presentsPaywall(for: "u1"))

        OnboardingV3DebugReplay(userDefaults: defaults).reset()
        coordinator.restartFromWelcome()

        #expect(coordinator.step == .welcome)
        #expect(!coordinator.canGoBack)
        #expect(!coordinator.isFinished)
        #expect(coordinator.answers == PreAuthOnboardingAnswers())
        #expect(!coordinator.presentsPaywall(for: "u1"))
    }

    @Test
    func theLatchOpensTheFlowWhenTheOverrideIsOnWithTheSwitchOff() async {
        let defaults = makeDefaults()
        let off = RemoteFeatureFlagStore()
        let latch = OnboardingV3RouteLatch(store: off, firstFetch: {}, holdLimit: .milliseconds(1))
        latch.beginHold()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(latch.showsFlow == false)

        OnboardingV3DebugReplay(userDefaults: defaults).reset()
        latch.forceFlow()

        #expect(latch.showsFlow == true)
    }
}
