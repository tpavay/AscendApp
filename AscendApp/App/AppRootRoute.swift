import Foundation

enum AppRootRoute: Equatable, Sendable {
    /// The hard update lockout. Sits above every other route because refusing a dead binary does
    /// not require knowing who is holding it.
    case updateRequired
    /// Signed out: the selling and setup screens, then sign-in. The only thing a signed-out climber
    /// can reach, on a fresh install and after every sign-out alike - there is no switch, no
    /// fallback flow and no landing screen behind it.
    case preAuthOnboarding
    case signingIn
    case restoringSession
    case resolving
    case paywall
    case mainApp
}

/// Resolves the single screen the app root shows, from state that was already resolved elsewhere.
///
/// Deliberately synchronous and free of I/O. The Remote Config read behind
/// ``AppUpdatePresentation`` and the RevenueCat read behind ``MonetizationEntitlementState`` both
/// happen outside, so cold start and every foreground run the identical decision over whatever that
/// pass already knows. Anything that needs an `await` does not belong in here.
///
/// A signed-in climber is never sent through questions: the onboarding ends at sign-in, so the next
/// thing an account meets is its entitlement.
struct AppRootRouteResolver {
    /// - Parameters:
    ///   - updatePresentation: The verdict ``AppVersionGateState`` resolved from the last
    ///     version floor this device received and this build's version, or `nil` when no floor applies.
    ///   - freeWeekAccess: Whether this account is on its server-granted free week
    ///     (``FreeWeekAccessStore``). A running week enters exactly as a paid entitlement does; a
    ///     record that has not been read yet holds on ``AppRootRoute/resolving`` for the same reason
    ///     an unknown entitlement does, because a paywall shown to a climber mid-week is a refusal
    ///     they were promised they would not get.
    static func resolve(
        updatePresentation: AppUpdatePresentation?,
        authenticationState: AuthenticationState,
        userId: String?,
        entitlementState: MonetizationEntitlementState,
        requiredEntitlementID: String,
        allowsUnentitledAppAccess: Bool = false,
        freeWeekAccess: FreeWeekRoutingAccess = .none
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
            return .preAuthOnboarding
        case .authenticatingWithApple,
             .authenticatingWithGoogle,
             .authenticatingWithInternalQA:
            return .signingIn
        case .restoringSession:
            return .restoringSession
        case .authenticated:
            // No account behind an authenticated state is still nobody signed in.
            guard userId != nil else {
                return .preAuthOnboarding
            }

            if allowsUnentitledAppAccess
                || entitlementState.hasActiveEntitlement(requiredEntitlementID)
                || freeWeekAccess == .live {
                return .mainApp
            }

            if entitlementState == .unknown || freeWeekAccess == .unresolved { return .resolving }

            return .paywall
        }
    }
}
