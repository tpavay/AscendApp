import Foundation

enum AppAccessGateRecoveryPath: String, Sendable {
    case hosted
    case native
    case entitlementStream = "entitlement_stream"
    case restore
    case account
    case freeWeek = "free_week"
}

enum AppAccessGateProviderOutcome: String, Sendable {
    case purchased
    case restored
    case nativeReady = "native_ready"
    case nativeUnavailable = "native_unavailable"
    case entitlementActive = "entitlement_active"
    case cancelled
    case backRequested = "back_requested"
    case deleteAccountRequested = "delete_account_requested"
    case signOutRequested = "sign_out_requested"
    case staleIdentity = "stale_identity"
    case pendingApproval = "pending_approval"
    case verificationUnavailable = "verification_unavailable"
    /// Every paid offer was declined and the account has never had its free week.
    case freeWeekOffered = "free_week_offered"
    /// Every paid offer was declined by an account whose free week is spent, so the hosted
    /// paywall reopens.
    case paywallFloor = "paywall_floor"
}

enum AppAccessGateRecoveryReason: String, Sendable {
    case watchdogTimeout = "watchdog_timeout"
    case hostedDismissed = "hosted_dismissed"
    case hostedBackRequested = "hosted_back_requested"
    case hostedDeleteAccountRequested = "hosted_delete_account_requested"
    case hostedSignOutRequested = "hosted_sign_out_requested"
    case hostedSkipped = "hosted_skipped"
    case hostedError = "hosted_error"
    /// The free week could not be started, or the account's record could not be read.
    case freeWeekUnavailable = "free_week_unavailable"
}

struct AppAccessGateAnalyticsContext: Sendable {
    let attemptCorrelationID: String
    let placement: String
    let recoveryPath: AppAccessGateRecoveryPath
    let providerOutcome: AppAccessGateProviderOutcome
    let recoveryReason: AppAccessGateRecoveryReason?
    let identityMatches: Bool
    let entitlementActive: Bool?

    var parameters: [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "gate_attempt_id": .string(attemptCorrelationID),
            "placement": .string(placement),
            "recovery_path": .string(recoveryPath.rawValue),
            "provider_outcome": .string(providerOutcome.rawValue),
            "identity_match": .bool(identityMatches)
        ]
        if let recoveryReason {
            parameters["recovery_reason"] = .string(recoveryReason.rawValue)
        }
        if let entitlementActive {
            parameters["entitlement_active"] = .bool(entitlementActive)
        }
        return parameters
    }
}
