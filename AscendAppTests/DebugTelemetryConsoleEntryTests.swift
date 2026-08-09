#if DEBUG
//
//  DebugTelemetryConsoleEntryTests.swift
//  AscendAppTests
//
//  Created by Codex on 4/6/26.
//

import Foundation
import Testing
@testable import AscendApp

struct DebugTelemetryConsoleEntryTests {
    @Test
    func breadcrumbEntriesUseFriendlyLabels() throws {
        let entry = DebugTelemetryConsoleEntry(
            record: try makeEnvelopedTestRecord(
                TelemetryRecord(
                    name: "auth:profile_loaded",
                    destinations: [.crashlytics]
                )
            ),
            timestamp: Date(timeIntervalSince1970: 0)
        )

        #expect(entry.kind == .breadcrumb)
        #expect(entry.title == "Profile Loaded")
        #expect(entry.feature == "Authentication")
        #expect(entry.summary == "The signed-in user's profile finished loading.")
        #expect(entry.whenItFires == "This fires after auth is known and Ascend finishes loading the user's app profile data.")
        #expect(entry.whyTracked == "It marks the point where the app has enough user data to personalize the experience.")
        #expect(entry.environment == "Staging")
        #expect(entry.destinationsSummary == "Sent to Crashlytics")
    }

    @Test
    func analyticsEntriesHumanizeParameters() throws {
        let entry = DebugTelemetryConsoleEntry(
            record: try makeEnvelopedTestRecord(
                TelemetryRecord(
                    name: "live_climb_completed",
                    parameters: [
                        "climb_id": .string("burj_khalifa"),
                        "outcome": .string("partial_success"),
                        "was_personal_record": .bool(true)
                    ],
                    destinations: [.analytics, .crashlytics]
                )
            ),
            timestamp: Date(timeIntervalSince1970: 0)
        )

        #expect(entry.kind == .analytics)
        #expect(entry.title == "Live Climb Completed")
        #expect(entry.environment == "Staging")
        #expect(entry.destinationsSummary == "Sent to Analytics, and Crashlytics")
        #expect(entry.parameters.contains(where: { $0.key == "Climb Id" && $0.value == "burj_khalifa" }))
        #expect(entry.parameters.contains(where: { $0.key == "Outcome" && $0.value == "Partial success" }))
        #expect(entry.parameters.contains(where: { $0.key == "Was Personal Record" && $0.value == "Yes" }))
    }
}
#endif
