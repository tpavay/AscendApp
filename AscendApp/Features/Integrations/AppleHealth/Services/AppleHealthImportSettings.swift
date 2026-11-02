import Foundation

/// The four small facts Apple Health import keeps between launches.
///
/// Keyed by the signed-in climber's uid, because each one is a statement about that climber's
/// ledger: an anchor from another account's store would skip workouts this account has never met,
/// and an auto-import choice is theirs to make. A different climber on the same device finds
/// nothing and starts from the defaults. Account deletion empties the whole defaults domain.
///
/// UserDefaults, not a row, because every one of these is a single scalar read on a hot path (the
/// badge, the observer) and none of them is a record anyone enters or earns.
struct AppleHealthImportSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On by default: connecting to Health in onboarding never shows the choice screen, so this is
    /// the setting a climber who was never asked lives with until they change it.
    func isAutoImportEnabled(for userID: String) -> Bool {
        defaults.object(forKey: key("autoImport", userID)) as? Bool ?? true
    }

    func setAutoImportEnabled(_ isEnabled: Bool, for userID: String) {
        defaults.set(isEnabled, forKey: key("autoImport", userID))
    }

    /// When Imports was last opened. The badge counts only workouts that started after it.
    func importsLastViewedAt(for userID: String) -> Date? {
        defaults.object(forKey: key("importsLastViewedAt", userID)) as? Date
    }

    func setImportsLastViewedAt(_ date: Date, for userID: String) {
        defaults.set(date, forKey: key("importsLastViewedAt", userID))
    }

    /// The HealthKit query anchor the next read resumes from. Nil means this climber has never had
    /// a read complete, which is how the first pass tells a backfill from a new workout.
    func anchorData(for userID: String) -> Data? {
        defaults.data(forKey: key("anchor", userID))
    }

    func setAnchorData(_ data: Data?, for userID: String) {
        defaults.set(data, forKey: key("anchor", userID))
    }

    private func key(_ name: String, _ userID: String) -> String {
        "appleHealthImport.\(name).\(userID)"
    }
}
