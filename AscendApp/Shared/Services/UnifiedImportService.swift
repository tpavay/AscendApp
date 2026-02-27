//
//  UnifiedImportService.swift
//  AscendApp
//
//  Created by Claude Code on 1/16/26.
//

import Foundation
import SwiftData
import HealthKit

/// Result of a batch import operation
struct ImportBatchResult {
    let importedWorkouts: [Workout]
    let failedPendingIds: [String]
    var successCount: Int { importedWorkouts.count }
    var failedCount: Int { failedPendingIds.count }
}

/// Single source of truth for all pending workout imports from Apple Health and Hevy
@MainActor
@Observable
class UnifiedImportService {
    static let shared = UnifiedImportService()

    /// Internal outcome per-workout import to disambiguate new vs updated vs failed
    enum ImportOutcome {
        case imported(Workout)      // genuinely new workout
        case updatedExisting        // Hevy upsert — not counted in celebration
        case failed(pendingId: String)
    }

    var isLoading = false
    var isImporting = false
    var pendingWorkouts: [PendingWorkout] = []
    var rejectedCount: Int = 0  // 190+ steps/min auto-rejected from Apple Health
    var currentImportingPendingId: String?

    private let healthKitService = HealthKitService.shared
    private let hevyManager = HevyManager.shared
    private var modelContext: ModelContext?
    private var lastCheckDate: Date?

    private init() {}

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Computed Properties

    var totalPendingCount: Int {
        pendingWorkouts.count
    }

    // MARK: - Check for New Workouts

    /// Throttled check for new workouts - prevents spam when app repeatedly comes to foreground
    func checkForNewWorkoutsInBackground() async {
        if let lastCheck = lastCheckDate, Date().timeIntervalSince(lastCheck) < 30 { // 30 seconds
            print("📊 Skipping duplicate background check")
            return
        }

        lastCheckDate = Date()
        await checkForNewWorkouts()
    }

    func resetBackgroundCheckThrottle() {
        lastCheckDate = nil
    }

    /// Fetches pending workouts from all sources and filters already-imported ones
    func checkForNewWorkouts() async {
        guard let modelContext = modelContext else {
            print("❌ No modelContext available for unified import")
            return
        }

        isLoading = true
        defer { isLoading = false }

        var allPendingWorkouts: [PendingWorkout] = []
        var rejected = 0

        // 1. Fetch Apple Health workouts
        print("🏥 Requesting HealthKit permission as per Apple guidelines...")
        let _ = await healthKitService.requestPermission()

        let searchStartDate = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        print("🔍 Searching for workouts since: \(searchStartDate)")

        let ahWorkouts = await healthKitService.fetchStairStepperWorkouts(from: searchStartDate)
        print("🏃‍♂️ Found \(ahWorkouts.count) total HealthKit workouts")

        // Filter Apple Health workouts
        for workout in ahWorkouts {
            let uuid = workout.uuid.uuidString

            // Skip already imported
            if isHealthKitUUIDImported(uuid, modelContext: modelContext) { continue }

            // Fetch metrics and validate - only auto-reject impossible values (190+ steps/min)
            let metrics = await healthKitService.fetchWorkoutMetrics(for: workout)
            if isWorkoutInvalid(workout, metrics: metrics) {
                rejected += 1
                let stepsPerMin = Double(metrics.steps ?? 0) / (workout.duration / 60)
                print("⚠️ Auto-rejected workout: \(Int(stepsPerMin)) steps/min is impossibly high")
            } else {
                allPendingWorkouts.append(.appleHealth(workout))
            }
        }

        // 2. Fetch Hevy exercises (if connected)
        // Track matched Apple Health UUIDs to avoid showing duplicates
        var matchedAHUUIDs: Set<String> = []

        if hevyManager.isConnected {
            do {
                let exercises = try await hevyManager.fetchPendingExercises()
                let autoLinkEnabled = hevyManager.autoLinkAppleHealth

                for exercise in exercises {
                    // Skip already imported
                    if isHevyWorkoutImported(exercise.workout_id, modelContext: modelContext) { continue }

                    // Find matching Apple Health workout if auto-link is enabled
                    var matchingAHWorkout: HKWorkout? = nil
                    if autoLinkEnabled, let startDate = exercise.startDate {
                        matchingAHWorkout = await findBestAppleHealthMatch(
                            for: startDate,
                            duration: exercise.duration,
                            modelContext: modelContext
                        )
                        // Track matched UUIDs to filter from pending list
                        if let match = matchingAHWorkout {
                            matchedAHUUIDs.insert(match.uuid.uuidString)
                        }
                    }

                    allPendingWorkouts.append(.hevy(exercise, matchingAHWorkout: matchingAHWorkout))
                }

                print("📊 Found \(exercises.count) Hevy exercises")
            } catch {
                print("❌ Failed to fetch Hevy exercises: \(error)")
            }
        }

        // Filter out Apple Health workouts that are matched to a Hevy workout (when auto-link is ON)
        // This avoids showing duplicates - the Hevy workout will show "Hevy + Apple Watch" instead
        if !matchedAHUUIDs.isEmpty {
            allPendingWorkouts.removeAll { pending in
                if case .appleHealth(let workout) = pending {
                    return matchedAHUUIDs.contains(workout.uuid.uuidString)
                }
                return false
            }
            print("📊 Filtered out \(matchedAHUUIDs.count) Apple Health workouts matched to Hevy")
        }

        // Sort by date (most recent first)
        pendingWorkouts = allPendingWorkouts.sorted { $0.startDate > $1.startDate }
        rejectedCount = rejected

        print("📊 Total pending workouts: \(pendingWorkouts.count) (rejected: \(rejected))")
    }

    // MARK: - Import Operations

    /// Imports a single pending workout
    func importWorkout(_ pending: PendingWorkout, skipPRRecalculation: Bool = false) async -> ImportOutcome {
        guard let modelContext = modelContext else { return .failed(pendingId: pending.id) }

        isImporting = true
        currentImportingPendingId = pending.id
        defer {
            currentImportingPendingId = nil
            isImporting = false
        }

        switch pending {
        case .appleHealth(let hkWorkout):
            return await importAppleHealthWorkout(hkWorkout, pendingId: pending.id, modelContext: modelContext, skipPRRecalculation: skipPRRecalculation)

        case .hevy(let exercise, let matchingAHWorkout):
            return await importHevyExercise(exercise, pendingId: pending.id, matchingAHWorkout: matchingAHWorkout, modelContext: modelContext, skipPRRecalculation: skipPRRecalculation)
        }
    }

    /// Imports all pending workouts and returns detailed results
    func importAllWorkouts() async -> ImportBatchResult {
        guard let modelContext = modelContext else {
            return ImportBatchResult(importedWorkouts: [], failedPendingIds: [])
        }

        isImporting = true
        defer {
            currentImportingPendingId = nil
            isImporting = false
        }

        TelemetryManager.shared.log(.workoutImportStarted)
        var importedWorkouts: [Workout] = []
        var failedPendingIds: [String] = []

        // Sort chronologically (oldest first) for import to maintain PR order
        let sortedWorkouts = pendingWorkouts.sorted { $0.startDate < $1.startDate }

        // Import all workouts, skipping individual PR recalculation
        for pending in sortedWorkouts {
            // Check for cancellation between items
            if Task.isCancelled { break }

            currentImportingPendingId = pending.id

            // Call internal batch import (doesn't set isImporting itself)
            let outcome = await importWorkoutForBatch(pending, modelContext: modelContext)

            switch outcome {
            case .imported(let workout):
                importedWorkouts.append(workout)
                // Remove from pending list
                pendingWorkouts.removeAll { $0.id == pending.id }
            case .updatedExisting:
                // Hevy upsert — remove from pending but don't count as new import
                pendingWorkouts.removeAll { $0.id == pending.id }
            case .failed:
                failedPendingIds.append(pending.id)
                // Failed items stay in pending list for retry
            }
        }

        currentImportingPendingId = nil

        // Recalculate all PRs once at the end
        if !importedWorkouts.isEmpty {
            do {
                let settingsManager = SettingsManager.shared
                try PersonalRecordService.recalculateAllPersonalRecords(
                    modelContext: modelContext,
                    measurementSystem: settingsManager.measurementSystem,
                    stepHeight: settingsManager.stepHeight
                )
                print("✅ Successfully recalculated all PRs after batch import")
            } catch {
                print("❌ Failed to recalculate PRs: \(error)")
                TelemetryManager.shared.recordError(error, context: .healthKit, code: "pr_recalculation_failed")
            }
        }

        // Update last import date
        UserDefaults.standard.set(Date(), forKey: "lastHealthKitImportDate")

        TelemetryManager.shared.log(.workoutImportCompleted)
        return ImportBatchResult(importedWorkouts: importedWorkouts, failedPendingIds: failedPendingIds)
    }

    /// Internal batch import helper — doesn't manage isImporting state
    private func importWorkoutForBatch(_ pending: PendingWorkout, modelContext: ModelContext) async -> ImportOutcome {
        switch pending {
        case .appleHealth(let hkWorkout):
            return await importAppleHealthWorkout(hkWorkout, pendingId: pending.id, modelContext: modelContext, skipPRRecalculation: true)

        case .hevy(let exercise, let matchingAHWorkout):
            return await importHevyExercise(exercise, pendingId: pending.id, matchingAHWorkout: matchingAHWorkout, modelContext: modelContext, skipPRRecalculation: true)
        }
    }

    // MARK: - Apple Health Import

    private func importAppleHealthWorkout(_ hkWorkout: HKWorkout, pendingId: String, modelContext: ModelContext, skipPRRecalculation: Bool) async -> ImportOutcome {
        do {
            let metrics = await healthKitService.fetchWorkoutMetrics(for: hkWorkout)
            let settingsManager = SettingsManager.shared
            let stepsPerFloor = settingsManager.stepsPerFloor
            let workout = hkWorkout.toAscendWorkout(with: metrics, stepsPerFloor: stepsPerFloor)

            // Calculate percentile scores for heat map before inserting
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

            // Remove from pending
            pendingWorkouts.removeAll { $0.id == pendingId }

            print("✅ Successfully imported Apple Health workout from \(hkWorkout.startDate)")
            return .imported(workout)
        } catch {
            print("❌ Failed to import Apple Health workout: \(error)")
            TelemetryManager.shared.recordError(error, context: .healthKit, code: "workout_import_failed")
            return .failed(pendingId: pendingId)
        }
    }

    // MARK: - Hevy Import

    private func importHevyExercise(_ exercise: HevyExerciseHistory, pendingId: String, matchingAHWorkout: HKWorkout?, modelContext: ModelContext, skipPRRecalculation: Bool) async -> ImportOutcome {
        // Check if already imported (upsert check)
        if let existingWorkout = findWorkoutByHevyId(exercise.workout_id, modelContext: modelContext) {
            let success = updateExistingWorkout(existingWorkout, with: exercise, modelContext: modelContext)
            return success ? .updatedExisting : .failed(pendingId: pendingId)
        }

        // Create new workout
        guard let startDate = exercise.startDate else {
            print("❌ Exercise has no valid start date")
            return .failed(pendingId: pendingId)
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

        // Merge Apple Health data if auto-link is enabled and we have a match
        if hevyManager.autoLinkAppleHealth, let ahWorkout = matchingAHWorkout {
            await mergeHealthKitData(from: ahWorkout, into: workout)
        }

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

            // Update last sync timestamp
            if let endDate = exercise.endDate ?? exercise.startDate {
                if HevySyncState.lastSyncAt == nil || endDate > HevySyncState.lastSyncAt! {
                    HevySyncState.lastSyncAt = endDate
                }
            }

            // Remove from pending - both the Hevy workout and the matched Apple Health workout
            pendingWorkouts.removeAll { $0.id == pendingId }
            if let ahWorkout = matchingAHWorkout {
                pendingWorkouts.removeAll { $0.id == "ah_\(ahWorkout.uuid.uuidString)" }
            }

            print("✅ Imported Hevy exercise: \(workout.name) with \(steps) steps")
            return .imported(workout)
        } catch {
            print("❌ Failed to import Hevy exercise: \(error)")
            return .failed(pendingId: pendingId)
        }
    }

    private func updateExistingWorkout(_ workout: Workout, with exercise: HevyExerciseHistory, modelContext: ModelContext) -> Bool {
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

    // MARK: - Apple Health Matching

    /// Finds the best matching Apple Health workout for a Hevy workout
    private func findBestAppleHealthMatch(for startDate: Date, duration: TimeInterval, modelContext: ModelContext) async -> HKWorkout? {
        let endDate = startDate.addingTimeInterval(duration)

        // Fetch potential matches with 15-minute tolerance
        let candidates = await healthKitService.fetchWorkoutsInTimeRange(
            start: startDate,
            end: endDate,
            toleranceMinutes: 15
        )

        guard !candidates.isEmpty else { return nil }

        // Skip candidates that are already linked to another workout
        let unlinkedCandidates = candidates.filter { hkWorkout in
            !isHealthKitUUIDUsed(hkWorkout.uuid.uuidString, modelContext: modelContext)
        }

        guard !unlinkedCandidates.isEmpty else { return nil }

        // Try strict matching first (5-minute tolerance)
        let strictTolerance: TimeInterval = 5 * 60 // 5 minutes in seconds
        let strictMatches = unlinkedCandidates.filter { hkWorkout in
            let startDiff = abs(hkWorkout.startDate.timeIntervalSince(startDate))
            let endDiff = abs(hkWorkout.endDate.timeIntervalSince(endDate))
            return startDiff <= strictTolerance && endDiff <= strictTolerance
        }

        if !strictMatches.isEmpty {
            // Return the one with closest start time
            return strictMatches.min { a, b in
                abs(a.startDate.timeIntervalSince(startDate)) < abs(b.startDate.timeIntervalSince(startDate))
            }
        }

        // Fall back to relaxed matching (15-minute tolerance)
        let relaxedTolerance: TimeInterval = 15 * 60 // 15 minutes in seconds
        let relaxedMatches = unlinkedCandidates.filter { hkWorkout in
            let startDiff = abs(hkWorkout.startDate.timeIntervalSince(startDate))
            let endDiff = abs(hkWorkout.endDate.timeIntervalSince(endDate))
            return startDiff <= relaxedTolerance && endDiff <= relaxedTolerance
        }

        // Return the one with closest start time
        return relaxedMatches.min { a, b in
            abs(a.startDate.timeIntervalSince(startDate)) < abs(b.startDate.timeIntervalSince(startDate))
        }
    }

    /// Merges heart rate and calorie data from Apple Health workout into a workout
    private func mergeHealthKitData(from hkWorkout: HKWorkout, into workout: Workout) async {
        let metrics = await healthKitService.fetchWorkoutMetrics(for: hkWorkout)

        // Update heart rate data (only if not already set)
        if workout.avgHeartRate == nil {
            workout.avgHeartRate = metrics.avgHeartRate
        }
        if workout.maxHeartRate == nil {
            workout.maxHeartRate = metrics.maxHeartRate
        }

        // Update heart rate time series
        if workout.heartRateData == nil && !metrics.heartRateTimeSeries.isEmpty {
            workout.heartRateData = metrics.heartRateTimeSeries.encoded
        }

        // Update calories (only if not already set)
        if workout.caloriesBurned == nil {
            workout.caloriesBurned = metrics.caloriesBurned
        }

        // Update METs (only if not already set)
        if workout.averageMETs == nil {
            workout.averageMETs = metrics.averageMETs
        }

        // Set healthKitUUID to prevent duplicate Apple Health imports
        workout.healthKitUUID = hkWorkout.uuid.uuidString

        print("📊 Merged: HR \(metrics.avgHeartRate ?? 0)/\(metrics.maxHeartRate ?? 0), Cal \(metrics.caloriesBurned ?? 0), METs \(metrics.averageMETs ?? 0)")
    }

    // MARK: - Validation

    private func isWorkoutInvalid(_ hkWorkout: HKWorkout, metrics: WorkoutMetrics) -> Bool {
        let steps = metrics.steps ?? 0
        let durationMinutes = hkWorkout.duration / 60

        guard durationMinutes > 0 else { return false }

        let stepsPerMin = Double(steps) / durationMinutes
        return stepsPerMin >= 190
    }

    // MARK: - Database Helpers

    private func isHealthKitUUIDImported(_ uuid: String, modelContext: ModelContext) -> Bool {
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

    private func isHealthKitUUIDUsed(_ uuid: String, modelContext: ModelContext) -> Bool {
        isHealthKitUUIDImported(uuid, modelContext: modelContext)
    }

    private func isHevyWorkoutImported(_ hevyWorkoutId: String, modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.hevyWorkoutId == hevyWorkoutId
            }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            return !existing.isEmpty
        } catch {
            return false
        }
    }

    private func findWorkoutByHevyId(_ hevyWorkoutId: String, modelContext: ModelContext) -> Workout? {
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

    private func fetchAllWorkouts(from modelContext: ModelContext) throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Check if a specific pending workout is imported
    func isWorkoutImported(_ pending: PendingWorkout) -> Bool {
        guard let modelContext = modelContext else { return false }

        switch pending {
        case .appleHealth(let workout):
            return isHealthKitUUIDImported(workout.uuid.uuidString, modelContext: modelContext)
        case .hevy(let exercise, _):
            return isHevyWorkoutImported(exercise.workout_id, modelContext: modelContext)
        }
    }
}
