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
                Color.black
            },
            content: { scaffoldLayout in
                AuthLandingContent(
                    layout: AuthLandingLayout(scaffoldLayout: scaffoldLayout),
                    errorMessage: hasAttemptedInteractiveSignIn ? authVM.errorMessage : nil,
                    googleIsLoading: authVM.authenticationState == .authenticatingWithGoogle,
                    appleIsLoading: authVM.authenticationState == .authenticatingWithApple,
                    lastUsedProvider: authVM.lastUsedProvider,
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

    var horizontalPadding: CGFloat { isCompactHeight ? 24 : 28 }

    /// Vertical position of the wordmark (top of A mark) as a proportion of the
    /// total screen height. ~27% from the top mirrors the Figma placement.
    var wordmarkTopPadding: CGFloat {
        let ratio: CGFloat = isCompactHeight ? 0.22 : 0.27
        return max(safeAreaInsets.top + 80, size.height * ratio)
    }

    var bottomPadding: CGFloat {
        safeAreaInsets.bottom + (isCompactHeight ? 10 : 14)
    }

    // Wordmark sizing — matches Figma (A mark 56px, SCEND 30pt)
    var letterFontSize: CGFloat { isCompactHeight ? 26 : 30 }
    var letterSpacing: CGFloat { isCompactHeight ? 4 : 5 }
    var iconSize: CGFloat { isCompactHeight ? 48 : 56 }
    var iconTrailingSpacing: CGFloat { isCompactHeight ? 12 : 14 }

    var accentLineTopSpacing: CGFloat { isCompactHeight ? 22 : 28 }
    var accentLineWidth: CGFloat { 48 }
    var accentLineHeight: CGFloat { 2 }

    var buttonSpacing: CGFloat { isCompactHeight ? 10 : 12 }
    var internalQATopSpacing: CGFloat { isCompactHeight ? 14 : 18 }
    var buttonHeight: CGFloat { isCompactHeight ? 52 : 56 }
    var buttonCornerRadius: CGFloat { 12 }
    var buttonFontSize: CGFloat { isCompactHeight ? 16 : 17 }

    var legalTopSpacing: CGFloat { isCompactHeight ? 14 : 18 }
    var legalFontSize: CGFloat { isCompactHeight ? 10 : 11 }
    var legalLineSpacing: CGFloat { 2 }
}

private struct AuthLandingContent: View {
    let layout: AuthLandingLayout
    let errorMessage: String?
    let googleIsLoading: Bool
    let appleIsLoading: Bool
    let lastUsedProvider: AuthProviderKind?
    let showsInternalQA: Bool
    let isDisabled: Bool
    let onGoogle: () -> Void
    let onApple: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: layout.wordmarkTopPadding)

            AuthLandingBrand(layout: layout)

            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: layout.accentLineWidth, height: layout.accentLineHeight)
                .clipShape(Capsule())
                .shadow(color: Color.accentColor.opacity(0.5), radius: 8, x: 0, y: 0)
                .padding(.top, layout.accentLineTopSpacing)

            Spacer()

            VStack(spacing: layout.buttonSpacing) {
                AuthProviderButton(
                    title: appleIsLoading ? "Signing In..." : "Continue with Apple",
                    style: .apple,
                    isLoading: appleIsLoading,
                    isDisabled: isDisabled,
                    height: layout.buttonHeight,
                    cornerRadius: layout.buttonCornerRadius,
                    fontSize: layout.buttonFontSize,
                    accessoryTitle: lastUsedProvider == .apple ? "Last Used" : nil,
                    icon: {
                        Image(systemName: "apple.logo")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.black)
                            .frame(width: 22, height: 22)
                    },
                    action: onApple
                )

                AuthProviderButton(
                    title: googleIsLoading ? "Signing In..." : "Continue with Google",
                    style: .google,
                    isLoading: googleIsLoading,
                    isDisabled: isDisabled,
                    height: layout.buttonHeight,
                    cornerRadius: layout.buttonCornerRadius,
                    fontSize: layout.buttonFontSize,
                    accessoryTitle: lastUsedProvider == .google ? "Last Used" : nil,
                    icon: {
                        Image("GoogleIcon")
                            .resizable()
                            .renderingMode(.original)
                            .frame(width: 24, height: 24)
                    },
                    action: onGoogle
                )

                if showsInternalQA {
                    NavigationLink {
                        InternalQASignInView()
                    } label: {
                        Text("Internal QA Sign-In")
                            .font(.montserratSemiBold(size: max(layout.buttonFontSize - 2, 14)))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
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
                    .padding(.top, layout.internalQATopSpacing - layout.buttonSpacing)
                    .accessibilityLabel("Internal QA Sign-In")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.red.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, layout.buttonSpacing)
                    .accessibilityLabel("Authentication error: \(errorMessage)")
            }

            AuthLegalText(layout: layout)
                .padding(.top, layout.legalTopSpacing)
                .padding(.bottom, layout.bottomPadding)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

private struct AuthLandingBrand: View {
    let layout: AuthLandingLayout

    var body: some View {
        AscendWordmark(
            size: layout.letterFontSize,
            letterColor: .white.opacity(0.95),
            letterSpacing: layout.letterSpacing,
            iconSize: layout.iconSize,
            iconTrailingSpacing: layout.iconTrailingSpacing
        )
    }
}

private enum AuthProviderButtonStyle {
    case google
    case apple

    var foregroundColor: Color {
        switch self {
        case .google:
            .white.opacity(0.92)
        case .apple:
            .black
        }
    }

    var loadingTint: Color {
        switch self {
        case .google:
            .white
        case .apple:
            .black
        }
    }

    var accessoryForegroundColor: Color {
        switch self {
        case .google:
            .white.opacity(0.78)
        case .apple:
            .black.opacity(0.7)
        }
    }

    var accessoryBackgroundColor: Color {
        switch self {
        case .google:
            .white.opacity(0.14)
        case .apple:
            Color.black.opacity(0.08)
        }
    }

    func background(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return shape
            .fill(backgroundFill)
            .overlay(shape.stroke(borderColor, lineWidth: 1))
    }

    private var backgroundFill: Color {
        switch self {
        case .google:
            .white.opacity(0.08)
        case .apple:
            .white
        }
    }

    private var borderColor: Color {
        switch self {
        case .google:
            .white.opacity(0.18)
        case .apple:
            .clear
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
    let accessoryTitle: String?
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    private let iconLeftPadding: CGFloat = 20
    private let badgeRightPadding: CGFloat = 14

    var body: some View {
        Button(action: action) {
            ZStack {
                // Centered title — anchored to the full button width
                Text(title)
                    .font(.montserratSemiBold(size: fontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .foregroundStyle(style.foregroundColor)

                // Left-anchored icon (or loading spinner)
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: style.loadingTint))
                            .scaleEffect(0.92)
                    } else {
                        icon()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, iconLeftPadding)

                // Right-anchored accessory badge (e.g. "LAST USED")
                if let accessoryTitle, !isLoading {
                    HStack {
                        Spacer(minLength: 0)
                        Text(accessoryTitle.uppercased())
                            .font(.montserratBold(size: 6.5))
                            .tracking(0.25)
                            .foregroundStyle(style.accessoryForegroundColor)
                            .lineLimit(1)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(style.accessoryBackgroundColor)
                            )
                            .accessibilityHidden(true)
                    }
                    .padding(.trailing, badgeRightPadding)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(style.background(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let accessoryTitle else { return title }
        return "\(title), \(accessoryTitle)"
    }
}

private struct AuthLegalText: View {
    let layout: AuthLandingLayout

    var body: some View {
        Text(.init("By continuing, you agree to our [Terms](https://ascendstepper.com/terms) and [Privacy Policy](https://ascendstepper.com/privacy)."))
            .font(.montserratMedium(size: layout.legalFontSize))
            .foregroundStyle(Color.white.opacity(0.55))
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
