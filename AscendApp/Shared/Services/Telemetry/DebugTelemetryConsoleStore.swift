#if DEBUG
import Foundation
import Observation

@MainActor
@Observable
final class DebugTelemetryConsoleStore {
    static let shared = DebugTelemetryConsoleStore()

    var entries: [DebugTelemetryConsoleEntry] = []
    var isCollectionEnabled = false
    var currentUserID: String?

    private let maxEntries: Int

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    func record(_ record: TelemetryRecord) {
        insert(DebugTelemetryConsoleEntry(record: record))
    }

    func record(screen: TelemetryScreen) {
        insert(DebugTelemetryConsoleEntry(screen: screen))
    }

    func setCollectionEnabled(_ enabled: Bool) {
        isCollectionEnabled = enabled
    }

    func setUserID(_ userID: String?) {
        currentUserID = userID
    }

    func clear() {
        entries.removeAll()
    }

    private func insert(_ entry: DebugTelemetryConsoleEntry) {
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }
}
#endif
