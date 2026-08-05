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

func makeTestTelemetryEnvelope() throws -> TelemetryEnvelope {
    try TelemetryEnvelope(
        validating: TelemetryBuildMetadata(
            appEnvironment: "staging",
            buildConfig: "staging",
            appVersion: "1.2.3",
            buildNumber: "456",
            bundleIdentifier: "com.tylerpavay.AscendApp.tests"
        )
    )
}

func makeEnvelopedTestRecord(_ record: TelemetryRecord) throws -> EnvelopedTelemetryRecord {
    EnvelopedTelemetryRecord(record: record, envelope: try makeTestTelemetryEnvelope())
}

func makeEnvelopedTestScreen(_ screen: TelemetryScreen) throws -> EnvelopedTelemetryScreen {
    EnvelopedTelemetryScreen(screen: screen, envelope: try makeTestTelemetryEnvelope())
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
