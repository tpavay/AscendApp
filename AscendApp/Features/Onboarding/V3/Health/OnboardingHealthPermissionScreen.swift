import SwiftUI

/// 06b Two taps and you're set: a picture of the iOS Health sheet and the two taps that clear it,
/// shown before the sheet so it never arrives as a surprise. "GOT IT" is the request itself.
///
/// After the sheet it reads what Health holds and routes: workouts found go to 07a, none go to
/// 07b. The read and the request live in ``OnboardingHealthPermissionViewModel``; nothing is
/// written before sign-in.
struct OnboardingHealthPermissionScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var viewModel: OnboardingHealthPermissionViewModel

    init(coordinator: OnboardingV3Coordinator, viewModel: OnboardingHealthPermissionViewModel? = nil) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: viewModel ?? OnboardingHealthPermissionViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: .healthPermission)
                .padding(.top, 9)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        HealthPermissionSheetMock()
                            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity)
                            .background(alignment: .center) { SellGlow(color: OnboardingV3Palette.accent, opacity: 0.14) }
                            .onboardingEntrance(style: .rise(30), duration: 0.6)

                        VStack(alignment: .leading, spacing: 14) {
                            OnboardingHeadline(["Two taps and"], accentLines: ["you're set."], size: 30)

                            VStack(alignment: .leading, spacing: 10) {
                                TapStepRow(number: 1, lead: "Tap ", highlight: "Turn On All", trail: "")
                                TapStepRow(number: 2, lead: "Tap ", highlight: "Allow", trail: " at the bottom")
                            }

                            if let message = viewModel.errorMessage {
                                Text(message)
                                    .font(.montserratMedium(size: 14))
                                    .foregroundStyle(Color.ascendCaution)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)
                        .onboardingEntrance(delay: 0.3, duration: 0.45)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }

            Button("Got it") { Task { await viewModel.gotIt(coordinator: coordinator) } }
                .buttonStyle(.onboardingPrimary)
                .disabled(viewModel.isWorking)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .trackOnce(screen: .onboardingHealthPermission)
    }
}

/// "1  Tap Turn On All": a numbered circle and a line with its target in the accent.
private struct TapStepRow: View {
    let number: Int
    let lead: String
    let highlight: String
    let trail: String

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 26

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number)")
                .font(.custom("Montserrat-Black", fixedSize: size * 0.87))
                .foregroundStyle(.black)
                .frame(width: circle, height: circle)
                .background(Circle().fill(OnboardingV3Palette.accent))
                .accessibilityHidden(true)

            Text("\(Text(lead).foregroundStyle(.white))\(Text(highlight).foregroundStyle(OnboardingV3Palette.accent))\(Text(trail).foregroundStyle(.white))")
                .font(.custom("Montserrat-Bold", fixedSize: size))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number). \(lead)\(highlight)\(trail)")
    }
}

#Preview("06b two taps") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-health-permission") ?? .standard),
        startingAt: .healthPermission
    ))
}
