import SwiftUI

struct AppRootContentView<MainContent: View>: View {
    let route: AppRootRoute
    let onOnboardingBack: () -> Void
    let onOnboardingContinue: () -> Void
    private let mainContent: () -> MainContent

    init(
        route: AppRootRoute,
        onOnboardingBack: @escaping () -> Void,
        onOnboardingContinue: @escaping () -> Void,
        @ViewBuilder mainContent: @escaping () -> MainContent
    ) {
        self.route = route
        self.onOnboardingBack = onOnboardingBack
        self.onOnboardingContinue = onOnboardingContinue
        self.mainContent = mainContent
    }

    var body: some View {
        switch route {
        case .signedOut:
            LandingScreen()
        case .signingIn:
            AscendLoadingView(
                title: "Signing in",
                message: "Connecting your account."
            )
        case .restoringSession:
            AscendLoadingView(
                title: "Restoring your climb field",
                message: "Loading your account."
            )
        case .resolving:
            AscendLoadingView()
        case .onboarding(let stage):
            PostAuthOnboardingFlowView(
                stage: stage,
                onBack: onOnboardingBack,
                onContinue: onOnboardingContinue
            )
        case .paywall:
            AppAccessPaywallPlaceholderView()
        case .mainApp:
            mainContent()
        }
    }
}
