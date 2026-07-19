import Foundation

enum PaywallPresentationOutcome: Equatable, Sendable {
    case presented
    case purchased
    case restored
    case dismissedWithoutPurchase
    case skipped(reason: String)
    case failed(message: String)
}
