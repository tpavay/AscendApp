import Testing
@testable import AscendApp

struct AppAccessRestoreStateTests {
    @Test
    func offersRestoreOnlyWhileRevenueCatIsConfigured() {
        #expect(AppAccessRestoreState.idle.isButtonEnabled(isRevenueCatConfigured: true))
        #expect(AppAccessRestoreState.failed.isButtonEnabled(isRevenueCatConfigured: true))
        #expect(AppAccessRestoreState.noPurchasesFound.isButtonEnabled(isRevenueCatConfigured: true))
        #expect(AppAccessRestoreState.restored.isButtonEnabled(isRevenueCatConfigured: true))
        #expect(!AppAccessRestoreState.restoring.isButtonEnabled(isRevenueCatConfigured: true))
    }

    @Test
    func neverOffersRestoreWhenRevenueCatIsUnconfigured() {
        let unconfigurableStates: [AppAccessRestoreState] = [
            .idle, .restoring, .restored, .noPurchasesFound, .failed
        ]

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
        #expect(AppAccessRestoreState.noPurchasesFound.buttonTitle(isRevenueCatConfigured: true) == "Nothing to Restore")
        #expect(AppAccessRestoreState.failed.buttonTitle(isRevenueCatConfigured: true) == "Restore Failed")
    }

    /// A restore that resolved nothing says so; one that resolved nothing *conclusively* is the
    /// only case allowed to claim there is nothing to restore.
    @Test
    func explainsOnlyTheOutcomesThatNeedAnExplanation() {
        #expect(AppAccessRestoreState.idle.statusMessage == nil)
        #expect(AppAccessRestoreState.restoring.statusMessage == nil)
        #expect(AppAccessRestoreState.restored.statusMessage == nil)
        #expect(AppAccessRestoreState.noPurchasesFound.statusMessage == "No purchases found to restore.")
        #expect(
            AppAccessRestoreState.failed.statusMessage
                == "Ascend couldn't restore your purchases. Check your connection and try again."
        )
    }

    @Test
    func mapsEveryRestoreOutcomeToItsOwnState() {
        #expect(AppAccessRestoreState(outcome: .restored(entitlementIDs: ["app_access"])) == .restored)
        #expect(AppAccessRestoreState(outcome: .notFound) == .noPurchasesFound)
        #expect(AppAccessRestoreState(outcome: .failed(StubGateRestoreError.offline)) == .failed)
    }
}

private enum StubGateRestoreError: Error {
    case offline
}
