import Foundation

struct RevenueCatPurchaseAnalyticsContext: Equatable, Sendable {
    let placement: RevenueCatPurchasePlacement
    let presentationID: String?
    let gateAttemptID: String?
    let recoveryPath: AppAccessGateRecoveryPath?
    let providerOutcome: String?
    let identityMatches: Bool?
    let entitlementActive: Bool?

    init(
        placement: String?,
        presentationID: String?,
        gateAttemptID: String? = nil,
        recoveryPath: AppAccessGateRecoveryPath? = nil,
        providerOutcome: String? = nil,
        identityMatches: Bool? = nil,
        entitlementActive: Bool? = nil
    ) {
        self.placement = RevenueCatPurchasePlacement(placement)
        self.presentationID = presentationID
        self.gateAttemptID = gateAttemptID
        self.recoveryPath = recoveryPath
        self.providerOutcome = providerOutcome
        self.identityMatches = identityMatches
        self.entitlementActive = entitlementActive
    }

    var parameters: [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "placement": .string(placement.analyticsValue)
        ]
        if let presentationID {
            parameters["presentation_id"] = .string(presentationID)
        }
        if let gateAttemptID {
            parameters["gate_attempt_id"] = .string(gateAttemptID)
        }
        if let recoveryPath {
            parameters["recovery_path"] = .string(recoveryPath.rawValue)
        }
        if let providerOutcome {
            parameters["provider_outcome"] = .string(providerOutcome)
        }
        if let identityMatches {
            parameters["identity_match"] = .bool(identityMatches)
        }
        if let entitlementActive {
            parameters["entitlement_active"] = .bool(entitlementActive)
        }
        return parameters
    }

    func terminal(
        providerOutcome: String,
        identityMatches: Bool,
        entitlementActive: Bool?
    ) -> Self {
        Self(
            placement: placement.analyticsValue,
            presentationID: presentationID,
            gateAttemptID: gateAttemptID,
            recoveryPath: recoveryPath,
            providerOutcome: gateAttemptID == nil ? nil : providerOutcome,
            identityMatches: gateAttemptID == nil ? nil : identityMatches,
            entitlementActive: gateAttemptID == nil ? nil : entitlementActive
        )
    }
}
