import Foundation

@MainActor
protocol RevenueCatEntitlementProviding: AnyObject {
    var customerInfoUpdates: AsyncStream<Void> { get }

    func customerInfoState() async throws -> MonetizationEntitlementState
    func logInState(userID: String) async throws -> MonetizationEntitlementState
    func logOutState() async throws -> MonetizationEntitlementState
    func restorePurchasesState() async throws -> MonetizationEntitlementState
}
