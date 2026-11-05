import Foundation

/// A screen that sends a climber to the sign-in step as someone who already has an account - the
/// paywall's "Already climbing? Sign in" - sets this first, so the sign-in opens in returning mode.
///
/// Persisted rather than held in memory so a relaunch on the sign-in step reopens the mode the
/// climber chose. It is cleared when they back out of returning mode.
struct OnboardingAuthReturningRequest: @unchecked Sendable {
    static let storageKey = "onboardingV3.auth.returningRequested"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isSet: Bool { userDefaults.bool(forKey: Self.storageKey) }

    func set() { userDefaults.set(true, forKey: Self.storageKey) }

    func clear() { userDefaults.removeObject(forKey: Self.storageKey) }
}
