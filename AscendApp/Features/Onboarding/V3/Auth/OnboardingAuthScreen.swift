import FirebaseCore
import SwiftUI

/// Screen 15: sign in. The last step of the flow, after the purchase, and also where "Already
/// climbing? Sign in" lands.
///
/// Apple and Google are the only two ways in, and nothing on this screen takes typed input: the
/// climber's row on the board is a picture of where they will stand, never a field. The name comes
/// from the sign-in itself (`SuppliedNameAdoption`).
struct OnboardingAuthScreen: View {
    let coordinator: OnboardingV3Coordinator

    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var mode: OnboardingAuthMode
    @State private var isShowingInternalQA = false

    init(coordinator: OnboardingV3Coordinator) {
        self.coordinator = coordinator
        _mode = State(initialValue: OnboardingAuthMode(arrivedFrom: coordinator.previousStep))
    }

    private var isDisabled: Bool { authVM.authenticationState.isAuthenticating }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                copy
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // The sign-in buttons are the screen's one job, so they stay on screen at the smallest
        // phone and at the largest text size while the board above them scrolls.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .background(OnboardingV3Palette.background)
        }
        .onAppear {
            // A mark left by an attempt that never finished must not close the flow for a later
            // sign-in that did not come through the full flow.
            OnboardingV3HandOffIntent().clear()
        }
        .fullScreenCover(isPresented: $isShowingInternalQA) {
            NavigationStack { InternalQASignInView() }
        }
        .trackOnce(screen: .onboardingAuth)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var topBar: some View {
        if mode == .returning {
            OnboardingAuthBackButton {
                OnboardingAuthReturningRequest().clear()
                coordinator.back()
            }
                .padding(.top, 9)
                .padding(.leading, 20)
        }

        AscendWordmark(height: 22, treatment: .onDark)
            .padding(.top, mode == .returning ? 14 : 13)
            .padding(.leading, 24)
            .contentShape(Rectangle())
            // Five taps open the QA sign-in on dev and staging builds only, the same hatch the
            // landing screen carries.
            .onTapGesture(count: 5) {
                guard InternalQASignInAvailability.isEnabled(projectID: FirebaseApp.app()?.options.projectID) else {
                    return
                }
                isShowingInternalQA = true
            }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch mode {
            case .claimSpot:
                Text("Last step")
                    .onboardingKicker()
                    .onboardingEntrance(index: 0)

                OnboardingHeadline(["Claim your", "spot on the", "board."], size: 31)
                    .onboardingEntrance(index: 1)

                OnboardingAuthBoardCard()
                    .onboardingEntrance(index: 2)

                Text("Your records, streak and gear stay with you on any device.")
                    .onboardingSecondary()
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingEntrance(index: 3)

            case .returning:
                OnboardingHeadline(["Welcome back", "Sign in to"], accentLines: ["Keep climbing."])
                    .onboardingEntrance(index: 0)

                Text("Your records, streak and gear are waiting.")
                    .onboardingBody()
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingEntrance(index: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let message = authVM.errorMessage {
                Text(message)
                    .font(.custom("Montserrat-Medium", size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.red.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityLabel("Sign in error: \(message)")
            }

            OnboardingAuthProviderButton(
                title: "Continue with Apple",
                style: .apple,
                isDisabled: isDisabled
            ) {
                signIn { await authVM.signInWithApple() }
            }

            OnboardingAuthProviderButton(
                title: "Continue with Google",
                style: .google,
                isDisabled: isDisabled
            ) {
                signIn { await authVM.signInWithGoogle() }
            }

            Text(.init("By continuing, you agree to our [Terms](https://ascendstepper.com/terms) and [Privacy Policy](https://ascendstepper.com/privacy)."))
                .font(.custom("Montserrat-Medium", size: 11, relativeTo: .caption2))
                .foregroundStyle(Color.white.opacity(0.55))
                .tint(OnboardingV3Palette.accent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // The pinned buttons may not grow until the board has no room; the legal line stays
                // readable at the largest sizes the rest of the screen offers it.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onboardingEntrance(index: 4)
    }

    // MARK: - Sign in

    /// Runs a provider's sign-in and, when it lands, closes the flow.
    ///
    /// The flow is finished only after the account exists: finishing first would send a climber
    /// whose sign-in failed to the old landing screen instead of back here. The root swaps this
    /// screen for its signing-in route the moment the attempt starts, so the work is an unstructured
    /// task that holds the coordinator and the auth model itself rather than anything the view owns.
    private func signIn(_ attempt: @escaping @MainActor () async -> Void) {
        authVM.errorMessage = nil
        let coordinator = coordinator
        let authVM = authVM
        let completesFlow = mode == .claimSpot
        let intent = OnboardingV3HandOffIntent()
        if completesFlow { intent.set() }

        Task { @MainActor in
            await attempt()
            guard authVM.authenticationState == .authenticated else {
                intent.clear()
                return
            }
            OnboardingAuthReturningRequest().clear()
            if completesFlow { coordinator.finish() }
        }
    }
}

// MARK: - Controls

private struct OnboardingAuthBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(OnboardingV3Palette.controlFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

private struct OnboardingAuthProviderButton: View {
    enum Style { case apple, google }

    let title: String
    let style: Style
    let isDisabled: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(style == .apple ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(style == .apple ? Color.white : OnboardingV3Palette.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style == .apple ? Color.clear : OnboardingV3Palette.cardBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var icon: some View {
        switch style {
        case .apple:
            Image(systemName: "apple.logo")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
        case .google:
            Image("GoogleIcon")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
        }
    }
}
