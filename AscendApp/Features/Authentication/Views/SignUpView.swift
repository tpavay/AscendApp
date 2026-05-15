import AuthenticationServices
import FirebaseCore
import SwiftUI

struct SignUpView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            let layout = SignInLayout(size: geometry.size)

            ZStack(alignment: .bottom) {
                SignInBackground(layout: layout)

                SignInHero(layout: layout)

                VStack(spacing: 0) {
                    HStack {
                        SignInBackButton(action: { dismiss() })
                        Spacer()
                    }
                    .padding(.leading, 18)

                    Spacer(minLength: 0)
                }

                SignInAuthCard(
                    layout: layout,
                    errorMessage: authVM.errorMessage,
                    appleIsLoading: authVM.authenticationState == .authenticatingWithApple,
                    googleIsLoading: authVM.authenticationState == .authenticatingWithGoogle,
                    isDisabled: authVM.authenticationState.isAuthenticating,
                    onApple: signInWithApple,
                    onGoogle: signInWithGoogle
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: authVM.user?.uid) { _, userId in
            if userId != nil {
                dismiss()
            }
        }
    }

    private func signInWithApple() {
        Task {
            await authVM.signInWithApple()
            dismissIfAuthenticated()
        }
    }

    private func signInWithGoogle() {
        Task {
            await authVM.signInWithGoogle()
            dismissIfAuthenticated()
        }
    }

    private func dismissIfAuthenticated() {
        if authVM.user != nil {
            dismiss()
        }
    }
}

private struct SignInLayout {
    let size: CGSize

    var heroWidth: CGFloat {
        size.width
    }

    var phoneCenterY: CGFloat {
        size.height * 0.36
    }

    var phoneCenterX: CGFloat {
        size.width / 2
    }

    var cardHeight: CGFloat {
        max(size.height * 0.46, 380)
    }

    var cardCornerRadius: CGFloat {
        min(52, size.width * 0.13)
    }

    var cardHorizontalPadding: CGFloat { 32 }

    var headlineSize: CGFloat { 32 }

    var subcopySize: CGFloat { 18 }

    var buttonHeight: CGFloat { 66 }

    var buttonCornerRadius: CGFloat { 20 }

    var buttonFontSize: CGFloat { 20 }

    var topGap: CGFloat { 18 }

    var contentSpacing: CGFloat { 18 }

    var textBlockSpacing: CGFloat { 10 }

    var buttonStackSpacing: CGFloat { 14 }

    var buttonStackTopPadding: CGFloat { 10 }
}

private struct SignInBackground: View {
    let layout: SignInLayout

    private var glowCenter: UnitPoint {
        UnitPoint(
            x: layout.phoneCenterX / layout.size.width,
            y: layout.phoneCenterY / layout.size.height
        )
    }

    var body: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.5),
                    Color.black.opacity(0.95)
                ],
                center: glowCenter,
                startRadius: 240,
                endRadius: 640
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct SignInHero: View {
    let layout: SignInLayout

    var body: some View {
        Image("OnboardingHomePreview")
            .resizable()
            .scaledToFit()
            .frame(width: layout.heroWidth)
            .position(x: layout.phoneCenterX, y: layout.phoneCenterY)
            .allowsHitTesting(false)
    }
}

private struct SignInBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

private struct SignInAuthCard: View {
    let layout: SignInLayout
    let errorMessage: String?
    let appleIsLoading: Bool
    let googleIsLoading: Bool
    let isDisabled: Bool
    let onApple: () -> Void
    let onGoogle: () -> Void

    var body: some View {
        VStack(spacing: layout.contentSpacing) {
            Spacer().frame(height: layout.topGap)

            VStack(spacing: layout.textBlockSpacing) {
                Text("Sign in to unlock\nthe full Ascend experience.")
                    .font(.montserratBold(size: layout.headlineSize))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Track climbs. Save progress and\ncompete on leaderboards.")
                    .font(.montserratMedium(size: layout.subcopySize))
                    .foregroundStyle(Color(red: 168 / 255, green: 168 / 255, blue: 168 / 255))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.cardHorizontalPadding)
            }

            VStack(spacing: layout.buttonStackSpacing) {
                AuthProviderButton(
                    title: appleIsLoading ? "Signing In..." : "Continue with Apple",
                    isLoading: appleIsLoading,
                    isDisabled: isDisabled,
                    height: layout.buttonHeight,
                    cornerRadius: layout.buttonCornerRadius,
                    fontSize: layout.buttonFontSize,
                    icon: {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 22, weight: .medium))
                    },
                    action: onApple
                )

                AuthProviderButton(
                    title: googleIsLoading ? "Signing In..." : "Continue with Google",
                    isLoading: googleIsLoading,
                    isDisabled: isDisabled,
                    height: layout.buttonHeight,
                    cornerRadius: layout.buttonCornerRadius,
                    fontSize: layout.buttonFontSize,
                    icon: {
                        Image("GoogleIcon")
                            .resizable()
                            .renderingMode(.original)
                            .frame(width: 22, height: 22)
                    },
                    action: onGoogle
                )
            }
            .padding(.horizontal, layout.cardHorizontalPadding)
            .padding(.top, layout.buttonStackTopPadding)

            Spacer(minLength: 0)
        }
        .frame(width: layout.size.width, height: layout.cardHeight, alignment: .top)
        .background(cardBackground)
    }

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: layout.cardCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: layout.cardCornerRadius,
            style: .continuous
        )
    }

    private var cardBackground: some View {
        cardShape
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 11 / 255, green: 11 / 255, blue: 11 / 255),
                        Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                cardShape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.38),
                                Color.accentColor.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.75), radius: 28, x: 0, y: -18)
    }
}

private struct AuthProviderButton<Icon: View>: View {
    let title: String
    let isLoading: Bool
    let isDisabled: Bool
    let height: CGFloat
    let cornerRadius: CGFloat
    let fontSize: CGFloat
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.95)
                } else {
                    icon()
                }

                Text(title)
                    .font(.montserratSemiBold(size: fontSize))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(buttonShape.fill(buttonGradient))
            .overlay(buttonShape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            .clipShape(buttonShape)
            .contentShape(buttonShape)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityLabel(title)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 27 / 255, green: 27 / 255, blue: 29 / 255),
                Color(red: 38 / 255, green: 38 / 255, blue: 40 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthenticationViewModel())
    }
}
