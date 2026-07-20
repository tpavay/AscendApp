import Foundation
@testable import AscendApp

struct NoopCrashlyticsReporter: CrashlyticsReporting {
    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {}
}

/// `configure()` is what applies the override; without it collection stays off and every
/// emission assertion would pass vacuously against an empty sink.
func makeTestTelemetry(
    sinks: [InMemoryTelemetrySink],
    collectionEnabled: Bool = true
) -> TelemetryManager {
    let telemetry = TelemetryManager(
        sinks: sinks,
        crashlyticsReporter: NoopCrashlyticsReporter(),
        collectionEnabledOverride: collectionEnabled
    )
    telemetry.configure()
    return telemetry
}

func makeTestTelemetry(
    sink: InMemoryTelemetrySink,
    collectionEnabled: Bool = true
) -> TelemetryManager {
    makeTestTelemetry(sinks: [sink], collectionEnabled: collectionEnabled)
}
