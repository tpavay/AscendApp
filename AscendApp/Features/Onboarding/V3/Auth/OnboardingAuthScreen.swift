import FirebaseCore
import SwiftUI

/// Sign in: the last step of the flow, before the paywall, so every purchase is made by an account.
/// Also where "Already have an account? Sign in" lands.
///
/// Apple and Google are the only two ways in, and nothing on this screen takes typed input: the
/// list under the headline is a record of what the flow collected and what saves the moment the
/// climber signs in, never a field. The name comes from the sign-in itself (`SuppliedNameAdoption`).
struct OnboardingAuthScreen: View {
    let coordinator: OnboardingV3Coordinator

    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var mode: OnboardingAuthMode
    @State private var isShowingInternalQA = false
    @State private var contentRunsUnderActions = false
    /// Read once: the answers cannot change while this screen is up.
    private let savedItems: [OnboardingSavedItem]

    init(coordinator: OnboardingV3Coordinator) {
        self.coordinator = coordinator
        _mode = State(initialValue: OnboardingAuthMode(arrivedFrom: coordinator.previousStep))
        savedItems = OnboardingSavedItems.make(from: coordinator.answers)
    }

    private var isDisabled: Bool { authVM.authenticationState.isAuthenticating }

    /// How far the pinned actions fade the content scrolling under them, and the gap the content
    /// keeps above them so a list that fits is never under the fade.
    private static let fadeHeight: CGFloat = 20

    /// Whether the content is taller than the room the pinned actions leave it, read from a scroll
    /// view whose bottom content inset is those actions.
    nonisolated static func contentRunsUnderActions(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            > geometry.containerSize.height
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                copy
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Nothing scrolls under the clock: a zero-height inset whose background reaches into the
        // status bar's band, so the band stays the screen's own black.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(OnboardingV3Palette.background)
        }
        // The sign-in buttons are the screen's one job, so they stay on screen at the smallest
        // phone and at the largest text size while the list above them scrolls.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .background(OnboardingV3Palette.background)
                // On a phone too short for the whole list, the rows run under the buttons: the
                // fade is the cue that they scroll.
                .overlay(alignment: .top) {
                    if mode == .saveEveryClimb, contentRunsUnderActions {
                        LinearGradient(
                            colors: [OnboardingV3Palette.background.opacity(0), OnboardingV3Palette.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: Self.fadeHeight)
                        .offset(y: -Self.fadeHeight)
                        .allowsHitTesting(false)
                    }
                }
        }
        .onScrollGeometryChange(for: Bool.self, of: Self.contentRunsUnderActions) { _, runsUnder in
            contentRunsUnderActions = runsUnder
        }
        .onAppear {
            // A mark left by an attempt that never finished must not close the flow for a later
            // sign-in that did not come through the full flow.
            OnboardingV3HandOffIntent().clear()
        }
        .fullScreenCover(isPresented: $isShowingInternalQA, onDismiss: internalQADismissed) {
            NavigationStack { InternalQASignInView() }
        }
        .trackOnce(screen: .onboardingAuth)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var topBar: some View {
        if coordinator.canGoBack {
            OnboardingAuthBackButton {
                coordinator.back()
            }
            .padding(.top, 9)
            .padding(.leading, 20)
        }

        AscendWordmark(height: 22, treatment: .onDark)
            .padding(.top, coordinator.canGoBack ? 14 : 13)
            .padding(.leading, 24)
            .contentShape(Rectangle())
            // Five taps open the QA sign-in on dev and staging builds only, the same hatch the
            // landing screen carries.
            .onTapGesture(count: 5) {
                guard InternalQASignInAvailability.isEnabled(projectID: FirebaseApp.app()?.options.projectID) else {
                    return
                }
                if mode == .saveEveryClimb { OnboardingV3HandOffIntent().set() }
                isShowingInternalQA = true
            }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch mode {
            case .saveEveryClimb:
                Text("Last step")
                    .onboardingKicker()
                    .padding(.bottom, 10)
                    .onboardingEntrance(index: 0)

                OnboardingHeadline(["Save every"], accentLines: ["climb."])
                    .padding(.bottom, 12)
                    .onboardingEntrance(index: 1)

                Text("Everything you do in Ascend saves to your account and follows you to any phone. Without one, none of it is kept.")
                    .onboardingSecondary()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                    .onboardingEntrance(index: 2)

                OnboardingSavedItemsCard(items: savedItems)
                    .onboardingEntrance(index: 3)

            case .returning:
                OnboardingHeadline(["Welcome back", "Sign in to"], accentLines: ["Keep climbing."])
                    .onboardingEntrance(index: 0)

                Text("Your records, streak and gear are waiting.")
                    .onboardingBody()
                    .padding(.top, 18)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingEntrance(index: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, Self.fadeHeight)
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
                // The pinned buttons may not grow until the list has no room; the legal line stays
                // readable at the largest sizes the rest of the screen offers it.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onboardingEntrance(index: 4)
    }

    // MARK: - Sign in

    /// Runs a provider's sign-in, leaving the mark that lets the root close the flow when the
    /// account appears.
    ///
    /// The flow is finished only after the account exists: finishing first would send a climber
    /// whose sign-in failed to the old landing screen instead of back here. The root swaps this
    /// screen for its signing-in route the moment the attempt starts, so the work is an unstructured
    /// task that holds the auth model itself rather than anything the view owns.
    private func signIn(_ attempt: @escaping @MainActor () async -> Void) {
        authVM.errorMessage = nil
        let authVM = authVM
        let intent = OnboardingV3HandOffIntent()
        if mode == .saveEveryClimb { intent.set() }

        Task { @MainActor in
            await attempt()
            if authVM.authenticationState != .authenticated {
                intent.clear()
            }
        }
    }

    /// A QA sign-in closed without an account leaves no mark behind. One still running keeps it,
    /// and if that one fails this screen returns and clears it on appearing.
    private func internalQADismissed() {
        guard !isDisabled, authVM.authenticationState != .authenticated else { return }
        OnboardingV3HandOffIntent().clear()
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
