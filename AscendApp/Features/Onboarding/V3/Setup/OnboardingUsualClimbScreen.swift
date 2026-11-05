import SwiftUI

/// 07b: how long a usual climb is, for the climber who has no Health history to read it from.
/// Nothing is preselected and CONTINUE stays dimmed until a row is tapped.
struct OnboardingUsualClimbScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var choice: UsualClimbChoice?

    init(coordinator: OnboardingV3Coordinator) {
        self.coordinator = coordinator
        _choice = State(initialValue: UsualClimbChoice.stored(
            steps: coordinator.answers.usualClimbSteps,
            minutes: coordinator.answers.usualClimbMinutes
        ))
    }

    var body: some View {
        OnboardingSetupLayout(step: .usualClimb) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeadline(["How long is a"], accentLines: ["usual climb?"])
                    .onboardingEntrance(index: 0)

                Text("We'll pick your first climb so it's hard, but doable.")
                    .onboardingSecondary()
                    .onboardingEntrance(index: 1)

                VStack(spacing: 8) {
                    ForEach(Array(UsualClimbChoice.allCases.enumerated()), id: \.element) { index, option in
                        OnboardingChoiceRow(
                            title: option.title,
                            detail: option.detail,
                            isSelected: choice == option
                        ) {
                            HapticsManager.shared.trigger(.selection)
                            choice = option
                        }
                        .onboardingEntrance(index: index + 2, duration: 0.45)
                    }
                }
                .padding(.top, 10)
            }
        } footer: {
            Button("Continue") {
                guard let choice else { return }
                coordinator.update {
                    $0.usualClimbSteps = choice.steps
                    $0.usualClimbMinutes = choice.minutes
                }
                coordinator.advance()
            }
            .buttonStyle(.onboardingPrimary)
            .disabled(choice == nil)
        }
        .task { OnboardingMonthlyEventModel.shared.prefetch() }
        .trackOnce(screen: .onboardingUsualClimb)
    }
}

#Preview("07b usual climb") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-usual") ?? .standard),
        startingAt: .usualClimb
    ))
}
