import Foundation

/// The climber's weekly target on this device, kept per account so a second account on a shared
/// phone never inherits the first one's ring.
///
/// Account deletion clears the whole UserDefaults domain, which clears this with it.
struct WeeklyTargetStore: @unchecked Sendable {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func target(for userId: String) -> WeeklyTarget? {
        let days = userDefaults.integer(forKey: Self.daysKey(userId))
        return WeeklyTarget(days: days)
    }

    /// Stores the target, or removes it when the climber cleared it. A change is also marked as
    /// not yet in the cloud until ``markSynced(for:)`` says it landed.
    func save(_ target: WeeklyTarget?, for userId: String) {
        if let target {
            userDefaults.set(target.days, forKey: Self.daysKey(userId))
        } else {
            userDefaults.removeObject(forKey: Self.daysKey(userId))
        }
        userDefaults.set(true, forKey: Self.pendingKey(userId))
        userDefaults.set(revision(for: userId) + 1, forKey: Self.revisionKey(userId))
    }

    /// Counts the changes made on this device, so a write can tell whether the change it carried
    /// is still the newest one when it is acknowledged.
    func revision(for userId: String) -> Int {
        userDefaults.integer(forKey: Self.revisionKey(userId))
    }

    /// Whether the last change on this device has not reached the account yet, so the device's
    /// answer wins over the cloud's.
    func hasUnsyncedChange(for userId: String) -> Bool {
        userDefaults.bool(forKey: Self.pendingKey(userId))
    }

    func markSynced(for userId: String) {
        userDefaults.removeObject(forKey: Self.pendingKey(userId))
    }

    /// Marks the change synced only if nothing newer was saved since `revision`, so the
    /// acknowledgement of an older write can never clear the flag of a newer change.
    func markSynced(for userId: String, ifRevision revision: Int) {
        guard self.revision(for: userId) == revision else { return }
        markSynced(for: userId)
    }

    /// Takes the account's answer as this device's, when the device has nothing newer to say.
    func adopt(_ target: WeeklyTarget?, for userId: String) {
        guard !hasUnsyncedChange(for: userId) else { return }
        if let target {
            userDefaults.set(target.days, forKey: Self.daysKey(userId))
        } else {
            userDefaults.removeObject(forKey: Self.daysKey(userId))
        }
    }

    private static func daysKey(_ userId: String) -> String { "weeklyTarget.days.\(userId)" }
    private static func revisionKey(_ userId: String) -> String { "weeklyTarget.revision.\(userId)" }
    private static func pendingKey(_ userId: String) -> String { "weeklyTarget.unsynced.\(userId)" }
}
