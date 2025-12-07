//
//  WorkoutImportService.swift
//  AscendApp
//
//  Created by Claude on 9/1/25.
//

import Foundation
import SwiftData
import HealthKit

@MainActor
@Observable
class WorkoutImportService {
    static let shared = WorkoutImportService()

    var pendingWorkoutsCount = 0
    var pendingWorkouts: [HKWorkout] = []
    var rejectedCount: Int = 0  // 190+ steps/min auto-rejected

    private let healthKitService = HealthKitService.shared
    private var modelContext: ModelContext?
    private var lastCheckDate: Date?

    private init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Validation

    /// Check if a workout has impossibly high steps/min (190+)
    private func isWorkoutInvalid(_ hkWorkout: HKWorkout, metrics: WorkoutMetrics) -> Bool {
        let steps = metrics.steps ?? 0
        let durationMinutes = hkWorkout.duration / 60

        guard durationMinutes > 0 else { return false }

        let stepsPerMin = Double(steps) / durationMinutes
        return stepsPerMin >= 190
    }

    // MARK: - Background Check

    func checkForNewWorkoutsInBackground() async {
        // Only check once per foreground session to avoid repeated queries
        // while app is running, but allow fresh checks each time app comes to foreground
        if let lastCheck = lastCheckDate, Date().timeIntervalSince(lastCheck) < 30 { // 30 seconds
            print("📊 Skipping duplicate background check")
            return
        }

        lastCheckDate = Date()
        await checkForNewWorkouts()
    }

    func resetBackgroundCheckThrottle() {
        // Reset when app goes to background so next foreground check works
        lastCheckDate = nil
    }

    func checkForNewWorkouts() async {
        // Per HealthKit guidelines: "people can change permissions, so your app needs to
        // make a request every time it needs access" - always request permission when needed
        print("🏥 Requesting HealthKit permission as per Apple guidelines...")
        let _ = await healthKitService.requestPermission()

        // Always attempt to fetch workouts regardless of authorization status
        // HealthKit will return available data based on actual user permissions
        let searchStartDate = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        print("🔍 Searching for workouts since: \(searchStartDate)")

        // Fetch all workouts from the past year
        let allWorkouts = await healthKitService.fetchStairStepperWorkouts(from: searchStartDate)
        print("🏃‍♂️ Found \(allWorkouts.count) total HealthKit workouts")

        // Filter workouts - auto-reject 190+ steps/min, include everything else
        var pending: [HKWorkout] = []
        var rejected = 0

        for workout in allWorkouts {
            let uuid = workout.uuid.uuidString

            // Skip already imported workouts
            if isWorkoutImported(uuid) { continue }

            // Fetch metrics and validate - only auto-reject impossible values (190+ steps/min)
            let metrics = await healthKitService.fetchWorkoutMetrics(for: workout)

            if isWorkoutInvalid(workout, metrics: metrics) {
                rejected += 1
                let stepsPerMin = Double(metrics.steps ?? 0) / (workout.duration / 60)
                print("⚠️ Auto-rejected workout: \(Int(stepsPerMin)) steps/min is impossibly high")
            } else {
                pending.append(workout)
            }
        }

        pendingWorkouts = pending
        rejectedCount = rejected
        pendingWorkoutsCount = pending.filter { !isWorkoutImported($0.uuid.uuidString) }.count

        print("📊 Found \(pending.count) importable, \(rejected) auto-rejected workouts")
    }

    private func filterUnimportedWorkouts(_ hkWorkouts: [HKWorkout]) async -> [HKWorkout] {
        guard let modelContext = modelContext else {
            print("❌ No modelContext available")
            return []
        }

        // Get all existing HealthKit UUIDs from our database
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.healthKitUUID != nil
            }
        )

        do {
            let existingWorkouts = try modelContext.fetch(descriptor)
            let existingUUIDs = Set(existingWorkouts.compactMap { $0.healthKitUUID })
            print("🗄️ Found \(existingWorkouts.count) existing workouts in database")
            print("🆔 Existing UUIDs count: \(existingUUIDs.count)")

            // Filter out workouts that we've already imported
            let filteredWorkouts = hkWorkouts.filter { workout in
                let isNotImported = !existingUUIDs.contains(workout.uuid.uuidString)
                if !isNotImported {
                    print("⏭️ Skipping already imported workout: \(workout.uuid.uuidString)")
                }
                return isNotImported
            }

            return filteredWorkouts
        } catch {
            print("❌ Error fetching existing workouts: \(error)")
            return hkWorkouts // If we can't check, import all to be safe
        }
    }

    func importWorkout(_ hkWorkout: HKWorkout, skipPRRecalculation: Bool = false) async -> Bool {
        guard let modelContext = modelContext else { return false }

        do {
            let metrics = await healthKitService.fetchWorkoutMetrics(for: hkWorkout)
            let stepsPerFloor = SettingsManager.shared.stepsPerFloor
            let workout = hkWorkout.toAscendWorkout(with: metrics, stepsPerFloor: stepsPerFloor)

            modelContext.insert(workout)
            try modelContext.save()

            // Recalculate all PRs to ensure correctness regardless of import order
            // The imported workout might be older than existing workouts, so we need
            // to recalculate the entire PR history based on chronological order
            if !skipPRRecalculation {
                let settingsManager = SettingsManager.shared
                try PersonalRecordService.recalculateAllPersonalRecords(
                    modelContext: modelContext,
                    measurementSystem: settingsManager.measurementSystem,
                    stepHeight: settingsManager.stepHeight
                )
            }

            // Update count to exclude imported workouts
            pendingWorkoutsCount = pendingWorkouts.filter { workout in
                !isWorkoutImported(workout.uuid.uuidString)
            }.count

            // Update last import date
            UserDefaults.standard.set(Date(), forKey: "lastHealthKitImportDate")

            print("✅ Successfully imported workout from \(hkWorkout.startDate)")
            return true
        } catch {
            print("❌ Failed to import workout: \(error)")
            return false
        }
    }

    func isWorkoutImported(_ uuid: String) -> Bool {
        guard let modelContext = modelContext else { return false }

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.healthKitUUID == uuid
            }
        )

        do {
            let existingWorkouts = try modelContext.fetch(descriptor)
            return !existingWorkouts.isEmpty
        } catch {
            print("❌ Error checking if workout is imported: \(error)")
            return false
        }
    }

    func importAllWorkouts() async -> Int {
        guard let modelContext = modelContext else { return 0 }

        var successCount = 0

        // Only import workouts that haven't been imported yet
        let workoutsToImport = pendingWorkouts.filter { workout in
            !isWorkoutImported(workout.uuid.uuidString)
        }

        // Sort workouts chronologically (oldest first) for import
        let sortedWorkouts = workoutsToImport.sorted { $0.startDate < $1.startDate }

        // Import all workouts first, skipping individual PR recalculation
        for workout in sortedWorkouts {
            if await importWorkout(workout, skipPRRecalculation: true) {
                successCount += 1
            }
        }

        // Recalculate all PRs once at the end based on chronological workout order
        // This ensures PRs are correct regardless of any existing workouts in the database
        if successCount > 0 {
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
            }
        }

        return successCount
    }
}
