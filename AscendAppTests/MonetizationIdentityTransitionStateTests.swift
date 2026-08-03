import Testing
@testable import AscendApp

struct MonetizationIdentityTransitionStateTests {
    @Test
    func preparingIdentitySynchronouslyInvalidatesPriorInactiveState() {
        var state = MonetizationIdentityTransitionState()
        let anonymousIdentity = state.prepare(userID: nil)
        state.resolve(.inactive, for: anonymousIdentity)

        _ = state.prepare(userID: "subscriber")

        #expect(state.entitlementState == .unknown)
    }

    @Test
    func staleIdentityCompletionCannotOverwriteCurrentEntitlement() {
        var state = MonetizationIdentityTransitionState()
        let firstIdentity = state.prepare(userID: "first-user")
        let reset = state.prepare(userID: nil)
        let currentIdentity = state.prepare(userID: "current-user")

        let acceptedCurrentIdentity = state.resolve(
            .active(["app_access"]),
            for: currentIdentity
        )
        let acceptedFirstIdentity = state.resolve(.inactive, for: firstIdentity)
        let acceptedReset = state.resolve(.inactive, for: reset)

        #expect(acceptedCurrentIdentity)
        #expect(acceptedFirstIdentity == false)
        #expect(acceptedReset == false)
        #expect(state.entitlementState == .active(["app_access"]))
    }

    @Test
    func refreshStartedBeforeIdentityChangeCannotPublishInactiveState() throws {
        var state = MonetizationIdentityTransitionState()
        let anonymousIdentity = state.prepare(userID: nil)
        state.resolve(.inactive, for: anonymousIdentity)
        let anonymousRefreshToken = try #require(state.refreshToken())

        _ = state.prepare(userID: "subscriber")
        let acceptedRefresh = state.applyRefresh(
            .inactive,
            for: anonymousRefreshToken
        )

        #expect(acceptedRefresh == false)
        #expect(state.entitlementState == .unknown)
    }

    @Test
    func unresolvedIdentityCannotIssueARefreshToken() {
        var state = MonetizationIdentityTransitionState()
        let identity = state.prepare(userID: "subscriber")

        #expect(state.refreshToken() == nil)

        state.resolve(.unknown, for: identity)

        #expect(state.pendingTransition == identity)
        #expect(state.refreshToken() == nil)
        #expect(state.entitlementState == .unknown)
    }

    @Test
    func anUnansweredIdentityIsFlaggedForRecoveryWhileAnInactiveOneIsNot() {
        var state = MonetizationIdentityTransitionState()

        let failing = state.prepare(userID: "subscriber")
        state.resolve(.unknown, for: failing)

        #expect(state.entitlementState == .unknown)
        #expect(state.hasFailedIdentityResolution)

        let retried = state.prepare(userID: "subscriber")

        #expect(state.hasFailedIdentityResolution == false)

        state.resolve(.inactive, for: retried)

        #expect(state.entitlementState == .inactive)
        #expect(state.hasFailedIdentityResolution == false)
    }

    /// Routing may never read "not yet known" as a denial. Only a confirmed `.inactive` may reach
    /// the paywall, so a future change that collapses the two states fails here.
    @Test(arguments: [
        (MonetizationEntitlementState.unknown, AppRootRoute.resolving),
        (.inactive, .paywall),
        (.active(["app_access"]), .mainApp)
    ])
    func routingSeparatesUnknownAccessFromDeniedAccess(
        entitlementState: MonetizationEntitlementState,
        expectedRoute: AppRootRoute
    ) {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "subscriber",
            postAuthOnboardingPhase: .complete,
            entitlementState: entitlementState,
            requiredEntitlementID: "app_access"
        )

        #expect(route == expectedRoute)
        #expect(entitlementState != .unknown || route != .paywall)
    }
}
