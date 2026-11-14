import Foundation
import Testing
@testable import AscendApp

/// Debug Tools' "Replay New Onboarding From Welcome": the replay clears the onboarding state on the
/// device, and the sign-out it makes returns the live coordinator to Welcome.
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
            $0.completedAt = Date()
        }
        OnboardingV3HandOffIntent(userDefaults: defaults).set()

        OnboardingV3DebugReplay(userDefaults: defaults).reset()

        #expect(store.answers() == PreAuthOnboardingAnswers())
        #expect(store.answers().completedAt == nil)
        #expect(!OnboardingV3HandOffIntent(userDefaults: defaults).isSet)
    }

    @Test
    func theReplaysSignOutReturnsALiveCoordinatorToWelcomeUnfinishedAndUnanswered() {
        let defaults = makeDefaults()
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        let coordinator = OnboardingV3Coordinator(store: store)
        coordinator.advance()
        coordinator.update { $0.weeklyTargetDays = 5 }
        coordinator.finish()
        #expect(coordinator.isFinished)
        #expect(coordinator.step != .welcome)
        #expect(coordinator.canGoBack)

        OnboardingV3DebugReplay(userDefaults: defaults).reset()
        coordinator.sessionEnded()

        #expect(coordinator.step == .welcome)
        #expect(!coordinator.canGoBack)
        #expect(!coordinator.isFinished)
        #expect(coordinator.answers == PreAuthOnboardingAnswers())
    }

}
