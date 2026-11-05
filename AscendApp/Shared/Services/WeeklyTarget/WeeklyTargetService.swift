import Foundation

/// Where a weekly target is read and changed: Settings, onboarding's hand-off after sign-in, and
/// Home's ring.
///
/// The device's copy answers instantly and is the one Home reads. The account's copy
/// (`users/{uid}.weekly_target_days`) carries it to a new phone, and its write sits behind the
/// `weekly_target_writes_enabled` switch: off, the change stays on the device, marked unsynced,
/// and goes up when the switch returns. Nothing here is a leaderboard input - the target is
/// private to its owner.
@MainActor
struct WeeklyTargetService {
    private let store: WeeklyTargetStore
    private let isWriteEnabled: @MainActor () -> Bool
    private let readRemote: @MainActor (String) async throws -> WeeklyTarget?
    private let writeRemote: @MainActor (String, WeeklyTarget?) async throws -> Void

    init(
        store: WeeklyTargetStore = WeeklyTargetStore(),
        isWriteEnabled: @escaping @MainActor () -> Bool = { RemoteFeatureFlagStore.shared.isEnabled(.weeklyTargetWrites) },
        readRemote: @escaping @MainActor (String) async throws -> WeeklyTarget? = { userId in
            try await UserDataRepository.shared.getUserFromFirestore(userId: userId).weeklyTarget
        },
        writeRemote: @escaping @MainActor (String, WeeklyTarget?) async throws -> Void = { userId, target in
            try await UserDataRepository.shared.updateWeeklyTarget(userId: userId, target: target)
        }
    ) {
        self.store = store
        self.isWriteEnabled = isWriteEnabled
        self.readRemote = readRemote
        self.writeRemote = writeRemote
    }

    /// The target on this device, with no network. Nil when the climber has none.
    func localTarget(for userId: String) -> WeeklyTarget? {
        store.target(for: userId)
    }

    /// Sets, changes or clears the target. The device keeps it whatever the network does.
    @discardableResult
    func save(_ target: WeeklyTarget?, for userId: String) async -> Bool {
        store.save(target, for: userId)
        return await pushIfNeeded(for: userId)
    }

    /// Brings the device and the account together: an unsynced change goes up, otherwise the
    /// account's answer is adopted. Returns the target to show.
    @discardableResult
    func reconcile(for userId: String) async -> WeeklyTarget? {
        if store.hasUnsyncedChange(for: userId) {
            _ = await pushIfNeeded(for: userId)
        } else {
            // A read that failed is not an account with no target, so only an answer is adopted.
            do {
                store.adopt(try await readRemote(userId), for: userId)
            } catch {
                // The device's copy stands until the next reconcile.
            }
        }
        return store.target(for: userId)
    }

    private func pushIfNeeded(for userId: String) async -> Bool {
        guard isWriteEnabled() else { return false }

        do {
            try await writeRemote(userId, store.target(for: userId))
            store.markSynced(for: userId)
            return true
        } catch {
            return false
        }
    }
}
