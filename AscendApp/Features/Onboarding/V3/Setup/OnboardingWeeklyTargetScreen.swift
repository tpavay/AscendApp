import SwiftUI

/// 10: how many days a week. Optional: Skip and "No target for now" leave the target unset, and a
/// climber with no target never gets the weekly ring or the reminder. Nothing is preselected and
/// the number reads "?" until a bar is tapped.
struct OnboardingWeeklyTargetScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var selection: WeeklyTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(coordinator: OnboardingV3Coordinator) {
        self.coordinator = coordinator
        _selection = State(initialValue: coordinator.answers.weeklyTargetDays.flatMap(WeeklyTarget.init(days:)))
    }

    var body: some View {
        GeometryReader { proxy in
            layout(isCompact: proxy.size.height < 720)
        }
        .task { OnboardingMonthlyEventModel.shared.prefetch() }
        .trackOnce(screen: .onboardingWeeklyTarget)
    }

    private func layout(isCompact: Bool) -> some View {
        OnboardingSetupLayout(step: .weeklyTarget, onSkip: { skip() }) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeadline(["How many days"], accentLines: ["a week?"], accent: .lime)
                    .onboardingEntrance(index: 0)

                Text("Set a target if you want one. Hit your days and close your week.")
                    .onboardingSecondary()
                    .onboardingEntrance(index: 1)

                bigNumber(isCompact: isCompact)
                    .frame(maxWidth: .infinity)
                    .padding(.top, isCompact ? 0 : 12)
                    .onboardingEntrance(index: 2)

                bars(isCompact: isCompact)
                    .padding(.top, 8)
                    .onboardingEntrance(index: 3)
            }
        } footer: {
            VStack(spacing: 4) {
                Button("Set my target") {
                    guard let selection else { return }
                    coordinator.update { $0.weeklyTargetDays = selection.days }
                    coordinator.advance()
                }
                .buttonStyle(.onboardingPrimary)
                .disabled(selection == nil)

                Button("No target for now") { skip() }
                    .buttonStyle(.onboardingQuietLink)
            }
        }
    }

    /// Leaves the target unset, clearing one a climber set on an earlier pass and then went back
    /// to undo.
    private func skip() {
        coordinator.update { $0.weeklyTargetDays = nil }
        coordinator.advance()
    }

    private func bigNumber(isCompact: Bool) -> some View {
        VStack(spacing: 6) {
            Text(selection.map { $0.days.formatted() } ?? "?")
                .font(.custom("Montserrat-Black", size: isCompact ? 64 : 120))
                .foregroundStyle(selection == nil ? OnboardingV3Palette.chipBorder : OnboardingV3Palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .scaleEffect(1)
                .id(selection?.days ?? 0)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))

            Text(selection?.tier.title ?? "PICK A DAY COUNT")
                .font(.custom("Montserrat-ExtraBold", size: 16))
                .tracking(3.2)
                .foregroundStyle(selection == nil ? OnboardingV3Palette.secondary : .white)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.25, dampingFraction: 0.6), value: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selection.map { "\($0.summary), \($0.tier.title.capitalized)" } ?? "No target chosen")
    }

    private func bars(isCompact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(WeeklyTarget.validDays, id: \.self) { days in
                let isLit = (selection?.days ?? 0) >= days

                Button {
                    HapticsManager.shared.trigger(.selection)
                    selection = WeeklyTarget(days: days)
                } label: {
                    Text(days.formatted())
                        .font(.custom("Montserrat-Black", size: 16))
                        .foregroundStyle(isLit ? Color.black : OnboardingV3Palette.secondary.opacity(0.6))
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: (isCompact ? 30 : 55) + CGFloat(days) * (isCompact ? 11 : 21), alignment: .top)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    isLit
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [OnboardingV3Palette.progressFillEnd, OnboardingV3Palette.accent],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ))
                                        : AnyShapeStyle(OnboardingV3Palette.controlFill)
                                )
                        )
                        .shadow(color: isLit ? OnboardingV3Palette.accent.opacity(0.35) : .clear, radius: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WeeklyTarget(days: days)?.summary ?? "")
                .accessibilityAddTraits(selection?.days == days ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: selection)
    }
}

#Preview("10 weekly target") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-target") ?? .standard),
        startingAt: .weeklyTarget
    ))
}
