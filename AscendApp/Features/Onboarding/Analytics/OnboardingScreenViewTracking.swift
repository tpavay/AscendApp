import SwiftUI

extension View {
    /// Emits `onboarding_screen_viewed` once per distinct `step_id` for the lifetime of the view.
    /// Navigating back to an already-viewed step re-emits nothing, so the funnel counts each step
    /// once per user regardless of how many times they pass through it. A `nil` context emits
    /// nothing, which lets callers whose step is index-derived pass an out-of-bounds state through.
    func trackOnboardingScreenView(
        _ context: OnboardingAnalyticsContext?,
        telemetry: TelemetryManager = .shared
    ) -> some View {
        modifier(OnboardingScreenViewTracker(context: context, telemetry: telemetry))
    }
}

private struct OnboardingScreenViewTracker: ViewModifier {
    let context: OnboardingAnalyticsContext?
    let telemetry: TelemetryManager

    @State private var viewedStepIDs: Set<String> = []

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
        guard let context, !viewedStepIDs.contains(context.stepID) else { return }

        viewedStepIDs.insert(context.stepID)
        telemetry.track(
            OnboardingAnalyticsEvent.screenViewed(context: context)
        )
    }
}
