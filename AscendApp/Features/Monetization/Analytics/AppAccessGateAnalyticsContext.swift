import Foundation

enum AppAccessGateRecoveryPath: String, Sendable {
    case hosted
    case native
    case entitlementStream = "entitlement_stream"
    case restore
    case account
}

enum AppAccessGateProviderOutcome: String, Sendable {
    case purchased
    case restored
    case nativeReady = "native_ready"
    case nativeUnavailable = "native_unavailable"
    case entitlementActive = "entitlement_active"
    case cancelled
    case backRequested = "back_requested"
    case staleIdentity = "stale_identity"
    case pendingApproval = "pending_approval"
    case verificationUnavailable = "verification_unavailable"
}

enum AppAccessGateRecoveryReason: String, Sendable {
    case watchdogTimeout = "watchdog_timeout"
    case hostedDismissed = "hosted_dismissed"
    case hostedBackRequested = "hosted_back_requested"
    case hostedSkipped = "hosted_skipped"
    case hostedError = "hosted_error"
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
