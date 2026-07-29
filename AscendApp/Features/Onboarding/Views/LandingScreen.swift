import SwiftUI

struct LandingScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var navigationState: LandingScreenNavigationState

    init(
        navigationState: LandingScreenNavigationState = LandingScreenNavigationState()
    ) {
        _navigationState = State(initialValue: navigationState)
    }

    var body: some View {
        @Bindable var navigationState = navigationState

        ZStack {
            OnboardingWelcomeBackground()

            GeometryReader { geometry in
                let scaleX = geometry.size.width / 390
                let scaleY = geometry.size.height / 844
                let typeScale = min(scaleX, scaleY)
                let centerX = geometry.size.width / 2

                ZStack(alignment: .topLeading) {
                    AscendWordmark(
                        size: 30 * typeScale,
                        letterColor: .white,
                        letterSpacing: 5.0 * typeScale,
                        iconSize: 52 * typeScale,
                        iconTrailingSpacing: 14 * typeScale
                    )
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .position(x: centerX, y: 200 * scaleY)

                    welcomeHeadline(typeScale: typeScale)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 334 * scaleX, height: 36 * scaleY, alignment: .top)
                        .position(x: centerX, y: 270 * scaleY)

                }
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
                .padding(.horizontal, 28)
                .padding(.bottom, LandingScreenActionLayoutPolicy.bottomPadding)
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $navigationState.destination) { destination in
            switch destination {
            case .valueCarousel:
                PreAuthOnboardingValueCarouselScreen()
            case .signIn:
                SignUpView()
            }
        }
        .trackOnboardingScreenView(OnboardingAnalyticsEvent.welcomeContext)
    }

    private var bottomActions: some View {
        VStack(spacing: LandingScreenActionLayoutPolicy.actionSpacing) {
            Button(action: startOnboarding) {
                Text("GET STARTED")
            }
            .buttonStyle(
                OnboardingPrimaryCTAButtonStyle(
                    height: LandingScreenActionLayoutPolicy.primaryActionHeight,
                    cornerRadius: 12,
                    fontSize: 16,
                    tint: brandAccentColor,
                    shadowOpacity: 0
                )
            )

            Button(action: openSignIn) {
                ViewThatFits(in: .horizontal) {
                    if LandingScreenActionLayoutPolicy.usesCompactSignInLabel(
                        for: dynamicTypeSize
                    ) {
                        Text(LandingScreenActionLayoutPolicy.signInTitle)
                            .foregroundStyle(.white)
                    } else {
                        HStack(spacing: 4) {
                            Text(LandingScreenActionLayoutPolicy.signInPrompt)
                                .foregroundStyle(.white.opacity(0.78))

                            Text(LandingScreenActionLayoutPolicy.signInTitle)
                                .foregroundStyle(.white)
                        }
                    }

                    Text(LandingScreenActionLayoutPolicy.signInTitle)
                        .foregroundStyle(.white)
                }
                .font(.montserratSemiBold(size: 14))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: LandingScreenActionLayoutPolicy.secondaryActionMinimumHeight
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LandingScreenActionLayoutPolicy.signInAccessibilityLabel)
            .accessibilityHint("Opens the sign-in screen.")
            .accessibilityIdentifier("welcomeSignIn")
        }
        .frame(maxWidth: 334)
    }

    private func startOnboarding() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenCompleted(
                context: OnboardingAnalyticsEvent.welcomeContext,
                inputType: "button",
                properties: ["action_id": .string("get_started")]
            )
        )
        navigationState.openValueCarousel()
    }

    private func openSignIn() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenCompleted(
                context: OnboardingAnalyticsEvent.welcomeContext,
                inputType: "button",
                properties: ["action_id": .string("sign_in")]
            )
        )
        navigationState.openSignIn()
    }

    private func welcomeHeadline(typeScale: CGFloat) -> Text {
        Text("The ")
            .foregroundStyle(.white.opacity(0.95))
            .font(.montserratSemiBold(size: 24 * typeScale))
        + Text("stair stepper")
            .foregroundStyle(brandAccentColor)
            .font(.montserratSemiBold(size: 24 * typeScale))
        + Text(" app.")
            .foregroundStyle(.white.opacity(0.95))
            .font(.montserratSemiBold(size: 24 * typeScale))
    }

    private var brandAccentColor: Color {
        Color.ascendAccent
    }
}

private struct OnboardingWelcomeBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Image("OnboardingWelcomeBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        LandingScreen()
    }
}
