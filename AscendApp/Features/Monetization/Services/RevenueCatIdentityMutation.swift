import Foundation

enum RevenueCatIdentityMutation: Equatable, Sendable {
    case identify(MonetizationCustomerIdentity)
    case reset
}
