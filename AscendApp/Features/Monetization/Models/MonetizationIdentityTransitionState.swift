import Foundation

struct MonetizationIdentityTransitionState: Equatable, Sendable {
    private(set) var entitlementState: MonetizationEntitlementState = .unknown
    private(set) var pendingTransition: MonetizationIdentityTransition?
    private var revision: UInt = 0
    private var userID: String?

    mutating func prepare(userID: String?) -> MonetizationIdentityTransition {
        revision &+= 1
        self.userID = userID
        entitlementState = .unknown

        let transition = MonetizationIdentityTransition(
            revision: revision,
            userID: userID
        )
        pendingTransition = transition
        return transition
    }

    @discardableResult
    mutating func resolve(
        _ state: MonetizationEntitlementState,
        for transition: MonetizationIdentityTransition
    ) -> Bool {
        guard pendingTransition == transition else {
            return false
        }

        entitlementState = state
        pendingTransition = nil
        return true
    }

    func snapshot() -> MonetizationIdentityTransition {
        MonetizationIdentityTransition(
            revision: revision,
            userID: userID
        )
    }

    @discardableResult
    mutating func applyRefresh(
        _ state: MonetizationEntitlementState,
        for snapshot: MonetizationIdentityTransition
    ) -> Bool {
        guard pendingTransition == nil, snapshot == self.snapshot() else {
            return false
        }

        entitlementState = state
        return true
    }
}
