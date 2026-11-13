import Foundation

enum AppAccessGateRecoveryPath: String, Sendable {
    case hosted
    case entitlementStream = "entitlement_stream"
    case account
    case freeWeek = "free_week"
}

enum AppAccessGateProviderOutcome: String, Sendable {
    case purchased
    case restored
    /// The access paywall did not reach the screen, and the gate is about to ask for it again.
    case hostedUnavailable = "hosted_unavailable"
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
    /// Every paid offer was declined and there is no free week to give - the rollout is off, the
    /// account's week is spent, or the server could not be asked - so the hosted paywall reopens.
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
    /// The onboarding pass the gate was reached from, so the terminal reads as that flow's outcome.
    let flowVersion: String?

    init(
        attemptCorrelationID: String,
        placement: String,
        recoveryPath: AppAccessGateRecoveryPath,
        providerOutcome: AppAccessGateProviderOutcome,
        recoveryReason: AppAccessGateRecoveryReason?,
        identityMatches: Bool,
        entitlementActive: Bool?,
        flowVersion: String? = nil
    ) {
        self.attemptCorrelationID = attemptCorrelationID
        self.placement = placement
        self.recoveryPath = recoveryPath
        self.providerOutcome = providerOutcome
        self.recoveryReason = recoveryReason
        self.identityMatches = identityMatches
        self.entitlementActive = entitlementActive
        self.flowVersion = flowVersion
    }

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
        if let flowVersion {
            parameters["flow_version"] = .string(flowVersion)
        }
        return parameters
    }
}
