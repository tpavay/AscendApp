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
    
    private let healthKitService = HealthKitService.shared
    private var modelContext: ModelContext?
    private var lastCheckDate: Date?
    
    private init() {}
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
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
        
        // Count only truly unimported workouts for the badge
        let unimportedCount = allWorkouts.filter { workout in
            !isWorkoutImported(workout.uuid.uuidString)
        }.count
        
        pendingWorkouts = allWorkouts
        pendingWorkoutsCount = unimportedCount
        
        print("📊 Found \(pendingWorkoutsCount) new workouts to import (showing \(allWorkouts.count) total)")
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
    
    func importWorkout(_ hkWorkout: HKWorkout) async -> Bool {
        guard let modelContext = modelContext else { return false }
        
        do {
            let metrics = await healthKitService.fetchWorkoutMetrics(for: hkWorkout)
            let stepsPerFloor = SettingsManager.shared.stepsPerFloor
            let workout = hkWorkout.toAscendWorkout(with: metrics, stepsPerFloor: stepsPerFloor)
            
            modelContext.insert(workout)
            try modelContext.save()
            
            // Check for personal records after the workout is saved
            let prResults = try checkAndSavePersonalRecords(
                for: workout,
                modelContext: modelContext
            )
            
            // Update workout with PR types if any were achieved
            if !prResults.isEmpty {
                let prTypes = prResults.map { $0.type.rawValue }
                workout.personalRecordTypes = prTypes
                try modelContext.save()
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
    
    // MARK: - Personal Records
    private func checkAndSavePersonalRecords(
        for workout: Workout,
        modelContext: ModelContext
    ) throws -> [PersonalRecordResult] {
        let settingsManager = SettingsManager.shared
        
        // Fetch all current personal records
        let allRecords = try PersonalRecordService.fetchCurrentPersonalRecords(
            modelContext: modelContext
        )
        
        // Check for PRs in this workout
        let prResults = PersonalRecordService.checkForPersonalRecords(
            workout: workout,
            allPersonalRecords: allRecords,
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )
        
        // Filter to only new records
        let newRecords = prResults.filter { $0.isNewRecord }
        
        // Save the new personal records
        if !newRecords.isEmpty {
            try PersonalRecordService.savePersonalRecords(
                results: newRecords,
                workout: workout,
                modelContext: modelContext
            )
        }
        
        return newRecords
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
        var successCount = 0
        
        // Only import workouts that haven't been imported yet
        let workoutsToImport = pendingWorkouts.filter { workout in
            !isWorkoutImported(workout.uuid.uuidString)
        }
        
        for workout in workoutsToImport {
            if await importWorkout(workout) {
                successCount += 1
            }
        }
        
        return successCount
    }
}