import SwiftUI

struct LandingScreen: View {
    var body: some View {
        ZStack {
            OnboardingWelcomeBackground()

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    VStack(spacing: 24) {
                        AscendWordmark(size: 11, letterColor: .white.opacity(0.85))

                        (Text("Race the world up ").foregroundStyle(.white)
                         + Text("real landmarks").foregroundStyle(Color.accentColor)
                         + Text(".").foregroundStyle(.white))
                            .font(.montserratBold(size: 34))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        NavigationLink(destination: PreAuthOnboardingValueCarouselScreen()) {
                            Text("GET STARTED")
                        }
                        .buttonStyle(
                            OnboardingPrimaryCTAButtonStyle(
                                height: 62,
                                tint: .accent,
                                shadowOpacity: 0
                            )
                        )
                        .padding(.horizontal, 28)

                        NavigationLink(destination: SignUpView()) {
                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .foregroundStyle(.white.opacity(0.66))

                                Text("Log in")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .font(.montserratSemiBold(size: 13))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Already have an account? Log in")
                    }
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom + 12, 36))
                }
                .padding(.top, geometry.size.height * 0.08)
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
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
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.78),
                            Color.black.opacity(0.24),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.2),
                            Color.black.opacity(0.82)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    Color.black.opacity(0.12)
                }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        LandingScreen()
    }
}
