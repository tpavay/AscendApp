import Foundation
import Testing
@testable import AscendApp

struct AppRootRouteResolverTests {
    @Test
    func resolvesTheOnboardingWhenThereIsNoAuthenticatedUser() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: nil,
            entitlementState: .active(["app_access"]),
            requiredEntitlementID: "app_access"
        )

        #expect(route == .preAuthOnboarding)
    }

    /// Nobody signed in gets the onboarding, however the question is asked. There is no switch and
    /// no other signed-out screen, so a fresh install and a climber who just signed out are
    /// indistinguishable here.
    @Test
    func aSignedOutClimberAlwaysGetsTheOnboarding() {
        let signedOut = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .unauthenticated,
            userId: nil,
            entitlementState: .unknown,
            requiredEntitlementID: "app_access"
        )
        let noAccountBehindAuthenticated = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: nil,
            entitlementState: .active(["app_access"]),
            requiredEntitlementID: "app_access"
        )

        #expect(signedOut == .preAuthOnboarding)
        #expect(noAccountBehindAuthenticated == .preAuthOnboarding)
    }

    @Test
    func resolvesSigningInBeforeUserIsAvailable() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticatingWithApple,
            userId: nil,
            entitlementState: .unknown,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .signingIn)
    }

    @Test
    func resolvesPaywallWithoutAccess() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .inactive,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .paywall)
    }

    @Test
    func resolvesMainAppWhenUnentitledAccessIsAllowed() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .inactive,
            requiredEntitlementID: "app_access",
            allowsUnentitledAppAccess: true
        )

        #expect(route == .mainApp)
    }

    @Test
    func resolvesMainAppWithAccess() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .active(["app_access"]),
            requiredEntitlementID: "app_access"
        )

        #expect(route == .mainApp)
    }

    @Test
    func resolvesWhileAccessStateIsUnknown() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .unknown,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .resolving)
    }

    @Test
    func resolvesMainAppWhenUnentitledAccessIsAllowedBeforeAccessStateLoads() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .unknown,
            requiredEntitlementID: "app_access",
            allowsUnentitledAppAccess: true
        )

        #expect(route == .mainApp)
    }
}

/// The lockout is resolved first, above authentication and above the entitlement gate.
///
/// It used to be a `.sheet` on `RootView`, which Superwall presents outside of - so the climber who
/// cold-started straight into the paywall, the one most likely to be on a stale build, could never
/// see it. As a route there is nothing left to occlude.
@Suite("The hard update lockout outranks every other root route")
struct AppRootRouteLockoutPrecedenceTests {
    /// The actual defect: unentitled *and* below the floor. The paywall used to win this.
    @Test("An unentitled climber below the floor is locked out, not sent to the paywall", .bug(id: 429))
    func lockoutOutranksThePaywallForAnUnentitledClimber() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: .required,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .inactive,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .updateRequired)
    }

    @Test("No authentication state can outrank the lockout", .bug(id: 429))
    func lockoutOutranksEveryAuthenticationState() {
        let states: [AuthenticationState] = [
            .unauthenticated,
            .authenticatingWithApple,
            .authenticatingWithGoogle,
            .authenticatingWithInternalQA,
            .restoringSession,
            .authenticated
        ]

        for state in states {
            let route = AppRootRouteResolver.resolve(
                updatePresentation: .required,
                authenticationState: state,
                userId: nil,
                entitlementState: .unknown,
                requiredEntitlementID: "app_access"
            )

            #expect(route == .updateRequired, "\(state) escaped the lockout")
        }
    }

    @Test("No entitlement state can outrank the lockout", .bug(id: 429))
    func lockoutOutranksEveryEntitlementState() {
        let entitlementStates: [MonetizationEntitlementState] = [
            .unknown,
            .inactive,
            .active(["app_access"])
        ]

        for entitlementState in entitlementStates {
            let route = AppRootRouteResolver.resolve(
                updatePresentation: .required,
                authenticationState: .authenticated,
                userId: "user-1",
                entitlementState: entitlementState,
                requiredEntitlementID: "app_access"
            )

            #expect(route == .updateRequired, "\(entitlementState) escaped the lockout")
        }
    }

    /// A build configuration that hands out unentitled access still cannot hand out a dead binary.
    @Test("Allowing unentitled access does not release the lockout", .bug(id: 429))
    func lockoutSurvivesUnentitledAppAccess() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: .required,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .active(["app_access"]),
            requiredEntitlementID: "app_access",
            allowsUnentitledAppAccess: true
        )

        #expect(route == .updateRequired)
    }

    /// The soft nudge is a sheet over whatever the climber is already doing, so it must not move
    /// anybody off their route - that is the whole difference between the two verdicts.
    @Test("The recommended nudge changes no route", .bug(id: 429))
    func recommendedUpdateLeavesEveryRouteAlone() {
        let cases: [(AuthenticationState, MonetizationEntitlementState, AppRootRoute)] = [
            (.unauthenticated, .unknown, .preAuthOnboarding),
            (.restoringSession, .unknown, .restoringSession),
            (.authenticated, .inactive, .paywall),
            (.authenticated, .active(["app_access"]), .mainApp)
        ]

        for (authenticationState, entitlementState, expected) in cases {
            let route = AppRootRouteResolver.resolve(
                updatePresentation: .recommended,
                authenticationState: authenticationState,
                userId: "user-1",
                entitlementState: entitlementState,
                requiredEntitlementID: "app_access"
            )

            #expect(route == expected)
        }
    }
}

/// The server-granted free week at the root route (`docs/free-week-after-decline.md`).
struct AppRootRouteFreeWeekTests {
    private func routeAtTheGate(
        entitlementState: MonetizationEntitlementState,
        freeWeekAccess: FreeWeekRoutingAccess
    ) -> AppRootRoute {
        AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: entitlementState,
            requiredEntitlementID: "app_access",
            freeWeekAccess: freeWeekAccess
        )
    }

    @Test
    func aRunningFreeWeekEntersTheAppExactlyAsAPaidEntitlementDoes() {
        #expect(routeAtTheGate(entitlementState: .inactive, freeWeekAccess: .live) == .mainApp)
        // The remembered week opens the app before RevenueCat has answered at all.
        #expect(routeAtTheGate(entitlementState: .unknown, freeWeekAccess: .live) == .mainApp)
        #expect(routeAtTheGate(entitlementState: .active(["app_access"]), freeWeekAccess: .live) == .mainApp)
    }

    @Test
    func aLapsedOrAbsentFreeWeekMeetsThePaywall() {
        // A week that is over and a week that never was both resolve to `.none`.
        #expect(routeAtTheGate(entitlementState: .inactive, freeWeekAccess: .none) == .paywall)
        #expect(routeAtTheGate(entitlementState: .unknown, freeWeekAccess: .none) == .resolving)
        #expect(routeAtTheGate(entitlementState: .active(["app_access"]), freeWeekAccess: .none) == .mainApp)
    }

    @Test
    func anUnreadFreeWeekRecordHoldsRatherThanShowingAPaywallToAClimberMidWeek() {
        #expect(routeAtTheGate(entitlementState: .inactive, freeWeekAccess: .unresolved) == .resolving)
        #expect(routeAtTheGate(entitlementState: .unknown, freeWeekAccess: .unresolved) == .resolving)
        // A paying climber never waits on it.
        #expect(
            routeAtTheGate(entitlementState: .active(["app_access"]), freeWeekAccess: .unresolved) == .mainApp
        )
    }

    @Test
    func aFreeWeekNeverSkipsTheUpdateLockout() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: .required,
            authenticationState: .authenticated,
            userId: "user-1",
            entitlementState: .inactive,
            requiredEntitlementID: "app_access",
            freeWeekAccess: .live
        )

        #expect(route == .updateRequired)
    }
}
