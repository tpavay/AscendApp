import SwiftUI

extension View {
    /// Emits `onboarding_screen_viewed` once per `step_id` for the lifetime of the onboarding pass,
    /// so back-navigation, re-renders, relaunches and route changes all re-emit nothing. A `nil`
    /// context emits nothing, which lets callers whose step is index-derived pass an out-of-bounds
    /// state through.
    @MainActor
    func trackOnboardingScreenView(
        _ context: OnboardingAnalyticsContext?,
        lifecycle: OnboardingFlowAnalyticsCoordinator = .shared
    ) -> some View {
        modifier(OnboardingScreenViewTracker(context: context, lifecycle: lifecycle))
    }
}

private struct OnboardingScreenViewTracker: ViewModifier {
    let context: OnboardingAnalyticsContext?
    let lifecycle: OnboardingFlowAnalyticsCoordinator

    func body(content: Content) -> some View {
        content
            .onAppear {
                recordScreenViewIfNeeded()
            }
            .onChange(of: context) { _, _ in
                recordScreenViewIfNeeded()
            }
    }

    private func recordScreenViewIfNeeded() {
        guard let context else { return }

        // Any onboarding screen can be the first one a pass shows: a reinstall keeps the Keychain
        // session while `UserDefaults` starts empty, so a climber who signed in but never finished
        // resumes mid-flow and never sees welcome.
        lifecycle.recordFlowStartedIfNeeded(context: context)
        lifecycle.reportResumeIfNeeded(context: context)

        OnboardingScreenViewRecorder(lifecycle: lifecycle).recordIfNeeded(context)
    }
}

/// Records the one `onboarding_screen_viewed` a step is allowed per onboarding pass.
///
/// Stateless on purpose. The dedupe lives on the persisted pass
/// (``OnboardingFlowAnalyticsCoordinator``) because the paywall is a different root route from
/// onboarding, so a view-scoped guard is destroyed by exactly the navigation it needs to survive.
@MainActor
struct OnboardingScreenViewRecorder {
    private let lifecycle: OnboardingFlowAnalyticsCoordinator

    init(lifecycle: OnboardingFlowAnalyticsCoordinator = .shared) {
        self.lifecycle = lifecycle
    }

    func recordIfNeeded(
        _ context: OnboardingAnalyticsContext?,
        telemetry: TelemetryManager = .shared,
        expectedUserID: String? = nil
    ) {
        guard let context, lifecycle.claimScreenView(stepID: context.stepID) else { return }

        let event = OnboardingAnalyticsEvent.screenViewed(context: context)
        let didDeliver: Bool
        if let expectedUserID {
            didDeliver = telemetry.track(event, ifIdentifiedAs: expectedUserID)
        } else {
            didDeliver = telemetry.track(event)
        }

        if !didDeliver {
            lifecycle.releaseScreenViewClaim(stepID: context.stepID)
        }
    }
}
