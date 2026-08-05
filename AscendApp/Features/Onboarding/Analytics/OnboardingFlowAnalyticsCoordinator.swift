import Foundation

@MainActor
final class OnboardingFlowAnalyticsCoordinator {
    static let shared = OnboardingFlowAnalyticsCoordinator()

    private static let flowStartedKey = "onboarding.analytics.flowStarted.v1"
    private static let flowCompletedKey = "onboarding.analytics.flowCompleted.v1"

    private let userDefaults: UserDefaults
    private let telemetry: TelemetryManager
    private var shouldMarkNextScreenAsResumed: Bool

    init(
        userDefaults: UserDefaults = .standard,
        telemetry: TelemetryManager = .shared
    ) {
        self.userDefaults = userDefaults
        self.telemetry = telemetry
        shouldMarkNextScreenAsResumed = userDefaults.bool(forKey: Self.flowStartedKey)
            && !userDefaults.bool(forKey: Self.flowCompletedKey)
    }

    func recordFlowStartedIfNeeded() {
        if userDefaults.bool(forKey: Self.flowCompletedKey) {
            userDefaults.removeObject(forKey: Self.flowStartedKey)
            userDefaults.removeObject(forKey: Self.flowCompletedKey)
            shouldMarkNextScreenAsResumed = false
        }

        guard !userDefaults.bool(forKey: Self.flowStartedKey) else { return }

        userDefaults.set(true, forKey: Self.flowStartedKey)
        telemetry.track(
            OnboardingAnalyticsEvent.flowStarted(
                context: OnboardingAnalyticsEvent.welcomeContext,
                resume: false
            )
        )
    }

    func consumeScreenResumeFlag() -> Bool {
        guard shouldMarkNextScreenAsResumed else { return false }
        shouldMarkNextScreenAsResumed = false
        return true
    }

    func recordFlowCompletedIfNeeded(reason: OnboardingFlowCompletionReason) {
        guard userDefaults.bool(forKey: Self.flowStartedKey),
              !userDefaults.bool(forKey: Self.flowCompletedKey) else {
            return
        }

        userDefaults.set(true, forKey: Self.flowCompletedKey)
        telemetry.track(
            OnboardingAnalyticsEvent.flowCompleted(
                context: OnboardingAnalyticsEvent.paywallContext,
                completionReason: reason
            )
        )
    }
}
