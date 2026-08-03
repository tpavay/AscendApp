import Foundation
import RevenueCat
import Testing
@testable import AscendApp

/// The only thing standing between a signed-out cold start and a logout that re-runs on every
/// `RootView.task` and every foreground is this error-shape match. If a RevenueCat upgrade changes
/// how `Purchases.logOut()` surfaces its already-anonymous refusal, these assertions must fail.
struct RevenueCatPurchasesProviderTests {
    @Test
    func alreadyAnonymousRefusalResolvesAsInactive() {
        #expect(
            RevenueCatPurchasesProvider.resolvedState(
                forLogOutError: ErrorCode.logOutAnonymousUserError
            ) == .inactive
        )
        #expect(
            RevenueCatPurchasesProvider.resolvedState(
                forLogOutError: NSError(
                    domain: ErrorCode.errorDomain,
                    code: ErrorCode.logOutAnonymousUserError.rawValue
                )
            ) == .inactive
        )
    }

    @Test
    func theRefusalIsMatchedOnDomainAndCodeTogether() {
        #expect(
            RevenueCatPurchasesProvider.resolvedState(
                forLogOutError: NSError(
                    domain: ErrorCode.errorDomain,
                    code: ErrorCode.networkError.rawValue
                )
            ) == nil
        )
        #expect(
            RevenueCatPurchasesProvider.resolvedState(
                forLogOutError: NSError(
                    domain: "com.ascendapp.not-revenuecat",
                    code: ErrorCode.logOutAnonymousUserError.rawValue
                )
            ) == nil
        )
    }

    @Test
    func genuineLogOutFailuresStayUnanswered() {
        #expect(
            RevenueCatPurchasesProvider.resolvedState(
                forLogOutError: ErrorCode.networkError
            ) == nil
        )
        #expect(
            RevenueCatPurchasesProvider.resolvedState(
                forLogOutError: UnrelatedLogOutError.failed
            ) == nil
        )
    }
}

private enum UnrelatedLogOutError: Error {
    case failed
}
