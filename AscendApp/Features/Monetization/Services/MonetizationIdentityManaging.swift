import Foundation

@MainActor
protocol MonetizationIdentityManaging: AnyObject {
    func prepareIdentity(_ customer: MonetizationCustomerIdentity) -> MonetizationIdentityTransition
    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async
    func prepareIdentityReset() -> MonetizationIdentityTransition
    func resetIdentity(transition: MonetizationIdentityTransition) async
}
