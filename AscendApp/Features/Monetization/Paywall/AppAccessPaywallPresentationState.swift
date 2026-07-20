import Foundation

enum AppAccessPaywallPresentationState: Equatable, Sendable {
    case ready
    case presenting
    case readyToRetry
    case failed

    var primaryButtonTitle: String {
        switch self {
        case .ready:
            return "View Plans"
        case .presenting:
            return "Opening Paywall..."
        case .readyToRetry, .failed:
            return "Try Again"
        }
    }

    var isPrimaryButtonEnabled: Bool {
        self != .presenting
    }

    var statusMessage: String? {
        switch self {
        case .ready:
            return nil
        case .presenting:
            return "Loading subscription options..."
        case .readyToRetry:
            return "Access is still locked. Open the paywall to keep climbing."
        case .failed:
            return "Paywall failed to load. Check your connection and try again."
        }
    }

    mutating func beginPresentation() {
        self = .presenting
    }

    mutating func handle(_ outcome: PaywallPresentationOutcome) {
        switch outcome {
        case .presented:
            self = .presenting
        case .purchased, .restored:
            self = .ready
        case .dismissedWithoutPurchase, .skipped:
            self = .readyToRetry
        case .failed:
            self = .failed
        }
    }
}
