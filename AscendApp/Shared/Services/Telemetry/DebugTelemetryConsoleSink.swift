#if DEBUG
import Foundation

final class DebugTelemetryConsoleSink: TelemetrySink {
    let supportedDestinations: Set<TelemetryDestination> = [.analytics, .crashlytics]

    private let storeProvider: @Sendable @MainActor () -> DebugTelemetryConsoleStore

    init(storeProvider: @escaping @Sendable @MainActor () -> DebugTelemetryConsoleStore) {
        self.storeProvider = storeProvider
    }

    func setCollectionEnabled(_ enabled: Bool) {
        Task { @MainActor in
            storeProvider().setCollectionEnabled(enabled)
        }
    }

    func setUserID(_ userID: String?) {
        Task { @MainActor in
            storeProvider().setUserID(userID)
        }
    }

    func record(_ record: EnvelopedTelemetryRecord) {
        Task { @MainActor in
            storeProvider().record(record)
        }
    }

    func record(screen: EnvelopedTelemetryScreen) {
        Task { @MainActor in
            storeProvider().record(screen: screen)
        }
    }
}
#endif
