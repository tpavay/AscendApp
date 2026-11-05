import Foundation

/// Runs one account's weekly target reads and writes one at a time, in the order they were asked
/// for, because `WeeklyTargetService` values are made per use and a write is a read then a set: two
/// quick changes running side by side could land oldest last, and leave the account on a value the
/// device has already replaced.
@MainActor
final class WeeklyTargetSyncQueue {
    static let shared = WeeklyTargetSyncQueue()

    private var tails: [String: Task<Bool, Never>] = [:]

    @discardableResult
    func run(for userId: String, _ operation: @escaping @MainActor () async -> Bool) async -> Bool {
        let previous = tails[userId]
        let turn = Task { @MainActor in
            _ = await previous?.value
            return await operation()
        }
        tails[userId] = turn
        return await turn.value
    }
}
