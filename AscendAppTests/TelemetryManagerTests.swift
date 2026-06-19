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
            crashlyticsReporter: TestCrashlyticsReporter(),
            collectionEnabledOverride: true
        )

        telemetry.configure()
        telemetry.track(
            TelemetryRecord(
                name: "test_event",
                parameters: ["result": .string("success")],
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
        #expect(analyticsSink.records.first?.parameters["app_environment"] != nil)
    }

    @Test
    func disabledCollectionSuppressesRecordsAndScreens() {
        let analyticsSink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = TelemetryManager(
            sinks: [analyticsSink],
            crashlyticsReporter: TestCrashlyticsReporter(),
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

        #expect(!disabled)
        #expect(!persisted)
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
    func debugCollectionDefaultsOffWithoutOverride() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let enabled = TelemetryManager.shouldEnableCollection(
            arguments: ["AscendApp"],
            environment: [:],
            userDefaults: defaults
        )

        #expect(!enabled)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "TelemetryManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
    #endif
}

private struct TestCrashlyticsReporter: CrashlyticsReporting {
    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {}
}
