import SwiftUI

/// 07a We found your climbs: what Apple Health already holds, said back to the climber before they
/// have an account, and the one choice about it.
///
/// ADD TO MY HISTORY brings in the workouts inside the range row's reach, which is everything
/// unless the climber changes it. The quiet link under it brings in none and still leaves Health
/// connected, so new stair stepper workouts keep importing. Either way the screen only looks: the
/// import runs after sign-in, when there is an account to put the climbs in, and files them off
/// the leaderboards, which is what the line above the button says.
struct OnboardingHealthHistoryScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var viewModel: OnboardingHealthHistoryViewModel

    init(coordinator: OnboardingV3Coordinator, viewModel: OnboardingHealthHistoryViewModel? = nil) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: viewModel ?? OnboardingHealthHistoryViewModel())
    }

    var body: some View {
        // The body is taller than a short phone now that it carries the range row, so its cut edge fades.
        OnboardingSetupLayout(step: .healthHistory, fadesWhenScrollable: true) {
            switch viewModel.state {
            case .loading, .nothing:
                // Nothing to draw until the read answers. A read that found nothing hands the climber
                // to the usual-climb question below, so this is never a screen to read.
                Color.clear.frame(height: 1)
            case .found(let choice):
                HealthHistoryContent(choice: choice)
            }
        } footer: {
            VStack(spacing: 10) {
                Text(Self.footnote)
                    .font(.custom("Montserrat-SemiBold", fixedSize: 12))
                    .foregroundStyle(Color(hex: "8E8E8E"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingEntrance(delay: 0.6)

                VStack(spacing: 2) {
                    Button(choice?.primaryTitle ?? Self.primaryPlaceholder) {
                        viewModel.addToHistory(coordinator: coordinator)
                    }
                    .buttonStyle(.onboardingPrimary)
                    // The title carries a number, so it is the longest primary title in the flow. Past
                    // this size the style's one line cannot shrink far enough on a small phone and
                    // would end in an ellipsis.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    Button(Self.skipTitle) { viewModel.skipHistory(coordinator: coordinator) }
                        .buttonStyle(.onboardingQuietLink)
                }
                .disabled(choice == nil)
            }
            // Solid, so a body that scrolls under it at a large text size is cut clean, not read through.
            .background(OnboardingV3Palette.background)
        }
        .task { await viewModel.load(coordinator: coordinator) }
        .trackOnce(screen: .onboardingHealthHistory)
    }

    static let footnote = "Past climbs fill your history and personal bests. Every climb after you sign up counts on the leaderboards."

    /// The way to connect and bring in nothing: Health stays connected and only new workouts import.
    static let skipTitle = "Skip history, just import new workouts"

    /// What the button says for the moment before the read answers, while it cannot be tapped.
    static let primaryPlaceholder = "Add to my history"

    private var choice: HealthHistoryChoice? {
        if case .found(let choice) = viewModel.state { return choice }
        return nil
    }
}

#Preview("07a we found your climbs") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-health-history") ?? .standard),
        startingAt: .healthHistory
    ))
}
