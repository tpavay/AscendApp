import Foundation

@MainActor
protocol MonetizationIdentityManaging: AnyObject {
    func prepareIdentity(userId: String) -> MonetizationIdentityTransition
    func identify(userId: String, transition: MonetizationIdentityTransition) async
    func prepareIdentityReset() -> MonetizationIdentityTransition
    func resetIdentity(transition: MonetizationIdentityTransition) async
}
