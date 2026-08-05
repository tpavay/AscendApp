import SwiftUI

extension View {
    /// Emits `onboarding_screen_viewed` once per distinct `step_id` for the lifetime of the view,
    /// so navigating back to an already-viewed step re-emits nothing and the funnel counts a step
    /// once per pass through the flow rather than once per visit. The dedupe is view-scoped rather
    /// than persisted: a relaunch mid-flow starts a fresh set and re-emits the current step. A
    /// `nil` context emits nothing, which lets callers whose step is index-derived pass an
    /// out-of-bounds state through.
    func trackOnboardingScreenView(_ context: OnboardingAnalyticsContext?) -> some View {
        modifier(OnboardingScreenViewTracker(context: context))
    }
}

private struct OnboardingScreenViewTracker: ViewModifier {
    let context: OnboardingAnalyticsContext?

    @State private var recorder = OnboardingScreenViewRecorder()

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

        if context.stepID == OnboardingAnalyticsEvent.welcomeContext.stepID {
            OnboardingFlowAnalyticsCoordinator.shared.recordFlowStartedIfNeeded()
        }

        recorder.recordIfNeeded(
            context,
            resume: OnboardingFlowAnalyticsCoordinator.shared.consumeScreenResumeFlag()
        )
    }
}

struct OnboardingScreenViewRecorder {
    private var viewedStepIDs: Set<String> = []

    mutating func recordIfNeeded(
        _ context: OnboardingAnalyticsContext?,
        resume: Bool = false,
        telemetry: TelemetryManager = .shared
    ) {
        guard let context, viewedStepIDs.insert(context.stepID).inserted else { return }

        telemetry.track(
            OnboardingAnalyticsEvent.screenViewed(context: context, resume: resume)
        )
    }
}
