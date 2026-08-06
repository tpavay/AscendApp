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

/// Captures the non-fatals a caller recorded.
///
/// Breadcrumbs and the diagnostics ring buffer cannot stand in for this: only a recorded error
/// uploads on its own, without waiting for a later crash to carry it.
final class RecordingCrashlyticsReporter: CrashlyticsReporting, @unchecked Sendable {
    struct RecordedError {
        let context: String
        let code: String
        let additionalInfo: [String: String]?
    }

    private let lock = NSLock()
    private var recorded: [RecordedError] = []

    var recordedErrors: [RecordedError] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}

    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {
        lock.lock()
        recorded.append(
            RecordedError(context: context, code: code, additionalInfo: additionalInfo)
        )
        lock.unlock()
    }
}

func makeTestTelemetry(
    reporter: any CrashlyticsReporting,
    collectionEnabled: Bool = true
) -> TelemetryManager {
    let telemetry = TelemetryManager(
        sinks: [],
        crashlyticsReporter: reporter,
        collectionEnabledOverride: collectionEnabled
    )
    telemetry.configure()
    return telemetry
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
