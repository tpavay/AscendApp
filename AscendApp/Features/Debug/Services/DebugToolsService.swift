//
//  DebugToolsService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftData

#if DEBUG
@MainActor
final class DebugToolsService {
    static let shared = DebugToolsService()
    
    private let workoutSeeder = WorkoutTestDataSeeder()
    
    private init() {}
    
    // MARK: - Workout Operations

    func seedWorkoutData(
        preset: WorkoutSeedPreset,
        modelContext: ModelContext
    ) async throws -> Int {
        try await workoutSeeder.seedWorkouts(
            preset: preset,
            modelContext: modelContext
        )
    }

    func clearSeededWorkoutData(modelContext: ModelContext) async throws -> Int {
        try workoutSeeder.clearSeededWorkouts(modelContext: modelContext)
    }

    func sendCrashlyticsTestDiagnostic() {
        TelemetryManager.shared.debugEnableCollectionForSession()
        TelemetryManager.shared.recordError(
            DebugDiagnosticsError.crashlyticsTestEvent,
            context: .network,
            // Wire identifier, not copy: renaming it would split this diagnostic
            // from every event already grouped under it in Crashlytics.
            code: "debug_sentry_test_event",
            additionalInfo: [
                "source": "debug_tools",
                "expected": "true"
            ]
        )
    }
    
    // MARK: - Future: Add more debug operations
    // func clearAllData() async throws { }
    // func resetUserPreferences() async throws { }
}

private enum DebugDiagnosticsError: LocalizedError {
    case crashlyticsTestEvent

    var errorDescription: String? {
        "Debug Crashlytics test diagnostic"
    }
}
#endif
