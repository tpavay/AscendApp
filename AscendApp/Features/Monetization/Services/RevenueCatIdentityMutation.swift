import Foundation

enum RevenueCatIdentityMutation: Equatable, Sendable {
    case identify(userID: String)
    case reset
}
