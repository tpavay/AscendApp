import Testing
@testable import AscendApp

struct MonetizationIdentityTransitionStateTests {
    @Test
    func preparingIdentitySynchronouslyInvalidatesPriorInactiveState() {
        var state = MonetizationIdentityTransitionState()
        let initialSnapshot = state.snapshot()
        state.applyRefresh(.inactive, for: initialSnapshot)

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
    func refreshStartedBeforeIdentityChangeCannotPublishInactiveState() {
        var state = MonetizationIdentityTransitionState()
        let anonymousSnapshot = state.snapshot()

        _ = state.prepare(userID: "subscriber")
        let acceptedRefresh = state.applyRefresh(
            .inactive,
            for: anonymousSnapshot
        )

        #expect(acceptedRefresh == false)
        #expect(state.entitlementState == .unknown)
    }
}
