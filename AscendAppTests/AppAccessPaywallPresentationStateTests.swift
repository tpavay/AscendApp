import Testing
@testable import AscendApp

struct AppAccessPaywallPresentationStateTests {
    @Test
    func beginsInAVisibleActionableState() {
        let state = AppAccessPaywallPresentationState.ready

        #expect(state.primaryButtonTitle == "View Plans")
        #expect(state.showsRecoveryActions)
        #expect(state.statusMessage == nil)
    }

    @Test
    func hidesControlsWhilePaywallIsOpening() {
        var state = AppAccessPaywallPresentationState.ready

        state.beginPresentation()

        #expect(state == .presenting)
        #expect(state.showsRecoveryActions == false)
        #expect(state.statusMessage == nil)
    }

    @Test
    func coveredGateKeepsTheLoadingSurfaceButStopsAnimatingIt() {
        var state = AppAccessPaywallPresentationState.presenting

        state.handle(.presented)

        #expect(state == .presented)
        #expect(state.showsRecoveryActions == false)
        #expect(state.pausesLoadingAnimation)
        #expect(state.statusMessage == nil)
    }

    @Test
    func openingGateAnimatesTheLoadingSurface() {
        var state = AppAccessPaywallPresentationState.ready

        state.beginPresentation()

        #expect(state.pausesLoadingAnimation == false)
    }

    @Test(arguments: [
        PaywallPresentationOutcome.dismissedWithoutPurchase,
        PaywallPresentationOutcome.skipped(reason: "no audience match")
    ])
    func declinedOrSkippedPaywallReturnsToRetry(outcome: PaywallPresentationOutcome) {
        var state = AppAccessPaywallPresentationState.presenting

        state.handle(outcome)

        #expect(state == .readyToRetry)
        #expect(state.primaryButtonTitle == "Try Again")
        #expect(state.showsRecoveryActions)
    }

    @Test
    func presentationFailureReturnsToRetryWithGuidance() {
        var state = AppAccessPaywallPresentationState.presenting

        state.handle(.failed(message: "network unavailable"))

        #expect(state == .failed)
        #expect(state.primaryButtonTitle == "Try Again")
        #expect(state.showsRecoveryActions)
        #expect(state.statusMessage == "Paywall failed to load. Check your connection and try again.")
    }

    @Test(arguments: [
        PaywallPresentationOutcome.purchased,
        PaywallPresentationOutcome.restored
    ])
    func successfulAccessOutcomeDoesNotLeaveGateStuck(outcome: PaywallPresentationOutcome) {
        var state = AppAccessPaywallPresentationState.presenting

        state.handle(outcome)

        #expect(state == .ready)
        #expect(state.showsRecoveryActions)
    }
}
