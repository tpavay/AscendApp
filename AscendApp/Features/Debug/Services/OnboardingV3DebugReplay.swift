#if DEBUG || STAGING
import Foundation

extension Notification.Name {
    /// Posted by Debug Tools after the v3 onboarding's device state has been cleared, so the root
    /// restarts the live coordinator and latch that were built at launch.
    static let onboardingV3DebugReplayRequested = Notification.Name("onboardingV3DebugReplayRequested")
}

/// Puts the device back where a fresh install of the v3 onboarding starts, so a tester can walk the
/// whole flow again on one account.
///
/// Reset: the answers with their `completedAt` (a finished pass is otherwise kept across sign-out on
/// purpose) and paywall-stage marker, and the sign-in hand-off intent. Added: a Debug-only override
/// of `onboarding_v3_enabled`, which ships off, so a build whose Remote Config has the switch off
/// still opens the v3 flow instead of the legacy one.
///
/// The purchase hold is not reset here: the sign-out the caller makes releases it, on disk and in
/// the live paywall model (`RootView`).
struct OnboardingV3DebugReplay: @unchecked Sendable {
    static let forcesFlowKey = "onboardingV3.debugForcesFlow"

    private let userDefaults: UserDefaults
    private let store: PreAuthOnboardingStore
    private let intent: OnboardingV3HandOffIntent

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        store = PreAuthOnboardingStore(userDefaults: userDefaults)
        intent = OnboardingV3HandOffIntent(userDefaults: userDefaults)
    }

    /// Whether the override is on. Read by ``OnboardingV3RouteLatch`` at launch.
    var forcesFlow: Bool { userDefaults.bool(forKey: Self.forcesFlowKey) }

    /// Clears the v3 state and turns the override on. Does not sign out; the caller does that.
    func reset() {
        store.clear()
        intent.clear()
        userDefaults.set(true, forKey: Self.forcesFlowKey)
    }
}
#endif
