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

    func queueSimulatedAppleHealthAutoImportReview(
        modelContext: ModelContext
    ) async throws -> Workout {
        try await WorkoutImportCoordinator.shared.debugQueueSimulatedAutoImportedReview(
            modelContext: modelContext
        )
    }

    func clearSimulatedAppleHealthAutoImports(modelContext: ModelContext) async throws -> Int {
        try WorkoutImportCoordinator.shared.debugClearSimulatedAutoImports(
            modelContext: modelContext
        )
    }

    func sendSentryTestDiagnostic() {
        TelemetryManager.shared.debugEnableCollectionForSession()
        TelemetryManager.shared.recordError(
            DebugDiagnosticsError.sentryTestEvent,
            context: .network,
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
    case sentryTestEvent

    var errorDescription: String? {
        "Debug Sentry test diagnostic"
    }
}
#endif
