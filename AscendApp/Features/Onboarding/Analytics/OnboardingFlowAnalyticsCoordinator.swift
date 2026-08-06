import Foundation
import Observation

/// How the pass in flight came to have app access, as far as that pass has been told.
enum OnboardingAccessGrantProvenance: Codable, Equatable {
    /// The pass has never asked to buy or restore access, so access it has is access it arrived
    /// with.
    case notRequested
    /// A paywall or restore is in flight and has not said how it ended.
    case pending
    /// The request closed. `nil` when it closed without naming how access was granted.
    case resolved(OnboardingFlowCompletionReason?)
}

/// Owns the single user-level onboarding lifecycle pair. A pass begins at the first onboarding
/// screen this install shows - which is the welcome screen on a clean run, and whatever step the
/// persisted onboarding snapshot resumes at otherwise - survives relaunch, and closes only once
/// active app access routes the app to Home.
///
/// The pass is scoped to the account that owns it. A pass opened before auth is adopted by the
/// account that finishes it; a different account, a sign-out, or a debug replay retires it, so one
/// climber's abandoned pass can never be closed by the next climber's completion.
///
/// How access was granted is part of that pass, not a fact about the running process: the app can
/// die on a StoreKit sheet between the purchase and the route to Home. It is therefore persisted
/// with the pass and retired with it, so the two can never disagree.
@MainActor
@Observable
final class OnboardingFlowAnalyticsCoordinator {
    static let shared = OnboardingFlowAnalyticsCoordinator()

    private static let passStateKey = "onboarding.analytics.pass.v1"

    private struct PassState: Codable, Equatable {
        var ownerUserID: String?
        var didStart = false
        var didComplete = false
        var accessGrant: OnboardingAccessGrantProvenance = .notRequested

        init(ownerUserID: String? = nil) {
            self.ownerUserID = ownerUserID
        }

        /// Decoded field by field so a pass persisted by an earlier build - one written before a
        /// field existed - resumes instead of silently starting over as a second pass.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ownerUserID = try container.decodeIfPresent(String.self, forKey: .ownerUserID)
            didStart = try container.decodeIfPresent(Bool.self, forKey: .didStart) ?? false
            didComplete = try container.decodeIfPresent(Bool.self, forKey: .didComplete) ?? false
            accessGrant = try container.decodeIfPresent(
                OnboardingAccessGrantProvenance.self,
                forKey: .accessGrant
            ) ?? .notRequested
        }
    }

    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private let telemetry: TelemetryManager
    private var passState: PassState
    @ObservationIgnored
    private var shouldMarkNextScreenAsResumed: Bool

    init(
        userDefaults: UserDefaults = .standard,
        telemetry: TelemetryManager = .shared
    ) {
        self.userDefaults = userDefaults
        self.telemetry = telemetry

        var state = Self.loadState(from: userDefaults)
        shouldMarkNextScreenAsResumed = state.didStart && !state.didComplete

        // A request still in flight when the process ended can never report its result, so it
        // closes here rather than deferring a completion nothing is left to release.
        if state.accessGrant == .pending {
            state.accessGrant = .resolved(nil)
            Self.save(state, to: userDefaults)
        }

        passState = state
    }

    var accessGrantProvenance: OnboardingAccessGrantProvenance {
        passState.accessGrant
    }

    /// Binds the in-flight pass to the account that owns it, and retires it when the account is a
    /// different one from the account that opened it.
    func adoptPassOwner(_ userID: String) {
        guard passState.ownerUserID != userID else { return }

        if passState.ownerUserID == nil, !passState.didComplete {
            var state = passState
            state.ownerUserID = userID
            save(state)
            return
        }

        save(PassState(ownerUserID: userID))
        shouldMarkNextScreenAsResumed = false
    }

    /// Retires the current pass so the next onboarding screen opens a fresh one. The debug replay
    /// tools hand the flow to a pass that has to be counted on its own.
    func resetPass() {
        passState = PassState()
        userDefaults.removeObject(forKey: Self.passStateKey)
        shouldMarkNextScreenAsResumed = false
    }

    /// Retires a pass an account already claimed, and leaves an unclaimed one alone. Losing the
    /// authenticated identity is not by itself a sign-out: a cold launch with no session reports
    /// exactly the same thing, and it must not wipe the pre-auth pass the climber is mid-way
    /// through and make the next screen open a second one.
    func retireAdoptedPass() {
        guard passState.ownerUserID != nil else { return }

        resetPass()
    }

    func recordFlowStartedIfNeeded(context: OnboardingAnalyticsContext) {
        var state = passState

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

    func beginAccessGrantRequest() {
        guard passState.accessGrant != .pending else { return }

        var state = passState
        state.accessGrant = .pending
        save(state)
    }

    func recordAccessGranted(_ reason: OnboardingFlowCompletionReason) {
        var state = passState
        state.accessGrant = .resolved(reason)
        save(state)
    }

    /// Closes a pending request without attributing anything, so a climber whose paywall reported
    /// nothing is never left waiting on a result that will not arrive.
    func recordAccessGrantRequestReportedNothing() {
        guard passState.accessGrant == .pending else { return }

        var state = passState
        state.accessGrant = .resolved(nil)
        save(state)
    }

    func recordFlowCompletedIfNeeded(reason: OnboardingFlowCompletionReason) {
        guard passState.didStart, !passState.didComplete else { return }

        var state = passState
        state.didComplete = true
        state.accessGrant = .notRequested
        save(state)
        shouldMarkNextScreenAsResumed = false

        telemetry.track(
            OnboardingAnalyticsEvent.flowCompleted(
                context: OnboardingAnalyticsEvent.paywallContext,
                completionReason: reason
            )
        )
    }

    private static func loadState(from userDefaults: UserDefaults) -> PassState {
        guard let data = userDefaults.data(forKey: passStateKey),
              let state = try? JSONDecoder().decode(PassState.self, from: data) else {
            return PassState()
        }

        return state
    }

    private func save(_ state: PassState) {
        passState = state
        Self.save(state, to: userDefaults)
    }

    private static func save(_ state: PassState, to userDefaults: UserDefaults) {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: passStateKey)
        } catch {
            assertionFailure("Failed to persist onboarding analytics pass state: \(error)")
        }
    }
}
