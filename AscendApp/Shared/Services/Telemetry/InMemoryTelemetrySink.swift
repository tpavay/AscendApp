import Foundation
import os.lock

final class InMemoryTelemetrySink: TelemetrySink, @unchecked Sendable {
    let supportedDestinations: Set<TelemetryDestination>

    private let lock = OSAllocatedUnfairLock(initialState: State())

    init(destination: TelemetryDestination) {
        self.supportedDestinations = [destination]
    }

    var collectionEnabledValues: [Bool] {
        lock.withLock(\.collectionEnabledValues)
    }

    var userIDs: [String?] {
        lock.withLock(\.userIDs)
    }

    var records: [EnvelopedTelemetryRecord] {
        lock.withLock(\.records)
    }

    var screens: [EnvelopedTelemetryScreen] {
        lock.withLock(\.screens)
    }

    func setCollectionEnabled(_ enabled: Bool) {
        lock.withLock { $0.collectionEnabledValues.append(enabled) }
    }

    func setUserID(_ userID: String?) {
        lock.withLock { $0.userIDs.append(userID) }
    }

    func record(_ record: EnvelopedTelemetryRecord) {
        lock.withLock { $0.records.append(record) }
    }

    func record(screen: EnvelopedTelemetryScreen) {
        lock.withLock { $0.screens.append(screen) }
    }
}

private extension InMemoryTelemetrySink {
    struct State {
        var collectionEnabledValues: [Bool] = []
        var userIDs: [String?] = []
        var records: [EnvelopedTelemetryRecord] = []
        var screens: [EnvelopedTelemetryScreen] = []
    }
}
