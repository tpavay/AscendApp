import Foundation

enum AppRootRoute: Equatable, Sendable {
    /// The hard update lockout. Sits above every other route because refusing a dead binary does
    /// not require knowing who is holding it.
    case updateRequired
    case signedOut
    case signingIn
    case restoringSession
    case resolving
    case onboarding(PostAuthOnboardingStage)
    case paywall
    case mainApp
}

/// Resolves the single screen the app root shows, from state that was already resolved elsewhere.
///
/// Deliberately synchronous and free of I/O. The Remote Config read behind
/// ``AppUpdatePresentation`` and the RevenueCat read behind ``MonetizationEntitlementState`` both
/// happen outside, so cold start and every foreground run the identical decision over whatever that
/// pass already knows. Anything that needs an `await` does not belong in here.
struct AppRootRouteResolver {
    /// - Parameter updatePresentation: The verdict ``AppVersionGateState`` resolved from the last
    ///   version floor this device received and this build's version, or `nil` when no floor applies.
    static func resolve(
        updatePresentation: AppUpdatePresentation?,
        authenticationState: AuthenticationState,
        userId: String?,
        postAuthOnboardingPhase: PostAuthOnboardingPhase,
        entitlementState: MonetizationEntitlementState,
        requiredEntitlementID: String,
        allowsUnentitledAppAccess: Bool = false
    ) -> AppRootRoute {
        // First, above authentication and above the entitlement gate. As a sheet this lost to the
        // paywall outright - Superwall presents outside `RootView`'s hierarchy, so an unentitled
        // climber who cold-started into it never saw the lockout, which is the population most
        // likely to be on a stale build (#429).
        if updatePresentation?.locksOutApp == true {
            return .updateRequired
        }

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
