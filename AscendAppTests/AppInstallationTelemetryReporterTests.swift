import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AppInstallationTelemetryReporterTests {
    @Test("First open persists its once-only boundary across reporter instances and identity changes")
    func firstOpenPersistsAcrossReporterInstancesAndIdentityChanges() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTelemetry(sink: sink)

        AppInstallationTelemetryReporter(
            telemetry: telemetry,
            defaults: defaults,
            buildMetadata: Self.buildMetadata
        ).recordFirstOpenIfNeeded()

        telemetry.setUserId("firebase-user")
        telemetry.clearUserId()

        AppInstallationTelemetryReporter(
            telemetry: telemetry,
            defaults: defaults,
            buildMetadata: Self.buildMetadata
        ).recordFirstOpenIfNeeded()

        let record = try #require(sink.records.only)
        #expect(record.name == "app_first_opened")
        #expect(
            record.parameters == [
                "app_environment": .string("staging"),
                "build_config": .string("staging"),
                "app_version": .string("1.2.3"),
                "build_number": .string("456"),
                "first_open_app_version": .string("1.2.3"),
                "first_open_build_number": .string("456")
            ]
        )
    }

    @Test("Clearing collection state cannot turn a later launch into a first open")
    func disabledCollectionStillConsumesTheInstallationBoundary() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let disabledSink = InMemoryTelemetrySink(destination: .analytics)
        AppInstallationTelemetryReporter(
            telemetry: makeTestTelemetry(sink: disabledSink, collectionEnabled: false),
            defaults: defaults,
            buildMetadata: Self.buildMetadata
        ).recordFirstOpenIfNeeded()

        let enabledSink = InMemoryTelemetrySink(destination: .analytics)
        AppInstallationTelemetryReporter(
            telemetry: makeTelemetry(sink: enabledSink),
            defaults: defaults,
            buildMetadata: Self.buildMetadata
        ).recordFirstOpenIfNeeded()

        #expect(disabledSink.records.isEmpty)
        #expect(enabledSink.records.isEmpty)
    }

    @Test("Clearing account preferences does not clear the installation boundary")
    func accountPreferenceResetCannotReemitFirstOpen() throws {
        let bundleIdentifier = "AppInstallationTelemetryReporterTests.\(UUID().uuidString)"
        let accountDefaults = try #require(UserDefaults(suiteName: bundleIdentifier))
        let installationDomain = "\(bundleIdentifier).installation"
        let installationDefaults = AppInstallationTelemetryReporter.installationDefaults(
            bundleIdentifier: bundleIdentifier
        )
        defer {
            accountDefaults.removePersistentDomain(forName: bundleIdentifier)
            installationDefaults.removePersistentDomain(forName: installationDomain)
        }

        AppInstallationTelemetryReporter(
            telemetry: makeTelemetry(sink: InMemoryTelemetrySink(destination: .analytics)),
            defaults: installationDefaults,
            buildMetadata: Self.buildMetadata
        ).recordFirstOpenIfNeeded()

        accountDefaults.removePersistentDomain(forName: bundleIdentifier)

        let laterLaunchSink = InMemoryTelemetrySink(destination: .analytics)
        AppInstallationTelemetryReporter(
            telemetry: makeTelemetry(sink: laterLaunchSink),
            defaults: AppInstallationTelemetryReporter.installationDefaults(
                bundleIdentifier: bundleIdentifier
            ),
            buildMetadata: Self.buildMetadata
        ).recordFirstOpenIfNeeded()

        #expect(laterLaunchSink.records.isEmpty)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppInstallationTelemetryReporterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeTelemetry(sink: InMemoryTelemetrySink) -> TelemetryManager {
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            buildMetadata: Self.buildMetadata,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        return telemetry
    }

    private static let buildMetadata = TelemetryBuildMetadata(
        appEnvironment: "staging",
        buildConfig: "staging",
        appVersion: "1.2.3",
        buildNumber: "456",
        bundleIdentifier: "com.tylerpavay.AscendApp.staging"
    )
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
