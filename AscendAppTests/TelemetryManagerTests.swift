//
//  TelemetryManagerTests.swift
//  AscendAppTests
//
//  Created by Codex on 4/6/26.
//

import Foundation
import Testing
@testable import AscendApp

struct TelemetryManagerTests {
    @Test
    func trackRoutesRecordsToMatchingDestinations() {
        let analyticsSink = InMemoryTelemetrySink(destination: .analytics)
        let crashlyticsSink = InMemoryTelemetrySink(destination: .crashlytics)
        let telemetry = TelemetryManager(
            sinks: [analyticsSink, crashlyticsSink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            buildMetadata: Self.stagingBuildMetadata
        )

        telemetry.configure()
        telemetry.track(
            TelemetryRecord(
                name: "test_event",
                parameters: [
                    "result": .string("success"),
                    "app_environment": .string("spoofed"),
                    "build_config": .string("spoofed"),
                    "app_version": .string("spoofed"),
                    "build_number": .string("spoofed")
                ],
                destinations: [.analytics, .crashlytics]
            )
        )
        telemetry.track(
            screen: TelemetryScreen(
                name: "test_screen",
                screenClass: "TestScreen"
            )
        )

        #expect(analyticsSink.collectionEnabledValues == [true])
        #expect(crashlyticsSink.collectionEnabledValues == [true])
        #expect(analyticsSink.records.count == 1)
        #expect(crashlyticsSink.records.count == 1)
        #expect(analyticsSink.screens.count == 1)
        #expect(crashlyticsSink.screens.isEmpty)
        #expect(analyticsSink.records.first?.parameters["app_environment"] == .string("staging"))
        #expect(analyticsSink.records.first?.parameters["build_config"] == .string("staging"))
        #expect(analyticsSink.records.first?.parameters["app_version"] == .string("1.2.3"))
        #expect(analyticsSink.records.first?.parameters["build_number"] == .string("456"))
        #expect(analyticsSink.screens.first?.parameters["app_environment"] == .string("staging"))
        #expect(analyticsSink.screens.first?.parameters["build_config"] == .string("staging"))
        #expect(analyticsSink.screens.first?.parameters["app_version"] == .string("1.2.3"))
        #expect(analyticsSink.screens.first?.parameters["build_number"] == .string("456"))
    }

    /// Only Mixpanel routes by environment, so a bundle missing a version key
    /// must degrade to a placeholder rather than silence Firebase, screen views,
    /// and every Crashlytics breadcrumb for the life of the install.
    @Test
    func aBundleMissingItsVersionKeysStillShipsACompleteEnvelope() {
        let analyticsSink = InMemoryTelemetrySink(destination: .analytics)
        let crashlyticsSink = InMemoryTelemetrySink(destination: .crashlytics)
        let telemetry = TelemetryManager(
            sinks: [analyticsSink, crashlyticsSink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            buildMetadata: TelemetryBuildMetadata(
                appEnvironment: "production",
                buildConfig: "release",
                appVersion: "",
                buildNumber: "",
                bundleIdentifier: "com.tylerpavay.AscendApp"
            )
        )

        telemetry.configure()
        telemetry.track(TelemetryRecord(name: "test_event", destinations: [.analytics, .crashlytics]))
        telemetry.track(screen: TelemetryScreen(name: "test_screen", screenClass: "TestScreen"))

        #expect(analyticsSink.records.count == 1)
        #expect(crashlyticsSink.records.count == 1)
        #expect(analyticsSink.screens.count == 1)
        #expect(analyticsSink.records.first?.parameters["app_environment"] == .string("production"))
        #expect(analyticsSink.records.first?.parameters["app_version"] == .string("unknown"))
        #expect(analyticsSink.records.first?.parameters["build_number"] == .string("unknown"))
        #expect(analyticsSink.screens.first?.parameters["app_version"] == .string("unknown"))
    }

    @Test
    func breadcrumbsOmitTheEnvelopeTheyAlreadyCarryAsCustomKeys() {
        let record = EnvelopedTelemetryRecord(
            record: TelemetryRecord(
                name: "auth:session_restored",
                destinations: [.crashlytics]
            ),
            envelope: TelemetryEnvelope(resolving: Self.stagingBuildMetadata)
        )
        let parameterized = EnvelopedTelemetryRecord(
            record: TelemetryRecord(
                name: "live_climb_completed",
                parameters: ["outcome": .string("success")],
                destinations: [.crashlytics]
            ),
            envelope: TelemetryEnvelope(resolving: Self.stagingBuildMetadata)
        )

        #expect(record.crashlyticsMessage == "auth:session_restored")
        #expect(parameterized.crashlyticsMessage == "live_climb_completed outcome=success")
        #expect(record.parameters.count == 4)
    }

    @Test
    func disabledCollectionSuppressesRecordsAndScreens() {
        let analyticsSink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = TelemetryManager(
            sinks: [analyticsSink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: false
        )

        telemetry.configure()
        telemetry.track(TelemetryRecord(name: "suppressed_event"))
        telemetry.track(screen: TelemetryScreen(name: "suppressed_screen", screenClass: "Screen"))

        #expect(analyticsSink.collectionEnabledValues == [false])
        #expect(analyticsSink.records.isEmpty)
        #expect(analyticsSink.screens.isEmpty)
    }

    #if DEBUG
    @Test
    func debugLaunchArgumentPersistsCollectionEnabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabled = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp", "-TelemetryEnabled"],
            environment: [:],
            userDefaults: defaults
        )
        let persisted = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp"],
            environment: [:],
            userDefaults: defaults
        )

        #expect(enabled)
        #expect(persisted)
    }

    @Test
    func debugDisabledLaunchArgumentOverridesPersistedCollectionEnabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp", "-TelemetryEnabled"],
            environment: [:],
            userDefaults: defaults
        )

        let disabled = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp", "-TelemetryDisabled"],
            environment: [:],
            userDefaults: defaults
        )
        let persisted = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp"],
            environment: [:],
            userDefaults: defaults
        )

        #expect(disabled == false)
        #expect(persisted == false)
    }

    @Test
    func debugEnvironmentVariableCanEnableCollection() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabled = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp"],
            environment: ["ASC_DEBUG_TELEMETRY_ENABLED": "1"],
            userDefaults: defaults
        )

        #expect(enabled)
    }

    @Test
    func xcTestEnvironmentDisablesCollectionOverridingAllOtherPaths() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabledArgumentUnderTests = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp", "-TelemetryEnabled"],
            environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"],
            userDefaults: defaults
        )
        let enabledEnvironmentUnderTests = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp"],
            environment: [
                "ASC_DEBUG_TELEMETRY_ENABLED": "1",
                "XCTestSessionIdentifier": UUID().uuidString
            ],
            userDefaults: defaults
        )
        let persistedAfterTestRuns = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp"],
            environment: [:],
            userDefaults: defaults
        )

        #expect(enabledArgumentUnderTests == false)
        #expect(enabledEnvironmentUnderTests == false)
        #expect(persistedAfterTestRuns == false)
    }

    @Test
    func debugCollectionDefaultsOffWithoutOverride() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabled = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp"],
            environment: [:],
            userDefaults: defaults
        )

        #expect(enabled == false)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "TelemetryManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
    #endif

    private static let stagingBuildMetadata = TelemetryBuildMetadata(
        appEnvironment: "staging",
        buildConfig: "staging",
        appVersion: "1.2.3",
        buildNumber: "456",
        bundleIdentifier: "com.tylerpavay.AscendApp.staging"
    )
}
