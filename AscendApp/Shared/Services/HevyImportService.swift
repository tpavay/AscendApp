//
//  HevyImportService.swift
//  AscendApp
//
//  Created by Claude Code on 12/12/24.
//

import Foundation
import SwiftData
import HealthKit

@MainActor
@Observable
class HevyImportService {
    static let shared = HevyImportService()

    var isImporting = false
    var pendingExercisesCount = 0
    var pendingExercises: [HevyExerciseHistory] = []
    var lastError: HevyError?

    // Apple Health linking
    var isLinking = false
    var linkableHevyWorkoutsCount = 0

    private let hevyManager = HevyManager.shared
    private let healthKitService = HealthKitService.shared
    private var modelContext: ModelContext?

    private init() {}

    /// Result of a linking operation
    struct LinkingResult {
        let linkedCount: Int
        let totalHevyWorkouts: Int
        let errors: [String]
    }

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
            // Calculate percentile scores for heat map before inserting
            let settingsManager = SettingsManager.shared
            let existingWorkouts = try fetchAllWorkouts(from: modelContext)
            let percentileScores = PercentileScoreService.calculateAllPercentiles(
                for: workout,
                existingWorkouts: existingWorkouts,
                fitnessLevel: settingsManager.fitnessLevel,
                preferredMetric: settingsManager.preferredWorkoutMetric
            )
            workout.percentileScores = percentileScores

            modelContext.insert(workout)
            try modelContext.save()

            if !skipPRRecalculation {
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

    // MARK: - Apple Health Linking

    /// Finds Hevy workouts that have matching Apple Health workouts available
    func checkForLinkableWorkouts() async -> Int {
        guard let modelContext = modelContext else { return 0 }

        // Request HealthKit permission first
        let _ = await healthKitService.requestPermission()

        // Fetch all Hevy workouts without healthKitUUID (not yet linked)
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.hevyWorkoutId != nil && workout.healthKitUUID == nil
            }
        )

        do {
            let hevyWorkouts = try modelContext.fetch(descriptor)

            // Actually check which ones have matching Apple Health workouts
            var matchCount = 0
            for hevyWorkout in hevyWorkouts {
                if await findBestAppleHealthMatch(for: hevyWorkout) != nil {
                    matchCount += 1
                }
            }

            linkableHevyWorkoutsCount = matchCount
            print("📊 Found \(matchCount) Hevy workouts with matching Apple Health data (out of \(hevyWorkouts.count) unlinked)")
            return matchCount
        } catch {
            print("❌ Error fetching linkable Hevy workouts: \(error)")
            return 0
        }
    }

    /// Links Apple Health data to all eligible Hevy workouts
    func linkAppleHealthData() async -> LinkingResult {
        guard let modelContext = modelContext else {
            return LinkingResult(linkedCount: 0, totalHevyWorkouts: 0, errors: ["No model context"])
        }

        isLinking = true
        defer { isLinking = false }

        var linkedCount = 0
        let errors: [String] = []

        // Request HealthKit permission
        let _ = await healthKitService.requestPermission()

        // Fetch all Hevy workouts without healthKitUUID
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.hevyWorkoutId != nil && workout.healthKitUUID == nil
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        do {
            let hevyWorkouts = try modelContext.fetch(descriptor)
            let totalCount = hevyWorkouts.count

            for hevyWorkout in hevyWorkouts {
                if let match = await findBestAppleHealthMatch(for: hevyWorkout) {
                    // Merge Apple Health data into Hevy workout
                    await mergeHealthKitData(from: match, into: hevyWorkout)
                    linkedCount += 1
                    print("✅ Linked Apple Health data to Hevy workout: \(hevyWorkout.name)")
                }
            }

            // Save all changes
            try modelContext.save()

            // Reset linkable count
            linkableHevyWorkoutsCount = max(0, linkableHevyWorkoutsCount - linkedCount)

            return LinkingResult(linkedCount: linkedCount, totalHevyWorkouts: totalCount, errors: errors)

        } catch {
            print("❌ Error linking Apple Health data: \(error)")
            return LinkingResult(linkedCount: 0, totalHevyWorkouts: 0, errors: [error.localizedDescription])
        }
    }

    /// Finds the best matching Apple Health workout for a Hevy workout
    private func findBestAppleHealthMatch(for hevyWorkout: Workout) async -> HKWorkout? {
        let hevyStart = hevyWorkout.date
        let hevyEnd = hevyWorkout.date.addingTimeInterval(hevyWorkout.duration)

        // Fetch potential matches with 15-minute tolerance
        let candidates = await healthKitService.fetchWorkoutsInTimeRange(
            start: hevyStart,
            end: hevyEnd,
            toleranceMinutes: 15
        )

        guard !candidates.isEmpty else { return nil }

        // Skip candidates that are already linked to another workout
        let unlinkedCandidates = candidates.filter { hkWorkout in
            !isHealthKitUUIDUsed(hkWorkout.uuid.uuidString)
        }

        guard !unlinkedCandidates.isEmpty else { return nil }

        // Try strict matching first (5-minute tolerance)
        let strictTolerance: TimeInterval = 5 * 60 // 5 minutes in seconds
        let strictMatches = unlinkedCandidates.filter { hkWorkout in
            let startDiff = abs(hkWorkout.startDate.timeIntervalSince(hevyStart))
            let endDiff = abs(hkWorkout.endDate.timeIntervalSince(hevyEnd))
            return startDiff <= strictTolerance && endDiff <= strictTolerance
        }

        if !strictMatches.isEmpty {
            // Return the one with closest start time
            return strictMatches.min { a, b in
                abs(a.startDate.timeIntervalSince(hevyStart)) < abs(b.startDate.timeIntervalSince(hevyStart))
            }
        }

        // Fall back to relaxed matching (15-minute tolerance)
        let relaxedTolerance: TimeInterval = 15 * 60 // 15 minutes in seconds
        let relaxedMatches = unlinkedCandidates.filter { hkWorkout in
            let startDiff = abs(hkWorkout.startDate.timeIntervalSince(hevyStart))
            let endDiff = abs(hkWorkout.endDate.timeIntervalSince(hevyEnd))
            return startDiff <= relaxedTolerance && endDiff <= relaxedTolerance
        }

        // Return the one with closest start time
        return relaxedMatches.min { a, b in
            abs(a.startDate.timeIntervalSince(hevyStart)) < abs(b.startDate.timeIntervalSince(hevyStart))
        }
    }

    /// Checks if a HealthKit UUID is already used by any workout
    private func isHealthKitUUIDUsed(_ uuid: String) -> Bool {
        guard let modelContext = modelContext else { return false }

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.healthKitUUID == uuid
            }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            return !existing.isEmpty
        } catch {
            return false
        }
    }

    /// Merges heart rate and calorie data from Apple Health workout into Hevy workout
    private func mergeHealthKitData(from hkWorkout: HKWorkout, into hevyWorkout: Workout) async {
        let metrics = await healthKitService.fetchWorkoutMetrics(for: hkWorkout)

        // Update heart rate data (only if not already set)
        if hevyWorkout.avgHeartRate == nil {
            hevyWorkout.avgHeartRate = metrics.avgHeartRate
        }
        if hevyWorkout.maxHeartRate == nil {
            hevyWorkout.maxHeartRate = metrics.maxHeartRate
        }

        // Update heart rate time series
        if hevyWorkout.heartRateData == nil && !metrics.heartRateTimeSeries.isEmpty {
            hevyWorkout.heartRateData = metrics.heartRateTimeSeries.encoded
        }

        // Update calories (only if not already set)
        if hevyWorkout.caloriesBurned == nil {
            hevyWorkout.caloriesBurned = metrics.caloriesBurned
        }

        // Update METs (only if not already set)
        if hevyWorkout.averageMETs == nil {
            hevyWorkout.averageMETs = metrics.averageMETs
        }

        // Set healthKitUUID to prevent duplicate Apple Health imports
        hevyWorkout.healthKitUUID = hkWorkout.uuid.uuidString

        print("📊 Merged: HR \(metrics.avgHeartRate ?? 0)/\(metrics.maxHeartRate ?? 0), Cal \(metrics.caloriesBurned ?? 0), METs \(metrics.averageMETs ?? 0)")
    }

    /// Fetch all workouts from the model context for percentile calculation
    private func fetchAllWorkouts(from modelContext: ModelContext) throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
}
