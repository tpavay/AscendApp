import Foundation

/// Where a climber left their account from. A closed set of screens, so a funnel can ask how many
/// climbers leave at the access gate without parsing a free string.
enum AccountExitSurface: String, Sendable {
    /// The hosted app-access paywall's own Sign out and Delete account controls.
    case appAccessGate = "app_access_gate"
    /// The spinner the gate draws while access resolves, which carries a Sign out control.
    case appAccessResolving = "app_access_resolving"
    /// The hard update lockout, which offers deletion only.
    case updateRequired = "update_required"
    case accountDataConflict = "account_data_conflict"
    case settings
    /// A signed-in climber partway through the legacy post-auth onboarding.
    case onboarding
}

/// An account left for good, reported when the action completes. The tap that asked for it is
/// already visible (`app_access_gate_attempt_terminal` with `sign_out_requested` or
/// `delete_account_requested`); these two are the other half, so a request that never lands or is
/// cancelled reads as the gap between them.
enum AccountExitAnalyticsEvent: TelemetryEvent {
    case signedOut(surface: AccountExitSurface)
    case deleted(surface: AccountExitSurface)

    var record: TelemetryRecord {
        switch self {
        case .signedOut(let surface):
            TelemetryRecord(name: "account_signed_out", parameters: ["surface": .string(surface.rawValue)])
        case .deleted(let surface):
            TelemetryRecord(name: "account_deleted", parameters: ["surface": .string(surface.rawValue)])
        }
    }
}
