import SwiftUI

struct OnboardingQuestionScaffold<Content: View>: View {
    let progressIndex: Int
    let progressCount: Int
    let backgroundImageName: String
    var eyebrow: String?
    let headline: String
    var subtitle: String?
    var showsBrandMark = true
    let primaryTitle: String
    var isPrimaryDisabled = false
    var isPrimaryLoading = false
    var isBackEnabled = true
    let onBack: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        OnboardingScaffold(
            backAction: onBack,
            isBackEnabled: isBackEnabled,
            background: {
                OnboardingValueImageBackground(
                    imageName: backgroundImageName,
                    dimmingOpacity: 0.12,
                    topReadabilityOpacity: 0.64
                )
            },
            content: { layout in
                ZStack(alignment: .top) {
                    progressBar(layout: layout)

                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                            .frame(height: topContentPadding(for: layout))

                        if showsBrandMark {
                            brandMark(layout: layout)
                                .padding(.bottom, brandBottomPadding(for: layout))
                        }

                        header(layout: layout)

                        content()
                            .padding(.top, layout.size.height < 740 ? 24 : 28)

                        Spacer(minLength: layout.primaryButtonHeight + 52)
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                }
            },
            bottomContent: { layout in
                Button(action: onContinue) {
                    HStack(spacing: 10) {
                        if isPrimaryLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.82)))
                                .scaleEffect(0.85)
                        }

                        Text(primaryTitle)
                    }
                }
                .buttonStyle(
                    OnboardingPrimaryCTAButtonStyle(
                        height: layout.primaryButtonHeight,
                        tint: .accent,
                        shadowOpacity: 0.24
                    )
                )
                .disabled(isPrimaryDisabled)
            }
        )
    }

    private func progressBar(layout: OnboardingScaffoldLayout) -> some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: OnboardingChromeMetrics.backButtonLeadingPadding + OnboardingChromeMetrics.backButtonSize + 18)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.22))

                    Capsule(style: .continuous)
                        .fill(OnboardingValuePalette.lime)
                        .frame(width: geometry.size.width * progressFraction)
                }
            }
            .frame(height: 4)

            Spacer()
                .frame(width: layout.horizontalPadding)
        }
        .frame(height: 4)
        .padding(.top, OnboardingChromeMetrics.backButtonTopPadding + 25)
        .animation(.easeInOut(duration: 0.22), value: progressFraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue(accessibilityProgressValue)
    }

    private func brandMark(layout: OnboardingScaffoldLayout) -> some View {
        AscendWordmark(
            size: layout.size.height < 740 ? 16 : 18,
            letterColor: .white.opacity(0.92)
        )
        .frame(maxWidth: .infinity)
    }

    private func header(layout: OnboardingScaffoldLayout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(OnboardingValuePalette.lime)
            }

            Text(headline)
                .font(.montserratBold(size: layout.size.width < 370 ? 33 : 37))
                .foregroundStyle(.white)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(Color(red: 168 / 255, green: 168 / 255, blue: 168 / 255))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func topContentPadding(for layout: OnboardingScaffoldLayout) -> CGFloat {
        layout.topChromeHeight + (layout.size.height < 740 ? 20 : 38)
    }

    private func brandBottomPadding(for layout: OnboardingScaffoldLayout) -> CGFloat {
        layout.size.height < 740 ? 42 : 56
    }

    private var progressFraction: CGFloat {
        guard progressCount > 0 else { return 0 }
        let completedStepCount = min(max(progressIndex + 1, 0), progressCount)
        return CGFloat(completedStepCount) / CGFloat(progressCount)
    }

    private var accessibilityProgressValue: String {
        guard progressCount > 0 else { return "0 of 0" }
        let completedStepCount = min(max(progressIndex + 1, 0), progressCount)
        return "\(completedStepCount) of \(progressCount)"
    }
}
