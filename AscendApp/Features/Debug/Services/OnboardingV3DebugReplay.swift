#if DEBUG || STAGING
import Foundation

/// Puts the device back where a fresh install of the onboarding starts, so a tester can walk the
/// whole flow again on one account.
///
/// Reset: the answers and the sign-in hand-off intent.
///
/// The purchase hold and the live coordinator are not reset here: the sign-out the caller makes
/// releases the one and returns the other to Welcome (`RootView`).
struct OnboardingV3DebugReplay: @unchecked Sendable {
    private let store: PreAuthOnboardingStore
    private let intent: OnboardingV3HandOffIntent

    init(userDefaults: UserDefaults = .standard) {
        store = PreAuthOnboardingStore(userDefaults: userDefaults)
        intent = OnboardingV3HandOffIntent(userDefaults: userDefaults)
    }

    /// Clears the onboarding state. Does not sign out; the caller does that.
    func reset() {
        store.clear()
        intent.clear()
    }
}
#endif
