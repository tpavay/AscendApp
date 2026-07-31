import Foundation

struct MonetizationIdentityTransition: Equatable, Hashable, Sendable {
    let revision: UInt
    let userID: String?
}
