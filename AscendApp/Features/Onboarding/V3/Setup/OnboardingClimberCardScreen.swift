import SwiftUI

/// 08: the climber card. Gender, birthday, height and weight, all visible, all skippable.
/// Writes only the pre-sign-in answers; the profile write waits for sign-in.
struct OnboardingClimberCardScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var draft: ClimberCardDraft
    /// Whether the climber has touched the wheel, so an untouched wheel never invents a birthday.
    @State private var wheelDate: Date

    init(coordinator: OnboardingV3Coordinator, system: MeasurementSystem = SettingsManager.shared.measurementSystem) {
        self.coordinator = coordinator
        let draft = ClimberCardDraft(answers: coordinator.answers, system: system)
        _draft = State(initialValue: draft)
        _wheelDate = State(initialValue: draft.birthdayDate() ?? ClimberCardDraft.wheelStart())
    }

    var body: some View {
        OnboardingSetupLayout(step: .climberCard, onSkip: { Self.skip(coordinator) }) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeadline(["Set up your"], accentLines: ["climber card."])
                    .onboardingEntrance(index: 0)

                Text("What people see when they tap your name or compare with you. Skip anything.")
                    .onboardingSecondary()
                    .onboardingEntrance(index: 1)

                ClimberCardView(draft: draft)
                    .padding(.top, 6)
                    .onboardingEntrance(index: 2)

                sectionLabel("Gender")
                    .padding(.top, 8)
                genderChips

                sectionLabel("Birthday")
                    .padding(.top, 8)
                birthdayWheel

                OnboardingStepperRow(title: "Height", value: draft.heightText) { direction in
                    HapticsManager.shared.trigger(.selection)
                    draft.stepHeight(direction)
                }

                OnboardingStepperRow(title: "Weight", value: draft.weightText) { direction in
                    HapticsManager.shared.trigger(.selection)
                    draft.stepWeight(direction)
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Text("Change any of it in Settings.")
                    .onboardingSecondary()
                    .multilineTextAlignment(.center)

                Button("Continue") {
                    coordinator.update { draft.apply(to: &$0) }
                    coordinator.advance()
                }
                .buttonStyle(.onboardingPrimary)
            }
        }
        .trackOnce(screen: .onboardingClimberCard)
    }

    /// Skip leaves the card unset, clearing an earlier pass's answers.
    static func skip(_ coordinator: OnboardingV3Coordinator) {
        coordinator.update { ClimberCardDraft.clearAnswers(in: &$0) }
        coordinator.advance()
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Montserrat-ExtraBold", size: 12))
            .tracking(2.4)
            .textCase(.uppercase)
            .foregroundStyle(OnboardingV3Palette.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var genderChips: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ClimberCardDraft.genderChoices, id: \.gender) { choice in
                let isSelected = draft.gender == choice.gender

                Button {
                    HapticsManager.shared.trigger(.selection)
                    draft.gender = isSelected ? nil : choice.gender
                } label: {
                    Text(choice.title)
                        .font(.custom("Montserrat-ExtraBold", size: 15))
                        .foregroundStyle(isSelected ? OnboardingV3Palette.accent : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? OnboardingV3Palette.accent.opacity(0.1) : OnboardingV3Palette.cardFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected ? OnboardingV3Palette.accent : OnboardingV3Palette.cardBorder,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    /// The month, day and year wheel in the card's look. Moving it is what sets a birthday.
    private var birthdayWheel: some View {
        DatePicker(
            "Birthday",
            selection: Binding(
                get: { wheelDate },
                set: { newValue in
                    wheelDate = newValue
                    draft.setBirthday(from: newValue)
                }
            ),
            in: ClimberCardDraft.birthdayRange(),
            displayedComponents: .date
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .colorScheme(.dark)
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipped()
        .padding(.horizontal, 8)
        .onboardingCard(cornerRadius: 20)
        .accessibilityLabel("Birthday")
    }
}

#Preview("08 climber card") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-card") ?? .standard),
        startingAt: .climberCard
    ))
}
