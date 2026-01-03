//
//  HevyImportService.swift
//  AscendApp
//
//  Created by Claude Code on 12/12/24.
//

import Foundation
import SwiftData

@MainActor
@Observable
class HevyImportService {
    static let shared = HevyImportService()

    var isImporting = false
    var pendingExercisesCount = 0
    var pendingExercises: [HevyExerciseHistory] = []
    var lastError: HevyError?

    private let hevyManager = HevyManager.shared
    private var modelContext: ModelContext?

    private init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Import Operations

    /// Checks for new exercises from Hevy
    func checkForNewExercises() async {
        guard hevyManager.isConnected else { return }

        do {
            lastError = nil
            let exercises = try await hevyManager.fetchPendingExercises()

            // Filter out already imported exercises
            pendingExercises = exercises.filter { exercise in
                !isExerciseImported(exercise.workout_id)
            }
            pendingExercisesCount = pendingExercises.count

            print("📊 Found \(pendingExercisesCount) new Hevy exercises to import")
        } catch let error as HevyError {
            lastError = error
            print("❌ Failed to check for Hevy exercises: \(error.localizedDescription)")
        } catch {
            lastError = .networkError(error)
            print("❌ Failed to check for Hevy exercises: \(error)")
        }
    }

    /// Imports a single Hevy exercise as a workout
    func importExercise(_ exercise: HevyExerciseHistory, skipPRRecalculation: Bool = false) async -> Bool {
        guard let modelContext = modelContext else {
            print("❌ No modelContext available for Hevy import")
            return false
        }

        // Check if already imported (upsert check)
        if let existingWorkout = findWorkoutByHevyId(exercise.workout_id) {
            // Update existing workout
            return updateExistingWorkout(existingWorkout, with: exercise)
        }

        // Create new workout
        guard let startDate = exercise.startDate else {
            print("❌ Exercise has no valid start date")
            return false
        }

        let stepsPerFloor = SettingsManager.shared.stepsPerFloor
        let templateType = HevySyncState.templateType ?? "steps"

        // Calculate steps and floors based on template type
        let steps: Int
        let floors: Int

        if templateType == "floors" {
            floors = exercise.metricValue
            steps = Workout.floorsToSteps(floors, stepsPerFloor: stepsPerFloor)
        } else {
            steps = exercise.metricValue
            floors = Workout.stepsToFloors(steps, stepsPerFloor: stepsPerFloor)
        }

        let workout = Workout(
            name: exercise.workout_title.isEmpty ? Workout.generateDefaultName(for: startDate) : exercise.workout_title,
            date: startDate,
            duration: exercise.duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: stepsPerFloor,
            source: .hevy,
            hevyWorkoutId: exercise.workout_id
        )

        do {
            modelContext.insert(workout)
            try modelContext.save()

            if !skipPRRecalculation {
                let settingsManager = SettingsManager.shared
                try PersonalRecordService.recalculateAllPersonalRecords(
                    modelContext: modelContext,
                    measurementSystem: settingsManager.measurementSystem,
                    stepHeight: settingsManager.stepHeight
                )
            }

            print("✅ Imported Hevy exercise: \(workout.name) with \(steps) steps")
            return true
        } catch {
            print("❌ Failed to import Hevy exercise: \(error)")
            return false
        }
    }

    /// Updates an existing workout with Hevy data
    private func updateExistingWorkout(_ workout: Workout, with exercise: HevyExerciseHistory) -> Bool {
        guard let modelContext = modelContext else { return false }

        let stepsPerFloor = SettingsManager.shared.stepsPerFloor
        let templateType = HevySyncState.templateType ?? "steps"

        if templateType == "floors" {
            workout.floors = exercise.metricValue
            workout.steps = Workout.floorsToSteps(workout.floors, stepsPerFloor: stepsPerFloor)
        } else {
            workout.steps = exercise.metricValue
            workout.floors = Workout.stepsToFloors(workout.steps, stepsPerFloor: stepsPerFloor)
        }

        workout.duration = exercise.duration

        do {
            try modelContext.save()
            print("✅ Updated existing Hevy workout: \(workout.name)")
            return true
        } catch {
            print("❌ Failed to update Hevy workout: \(error)")
            return false
        }
    }

    /// Imports all pending exercises
    func importAllExercises() async -> Int {
        guard let modelContext = modelContext else { return 0 }

        isImporting = true
        defer { isImporting = false }

        var successCount = 0

        // Sort exercises chronologically (oldest first)
        let sortedExercises = pendingExercises.sorted {
            ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast)
        }

        // Import all exercises, skipping individual PR recalculation
        for exercise in sortedExercises {
            if await importExercise(exercise, skipPRRecalculation: true) {
                successCount += 1
            }
        }

        // Recalculate PRs once at the end
        if successCount > 0 {
            do {
                let settingsManager = SettingsManager.shared
                try PersonalRecordService.recalculateAllPersonalRecords(
                    modelContext: modelContext,
                    measurementSystem: settingsManager.measurementSystem,
                    stepHeight: settingsManager.stepHeight
                )
                print("✅ Recalculated PRs after Hevy import")
            } catch {
                print("❌ Failed to recalculate PRs: \(error)")
            }

            // Update last sync timestamp from imported exercises
            updateLastSyncTimestamp(from: sortedExercises)
        }

        // Clear pending exercises
        pendingExercises = []
        pendingExercisesCount = 0

        return successCount
    }

    // MARK: - Helpers

    /// Checks if an exercise has already been imported
    func isExerciseImported(_ hevyWorkoutId: String) -> Bool {
        findWorkoutByHevyId(hevyWorkoutId) != nil
    }

    /// Finds a workout by its Hevy workout ID
    private func findWorkoutByHevyId(_ hevyWorkoutId: String) -> Workout? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.hevyWorkoutId == hevyWorkoutId
            }
        )

        do {
            let workouts = try modelContext.fetch(descriptor)
            return workouts.first
        } catch {
            print("❌ Error finding workout by Hevy ID: \(error)")
            return nil
        }
    }

    /// Updates lastSyncAt to the max end time from imported exercises
    private func updateLastSyncTimestamp(from exercises: [HevyExerciseHistory]) {
        let maxEndDate = exercises.compactMap { $0.endDate ?? $0.startDate }.max()
        if let maxDate = maxEndDate {
            HevySyncState.lastSyncAt = maxDate
            print("📅 Updated lastHevySyncAt to: \(maxDate)")
        }
    }
}
