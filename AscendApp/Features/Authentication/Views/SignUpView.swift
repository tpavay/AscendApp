import SwiftUI
import FirebaseCore

struct SignUpView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var hasAttemptedInteractiveSignIn = false

    var body: some View {
        OnboardingScaffold(
            backAction: { dismiss() },
            background: {
                AuthLandingBackground()
            },
            content: { scaffoldLayout in
                AuthLandingContent(
                    layout: AuthLandingLayout(scaffoldLayout: scaffoldLayout),
                    errorMessage: hasAttemptedInteractiveSignIn ? authVM.errorMessage : nil,
                    googleIsLoading: authVM.authenticationState == .authenticatingWithGoogle,
                    appleIsLoading: authVM.authenticationState == .authenticatingWithApple,
                    showsInternalQA: InternalQASignInAvailability.isEnabled(projectID: FirebaseApp.app()?.options.projectID),
                    isDisabled: authVM.authenticationState.isAuthenticating,
                    onGoogle: signInWithGoogle,
                    onApple: signInWithApple
                )
            }
        )
        .onAppear {
            hasAttemptedInteractiveSignIn = false
            authVM.errorMessage = nil
        }
    }

    private func signInWithGoogle() {
        hasAttemptedInteractiveSignIn = true
        Task {
            await authVM.signInWithGoogle()
        }
    }

    private func signInWithApple() {
        hasAttemptedInteractiveSignIn = true
        Task {
            await authVM.signInWithApple()
        }
    }
}

private struct AuthLandingLayout {
    private let scaffoldLayout: OnboardingScaffoldLayout

    init(scaffoldLayout: OnboardingScaffoldLayout) {
        self.scaffoldLayout = scaffoldLayout
    }

    var size: CGSize { scaffoldLayout.size }
    var safeAreaInsets: EdgeInsets { scaffoldLayout.safeAreaInsets }

    var isCompactHeight: Bool { size.height < 740 }

    var horizontalPadding: CGFloat { isCompactHeight ? 28 : 32 }

    var brandTopPadding: CGFloat {
        isCompactHeight ? safeAreaInsets.top + 34 : max(safeAreaInsets.top + 44, size.height * 0.11)
    }

    var bottomPadding: CGFloat {
        safeAreaInsets.bottom + (isCompactHeight ? 14 : 26)
    }

    var brandIconSize: CGFloat { isCompactHeight ? 74 : 84 }

    var brandSpacing: CGFloat { isCompactHeight ? 8 : 10 }

    var brandLetterSpacing: CGFloat { isCompactHeight ? 13 : 15 }

    var brandLetterFontSize: CGFloat { isCompactHeight ? 18 : 20 }

    var brandToContentSpacing: CGFloat { isCompactHeight ? 28 : 44 }

    var authContentSpacing: CGFloat { isCompactHeight ? 20 : 28 }

    var headlineSpacing: CGFloat { 2 }

    var headlineFontSize: CGFloat { isCompactHeight ? 38 : 42 }

    var bodySpacing: CGFloat { isCompactHeight ? 12 : 18 }

    var subtitleFontSize: CGFloat { isCompactHeight ? 14 : 16 }

    var subtitleLineSpacing: CGFloat { isCompactHeight ? 3 : 5 }

    var buttonSpacing: CGFloat { isCompactHeight ? 12 : 14 }

    var buttonHeight: CGFloat { isCompactHeight ? 52 : 58 }

    var buttonCornerRadius: CGFloat { 10 }

    var buttonFontSize: CGFloat { isCompactHeight ? 16 : 18 }

    var legalFontSize: CGFloat { isCompactHeight ? 9.5 : 10.5 }

    var legalLineSpacing: CGFloat { isCompactHeight ? 1.5 : 2 }
}

private struct AuthLandingBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Image("AuthStaircaseBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.28),
                            Color.black.opacity(0.16),
                            Color.black.opacity(0.34),
                            Color.black.opacity(0.94)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.5),
                            Color.black.opacity(0.12),
                            Color.black.opacity(0.42)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
        }
    }
}

private struct AuthLandingContent: View {
    let layout: AuthLandingLayout
    let errorMessage: String?
    let googleIsLoading: Bool
    let appleIsLoading: Bool
    let showsInternalQA: Bool
    let isDisabled: Bool
    let onGoogle: () -> Void
    let onApple: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: layout.brandTopPadding)

            AuthLandingBrand(layout: layout)

            Spacer(minLength: layout.brandToContentSpacing)

            VStack(alignment: .leading, spacing: layout.authContentSpacing) {
                VStack(alignment: .leading, spacing: layout.bodySpacing) {
                    AuthLandingHeadline(
                        spacing: layout.headlineSpacing,
                        fontSize: layout.headlineFontSize
                    )

                    Text("Track climbs, save progress, and\ncompete against climbers around the world.")
                        .font(.montserratSemiBold(size: layout.subtitleFontSize))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineSpacing(layout.subtitleLineSpacing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Track climbs, save progress, and compete against climbers around the world.")
                }

                VStack(spacing: layout.buttonSpacing) {
                    AuthProviderButton(
                        title: googleIsLoading ? "Signing In..." : "Continue with Google",
                        style: .google,
                        isLoading: googleIsLoading,
                        isDisabled: isDisabled,
                        height: layout.buttonHeight,
                        cornerRadius: layout.buttonCornerRadius,
                        fontSize: layout.buttonFontSize,
                        icon: {
                            Image("GoogleIcon")
                                .resizable()
                                .renderingMode(.original)
                                .frame(width: 24, height: 24)
                        },
                        action: onGoogle
                    )

                    AuthProviderButton(
                        title: appleIsLoading ? "Signing In..." : "Continue with Apple",
                        style: .apple,
                        isLoading: appleIsLoading,
                        isDisabled: isDisabled,
                        height: layout.buttonHeight,
                        cornerRadius: layout.buttonCornerRadius,
                        fontSize: layout.buttonFontSize,
                        icon: {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 24, weight: .semibold))
                        },
                        action: onApple
                    )

                    if showsInternalQA {
                        NavigationLink {
                            InternalQASignInView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 20, weight: .semibold))

                                Text("Internal QA Sign-In")
                                    .font(.montserratSemiBold(size: max(layout.buttonFontSize - 1, 14)))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.76)
                            }
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(maxWidth: .infinity)
                            .frame(height: layout.buttonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: layout.buttonCornerRadius, style: .continuous)
                                    .fill(Color.black.opacity(0.36))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: layout.buttonCornerRadius, style: .continuous)
                                            .stroke(Color.accentColor.opacity(0.44), lineWidth: 1)
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: layout.buttonCornerRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                        .opacity(isDisabled ? 0.72 : 1)
                        .accessibilityLabel("Internal QA Sign-In")
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.red.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Authentication error: \(errorMessage)")
                }

                AuthLegalText(layout: layout)
                    .padding(.top, errorMessage == nil ? 4 : 0)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, layout.bottomPadding)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

private struct AuthLandingBrand: View {
    let layout: AuthLandingLayout

    var body: some View {
        AscendWordmark(
            size: layout.brandLetterFontSize * 1.6,
            letterColor: .white.opacity(0.94)
        )
        .frame(maxWidth: .infinity)
    }
}

private struct AuthLandingHeadline: View {
    let spacing: CGFloat
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text("Start")
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text("building endurance")
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text("that lasts.")
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.montserratBold(size: fontSize))
        .lineSpacing(0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start building endurance that lasts.")
    }
}

private enum AuthProviderButtonStyle {
    case google
    case apple

    var foregroundColor: Color {
        switch self {
        case .google:
            Color(red: 23 / 255, green: 25 / 255, blue: 31 / 255)
        case .apple:
            .white
        }
    }

    var loadingTint: Color {
        switch self {
        case .google:
            Color(red: 23 / 255, green: 25 / 255, blue: 31 / 255)
        case .apple:
            .white
        }
    }

    func background(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return shape
            .fill(backgroundFill)
            .overlay(shape.stroke(borderColor, lineWidth: 1))
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 10)
    }

    private var backgroundFill: Color {
        switch self {
        case .google:
            .white
        case .apple:
            Color.black.opacity(0.42)
        }
    }

    private var borderColor: Color {
        switch self {
        case .google:
            .white.opacity(0.72)
        case .apple:
            .white.opacity(0.2)
        }
    }

    private var shadowColor: Color {
        switch self {
        case .google:
            .black.opacity(0.28)
        case .apple:
            .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch self {
        case .google:
            20
        case .apple:
            0
        }
    }
}

private struct AuthProviderButton<Icon: View>: View {
    let title: String
    let style: AuthProviderButtonStyle
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
                        .progressViewStyle(CircularProgressViewStyle(tint: style.loadingTint))
                        .scaleEffect(0.92)
                } else {
                    icon()
                }

                Text(title)
                    .font(.montserratSemiBold(size: fontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(style.foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(style.background(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityLabel(title)
    }
}

private struct AuthLegalText: View {
    let layout: AuthLandingLayout

    var body: some View {
        Text(.init("By continuing, you acknowledge that you have read and agreed to our [Terms of Service](https://ascendstepper.com/terms) and [Privacy Policy](https://ascendstepper.com/privacy)."))
            .font(.montserratMedium(size: layout.legalFontSize))
            .foregroundStyle(Color.white.opacity(0.62))
            .tint(Color.accentColor)
            .multilineTextAlignment(.center)
            .lineSpacing(layout.legalLineSpacing)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthenticationViewModel())
    }
}
