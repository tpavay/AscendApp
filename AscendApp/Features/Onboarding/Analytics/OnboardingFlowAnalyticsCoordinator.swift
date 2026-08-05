import Foundation

/// Owns the single user-level onboarding lifecycle pair. A pass begins at the first onboarding
/// screen this install shows - which is the welcome screen on a clean run, and whatever step the
/// persisted onboarding snapshot resumes at otherwise - survives relaunch, and closes only once
/// active app access routes the app to Home.
///
/// The pass is scoped to the account that owns it. A pass opened before auth is adopted by the
/// account that finishes it; a different account, a sign-out, or a debug replay retires it, so one
/// climber's abandoned pass can never be closed by the next climber's completion.
@MainActor
final class OnboardingFlowAnalyticsCoordinator {
    static let shared = OnboardingFlowAnalyticsCoordinator()

    private static let passStateKey = "onboarding.analytics.pass.v1"

    private struct PassState: Codable, Equatable {
        var ownerUserID: String?
        var didStart = false
        var didComplete = false
    }

    private let userDefaults: UserDefaults
    private let telemetry: TelemetryManager
    private var shouldMarkNextScreenAsResumed: Bool

    init(
        userDefaults: UserDefaults = .standard,
        telemetry: TelemetryManager = .shared
    ) {
        self.userDefaults = userDefaults
        self.telemetry = telemetry

        let state = Self.loadState(from: userDefaults)
        shouldMarkNextScreenAsResumed = state.didStart && !state.didComplete
    }

    /// Binds the in-flight pass to the account that owns it, and retires it when the account is a
    /// different one from the account that opened it.
    func adoptPassOwner(_ userID: String) {
        var state = loadState()
        guard state.ownerUserID != userID else { return }

        if state.ownerUserID == nil, !state.didComplete {
            state.ownerUserID = userID
            save(state)
            return
        }

        save(PassState(ownerUserID: userID))
        shouldMarkNextScreenAsResumed = false
    }

    /// Retires the current pass so the next onboarding screen opens a fresh one. Sign-out, account
    /// deletion, and the debug replay tools all hand the flow to a pass that has to be counted on
    /// its own.
    func resetPass() {
        userDefaults.removeObject(forKey: Self.passStateKey)
        shouldMarkNextScreenAsResumed = false
    }

    func recordFlowStartedIfNeeded(context: OnboardingAnalyticsContext) {
        var state = loadState()

        if state.didComplete {
            state = PassState(ownerUserID: state.ownerUserID)
            shouldMarkNextScreenAsResumed = false
        }

        guard !state.didStart else { return }

        state.didStart = true
        save(state)

        // A pass that opens past the first canonical step is resuming work an earlier install or
        // an earlier launch already did, and its first screen has to say so.
        let isResumedPass = context.stepIndex > 0
        if isResumedPass {
            shouldMarkNextScreenAsResumed = true
        }

        telemetry.track(
            OnboardingAnalyticsEvent.flowStarted(context: context, resume: isResumedPass)
        )
    }

    func consumeScreenResumeFlag() -> Bool {
        guard shouldMarkNextScreenAsResumed else { return false }
        shouldMarkNextScreenAsResumed = false
        return true
    }

    func recordFlowCompletedIfNeeded(reason: OnboardingFlowCompletionReason) {
        var state = loadState()
        guard state.didStart, !state.didComplete else { return }

        state.didComplete = true
        save(state)
        shouldMarkNextScreenAsResumed = false

        telemetry.track(
            OnboardingAnalyticsEvent.flowCompleted(
                context: OnboardingAnalyticsEvent.paywallContext,
                completionReason: reason
            )
        )
    }

    private func loadState() -> PassState {
        Self.loadState(from: userDefaults)
    }

    private static func loadState(from userDefaults: UserDefaults) -> PassState {
        guard let data = userDefaults.data(forKey: passStateKey),
              let state = try? JSONDecoder().decode(PassState.self, from: data) else {
            return PassState()
        }

        return state
    }

    private func save(_ state: PassState) {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: Self.passStateKey)
        } catch {
            assertionFailure("Failed to persist onboarding analytics pass state: \(error)")
        }
    }
}
