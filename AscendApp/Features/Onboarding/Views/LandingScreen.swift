import SwiftUI

struct LandingScreen: View {
    @State private var isShowingValueCarousel = false
    @State private var isShowingSignIn = false

    var body: some View {
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
                    .position(x: centerX, y: 200 * scaleY)

                    welcomeHeadline(typeScale: typeScale)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 334 * scaleX, height: 36 * scaleY, alignment: .top)
                        .position(x: centerX, y: 270 * scaleY)

                    Button(action: startOnboarding) {
                        Text("GET STARTED")
                    }
                    .buttonStyle(
                        OnboardingPrimaryCTAButtonStyle(
                            height: 56 * scaleY,
                            cornerRadius: 12 * typeScale,
                            fontSize: 16 * typeScale,
                            tint: brandAccentColor,
                            shadowOpacity: 0
                        )
                    )
                    .frame(width: 334 * scaleX)
                    .position(x: centerX, y: 724 * scaleY)

                    Button(action: openSignIn) {
                        HStack(spacing: 4 * typeScale) {
                            Text("Already have an account?")
                                .foregroundStyle(.white.opacity(0.78))

                            Text("Sign in")
                                .foregroundStyle(.white)
                        }
                        .font(.montserratSemiBold(size: 14 * typeScale))
                        .frame(maxWidth: .infinity, minHeight: 44 * scaleY)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 334 * scaleX)
                    .position(x: centerX, y: 786 * scaleY)
                    .accessibilityLabel("Already have an account? Sign in")
                    .accessibilityHint("Opens the sign-in screen.")
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isShowingValueCarousel) {
            PreAuthOnboardingValueCarouselScreen()
        }
        .navigationDestination(isPresented: $isShowingSignIn) {
            SignUpView()
        }
        .trackOnboardingScreenView(OnboardingAnalyticsEvent.welcomeContext)
    }

    private func startOnboarding() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenCompleted(
                context: OnboardingAnalyticsEvent.welcomeContext,
                inputType: "button",
                properties: ["action_id": .string("get_started")]
            )
        )
        isShowingValueCarousel = true
    }

    private func openSignIn() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenCompleted(
                context: OnboardingAnalyticsEvent.welcomeContext,
                inputType: "button",
                properties: ["action_id": .string("sign_in")]
            )
        )
        isShowingSignIn = true
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
