import Foundation

enum AppAccessRestoreSource: String, Sendable {
    case appAccessGate = "app_access_gate"
    case hostedPaywall = "hosted_paywall"
    case accountSettings = "account_settings"
}

struct AppAccessRestoreAnalyticsContext: Equatable, Sendable {
    let restoreAttemptID: String
    let gateAttemptID: String?
    let placement: RevenueCatPurchasePlacement
    let presentationID: String?
    let source: AppAccessRestoreSource
    let recoveryPath: AppAccessGateRecoveryPath
    /// Internal delivery owner. Never included in `parameters`.
    let identity: MonetizationIdentityTransition?

    static func appAccessGate(
        gateAttemptID: String?,
        identity: MonetizationIdentityTransition? = nil
    ) -> Self {
        Self(
            restoreAttemptID: makeAttemptID(),
            gateAttemptID: boundedIdentifier(gateAttemptID),
            placement: RevenueCatPurchasePlacement(SuperwallPlacement.appAccessGate.rawValue),
            presentationID: nil,
            source: .appAccessGate,
            recoveryPath: .restore,
            identity: identity
        )
    }

    static func hostedPaywall(
        placement: String?,
        presentationID: String?,
        gateAttemptID: String?,
        identity: MonetizationIdentityTransition? = nil
    ) -> Self {
        Self(
            restoreAttemptID: makeAttemptID(),
            gateAttemptID: boundedIdentifier(gateAttemptID),
            placement: RevenueCatPurchasePlacement(placement),
            presentationID: boundedIdentifier(presentationID),
            source: .hostedPaywall,
            recoveryPath: .hosted,
            identity: identity
        )
    }

    static func accountSettings() -> Self {
        Self(
            restoreAttemptID: makeAttemptID(),
            gateAttemptID: nil,
            placement: RevenueCatPurchasePlacement(nil),
            presentationID: nil,
            source: .accountSettings,
            recoveryPath: .account,
            identity: nil
        )
    }

    var parameters: [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "restore_attempt_id": .string(restoreAttemptID),
            "placement": .string(placement.analyticsValue),
            "restore_source": .string(source.rawValue),
            "recovery_path": .string(recoveryPath.rawValue)
        ]
        if let gateAttemptID {
            parameters["gate_attempt_id"] = .string(gateAttemptID)
        }
        if let presentationID {
            parameters["presentation_id"] = .string(presentationID)
        }
        return parameters
    }

    private static func makeAttemptID() -> String {
        "restore_\(UUID().uuidString.lowercased())"
    }

    private static func boundedIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let filteredScalars = value.unicodeScalars.filter { allowed.contains($0) }
        let bounded = String(String.UnicodeScalarView(filteredScalars).prefix(64))
        return bounded.isEmpty ? nil : bounded
    }
}
