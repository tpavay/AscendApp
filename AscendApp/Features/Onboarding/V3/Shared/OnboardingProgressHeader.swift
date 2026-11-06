import SwiftUI

/// How far along the bar is on each screen, as a percentage. One table keyed by step, front-loaded
/// on purpose: the first screens move the bar a long way so a climber feels the end is near.
///
/// 01 and the sign-in screen (13) have no bar. 06b holds 06's value, and the two branches of 07 share one.
enum OnboardingProgressTable {
    /// Where the bar starts on the first screen that shows it.
    static let entryValue: Double = 15

    static func value(for step: OnboardingV3Step) -> Double? {
        switch step {
        case .welcome, .auth: nil
        case .goHarder: 38
        case .getBetter: 55
        case .somethingToChase: 67
        case .countMethods: 75
        case .healthConnect, .healthPermission: 81
        case .healthHistory, .usualClimb: 86
        case .climberCard: 90
        case .claimCity: 93
        case .weeklyTarget: 95
        case .thisMonthEvent: 97
        case .notificationPrimer: 98
        }
    }
}

/// The top of an onboarding screen: a back circle, the progress bar, and an optional Skip.
///
/// The bar animates from the value the previous screen showed to this screen's value, and going
/// back animates it downward, because the coordinator hands every screen the value it left from.
/// The close variant has an X and no bar and serves the Health screen when it is opened later from
/// the Climb sheet or Settings.
struct OnboardingProgressHeader: View {
    private enum Content {
        case progress(step: OnboardingV3Step, skipTitle: String?, onSkip: (() -> Void)?)
        case close(onClose: () -> Void)
    }

    private let content: Content

    @Environment(\.onboardingV3Coordinator) private var coordinator

    /// The bar for `step`, with a Skip on the right when `onSkip` is given. Back goes to the
    /// previous screen through the flow's coordinator.
    init(step: OnboardingV3Step, skipTitle: String? = "Skip", onSkip: (() -> Void)? = nil) {
        content = .progress(step: step, skipTitle: onSkip == nil ? nil : skipTitle, onSkip: onSkip)
    }

    /// An X and no bar.
    init(onClose: @escaping () -> Void) {
        content = .close(onClose: onClose)
    }

    var body: some View {
        switch content {
        case .progress(let step, let skipTitle, let onSkip):
            HStack(spacing: 14) {
                OnboardingHeaderCircleButton(symbol: "chevron.left", label: "Back") {
                    coordinator?.back()
                }
                .disabled(coordinator?.canGoBack == false)

                OnboardingProgressBar(
                    step: step,
                    origin: coordinator?.progressOrigin(for: step)
                )

                if let skipTitle, let onSkip {
                    Button(skipTitle, action: onSkip)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(OnboardingV3Palette.skip)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 44)

        case .close(let onClose):
            HStack {
                Spacer(minLength: 0)
                OnboardingHeaderCircleButton(symbol: "xmark", label: "Close", action: onClose)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
        }
    }
}

private struct OnboardingHeaderCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(OnboardingV3Palette.controlFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The bar itself: 6 pt, 3 pt radius, a lime gradient on a `#262626` track. It reads as a
/// percentage to VoiceOver and does not take focus as a control.
struct OnboardingProgressBar: View {
    let step: OnboardingV3Step
    /// The value to animate from. Nil, or the step's own value, means no movement.
    var origin: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Double?

    private var target: Double { OnboardingProgressTable.value(for: step) ?? 0 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(OnboardingV3Palette.progressTrack)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [OnboardingV3Palette.progressFillStart, OnboardingV3Palette.progressFillEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * (displayed ?? origin ?? target) / 100)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue(Text("\(Int(target)) percent"))
        .onAppear {
            guard displayed == nil else { return }
            displayed = origin ?? target

            if reduceMotion {
                displayed = target
            } else {
                // 0.8 s after a 0.15 s beat, on the design's curve.
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8).delay(0.15)) {
                    displayed = target
                }
            }
        }
    }
}

// MARK: - Coordinator environment

private struct OnboardingV3CoordinatorKey: EnvironmentKey {
    static var defaultValue: OnboardingV3Coordinator? { nil }
}

extension EnvironmentValues {
    /// The coordinator of the flow this screen sits in. Nil outside the flow, in a preview or a test.
    var onboardingV3Coordinator: OnboardingV3Coordinator? {
        get { self[OnboardingV3CoordinatorKey.self] }
        set { self[OnboardingV3CoordinatorKey.self] = newValue }
    }
}

#Preview("Progress header") {
    VStack(spacing: 30) {
        OnboardingProgressHeader(step: .goHarder)
        OnboardingProgressHeader(step: .climberCard, onSkip: {})
        OnboardingProgressHeader(onClose: {})
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.black)
}
