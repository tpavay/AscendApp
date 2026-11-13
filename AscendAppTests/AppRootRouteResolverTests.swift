import Foundation
import Testing
@testable import AscendApp

struct AppRootRouteResolverTests {
    @Test
    func resolvesSignedOutWhenThereIsNoAuthenticatedUser() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: nil,
            postAuthOnboardingPhase: .complete,
            entitlementState: .active(["app_access"]),
            requiredEntitlementID: "app_access"
        )

        #expect(route == .signedOut)
    }

    /// An authenticated state with no account behind it is nobody signed in, and takes the same
    /// signed-out decision as any other: with the v3 onboarding on it never falls to the landing.
    @Test
    func anAuthenticatedStateWithNoUserTakesTheSignedOutDecision() {
        func route(showsV3: Bool?) -> AppRootRoute {
            AppRootRouteResolver.resolve(
                updatePresentation: nil,
                authenticationState: .authenticated,
                userId: nil,
                postAuthOnboardingPhase: .complete,
                entitlementState: .active(["app_access"]),
                requiredEntitlementID: "app_access",
                showsPreAuthOnboardingV3: showsV3
            )
        }

        #expect(route(showsV3: true) == .preAuthOnboarding)
        #expect(route(showsV3: nil) == .signedOutHold)
        #expect(route(showsV3: false) == .signedOut)
    }

    @Test
    func resolvesSigningInBeforeUserIsAvailable() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticatingWithApple,
            userId: nil,
            postAuthOnboardingPhase: .signedOut,
            entitlementState: .unknown,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .signingIn)
    }

    @Test
    func resolvesOnboardingBeforeCheckingAccess() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .onboarding(.stairStepperBaseline),
            entitlementState: .inactive,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .onboarding(.stairStepperBaseline))
    }

    @Test
    func resolvesPaywallWhenOnboardingIsCompleteWithoutAccess() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .complete,
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
            postAuthOnboardingPhase: .complete,
            entitlementState: .inactive,
            requiredEntitlementID: "app_access",
            allowsUnentitledAppAccess: true
        )

        #expect(route == .mainApp)
    }

    @Test
    func resolvesMainAppWhenOnboardingIsCompleteWithAccess() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .complete,
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
            postAuthOnboardingPhase: .complete,
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
            postAuthOnboardingPhase: .complete,
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
            postAuthOnboardingPhase: .complete,
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
                postAuthOnboardingPhase: .signedOut,
                entitlementState: .unknown,
                requiredEntitlementID: "app_access"
            )

            #expect(route == .updateRequired, "\(state) escaped the lockout")
        }
    }

    @Test("No onboarding phase can outrank the lockout", .bug(id: 429))
    func lockoutOutranksEveryOnboardingPhase() {
        let phases: [PostAuthOnboardingPhase] = [
            .signedOut,
            .resolving,
            .onboarding(.stairStepperBaseline),
            .complete
        ]

        for phase in phases {
            let route = AppRootRouteResolver.resolve(
                updatePresentation: .required,
                authenticationState: .authenticated,
                userId: "user-1",
                postAuthOnboardingPhase: phase,
                entitlementState: .inactive,
                requiredEntitlementID: "app_access"
            )

            #expect(route == .updateRequired, "\(phase) escaped the lockout")
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
                postAuthOnboardingPhase: .complete,
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
            postAuthOnboardingPhase: .complete,
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
        let cases: [(AuthenticationState, PostAuthOnboardingPhase, MonetizationEntitlementState, AppRootRoute)] = [
            (.unauthenticated, .signedOut, .unknown, .signedOut),
            (.restoringSession, .signedOut, .unknown, .restoringSession),
            (.authenticated, .onboarding(.stairStepperBaseline), .inactive, .onboarding(.stairStepperBaseline)),
            (.authenticated, .complete, .inactive, .paywall),
            (.authenticated, .complete, .active(["app_access"]), .mainApp)
        ]

        for (authenticationState, phase, entitlementState, expected) in cases {
            let route = AppRootRouteResolver.resolve(
                updatePresentation: .recommended,
                authenticationState: authenticationState,
                userId: "user-1",
                postAuthOnboardingPhase: phase,
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
        freeWeekAccess: FreeWeekRoutingAccess,
        postAuthOnboardingPhase: PostAuthOnboardingPhase = .complete
    ) -> AppRootRoute {
        AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: postAuthOnboardingPhase,
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
    func aFreeWeekNeverSkipsOnboardingOrTheUpdateLockout() {
        #expect(
            routeAtTheGate(
                entitlementState: .inactive,
                freeWeekAccess: .live,
                postAuthOnboardingPhase: .onboarding(.first)
            ) == .onboarding(.first)
        )
        #expect(
            routeAtTheGate(
                entitlementState: .inactive,
                freeWeekAccess: .live,
                postAuthOnboardingPhase: .resolving
            ) == .resolving
        )
    }
}
