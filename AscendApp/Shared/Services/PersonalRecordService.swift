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
        var results: [PersonalRecordResult] = []
        
        // Check steps PR
        if let steps = workout.steps {
            let result = checkRecord(
                type: .mostSteps,
                newValue: Double(steps),
                currentRecords: allPersonalRecords
            )
            results.append(result)
        }
        
        // Check floors PR
        if let floors = workout.floors {
            let result = checkRecord(
                type: .mostFloors,
                newValue: Double(floors),
                currentRecords: allPersonalRecords
            )
            results.append(result)
        }
        
        // Check duration PR
        let result = checkRecord(
            type: .longestDuration,
            newValue: workout.duration,
            currentRecords: allPersonalRecords
        )
        results.append(result)
        
        // Check pace PR
        if let pace = workout.pace {
            let result = checkRecord(
                type: .highestAveragePace,
                newValue: pace,
                currentRecords: allPersonalRecords
            )
            results.append(result)
        }
        
        // Check vertical climb PR
        if let verticalClimb = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        ) {
            let result = checkRecord(
                type: .highestVerticalClimb,
                newValue: verticalClimb,
                currentRecords: allPersonalRecords
            )
            results.append(result)
        }
        
        // Check average heart rate PR
        if let avgHR = workout.avgHeartRate {
            let result = checkRecord(
                type: .highestAverageHeartRate,
                newValue: Double(avgHR),
                currentRecords: allPersonalRecords
            )
            results.append(result)
        }
        
        // Check max heart rate PR
        if let maxHR = workout.maxHeartRate {
            let result = checkRecord(
                type: .highestMaxHeartRate,
                newValue: Double(maxHR),
                currentRecords: allPersonalRecords
            )
            results.append(result)
        }
        
        // Check calories burned PR
        if let calories = workout.caloriesBurned {
            let result = checkRecord(
                type: .mostCaloriesBurned,
                newValue: Double(calories),
                currentRecords: allPersonalRecords
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
        for result in results where result.isNewRecord {
            // If there was a previous record, mark it as no longer current
            if let previousId = result.previousRecordId {
                let descriptor = FetchDescriptor<PersonalRecord>(
                    predicate: #Predicate<PersonalRecord> { record in
                        record.id == previousId
                    }
                )
                if let previousRecord = try modelContext.fetch(descriptor).first {
                    previousRecord.isCurrent = false
                }
            }
            
            // Create the new personal record
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
        currentRecords: [PersonalRecord]
    ) -> PersonalRecordResult {
        // Find the current record for this type
        let currentRecord = currentRecords.first { record in
            record.type == type && record.isCurrent
        }
        
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
}

