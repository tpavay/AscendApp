import Foundation

struct MonetizationIdentityTransitionState: Equatable, Sendable {
    private(set) var entitlementState: MonetizationEntitlementState = .unknown
    private(set) var pendingTransition: MonetizationIdentityTransition?
    private var resolvedTransition: MonetizationIdentityTransition?
    private var revision: UInt = 0
    private var userID: String?

    mutating func prepare(userID: String?) -> MonetizationIdentityTransition {
        revision &+= 1
        self.userID = userID
        entitlementState = .unknown
        resolvedTransition = nil

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
        guard state != .unknown else {
            return true
        }

        pendingTransition = nil
        resolvedTransition = transition
        return true
    }

    func isPending(_ transition: MonetizationIdentityTransition) -> Bool {
        pendingTransition == transition
    }

    func refreshToken() -> MonetizationIdentityTransition? {
        guard pendingTransition == nil,
              resolvedTransition == snapshot() else {
            return nil
        }

        return resolvedTransition
    }

    private func snapshot() -> MonetizationIdentityTransition {
        MonetizationIdentityTransition(
            revision: revision,
            userID: userID
        )
    }

    @discardableResult
    mutating func applyRefresh(
        _ state: MonetizationEntitlementState,
        for token: MonetizationIdentityTransition
    ) -> Bool {
        guard pendingTransition == nil,
              resolvedTransition == token,
              token == snapshot() else {
            return false
        }

        entitlementState = state
        return true
    }
}
