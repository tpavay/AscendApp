import SwiftUI
import FirebaseCore

struct SignUpView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var hasAttemptedInteractiveSignIn = false
    @State private var isShowingInternalQA = false

    var body: some View {
        OnboardingScaffold(
            backAction: handleBack,
            background: {
                AuthStaircaseBackground()
            },
            content: { scaffoldLayout in
                AuthLandingContent(
                    layout: AuthLandingLayout(scaffoldLayout: scaffoldLayout),
                    errorMessage: hasAttemptedInteractiveSignIn ? authVM.errorMessage : nil,
                    lastUsedProvider: authVM.lastUsedProvider,
                    googleIsLoading: authVM.authenticationState == .authenticatingWithGoogle,
                    appleIsLoading: authVM.authenticationState == .authenticatingWithApple,
                    internalQAIsLoading: authVM.authenticationState == .authenticatingWithInternalQA,
                    showsInternalQA: InternalQASignInAvailability.isEnabled(projectID: FirebaseApp.app()?.options.projectID),
                    isDisabled: authVM.authenticationState.isAuthenticating,
                    onInternalQA: { isShowingInternalQA = true },
                    onGoogle: signInWithGoogle,
                    onApple: signInWithApple
                )
            }
        )
        .onAppear {
            hasAttemptedInteractiveSignIn = false
            authVM.errorMessage = nil
        }
        .trackOnboardingScreenView(OnboardingAnalyticsEvent.authContext)
        .navigationDestination(isPresented: $isShowingInternalQA) {
            InternalQASignInView()
        }
    }

    private func handleBack() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.backTapped(context: OnboardingAnalyticsEvent.authContext)
        )
        dismiss()
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

private struct AuthStaircaseBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / 390
            let scaleY = geometry.size.height / 844

            Image("AuthStaircaseBackground")
                .resizable()
                .scaledToFill()
                .frame(width: 568 * scaleX, height: 844 * scaleY)
                .clipped()
                .position(x: 194 * scaleX, y: 421 * scaleY)
        }
        .ignoresSafeArea()
    }
}

private struct AuthLandingLayout {
    private let scaffoldLayout: OnboardingScaffoldLayout

    init(scaffoldLayout: OnboardingScaffoldLayout) {
        self.scaffoldLayout = scaffoldLayout
    }

    var size: CGSize { scaffoldLayout.size }

    var isCompactHeight: Bool { size.height < 740 }

    var letterFontSize: CGFloat { isCompactHeight ? 27 : 30 }
    var letterSpacing: CGFloat { isCompactHeight ? 4.5 : 5 }
    var iconSize: CGFloat { isCompactHeight ? 40 : 44 }
    var iconTrailingSpacing: CGFloat { isCompactHeight ? 4 : 5 }

    var legalFontSize: CGFloat { isCompactHeight ? 10 : 11 }
    var legalLineSpacing: CGFloat { 2 }
}

private struct AuthLandingContent: View {
    let layout: AuthLandingLayout
    let errorMessage: String?
    let lastUsedProvider: AuthProviderKind?
    let googleIsLoading: Bool
    let appleIsLoading: Bool
    let internalQAIsLoading: Bool
    let showsInternalQA: Bool
    let isDisabled: Bool
    let onInternalQA: () -> Void
    let onGoogle: () -> Void
    let onApple: () -> Void

    var body: some View {
        let scaleX = layout.size.width / 390
        let scaleY = layout.size.height / 844
        let typeScale = min(scaleX, scaleY)

        ZStack(alignment: .topLeading) {
            AuthLandingBrand(layout: layout)
                .contentShape(Rectangle())
                .onTapGesture(count: 5) {
                    guard showsInternalQA else { return }
                    onInternalQA()
                }
                .position(x: layout.size.width / 2, y: 422 * scaleY)

            VStack(spacing: 15 * scaleY) {
                AuthProviderButton(
                    title: appleIsLoading ? "SIGNING IN..." : "CONTINUE WITH APPLE",
                    style: .apple,
                    isLoading: appleIsLoading,
                    isDisabled: isDisabled,
                    height: 56 * scaleY,
                    cornerRadius: 12 * typeScale,
                    fontSize: 16 * typeScale,
                    accessoryTitle: lastUsedProvider == .apple ? "LAST USED" : nil,
                    icon: {
                        Image(systemName: "apple.logo")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.black)
                            .frame(width: 21 * typeScale, height: 21 * typeScale)
                    },
                    action: onApple
                )

                AuthProviderButton(
                    title: googleIsLoading ? "SIGNING IN..." : "CONTINUE WITH GOOGLE",
                    style: .google,
                    isLoading: googleIsLoading,
                    isDisabled: isDisabled,
                    height: 56 * scaleY,
                    cornerRadius: 12 * typeScale,
                    fontSize: 16 * typeScale,
                    accessoryTitle: lastUsedProvider == .google ? "LAST USED" : nil,
                    icon: {
                        Image("GoogleIcon")
                            .resizable()
                            .renderingMode(.original)
                            .frame(width: 21 * typeScale, height: 21 * typeScale)
                    },
                    action: onGoogle
                )

                if showsInternalQA {
                    AuthProviderButton(
                        title: internalQAIsLoading ? "SIGNING IN..." : "INTERNAL QA SIGN IN",
                        style: .internalQA,
                        isLoading: internalQAIsLoading,
                        isDisabled: isDisabled,
                        height: 44 * scaleY,
                        cornerRadius: 10 * typeScale,
                        fontSize: 12.5 * typeScale,
                        accessoryTitle: lastUsedProvider == .internalQA ? "LAST USED" : nil,
                        icon: {
                            Image(systemName: "key.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(OnboardingValuePalette.lime)
                                .frame(width: 16 * typeScale, height: 16 * typeScale)
                        },
                        action: onInternalQA
                    )
                }

                AuthLegalText(layout: layout)
                    .frame(width: 334 * scaleX)
            }
            .frame(width: 334 * scaleX, alignment: .top)
            .offset(x: 28 * scaleX, y: 603 * scaleY)

            if let errorMessage {
                Text(errorMessage)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.red.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .frame(width: 334 * scaleX)
                    .offset(x: 28 * scaleX, y: 575 * scaleY)
                    .accessibilityLabel("Authentication error: \(errorMessage)")
            }
        }
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
    case internalQA

    var foregroundColor: Color {
        switch self {
        case .google:
            .white.opacity(0.92)
        case .apple:
            .black
        case .internalQA:
            OnboardingValuePalette.lime
        }
    }

    var loadingTint: Color {
        switch self {
        case .google:
            .white
        case .apple:
            .black
        case .internalQA:
            OnboardingValuePalette.lime
        }
    }

    var accessoryForegroundColor: Color {
        .black.opacity(0.88)
    }

    var accessoryBackgroundColor: Color {
        OnboardingValuePalette.lime
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
        case .internalQA:
            .black.opacity(0.48)
        }
    }

    private var borderColor: Color {
        switch self {
        case .google:
            .white.opacity(0.18)
        case .apple:
            .clear
        case .internalQA:
            OnboardingValuePalette.lime.opacity(0.55)
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

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: style.loadingTint))
                            .scaleEffect(0.92)
                    } else {
                        icon()
                    }

                    Text(title)
                        .font(.montserratBold(size: fontSize))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .foregroundStyle(style.foregroundColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(style.background(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let accessoryTitle, !isLoading {
                    Text(accessoryTitle.uppercased())
                        .font(.montserratBold(size: max(fontSize * 0.42, 6.5)))
                        .tracking(0.35)
                        .foregroundStyle(style.accessoryForegroundColor)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(style.accessoryBackgroundColor)
                        )
                        .overlay(
                            Capsule()
                                .stroke(.black.opacity(0.12), lineWidth: 0.5)
                        )
                        .offset(x: -10, y: -8)
                        .accessibilityHidden(true)
                }
            }
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
            .tint(Color.ascendAccent)
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
