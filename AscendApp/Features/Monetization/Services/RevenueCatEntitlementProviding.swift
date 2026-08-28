import Foundation

@MainActor
protocol RevenueCatEntitlementProviding: AnyObject {
    var customerInfoUpdates: AsyncStream<MonetizationEntitlementState> { get }

    func customerInfoState() async throws -> MonetizationEntitlementState
    func logInState(userID: String) async throws -> MonetizationEntitlementState
    func logOutState() async throws -> MonetizationEntitlementState
    /// Attaches the address to whichever customer RevenueCat is signed in as *right now*.
    ///
    /// Subscriber attributes are keyed by the app user id in flight at the moment they are set, so
    /// this is only ever correct immediately after a log-in has settled, inside the serialized
    /// identity mutation that performed it. Called anywhere else it stamps one climber's address
    /// onto another climber's customer record.
    ///
    /// Deliberately non-optional: the app never clears the attribute. Not knowing an address is not
    /// the same as knowing there is none, and a customer whose email is blanked on a launch that
    /// happened to read nothing is exactly the record the captain then cannot identify.
    func setCustomerEmail(_ email: String)
    func restorePurchasesState() async throws -> MonetizationEntitlementState
}
