//
//  WeightPersonalRecordService.swift
//  AscendApp
//
//  Created by Claude on 1/9/26.
//

import Foundation
import SwiftData

/// Service for checking and recording weight-based personal records
final class WeightPersonalRecordService {

    // MARK: - Weight Combo PRs

    /// Check a workout for weight-combo personal records
    static func checkForWeightPersonalRecords(
        workout: Workout,
        allWeightRecords: [WeightPersonalRecord],
        measurementSystem: MeasurementSystem
    ) -> [WeightPersonalRecordResult] {
        guard let config = workout.weightConfiguration, !config.isEmpty else {
            return []
        }

        var results: [WeightPersonalRecordResult] = []

        // For each enabled weight entry, check all 4 metrics
        for entry in config.entries where entry.isEnabled {
            let comboKey = WeightComboKey(
                equipmentType: entry.equipmentType,
                weightValue: entry.weightValue
            )

            // Check duration PR
            results.append(checkWeightRecord(
                type: .longestDuration,
                comboKey: comboKey,
                newValue: workout.duration,
                currentRecords: allWeightRecords
            ))

            // Check steps PR
            results.append(checkWeightRecord(
                type: .mostSteps,
                comboKey: comboKey,
                newValue: Double(workout.steps),
                currentRecords: allWeightRecords
            ))

            // Check pace PR
            if let pace = workout.pace {
                results.append(checkWeightRecord(
                    type: .bestPace,
                    comboKey: comboKey,
                    newValue: pace,
                    currentRecords: allWeightRecords
                ))
            }

            // Check floors PR
            results.append(checkWeightRecord(
                type: .mostFloors,
                comboKey: comboKey,
                newValue: Double(workout.floors),
                currentRecords: allWeightRecords
            ))
        }

        return results
    }

    /// Check a specific weight combo record
    private static func checkWeightRecord(
        type: WeightRecordType,
        comboKey: WeightComboKey,
        newValue: Double,
        currentRecords: [WeightPersonalRecord]
    ) -> WeightPersonalRecordResult {
        let keyString = comboKey.keyString

        let currentRecord = currentRecords.first { record in
            record.recordType == type &&
            record.weightComboKey == keyString &&
            record.isCurrent
        }

        if let current = currentRecord {
            let isNewRecord = newValue > current.value
            return WeightPersonalRecordResult(
                recordType: type,
                weightComboKey: comboKey,
                newValue: newValue,
                previousValue: current.value,
                previousRecordId: current.id,
                isNewRecord: isNewRecord
            )
        } else {
            // No existing record for this combo - new PR
            return WeightPersonalRecordResult(
                recordType: type,
                weightComboKey: comboKey,
                newValue: newValue,
                previousValue: nil,
                previousRecordId: nil,
                isNewRecord: true
            )
        }
    }

    // MARK: - Aggregate Weight Records

    /// Check for aggregate weight records (heaviest per type, most total)
    static func checkForAggregateWeightRecords(
        workout: Workout,
        allAggregateRecords: [AggregateWeightRecord],
        measurementSystem: MeasurementSystem
    ) -> [AggregateWeightRecordResult] {
        guard let config = workout.weightConfiguration, !config.isEmpty else {
            return []
        }

        var results: [AggregateWeightRecordResult] = []

        // Check heaviest for each equipment type used
        for entry in config.entries where entry.isEnabled {
            let recordType = AggregateWeightRecordType.from(entry.equipmentType)
            results.append(checkAggregateRecord(
                type: recordType,
                newValue: entry.totalWeight,
                currentRecords: allAggregateRecords
            ))
        }

        // Check most total weight
        results.append(checkAggregateRecord(
            type: .mostTotalWeight,
            newValue: config.totalWeight,
            currentRecords: allAggregateRecords
        ))

        return results
    }

    private static func checkAggregateRecord(
        type: AggregateWeightRecordType,
        newValue: Double,
        currentRecords: [AggregateWeightRecord]
    ) -> AggregateWeightRecordResult {
        let currentRecord = currentRecords.first { $0.recordType == type && $0.isCurrent }

        if let current = currentRecord {
            let isNewRecord = newValue > current.value
            return AggregateWeightRecordResult(
                recordType: type,
                newValue: newValue,
                previousValue: current.value,
                previousRecordId: current.id,
                isNewRecord: isNewRecord
            )
        } else {
            return AggregateWeightRecordResult(
                recordType: type,
                newValue: newValue,
                previousValue: nil,
                previousRecordId: nil,
                isNewRecord: true
            )
        }
    }

    // MARK: - Save Records

    /// Save weight personal records after workout is logged
    static func saveWeightPersonalRecords(
        weightResults: [WeightPersonalRecordResult],
        aggregateResults: [AggregateWeightRecordResult],
        workout: Workout,
        modelContext: ModelContext
    ) throws {
        var newWeightPRTypes: [String] = []

        // Save weight combo PRs
        for result in weightResults where result.isNewRecord {
            if let previousId = result.previousRecordId {
                let descriptor = FetchDescriptor<WeightPersonalRecord>(
                    predicate: #Predicate<WeightPersonalRecord> { $0.id == previousId }
                )
                if let previousRecord = try modelContext.fetch(descriptor).first {
                    previousRecord.isCurrent = false
                }
            }

            let newRecord = WeightPersonalRecord(
                recordType: result.recordType,
                weightComboKey: result.weightComboKey,
                value: result.newValue,
                workoutId: workout.id,
                achievedAt: Date(),
                isCurrent: true,
                previousRecordId: result.previousRecordId,
                workoutName: workout.name,
                workoutDate: workout.date
            )
            modelContext.insert(newRecord)

            // Track for workout annotation
            let prKey = "\(result.weightComboKey.keyString)_\(result.recordType.rawValue)"
            newWeightPRTypes.append(prKey)
        }

        // Save aggregate PRs
        for result in aggregateResults where result.isNewRecord {
            if let previousId = result.previousRecordId {
                let descriptor = FetchDescriptor<AggregateWeightRecord>(
                    predicate: #Predicate<AggregateWeightRecord> { $0.id == previousId }
                )
                if let previousRecord = try modelContext.fetch(descriptor).first {
                    previousRecord.isCurrent = false
                }
            }

            let newRecord = AggregateWeightRecord(
                recordType: result.recordType,
                value: result.newValue,
                workoutId: workout.id,
                achievedAt: Date(),
                isCurrent: true,
                previousRecordId: result.previousRecordId,
                workoutName: workout.name,
                workoutDate: workout.date
            )
            modelContext.insert(newRecord)

            newWeightPRTypes.append(result.recordType.rawValue)
        }

        // Update workout with achieved weight PRs
        if !newWeightPRTypes.isEmpty {
            workout.weightPersonalRecordTypes = newWeightPRTypes
        }

        try modelContext.save()
    }

    // MARK: - Recalculation

    /// Recalculate all weight personal records from scratch
    static func recalculateAllWeightPersonalRecords(
        modelContext: ModelContext,
        measurementSystem: MeasurementSystem
    ) throws {
        // 1. Fetch all workouts sorted by date (oldest first)
        let workoutDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let allWorkouts = try modelContext.fetch(workoutDescriptor)

        // 2. Delete all existing weight records
        let weightPRDescriptor = FetchDescriptor<WeightPersonalRecord>()
        let existingWeightPRs = try modelContext.fetch(weightPRDescriptor)
        for pr in existingWeightPRs {
            modelContext.delete(pr)
        }

        let aggregateDescriptor = FetchDescriptor<AggregateWeightRecord>()
        let existingAggregatePRs = try modelContext.fetch(aggregateDescriptor)
        for pr in existingAggregatePRs {
            modelContext.delete(pr)
        }

        // 3. Clear weight PR types from all workouts
        for workout in allWorkouts {
            workout.weightPersonalRecordTypes = nil
        }

        try modelContext.save()

        // 4. Process workouts chronologically
        // Track best values per combo key per record type
        var comboBests: [String: [WeightRecordType: (value: Double, recordId: UUID)]] = [:]
        var aggregateBests: [AggregateWeightRecordType: (value: Double, recordId: UUID)] = [:]

        for workout in allWorkouts {
            guard let config = workout.weightConfiguration, !config.isEmpty else {
                continue
            }

            var newWeightPRTypes: [String] = []

            // Process each weight entry
            for entry in config.entries where entry.isEnabled {
                let comboKey = WeightComboKey(
                    equipmentType: entry.equipmentType,
                    weightValue: entry.weightValue
                )
                let keyString = comboKey.keyString

                // Ensure we have a dictionary for this combo
                if comboBests[keyString] == nil {
                    comboBests[keyString] = [:]
                }

                // Check each metric type
                let metrics: [(WeightRecordType, Double?)] = [
                    (.longestDuration, workout.duration),
                    (.mostSteps, Double(workout.steps)),
                    (.bestPace, workout.pace),
                    (.mostFloors, Double(workout.floors))
                ]

                for (recordType, optionalValue) in metrics {
                    guard let value = optionalValue, value > 0 else { continue }

                    let previousBest = comboBests[keyString]?[recordType]
                    let isNewRecord = previousBest == nil || value > previousBest!.value

                    if isNewRecord {
                        // Mark previous as non-current
                        if let prevId = previousBest?.recordId {
                            let descriptor = FetchDescriptor<WeightPersonalRecord>(
                                predicate: #Predicate<WeightPersonalRecord> { $0.id == prevId }
                            )
                            if let prevRecord = try modelContext.fetch(descriptor).first {
                                prevRecord.isCurrent = false
                            }
                        }

                        // Create new record
                        let newRecord = WeightPersonalRecord(
                            recordType: recordType,
                            weightComboKey: comboKey,
                            value: value,
                            workoutId: workout.id,
                            achievedAt: workout.date,
                            isCurrent: true,
                            previousRecordId: previousBest?.recordId,
                            workoutName: workout.name,
                            workoutDate: workout.date
                        )
                        modelContext.insert(newRecord)

                        comboBests[keyString]?[recordType] = (value, newRecord.id)
                        newWeightPRTypes.append("\(keyString)_\(recordType.rawValue)")
                    }
                }

                // Check aggregate for this equipment type
                let aggregateType = AggregateWeightRecordType.from(entry.equipmentType)
                let totalWeight = entry.totalWeight
                let prevAggregate = aggregateBests[aggregateType]

                if prevAggregate == nil || totalWeight > prevAggregate!.value {
                    if let prevId = prevAggregate?.recordId {
                        let descriptor = FetchDescriptor<AggregateWeightRecord>(
                            predicate: #Predicate<AggregateWeightRecord> { $0.id == prevId }
                        )
                        if let prevRecord = try modelContext.fetch(descriptor).first {
                            prevRecord.isCurrent = false
                        }
                    }

                    let newRecord = AggregateWeightRecord(
                        recordType: aggregateType,
                        value: totalWeight,
                        workoutId: workout.id,
                        achievedAt: workout.date,
                        isCurrent: true,
                        previousRecordId: prevAggregate?.recordId,
                        workoutName: workout.name,
                        workoutDate: workout.date
                    )
                    modelContext.insert(newRecord)

                    aggregateBests[aggregateType] = (totalWeight, newRecord.id)
                    newWeightPRTypes.append(aggregateType.rawValue)
                }
            }

            // Check most total weight
            let totalWeight = config.totalWeight
            let prevTotal = aggregateBests[.mostTotalWeight]

            if prevTotal == nil || totalWeight > prevTotal!.value {
                if let prevId = prevTotal?.recordId {
                    let descriptor = FetchDescriptor<AggregateWeightRecord>(
                        predicate: #Predicate<AggregateWeightRecord> { $0.id == prevId }
                    )
                    if let prevRecord = try modelContext.fetch(descriptor).first {
                        prevRecord.isCurrent = false
                    }
                }

                let newRecord = AggregateWeightRecord(
                    recordType: .mostTotalWeight,
                    value: totalWeight,
                    workoutId: workout.id,
                    achievedAt: workout.date,
                    isCurrent: true,
                    previousRecordId: prevTotal?.recordId,
                    workoutName: workout.name,
                    workoutDate: workout.date
                )
                modelContext.insert(newRecord)

                aggregateBests[.mostTotalWeight] = (totalWeight, newRecord.id)
                newWeightPRTypes.append(AggregateWeightRecordType.mostTotalWeight.rawValue)
            }

            // Update workout with its weight PRs
            if !newWeightPRTypes.isEmpty {
                workout.weightPersonalRecordTypes = newWeightPRTypes
            }
        }

        try modelContext.save()
    }

    // MARK: - Fetch Methods

    static func fetchCurrentWeightPersonalRecords(modelContext: ModelContext) throws -> [WeightPersonalRecord] {
        let descriptor = FetchDescriptor<WeightPersonalRecord>(
            predicate: #Predicate<WeightPersonalRecord> { $0.isCurrent == true }
        )
        return try modelContext.fetch(descriptor)
    }

    static func fetchCurrentAggregateRecords(modelContext: ModelContext) throws -> [AggregateWeightRecord] {
        let descriptor = FetchDescriptor<AggregateWeightRecord>(
            predicate: #Predicate<AggregateWeightRecord> { $0.isCurrent == true }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all weight PRs for a specific combo key
    static func fetchWeightRecords(
        forComboKey keyString: String,
        modelContext: ModelContext
    ) throws -> [WeightPersonalRecord] {
        let descriptor = FetchDescriptor<WeightPersonalRecord>(
            predicate: #Predicate<WeightPersonalRecord> { $0.weightComboKey == keyString },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all weight PRs for a specific workout
    static func fetchWeightRecords(
        forWorkout workoutId: UUID,
        modelContext: ModelContext
    ) throws -> [WeightPersonalRecord] {
        let descriptor = FetchDescriptor<WeightPersonalRecord>(
            predicate: #Predicate<WeightPersonalRecord> { $0.workoutId == workoutId }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all aggregate records for a specific workout
    static func fetchAggregateRecords(
        forWorkout workoutId: UUID,
        modelContext: ModelContext
    ) throws -> [AggregateWeightRecord] {
        let descriptor = FetchDescriptor<AggregateWeightRecord>(
            predicate: #Predicate<AggregateWeightRecord> { $0.workoutId == workoutId }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all weight records (including historical) for progression tracking
    static func fetchAllWeightRecords(
        forComboKey keyString: String,
        recordType: WeightRecordType,
        modelContext: ModelContext
    ) throws -> [WeightPersonalRecord] {
        let descriptor = FetchDescriptor<WeightPersonalRecord>(
            predicate: #Predicate<WeightPersonalRecord> {
                $0.weightComboKey == keyString && $0.recordType == recordType
            },
            sortBy: [SortDescriptor(\.achievedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
}
