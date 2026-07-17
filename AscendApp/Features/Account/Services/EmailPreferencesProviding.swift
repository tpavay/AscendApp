import Foundation

/// Reads and writes the account-scoped email preferences shown in settings.
///
/// The preference lives on the server rather than on the device because the
/// unsubscribe link in an email can change it from outside the app.
protocol EmailPreferencesProviding: Sendable {
    func loadLifecycleEmailsEnabled() async throws -> Bool
    func setLifecycleEmailsEnabled(_ isEnabled: Bool) async throws
}
