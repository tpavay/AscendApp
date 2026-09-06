import Foundation

enum HostedPurchaseRecovery: String, Equatable, Sendable {
    case pendingApproval = "pending_approval"
    case verificationUnavailable = "verification_unavailable"
}

@MainActor
protocol HostedPurchaseRecoveryRouting: AnyObject {
    func recoverHostedPurchase(
        _ recovery: HostedPurchaseRecovery,
        context: RevenueCatPurchaseAnalyticsContext,
        identity: MonetizationIdentityTransition
    ) async -> Bool
}
