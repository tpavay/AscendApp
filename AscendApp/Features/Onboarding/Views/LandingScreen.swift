import SwiftUI

struct LandingScreen: View {
    var body: some View {
        ZStack {
            OnboardingWelcomeBackground()

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Image("AppIconInternal")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 210, height: 210)
                            .accessibilityLabel("Ascend")

                        VStack(spacing: 8) {
                            Text("WELCOME TO ASCEND")
                                .font(.montserratBold(size: 20))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .kerning(0.6)

                            Text("Build endurance that changes what’s possible.")
                                .font(.montserratRegular(size: 13.5))
                                .foregroundStyle(.white.opacity(0.78))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .frame(maxWidth: 330)
                        }
                    }
                    .padding(.horizontal, 24)
                    .offset(y: -60)

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
                .padding(.top, geometry.size.height * 0.23)
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
