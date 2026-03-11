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

        let currentRecordsByLookup = currentWeightRecordsByLookup(from: allWeightRecords)
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
                currentRecord: currentRecordsByLookup[weightLookupKey(type: .longestDuration, comboKey: comboKey)]
            ))

            // Check steps PR
            results.append(checkWeightRecord(
                type: .mostSteps,
                comboKey: comboKey,
                newValue: Double(workout.steps),
                currentRecord: currentRecordsByLookup[weightLookupKey(type: .mostSteps, comboKey: comboKey)]
            ))

            // Check pace PR
            if let pace = workout.pace {
                results.append(checkWeightRecord(
                    type: .bestPace,
                    comboKey: comboKey,
                    newValue: pace,
                    currentRecord: currentRecordsByLookup[weightLookupKey(type: .bestPace, comboKey: comboKey)]
                ))
            }

            // Check floors PR
            results.append(checkWeightRecord(
                type: .mostFloors,
                comboKey: comboKey,
                newValue: Double(workout.floors),
                currentRecord: currentRecordsByLookup[weightLookupKey(type: .mostFloors, comboKey: comboKey)]
            ))
        }

        return results
    }

    /// Check a specific weight combo record
    private static func checkWeightRecord(
        type: WeightRecordType,
        comboKey: WeightComboKey,
        newValue: Double,
        currentRecord: WeightPersonalRecord?
    ) -> WeightPersonalRecordResult {
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

        let currentRecordsByType = currentAggregateRecordsByType(from: allAggregateRecords)
        var results: [AggregateWeightRecordResult] = []

        // Check heaviest for each equipment type used
        for entry in config.entries where entry.isEnabled {
            let recordType = AggregateWeightRecordType.from(entry.equipmentType)
            results.append(checkAggregateRecord(
                type: recordType,
                newValue: entry.totalWeight,
                currentRecord: currentRecordsByType[recordType]
            ))
        }

        // Check most total weight
        results.append(checkAggregateRecord(
            type: .mostTotalWeight,
            newValue: config.totalWeight,
            currentRecord: currentRecordsByType[.mostTotalWeight]
        ))

        return results
    }

    private static func checkAggregateRecord(
        type: AggregateWeightRecordType,
        newValue: Double,
        currentRecord: AggregateWeightRecord?
    ) -> AggregateWeightRecordResult {
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

        let weightRecordById = try fetchCurrentWeightRecordsByID(modelContext: modelContext)
        let aggregateRecordById = try fetchCurrentAggregateRecordsByID(modelContext: modelContext)

        // Save weight combo PRs
        for result in weightResults where result.isNewRecord {
            if let previousId = result.previousRecordId {
                weightRecordById[previousId]?.isCurrent = false
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

            let prKey = "\(result.weightComboKey.keyString)_\(result.recordType.rawValue)"
            newWeightPRTypes.append(prKey)
        }

        // Save aggregate PRs
        for result in aggregateResults where result.isNewRecord {
            if let previousId = result.previousRecordId {
                aggregateRecordById[previousId]?.isCurrent = false
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

        // 4. Process workouts chronologically, tracking best values and their record objects.
        // By keeping direct references to inserted objects, we avoid per-record
        // SwiftData fetch queries inside the loop.
        var comboBests: [String: [WeightRecordType: (value: Double, record: WeightPersonalRecord)]] = [:]
        var aggregateBests: [AggregateWeightRecordType: (value: Double, record: AggregateWeightRecord)] = [:]

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

                if comboBests[keyString] == nil {
                    comboBests[keyString] = [:]
                }

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
                        // Mark previous record as non-current via direct object reference
                        previousBest?.record.isCurrent = false

                        let newRecord = WeightPersonalRecord(
                            recordType: recordType,
                            weightComboKey: comboKey,
                            value: value,
                            workoutId: workout.id,
                            achievedAt: workout.date,
                            isCurrent: true,
                            previousRecordId: previousBest?.record.id,
                            workoutName: workout.name,
                            workoutDate: workout.date
                        )
                        modelContext.insert(newRecord)

                        comboBests[keyString]?[recordType] = (value, newRecord)
                        newWeightPRTypes.append("\(keyString)_\(recordType.rawValue)")
                    }
                }

                // Check aggregate for this equipment type
                let aggregateType = AggregateWeightRecordType.from(entry.equipmentType)
                let totalWeight = entry.totalWeight
                let prevAggregate = aggregateBests[aggregateType]

                if prevAggregate == nil || totalWeight > prevAggregate!.value {
                    // Mark previous record as non-current via direct object reference
                    prevAggregate?.record.isCurrent = false

                    let newRecord = AggregateWeightRecord(
                        recordType: aggregateType,
                        value: totalWeight,
                        workoutId: workout.id,
                        achievedAt: workout.date,
                        isCurrent: true,
                        previousRecordId: prevAggregate?.record.id,
                        workoutName: workout.name,
                        workoutDate: workout.date
                    )
                    modelContext.insert(newRecord)

                    aggregateBests[aggregateType] = (totalWeight, newRecord)
                    newWeightPRTypes.append(aggregateType.rawValue)
                }
            }

            // Check most total weight
            let totalWeight = config.totalWeight
            let prevTotal = aggregateBests[.mostTotalWeight]

            if prevTotal == nil || totalWeight > prevTotal!.value {
                prevTotal?.record.isCurrent = false

                let newRecord = AggregateWeightRecord(
                    recordType: .mostTotalWeight,
                    value: totalWeight,
                    workoutId: workout.id,
                    achievedAt: workout.date,
                    isCurrent: true,
                    previousRecordId: prevTotal?.record.id,
                    workoutName: workout.name,
                    workoutDate: workout.date
                )
                modelContext.insert(newRecord)

                aggregateBests[.mostTotalWeight] = (totalWeight, newRecord)
                newWeightPRTypes.append(AggregateWeightRecordType.mostTotalWeight.rawValue)
            }

            // Update workout with its weight PRs
            if !newWeightPRTypes.isEmpty {
                workout.weightPersonalRecordTypes = newWeightPRTypes
            }
        }

        // Single save for all deletions, insertions, and updates
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

    private static func currentWeightRecordsByLookup(
        from records: [WeightPersonalRecord]
    ) -> [String: WeightPersonalRecord] {
        records.reduce(into: [:]) { result, record in
            guard record.isCurrent else { return }
            result[weightLookupKey(type: record.recordType, comboKeyString: record.weightComboKey)] = record
        }
    }

    private static func currentAggregateRecordsByType(
        from records: [AggregateWeightRecord]
    ) -> [AggregateWeightRecordType: AggregateWeightRecord] {
        records.reduce(into: [:]) { result, record in
            guard record.isCurrent else { return }
            result[record.recordType] = record
        }
    }

    private static func fetchCurrentWeightRecordsByID(
        modelContext: ModelContext
    ) throws -> [UUID: WeightPersonalRecord] {
        try fetchCurrentWeightPersonalRecords(modelContext: modelContext).reduce(into: [:]) { result, record in
            result[record.id] = record
        }
    }

    private static func fetchCurrentAggregateRecordsByID(
        modelContext: ModelContext
    ) throws -> [UUID: AggregateWeightRecord] {
        try fetchCurrentAggregateRecords(modelContext: modelContext).reduce(into: [:]) { result, record in
            result[record.id] = record
        }
    }

    private static func weightLookupKey(type: WeightRecordType, comboKey: WeightComboKey) -> String {
        weightLookupKey(type: type, comboKeyString: comboKey.keyString)
    }

    private static func weightLookupKey(type: WeightRecordType, comboKeyString: String) -> String {
        "\(comboKeyString)_\(type.rawValue)"
    }
}
