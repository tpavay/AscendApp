import Foundation

/// Reads and writes the account-scoped email consent shown in settings.
///
/// The decision lives on the server rather than on the device because the
/// unsubscribe link in an email can change it from outside the app, and because
/// a consent record is only worth anything where it can be produced on demand.
protocol EmailPreferencesProviding: Sendable {
    /// The stored decision, which may be that no decision exists.
    func loadConsent() async throws -> LifecycleEmailConsent

    /// Records a decision the climber just made, with where they made it.
    func recordConsent(
        isGranted: Bool,
        source: LifecycleEmailConsentSource
    ) async throws
}
