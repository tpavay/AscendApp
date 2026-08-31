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
        /// Every step this pass has already reported a view for.
        ///
        /// It lives on the pass rather than in a view's `@State` because the paywall is a different
        /// root route from onboarding: walking back from it tears down the view that used to hold
        /// this set, and every re-passed screen would report itself a second time.
        var viewedStepIDs: Set<String> = []

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
            viewedStepIDs = try container.decodeIfPresent(Set<String>.self, forKey: .viewedStepIDs) ?? []
        }
    }

    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private let telemetry: TelemetryManager
    private var passState: PassState
    /// Set when this launch opened a pass that was already under way, and consumed by the first
    /// screen it shows.
    @ObservationIgnored
    private var shouldReportResume: Bool

    init(
        userDefaults: UserDefaults = .standard,
        telemetry: TelemetryManager = .shared
    ) {
        self.userDefaults = userDefaults
        self.telemetry = telemetry

        var state = Self.loadState(from: userDefaults)
        shouldReportResume = state.didStart && !state.didComplete

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
        shouldReportResume = false
    }

    /// Retires the current pass so the next onboarding screen opens a fresh one. The debug replay
    /// tools hand the flow to a pass that has to be counted on its own.
    func resetPass() {
        passState = PassState()
        userDefaults.removeObject(forKey: Self.passStateKey)
        shouldReportResume = false
    }

    /// Retires a pass an account already claimed, and leaves an unclaimed one alone. Losing the
    /// authenticated identity is not by itself a sign-out: a cold launch with no session reports
    /// exactly the same thing, and it must not wipe the pre-auth pass the climber is mid-way
    /// through and make the next screen open a second one.
    func retireAdoptedPass() {
        guard passState.ownerUserID != nil else { return }

        resetPass()
    }

    /// Claims the one screen view this pass is allowed to report for `stepID`.
    ///
    /// Returns `false` once the pass has already reported it, so a climber walking back through
    /// onboarding re-reports nothing. Retiring the pass is what makes a step reportable again.
    func claimScreenView(stepID: String) -> Bool {
        guard !passState.viewedStepIDs.contains(stepID) else { return false }

        var state = passState
        state.viewedStepIDs.insert(stepID)
        save(state)
        return true
    }

    /// Hands a claim back when the view it was claimed for was never delivered.
    ///
    /// Telemetry refuses an event outright when collection is off or the identified user is not
    /// the one the caller expected, and the claim is persisted for the whole pass - so a claim kept
    /// after a refusal is not a deduped view, it is a view this pass can never report.
    func releaseScreenViewClaim(stepID: String) {
        guard passState.viewedStepIDs.contains(stepID) else { return }

        var state = passState
        state.viewedStepIDs.remove(stepID)
        save(state)
    }

    /// Reports, once per launch, that this launch opened onboarding somewhere other than its start.
    ///
    /// The interrupted-position signal used to ride on a re-emitted `onboarding_screen_viewed`
    /// carrying `resume=true`. Once a step reports only once per pass that re-emission is gone, so
    /// the signal gets an event of its own rather than disappearing.
    func reportResumeIfNeeded(context: OnboardingAnalyticsContext) {
        guard shouldReportResume else { return }

        shouldReportResume = false
        telemetry.track(OnboardingAnalyticsEvent.flowResumed(context: context))
    }

    func recordFlowStartedIfNeeded(context: OnboardingAnalyticsContext) {
        var state = passState

        if state.didComplete {
            state = PassState(ownerUserID: state.ownerUserID)
            shouldReportResume = false
        }

        guard !state.didStart else { return }

        state.didStart = true
        save(state)

        // A pass that opens past the first canonical step is resuming work an earlier install or
        // an earlier launch already did, and its start has to say so.
        //
        // There are two ways a launch resumes, and both have to report it: this one, where the pass
        // itself is new because a reinstall kept the Keychain session but not `UserDefaults`, and
        // the one `init` detects, where a pass persisted here was picked up by a later launch.
        let isResumedPass = context.stepIndex > 0
        if isResumedPass {
            shouldReportResume = true
        }

        telemetry.track(
            OnboardingAnalyticsEvent.flowStarted(context: context, resume: isResumedPass)
        )
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
        shouldReportResume = false

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
