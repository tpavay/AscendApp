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
    func breadcrumbEntriesUseFriendlyLabels() {
        let entry = DebugTelemetryConsoleEntry(
            record: TelemetryRecord(
                name: "auth:profile_loaded",
                parameters: [
                    "app_environment": .string("dev")
                ],
                destinations: [.crashlytics]
            ),
            timestamp: Date(timeIntervalSince1970: 0)
        )

        #expect(entry.kind == .breadcrumb)
        #expect(entry.title == "Profile Loaded")
        #expect(entry.feature == "Authentication")
        #expect(entry.summary == "The signed-in user's profile finished loading.")
        #expect(entry.whenItFires == "This fires after auth is known and Ascend finishes loading the user's app profile data.")
        #expect(entry.whyTracked == "It marks the point where the app has enough user data to personalize the experience.")
        #expect(entry.environment == "Dev")
        #expect(entry.destinationsSummary == "Sent to Crashlytics")
    }

    @Test
    func analyticsEntriesHumanizeParameters() {
        let entry = DebugTelemetryConsoleEntry(
            record: TelemetryRecord(
                name: "workout_import_finished",
                parameters: [
                    "app_environment": .string("dev"),
                    "import_mode": .string("selected"),
                    "source_mix": .string("apple_health_only"),
                    "candidate_count_bucket": .string("2_5"),
                    "outcome": .string("partial_success")
                ],
                destinations: [.analytics, .crashlytics]
            ),
            timestamp: Date(timeIntervalSince1970: 0)
        )

        #expect(entry.kind == .analytics)
        #expect(entry.title == "Workout Import Finished")
        #expect(entry.feature == "Workouts")
        #expect(entry.environment == "Dev")
        #expect(entry.destinationsSummary == "Sent to Analytics, and Crashlytics")
        #expect(entry.whenItFires == "This fires when the import flow ends, whether it created workouts, updated existing ones, partially succeeded, or failed.")
        #expect(entry.whyTracked == "It tells us whether imports are succeeding, where users hit failures, and how much workout data is actually getting into the app.")
        #expect(entry.parameters.contains(where: { $0.key == "Import Mode" && $0.value == "Selected workouts" }))
        #expect(entry.parameters.contains(where: { $0.key == "Source Mix" && $0.value == "Apple Health only" }))
        #expect(entry.parameters.contains(where: { $0.key == "Workout Count" && $0.value == "2-5" }))
        #expect(entry.parameters.contains(where: { $0.key == "Outcome" && $0.value == "Partial success" }))
        #expect(entry.parameters.first(where: { $0.rawKey == "candidate_count_bucket" })?.helpText == "How many workout candidates were included in this import action.")
    }
}
#endif
