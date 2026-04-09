//
//  TelemetryManagerTests.swift
//  AscendAppTests
//
//  Created by Codex on 4/6/26.
//

import Testing
@testable import AscendApp

struct TelemetryManagerTests {
    @Test
    func trackRoutesRecordsToMatchingDestinations() {
        let analyticsSink = InMemoryTelemetrySink(destination: .analytics)
        let crashlyticsSink = InMemoryTelemetrySink(destination: .crashlytics)
        let telemetry = TelemetryManager(
            sinks: [analyticsSink, crashlyticsSink],
            crashlyticsReporter: NoOpCrashlyticsReporter(),
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
            crashlyticsReporter: NoOpCrashlyticsReporter(),
            collectionEnabledOverride: false
        )

        telemetry.configure()
        telemetry.track(TelemetryRecord(name: "suppressed_event"))
        telemetry.track(screen: TelemetryScreen(name: "suppressed_screen", screenClass: "Screen"))

        #expect(analyticsSink.collectionEnabledValues == [false])
        #expect(analyticsSink.records.isEmpty)
        #expect(analyticsSink.screens.isEmpty)
    }
}
