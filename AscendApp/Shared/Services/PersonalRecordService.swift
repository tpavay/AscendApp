//
//  PersonalRecordService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//

import Foundation
import SwiftData

/// Service for checking and recording personal records
final class PersonalRecordService {
    
    /// Check a workout for any personal records and return the results
    /// This method does NOT save anything to the database - it only checks for PRs
    static func checkForPersonalRecords(
        workout: Workout,
        allPersonalRecords: [PersonalRecord],
        measurementSystem: MeasurementSystem,
        stepHeight: Double
    ) -> [PersonalRecordResult] {
        let currentRecordsByType = currentRecordsByType(from: allPersonalRecords)
        var results: [PersonalRecordResult] = []
        
        // Check steps PR
        let stepsResult = checkRecord(
            type: .mostSteps,
            newValue: Double(workout.steps),
            currentRecord: currentRecordsByType[.mostSteps]
        )
        results.append(stepsResult)
        
        // Check floors PR
        let floorsResult = checkRecord(
            type: .mostFloors,
            newValue: Double(workout.floors),
            currentRecord: currentRecordsByType[.mostFloors]
        )
        results.append(floorsResult)
        
        // Check duration PR
        let result = checkRecord(
            type: .longestDuration,
            newValue: workout.duration,
            currentRecord: currentRecordsByType[.longestDuration]
        )
        results.append(result)
        
        // Check pace PR
        if let pace = workout.pace {
            let result = checkRecord(
                type: .highestAveragePace,
                newValue: pace,
                currentRecord: currentRecordsByType[.highestAveragePace]
            )
            results.append(result)
        }
        
        // Check vertical climb PR (only if there are steps)
        if workout.steps > 0 {
            let verticalClimb = workout.totalVerticalClimb(
                stepHeight: stepHeight,
                measurementSystem: measurementSystem
            )
            let result = checkRecord(
                type: .highestVerticalClimb,
                newValue: verticalClimb,
                currentRecord: currentRecordsByType[.highestVerticalClimb]
            )
            results.append(result)
        }
        
        // Check average heart rate PR
        if let avgHR = workout.avgHeartRate {
            let result = checkRecord(
                type: .highestAverageHeartRate,
                newValue: Double(avgHR),
                currentRecord: currentRecordsByType[.highestAverageHeartRate]
            )
            results.append(result)
        }
        
        // Check max heart rate PR
        if let maxHR = workout.maxHeartRate {
            let result = checkRecord(
                type: .highestMaxHeartRate,
                newValue: Double(maxHR),
                currentRecord: currentRecordsByType[.highestMaxHeartRate]
            )
            results.append(result)
        }
        
        // Check calories burned PR
        if let calories = workout.caloriesBurned {
            let result = checkRecord(
                type: .mostCaloriesBurned,
                newValue: Double(calories),
                currentRecord: currentRecordsByType[.mostCaloriesBurned]
            )
            results.append(result)
        }
        
        return results
    }
    
    /// Save personal records to the database after a workout is logged
    /// This will create new PR entries and mark old ones as historical
    static func savePersonalRecords(
        results: [PersonalRecordResult],
        workout: Workout,
        modelContext: ModelContext
    ) throws {
        let currentRecordsByID = try fetchCurrentRecordsByID(modelContext: modelContext)

        for result in results where result.isNewRecord {
            if let previousId = result.previousRecordId,
               let previousRecord = currentRecordsByID[previousId] {
                previousRecord.isCurrent = false
            }
        }

        for result in results where result.isNewRecord {
            let newRecord = PersonalRecord(
                type: result.type,
                value: result.newValue,
                workoutId: workout.id,
                achievedAt: Date(),
                isCurrent: true,
                previousRecordId: result.previousRecordId,
                workoutName: workout.name,
                workoutDate: workout.date
            )

            modelContext.insert(newRecord)
        }

        try modelContext.save()
    }
    
    /// Check a specific record type against current records
    private static func checkRecord(
        type: PersonalRecordType,
        newValue: Double,
        currentRecord: PersonalRecord?
    ) -> PersonalRecordResult {
        if let current = currentRecord {
            // Check if new value beats the current record
            let isNewRecord = newValue > current.value
            return PersonalRecordResult(
                type: type,
                newValue: newValue,
                previousValue: current.value,
                previousRecordId: current.id,
                isNewRecord: isNewRecord
            )
        } else {
            // No existing record, so this is a new PR
            return PersonalRecordResult(
                type: type,
                newValue: newValue,
                previousValue: nil,
                previousRecordId: nil,
                isNewRecord: true
            )
        }
    }
    
    /// Fetch all current personal records for a user
    static func fetchCurrentPersonalRecords(modelContext: ModelContext) throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { record in
                record.isCurrent == true
            }
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch all personal records (including historical) for a user
    static func fetchAllPersonalRecords(modelContext: ModelContext) throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch personal records for a specific workout
    static func fetchPersonalRecords(
        forWorkout workoutId: UUID,
        modelContext: ModelContext
    ) throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { record in
                record.workoutId == workoutId
            }
        )
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - PR Recalculation
    
    /// Recalculate all personal records from scratch based on chronological workout order.
    /// This ensures PRs are correct regardless of the order workouts were imported.
    /// Call this after batch imports, workout deletions, or workout edits.
    static func recalculateAllPersonalRecords(
        modelContext: ModelContext,
        measurementSystem: MeasurementSystem,
        stepHeight: Double
    ) throws {
        // 1. Fetch all workouts sorted by date (oldest first)
        let workoutDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let allWorkouts = try modelContext.fetch(workoutDescriptor)
        
        // 2. Fetch all existing PersonalRecord entries and delete them
        let prDescriptor = FetchDescriptor<PersonalRecord>()
        let existingPRs = try modelContext.fetch(prDescriptor)
        for pr in existingPRs {
            modelContext.delete(pr)
        }
        
        // 3. Clear personalRecordTypes from all workouts
        for workout in allWorkouts {
            workout.personalRecordTypes = nil
        }

        // 4. Process workouts chronologically, tracking the best values
        var currentBests: [PersonalRecordType: (value: Double, record: PersonalRecord)] = [:]
        
        for workout in allWorkouts {
            var newPRTypes: [String] = []
            
            // Build metrics to check for this workout
            var metrics: [(type: PersonalRecordType, value: Double?)] = [
                (.mostSteps, Double(workout.steps)),
                (.mostFloors, Double(workout.floors)),
                (.longestDuration, workout.duration),
                (.highestAveragePace, workout.pace),
                (.highestAverageHeartRate, workout.avgHeartRate.map { Double($0) }),
                (.highestMaxHeartRate, workout.maxHeartRate.map { Double($0) }),
                (.mostCaloriesBurned, workout.caloriesBurned.map { Double($0) })
            ]
            
            // Add vertical climb only if there are steps
            if workout.steps > 0 {
                let verticalClimb = workout.totalVerticalClimb(
                    stepHeight: stepHeight,
                    measurementSystem: measurementSystem
                )
                metrics.append((.highestVerticalClimb, verticalClimb))
            }
            
            for (type, optionalValue) in metrics {
                guard let value = optionalValue, value > 0 else { continue }
                
                let previousBest = currentBests[type]
                let isNewRecord = previousBest == nil || value > previousBest!.value
                
                if isNewRecord {
                    // Mark previous record as no longer current
                    if let prev = previousBest?.record {
                        prev.isCurrent = false
                    }
                    
                    // Create new PR
                    let newRecord = PersonalRecord(
                        type: type,
                        value: value,
                        workoutId: workout.id,
                        achievedAt: workout.date,
                        isCurrent: true,
                        previousRecordId: previousBest?.record.id,
                        workoutName: workout.name,
                        workoutDate: workout.date
                    )
                    modelContext.insert(newRecord)
                    
                    // Update tracking
                    currentBests[type] = (value, newRecord)
                    newPRTypes.append(type.rawValue)
                }
            }
            
            // Update workout with its PRs
            if !newPRTypes.isEmpty {
                workout.personalRecordTypes = newPRTypes
            }
        }

        try modelContext.save()

        // Also recalculate weight personal records
        try WeightPersonalRecordService.recalculateAllWeightPersonalRecords(
            modelContext: modelContext,
            measurementSystem: measurementSystem
        )
    }

    private static func currentRecordsByType(
        from records: [PersonalRecord]
    ) -> [PersonalRecordType: PersonalRecord] {
        records.reduce(into: [:]) { result, record in
            guard record.isCurrent else { return }
            result[record.type] = record
        }
    }

    private static func fetchCurrentRecordsByID(
        modelContext: ModelContext
    ) throws -> [UUID: PersonalRecord] {
        try fetchCurrentPersonalRecords(modelContext: modelContext).reduce(into: [:]) { result, record in
            result[record.id] = record
        }
    }
}
