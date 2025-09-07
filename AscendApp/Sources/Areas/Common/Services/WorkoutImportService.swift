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
    var importedWorkoutUUIDs: Set<String> = []
    
    private let healthKitService = HealthKitService.shared
    private var modelContext: ModelContext?
    
    private init() {}
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func checkForNewWorkouts() async {
        // Per HealthKit guidelines: "people can change permissions, so your app needs to 
        // make a request every time it needs access" - always request permission when needed
        print("🏥 Requesting HealthKit permission as per Apple guidelines...")
        let _ = await healthKitService.requestPermission()
        
        // Always attempt to fetch workouts regardless of authorization status
        // HealthKit will return available data based on actual user permissions
        let searchStartDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        print("🔍 Searching for workouts since: \(searchStartDate)")
        
        // Fetch all workouts from the past year
        let allWorkouts = await healthKitService.fetchStairStepperWorkouts(from: searchStartDate)
        print("🏃‍♂️ Found \(allWorkouts.count) total HealthKit workouts")
        
        // Show all workouts but track which ones are already imported
        await updateImportedStatus(for: allWorkouts)
        
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
            let workout = hkWorkout.toAscendWorkout(with: metrics)
            
            modelContext.insert(workout)
            try modelContext.save()
            
            // Mark as imported but keep in list for visual feedback
            importedWorkoutUUIDs.insert(hkWorkout.uuid.uuidString)
            
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
    
    private func updateImportedStatus(for workouts: [HKWorkout]) async {
        guard let modelContext = modelContext else { return }
        
        // Get all existing HealthKit UUIDs from our database
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.healthKitUUID != nil
            }
        )
        
        do {
            let existingWorkouts = try modelContext.fetch(descriptor)
            let existingUUIDs = Set(existingWorkouts.compactMap { $0.healthKitUUID })
            
            // Update imported status based on database
            for workout in workouts {
                if existingUUIDs.contains(workout.uuid.uuidString) {
                    importedWorkoutUUIDs.insert(workout.uuid.uuidString)
                }
            }
            
            print("🔄 Updated imported status - \(importedWorkoutUUIDs.count) workouts marked as imported")
        } catch {
            print("❌ Error updating imported status: \(error)")
        }
    }
    
    func isWorkoutImported(_ uuid: String) -> Bool {
        return importedWorkoutUUIDs.contains(uuid)
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