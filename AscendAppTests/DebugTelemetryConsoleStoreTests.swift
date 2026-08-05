#if DEBUG
//
//  DebugTelemetryConsoleStoreTests.swift
//  AscendAppTests
//
//  Created by Codex on 4/6/26.
//

import Foundation
import Testing
@testable import AscendApp

@MainActor
struct DebugTelemetryConsoleStoreTests {
    @Test
    func storeKeepsNewestEntriesAndCapsHistory() throws {
        let store = DebugTelemetryConsoleStore(maxEntries: 2)

        store.record(
            try makeEnvelopedTestRecord(TelemetryRecord(
                name: "first_event",
                destinations: [.analytics]
            ))
        )
        store.record(
            screen: try makeEnvelopedTestScreen(TelemetryScreen(
                name: "import_screen",
                screenClass: "WorkoutImportSheet"
            ))
        )
        store.record(
            try makeEnvelopedTestRecord(TelemetryRecord(
                name: "second_event",
                destinations: [.crashlytics]
            ))
        )

        #expect(store.entries.count == 2)
        #expect(store.entries.map(\.rawName) == ["second_event", "import_screen"])
        #expect(store.entries.first?.destinations == ["Crashlytics"])
    }

    @Test
    func sinkMirrorsCollectionStateAndRecentTelemetry() async throws {
        let store = DebugTelemetryConsoleStore(maxEntries: 10)
        let sink = DebugTelemetryConsoleSink {
            store
        }

        sink.setCollectionEnabled(true)
        sink.setUserID("user_123")
        sink.record(
            try makeEnvelopedTestRecord(TelemetryRecord(
                name: "test_event",
                parameters: ["result": .string("success")],
                destinations: [.analytics, .crashlytics]
            ))
        )
        sink.record(
            screen: try makeEnvelopedTestScreen(TelemetryScreen(
                name: "test_screen",
                screenClass: "TelemetryConsoleView"
            ))
        )

        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(store.isCollectionEnabled)
        #expect(store.currentUserID == "user_123")
        #expect(store.entries.count == 2)
        #expect(store.entries[0].kind == .screen)
        #expect(store.entries[1].kind == .analytics)
    }
}
#endif
