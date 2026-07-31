import Foundation

/// Records, per account, that a server read of that account's block list has
/// succeeded on this device at least once.
///
/// A cache read of the `blocked` collection cannot tell "this device has never
/// synced the list" from "this account has blocked nobody": an unsynced query
/// returns an empty snapshot rather than an error. Masking is fail-closed, so
/// that distinction has to be written down rather than inferred from a side
/// effect.
///
/// Separate from `ModerationStore` because it outlives a session: the marker
/// survives sign-out exactly as Firestore's own local cache does, so a
/// returning user launching offline still gets their blocks.
@MainActor
protocol BlockListServerSyncMarking {
    func hasSyncedFromServer(userId: String) -> Bool
    func recordServerSync(userId: String)
}

/// The production marker, stored in UserDefaults alongside the app's other
/// device-local account state. Account deletion drops it with the rest of the
/// app domain in `AppAccountDeletionLocalCleanup.clearUserDefaults`.
@MainActor
struct UserDefaultsBlockListServerSyncMarker: BlockListServerSyncMarking {
    private static let keyPrefix = "moderation.blockListServerSync."

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasSyncedFromServer(userId: String) -> Bool {
        guard let key = Self.key(for: userId) else {
            return false
        }
        return userDefaults.bool(forKey: key)
    }

    func recordServerSync(userId: String) {
        guard let key = Self.key(for: userId) else {
            return
        }
        userDefaults.set(true, forKey: key)
    }

    private static func key(for userId: String) -> String? {
        let normalized = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        return keyPrefix + normalized
    }
}
