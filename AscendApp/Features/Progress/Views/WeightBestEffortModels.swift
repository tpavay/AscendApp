//
//  WeightBestEffortModels.swift
//  AscendApp
//
//  Created by Claude on 1/9/26.
//

import Foundation

// MARK: - Weight Best Effort UI Models

/// Represents a weight-based best effort for UI display
struct WeightBestEffort: Identifiable {
    let id = UUID()
    let comboKey: WeightComboKey
    let recordType: WeightRecordType
    let title: String           // "Longest Duration"
    let valueText: String       // "45:30"
    let detailText: String      // "Dec 15, 2025"
    let date: Date
    let workout: Workout
    let iconName: String
}

/// Represents an aggregate weight record for UI
struct AggregateWeightBestEffort: Identifiable {
    let id = UUID()
    let recordType: AggregateWeightRecordType
    let title: String           // "Heaviest Vest"
    let valueText: String       // "40 lb"
    let detailText: String      // "Dec 15, 2025"
    let date: Date
    let workout: Workout
    let iconName: String
}

/// Groups weight PRs by equipment type for organized display
struct WeightRecordsSection: Identifiable {
    let id: String              // Equipment type raw value
    let equipmentType: WeightEquipmentType
    let title: String           // "Weighted Vest Records"
    let iconName: String
    let weightCombos: [WeightComboSection]
}

struct WeightComboSection: Identifiable {
    let id: String              // Combo key string
    let displayName: String     // "40 lb"
    let records: [WeightBestEffort]
}

/// Data point for weight PR progression charts
struct WeightProgressionDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let workout: Workout
}

// MARK: - Builder

struct WeightBestEffortsBuilder {

    /// Build weight records sections organized by equipment type
    static func buildWeightRecordsSections(
        from weightRecords: [WeightPersonalRecord],
        workouts: [Workout],
        measurementSystem: MeasurementSystem
    ) -> [WeightRecordsSection] {
        // Filter to current records only
        let currentRecords = weightRecords.filter { $0.isCurrent }

        // Create lookup for workouts
        let workoutLookup = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })

        // Group by equipment type, then by weight combo
        var sectionsByType: [WeightEquipmentType: [WeightComboKey: [WeightPersonalRecord]]] = [:]

        for record in currentRecords {
            let type = record.equipmentType
            let comboKey = record.comboKey

            if sectionsByType[type] == nil {
                sectionsByType[type] = [:]
            }
            if sectionsByType[type]![comboKey] == nil {
                sectionsByType[type]![comboKey] = []
            }
            sectionsByType[type]![comboKey]!.append(record)
        }

        // Build sections
        var sections: [WeightRecordsSection] = []

        for type in WeightEquipmentType.allCases {
            guard let comboDict = sectionsByType[type], !comboDict.isEmpty else { continue }

            var comboSections: [WeightComboSection] = []

            // Sort combos by weight (heaviest first)
            let sortedCombos = comboDict.keys.sorted { $0.weightValue > $1.weightValue }

            for comboKey in sortedCombos {
                guard let records = comboDict[comboKey] else { continue }

                let efforts = records.compactMap { record -> WeightBestEffort? in
                    guard let workout = workoutLookup[record.workoutId] else { return nil }

                    return WeightBestEffort(
                        comboKey: comboKey,
                        recordType: record.recordType,
                        title: record.recordType.displayName,
                        valueText: record.formattedValue(measurementSystem: measurementSystem),
                        detailText: formatDate(record.workoutDate),
                        date: record.workoutDate,
                        workout: workout,
                        iconName: record.recordType.iconName
                    )
                }

                if !efforts.isEmpty {
                    let unit = measurementSystem.weightAbbreviation
                    comboSections.append(WeightComboSection(
                        id: comboKey.keyString,
                        displayName: comboKey.shortDisplayName(unit: unit),
                        records: efforts.sorted { $0.recordType.rawValue < $1.recordType.rawValue }
                    ))
                }
            }

            if !comboSections.isEmpty {
                sections.append(WeightRecordsSection(
                    id: type.rawValue,
                    equipmentType: type,
                    title: "\(type.displayName) Records",
                    iconName: type.iconName,
                    weightCombos: comboSections
                ))
            }
        }

        return sections
    }

    /// Build aggregate efforts (heaviest per type, most total)
    static func buildAggregateEfforts(
        from aggregateRecords: [AggregateWeightRecord],
        workouts: [Workout],
        measurementSystem: MeasurementSystem
    ) -> [AggregateWeightBestEffort] {
        let currentRecords = aggregateRecords.filter { $0.isCurrent }
        let workoutLookup = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })

        return currentRecords.compactMap { record -> AggregateWeightBestEffort? in
            guard let workout = workoutLookup[record.workoutId] else { return nil }

            return AggregateWeightBestEffort(
                recordType: record.recordType,
                title: record.recordType.displayName,
                valueText: record.formattedValue(measurementSystem: measurementSystem),
                detailText: formatDate(record.workoutDate),
                date: record.workoutDate,
                workout: workout,
                iconName: record.recordType.iconName
            )
        }.sorted { $0.recordType.rawValue < $1.recordType.rawValue }
    }

    /// Build progression data for a specific weight combo and record type
    static func buildProgressionData(
        from weightRecords: [WeightPersonalRecord],
        comboKey: WeightComboKey,
        recordType: WeightRecordType,
        workouts: [Workout]
    ) -> [WeightProgressionDataPoint] {
        let workoutLookup = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        let keyString = comboKey.keyString

        // Filter to this combo and type, then sort by date
        let relevantRecords = weightRecords
            .filter { $0.weightComboKey == keyString && $0.recordType == recordType }
            .sorted { $0.achievedAt < $1.achievedAt }

        return relevantRecords.compactMap { record -> WeightProgressionDataPoint? in
            guard let workout = workoutLookup[record.workoutId] else { return nil }

            return WeightProgressionDataPoint(
                date: record.achievedAt,
                value: record.value,
                workout: workout
            )
        }
    }

    /// Build progression data for aggregate records
    static func buildAggregateProgressionData(
        from aggregateRecords: [AggregateWeightRecord],
        recordType: AggregateWeightRecordType,
        workouts: [Workout]
    ) -> [WeightProgressionDataPoint] {
        let workoutLookup = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })

        // Filter to this type, then sort by date
        let relevantRecords = aggregateRecords
            .filter { $0.recordType == recordType }
            .sorted { $0.achievedAt < $1.achievedAt }

        return relevantRecords.compactMap { record -> WeightProgressionDataPoint? in
            guard let workout = workoutLookup[record.workoutId] else { return nil }

            return WeightProgressionDataPoint(
                date: record.achievedAt,
                value: record.value,
                workout: workout
            )
        }
    }

    /// Get all unique weight combos from records
    static func getAllWeightCombos(from records: [WeightPersonalRecord]) -> [WeightComboKey] {
        let currentRecords = records.filter { $0.isCurrent }
        var uniqueCombos: [String: WeightComboKey] = [:]

        for record in currentRecords {
            let key = record.weightComboKey
            if uniqueCombos[key] == nil {
                uniqueCombos[key] = record.comboKey
            }
        }

        // Sort by equipment type, then by weight
        return uniqueCombos.values.sorted { lhs, rhs in
            if lhs.equipmentType.rawValue == rhs.equipmentType.rawValue {
                return lhs.weightValue > rhs.weightValue
            }
            return lhs.equipmentType.rawValue < rhs.equipmentType.rawValue
        }
    }

    // MARK: - Formatting Helpers

    private static func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return dateFormatter.string(from: date)
    }

    static func formatRecordValue(
        _ value: Double,
        recordType: WeightRecordType,
        measurementSystem: MeasurementSystem
    ) -> String {
        switch recordType {
        case .mostSteps, .mostFloors:
            return formatNumber(Int(value))
        case .longestDuration:
            return formatDuration(value)
        case .bestPace:
            return String(format: "%.1f/min", value)
        }
    }

    private static func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
