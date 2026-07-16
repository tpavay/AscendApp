import Foundation

enum MonetizationEntitlementState: Equatable, Sendable {
    case unknown
    case inactive
    case active(Set<String>)

    func hasActiveEntitlement(_ entitlementID: String) -> Bool {
        guard case .active(let entitlementIDs) = self else {
            return false
        }

        return entitlementIDs.contains(entitlementID)
    }
}
