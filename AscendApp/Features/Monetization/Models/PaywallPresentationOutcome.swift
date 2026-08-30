import Foundation

enum PaywallPresentationOutcome: Equatable, Sendable {
    case presented
    case purchased
    case restored
    case pendingApproval
    case verificationUnavailable
    case dismissedWithoutPurchase
    case skipped(reason: String)
    case failed(message: String)
}

extension PaywallPresentationOutcome {
    var isTerminal: Bool {
        switch self {
        case .presented:
            return false
        case .purchased, .restored, .pendingApproval, .verificationUnavailable,
             .dismissedWithoutPurchase, .skipped, .failed:
            return true
        }
    }
}
