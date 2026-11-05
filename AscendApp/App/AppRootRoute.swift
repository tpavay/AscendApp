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
    /// Signed out with `onboarding_v3_enabled` on: the pre-sign-in flow, selling screens through the
    /// paywall and then sign-in. Replaces ``signedOut``'s landing screen while the switch is on.
    case preAuthOnboarding
    /// Signed out with the pre-sign-in onboarding on, setup finished and nothing bought: a relaunch
    /// opens on the paywall instead of replaying the screens before it. Draws the same flow view as
    /// ``preAuthOnboarding`` - the coordinator already starts on the paywall - so the two never
    /// rebuild it when the climber buys and the route flips.
    case preAuthPaywall
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
    /// - Parameters:
    ///   - updatePresentation: The verdict ``AppVersionGateState`` resolved from the last
    ///     version floor this device received and this build's version, or `nil` when no floor applies.
    ///   - showsPreAuthOnboardingV3: Whether a signed-out climber gets the v3 onboarding: the
    ///     switch is on and the flow has not reached its end. `nil` while this launch has not
    ///     decided (``OnboardingV3RouteLatch``). Resolved outside, like every other input, so the
    ///     decision stays synchronous and pure.
    ///   - resumesAtPreAuthPaywall: Whether this device already got as far as the paywall and the
    ///     `preauth_paywall_enabled` switch is on. Resolved outside, like every other input.
    static func resolve(
        updatePresentation: AppUpdatePresentation?,
        authenticationState: AuthenticationState,
        userId: String?,
        postAuthOnboardingPhase: PostAuthOnboardingPhase,
        entitlementState: MonetizationEntitlementState,
        requiredEntitlementID: String,
        allowsUnentitledAppAccess: Bool = false,
        showsPreAuthOnboardingV3: Bool? = false,
        resumesAtPreAuthPaywall: Bool = false
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

            guard showsPreAuthOnboardingV3 else {
                return .signedOut
            }

            // A purchase made as the anonymous customer is access the climber already holds, so
            // only an install with nothing bought resumes on the paywall. An answer still in flight
            // counts as nothing bought: the paywall steps aside by itself once it reads access.
            if resumesAtPreAuthPaywall,
               !entitlementState.hasActiveEntitlement(requiredEntitlementID) {
                return .preAuthPaywall
            }

            return .preAuthOnboarding
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
