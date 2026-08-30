import Foundation

enum PaywallPresentationOutcome: Equatable, Sendable {
    case presented
    case purchased
    case restored
    case pendingApproval
    case verificationUnavailable
    case dismissedWithoutPurchase
    /// The climber tapped the paywall's back control, which is a custom action rather than a close.
    case backRequested
    case skipped(reason: String)
    case failed(message: String)
}

extension PaywallPresentationOutcome {
    var isTerminal: Bool {
        switch self {
        case .presented:
            return false
        case .purchased, .restored, .pendingApproval, .verificationUnavailable,
             .dismissedWithoutPurchase, .backRequested, .skipped, .failed:
            return true
        }
    }
}
