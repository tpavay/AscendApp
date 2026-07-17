import SwiftUI

extension View {
    /// Emits `onboarding_screen_viewed` once per distinct `step_id` for the lifetime of the view.
    /// Navigating back to an already-viewed step re-emits nothing, so the funnel counts each step
    /// once per user regardless of how many times they pass through it. A `nil` context emits
    /// nothing, which lets callers whose step is index-derived pass an out-of-bounds state through.
    func trackOnboardingScreenView(_ context: OnboardingAnalyticsContext?) -> some View {
        modifier(OnboardingScreenViewTracker(context: context))
    }
}

private struct OnboardingScreenViewTracker: ViewModifier {
    let context: OnboardingAnalyticsContext?

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
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenViewed(context: context)
        )
    }
}
