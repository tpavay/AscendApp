import Foundation

enum AppRootRoute: Equatable, Sendable {
    /// The hard update lockout. Sits above every other route because refusing a dead binary does
    /// not require knowing who is holding it.
    case updateRequired
    case signedOut
    /// Signed out on a launch that has not yet decided between ``signedOut`` and
    /// ``preAuthOnboarding``: a device the backend has never answered about the switch, for at most
    /// ``OnboardingV3RouteLatch/holdLimit``.
    case signedOutHold
    /// Signed out with `onboarding_v3_enabled` on: the selling and setup screens, then sign-in.
    /// Replaces ``signedOut``'s landing screen while the switch is on.
    case preAuthOnboarding
    case signingIn
    case restoringSession
    case resolving
    case onboarding(PostAuthOnboardingStage)
    /// Signed in at the end of the v3 flow and holding no access: the onboarding's own paywall and
    /// welcome gift. Replaces ``paywall`` for that one session only; a relaunch meets ``paywall``.
    case onboardingPaywall
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
    /// - Parameters:
    ///   - updatePresentation: The verdict ``AppVersionGateState`` resolved from the last
    ///     version floor this device received and this build's version, or `nil` when no floor applies.
    ///   - showsPreAuthOnboardingV3: Whether a signed-out climber gets the v3 onboarding: the
    ///     switch is on and the flow has not reached its end. `nil` while this launch has not
    ///     decided (``OnboardingV3RouteLatch``). Resolved outside, like every other input, so the
    ///     decision stays synchronous and pure.
    ///   - showsOnboardingPaywallV3: Whether a signed-in climber without access gets the onboarding's
    ///     paywall instead of the app-access gate: they signed in at the end of the v3 flow in this
    ///     session and `onboarding_paywall_enabled` is on. Entitlement still decides whether anyone
    ///     sees it, so a climber who already pays never does.
    static func resolve(
        updatePresentation: AppUpdatePresentation?,
        authenticationState: AuthenticationState,
        userId: String?,
        postAuthOnboardingPhase: PostAuthOnboardingPhase,
        entitlementState: MonetizationEntitlementState,
        requiredEntitlementID: String,
        allowsUnentitledAppAccess: Bool = false,
        showsPreAuthOnboardingV3: Bool? = false,
        showsOnboardingPaywallV3: Bool = false
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
            guard let showsPreAuthOnboardingV3 else {
                return .signedOutHold
            }

            return showsPreAuthOnboardingV3 ? .preAuthOnboarding : .signedOut
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
                allowsUnentitledAppAccess: allowsUnentitledAppAccess,
                showsOnboardingPaywallV3: showsOnboardingPaywallV3
            )
        }
    }

    private static func resolveAuthenticatedRoute(
        postAuthOnboardingPhase: PostAuthOnboardingPhase,
        entitlementState: MonetizationEntitlementState,
        requiredEntitlementID: String,
        allowsUnentitledAppAccess: Bool,
        showsOnboardingPaywallV3: Bool
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

            if entitlementState == .unknown { return .resolving }

            return showsOnboardingPaywallV3 ? .onboardingPaywall : .paywall
        }
    }
}
