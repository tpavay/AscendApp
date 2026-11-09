import Foundation

/// The small facts Apple Health import keeps between launches.
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

    /// Whether the Connect flow has looked at Health and the climber has not yet picked how workouts
    /// import. Durable because the app can end on that screen, and a relaunch reading the default
    /// of auto-import on would make the choice for them.
    func isImportChoicePending(for userID: String) -> Bool {
        defaults.bool(forKey: key("importChoicePending", userID))
    }

    func setImportChoicePending(_ isPending: Bool, for userID: String) {
        defaults.set(isPending, forKey: key("importChoicePending", userID))
    }

    /// When Imports was last opened. The badge counts only workouts Ascend found after it.
    func importsLastViewedAt(for userID: String) -> Date? {
        defaults.object(forKey: key("importsLastViewedAt", userID)) as? Date
    }

    func setImportsLastViewedAt(_ date: Date, for userID: String) {
        defaults.set(date, forKey: key("importsLastViewedAt", userID))
    }

    /// Which read the stored anchor belongs to: the activity types of
    /// `HealthKitWorkoutReader.stairActivityTypes`.
    ///
    /// An anchor is a mark in Health's database, and it says "nothing new before here" only about
    /// the workouts the read that produced it asked for. When the read grew from two stair types to
    /// three, an anchor kept from the narrower read would have hidden every `stepTraining` workout
    /// already behind it for good. An anchor stored under another scope is therefore not this
    /// read's anchor: the next pass starts from the join date like a first pass, silently, and the
    /// ledger stops anything it already knows from importing twice.
    static let anchorScope = "stair3"

    /// The HealthKit query anchor the next read resumes from. Nil means this climber has never had
    /// a read of this scope complete, which is how the first pass tells a backfill from a new
    /// workout.
    func anchorData(for userID: String) -> Data? {
        defaults.data(forKey: anchorKey(userID))
    }

    func setAnchorData(_ data: Data?, for userID: String) {
        defaults.set(data, forKey: anchorKey(userID))
        // The two-type read's anchor, which nothing reads any more.
        defaults.removeObject(forKey: key("anchor", userID))
    }

    private func anchorKey(_ userID: String) -> String {
        key("anchor.\(Self.anchorScope)", userID)
    }

    private func key(_ name: String, _ userID: String) -> String {
        "appleHealthImport.\(name).\(userID)"
    }
}
