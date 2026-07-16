import Foundation

enum AppRootRoute: Equatable, Sendable {
    case signedOut
    case signingIn
    case restoringSession
    case resolving
    case onboarding(PostAuthOnboardingStage)
    case paywall
    case mainApp
}

struct AppRootRouteResolver {
    static func resolve(
        authenticationState: AuthenticationState,
        userId: String?,
        postAuthOnboardingPhase: PostAuthOnboardingPhase,
        entitlementState: MonetizationEntitlementState,
        requiredEntitlementID: String,
        allowsUnentitledAppAccess: Bool = false
    ) -> AppRootRoute {
        switch authenticationState {
        case .unauthenticated:
            return .signedOut
        case .authenticatingWithApple,
             .authenticatingWithGoogle,
             .authenticatingWithInternalQA:
            return .signingIn
        case .restoringSession:
            return .restoringSession
        case .authenticated:
            guard userId != nil else {
                return .signedOut
            }

            return resolveAuthenticatedRoute(
                postAuthOnboardingPhase: postAuthOnboardingPhase,
                entitlementState: entitlementState,
                requiredEntitlementID: requiredEntitlementID,
                allowsUnentitledAppAccess: allowsUnentitledAppAccess
            )
        }
    }

    private static func resolveAuthenticatedRoute(
        postAuthOnboardingPhase: PostAuthOnboardingPhase,
        entitlementState: MonetizationEntitlementState,
        requiredEntitlementID: String,
        allowsUnentitledAppAccess: Bool
    ) -> AppRootRoute {
        switch postAuthOnboardingPhase {
        case .signedOut, .resolving:
            return .resolving
        case .onboarding(let stage):
            return .onboarding(stage)
        case .complete:
            if allowsUnentitledAppAccess || entitlementState.hasActiveEntitlement(requiredEntitlementID) {
                return .mainApp
            }

            return entitlementState == .unknown ? .resolving : .paywall
        }
    }
}
