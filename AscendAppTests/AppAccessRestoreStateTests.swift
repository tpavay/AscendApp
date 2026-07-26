import Testing
@testable import AscendApp

struct AppAccessRestoreStateTests {
    @Test
    func offersRestoreOnlyWhileRevenueCatIsConfigured() {
        #expect(AppAccessRestoreState.idle.isButtonEnabled(isRevenueCatConfigured: true))
        #expect(AppAccessRestoreState.failed.isButtonEnabled(isRevenueCatConfigured: true))
        #expect(AppAccessRestoreState.restored.isButtonEnabled(isRevenueCatConfigured: true))
        #expect(!AppAccessRestoreState.restoring.isButtonEnabled(isRevenueCatConfigured: true))
    }

    @Test
    func neverOffersRestoreWhenRevenueCatIsUnconfigured() {
        let unconfigurableStates: [AppAccessRestoreState] = [.idle, .restoring, .restored, .failed]

        for state in unconfigurableStates {
            #expect(!state.isButtonEnabled(isRevenueCatConfigured: false))
            #expect(state.buttonTitle(isRevenueCatConfigured: false) == "Restore Unavailable")
        }
    }

    @Test
    func namesEveryRestoreOutcomeWhileConfigured() {
        #expect(AppAccessRestoreState.idle.buttonTitle(isRevenueCatConfigured: true) == "Restore Purchases")
        #expect(AppAccessRestoreState.restoring.buttonTitle(isRevenueCatConfigured: true) == "Restoring...")
        #expect(AppAccessRestoreState.restored.buttonTitle(isRevenueCatConfigured: true) == "Restored")
        #expect(AppAccessRestoreState.failed.buttonTitle(isRevenueCatConfigured: true) == "Restore Failed")
    }
}
