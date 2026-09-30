import Foundation

/// Recaps this device has shown, per account, so an offline open is never followed by the
/// same recap again before its `seenAt` write reaches the server.
struct PeriodRecapLocalSeenStore: Sendable {
    /// Plenty for a year of weeks and months; older IDs can never be unseen again anyway.
    static let retainedCount = 80

    private let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func seenIDs(userId: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key(userId)) ?? [])
    }

    func markSeen(userId: String, recapIDs: [String]) {
        var ids = defaults.stringArray(forKey: key(userId)) ?? []
        for id in recapIDs where !ids.contains(id) {
            ids.append(id)
        }
        defaults.set(Array(ids.suffix(Self.retainedCount)), forKey: key(userId))
    }

    private func key(_ userId: String) -> String {
        "period_recap_seen_ids.\(userId)"
    }
}
