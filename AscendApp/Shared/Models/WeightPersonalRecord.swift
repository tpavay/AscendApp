//
//  WeightPersonalRecord.swift
//  AscendApp
//
//  Created by Claude on 1/9/26.
//

import Foundation
import SwiftData

// MARK: - Weight Record Types

/// Represents the type of weight-based personal record for a specific weight combo
enum WeightRecordType: String, CaseIterable, Codable {
    case longestDuration = "weight_longest_duration"
    case mostSteps = "weight_most_steps"
    case bestPace = "weight_best_pace"
    case mostFloors = "weight_most_floors"

    var displayName: String {
        switch self {
        case .longestDuration: return "Longest Duration"
        case .mostSteps: return "Most Steps"
        case .bestPace: return "Best Pace"
        case .mostFloors: return "Most Floors"
        }
    }

    var emoji: String {
        switch self {
        case .longestDuration: return "⏱️"
        case .mostSteps: return "👟"
        case .bestPace: return "⚡"
        case .mostFloors: return "🪜"
        }
    }

    var iconName: String {
        switch self {
        case .longestDuration: return "clock"
        case .mostSteps: return "figure.walk"
        case .bestPace: return "bolt.fill"
        case .mostFloors: return "stairs"
        }
    }
}

/// Represents aggregate weight records (not tied to specific weight combo)
enum AggregateWeightRecordType: String, CaseIterable, Codable {
    case heaviestVest = "heaviest_vest"
    case heaviestDumbbells = "heaviest_dumbbells"
    case heaviestBarbell = "heaviest_barbell"
    case heaviestAnkleWeights = "heaviest_ankle"
    case heaviestWristWeights = "heaviest_wrist"
    case mostTotalWeight = "most_total_weight"

    var displayName: String {
        switch self {
        case .heaviestVest: return "Heaviest Vest"
        case .heaviestDumbbells: return "Heaviest Dumbbells"
        case .heaviestBarbell: return "Heaviest Barbell"
        case .heaviestAnkleWeights: return "Heaviest Ankle Weights"
        case .heaviestWristWeights: return "Heaviest Wrist Weights"
        case .mostTotalWeight: return "Most Total Weight"
        }
    }

    var emoji: String {
        switch self {
        case .heaviestVest: return "🦺"
        case .heaviestDumbbells: return "🏋️"
        case .heaviestBarbell: return "🏋️"
        case .heaviestAnkleWeights: return "🦶"
        case .heaviestWristWeights: return "✋"
        case .mostTotalWeight: return "⚖️"
        }
    }

    var iconName: String {
        switch self {
        case .heaviestVest: return "weight-vest"
        case .heaviestDumbbells: return "weight-dumbbells"
        case .heaviestBarbell: return "weight-barbell"
        case .heaviestAnkleWeights: return "weight-ankle"
        case .heaviestWristWeights: return "weight-wrist"
        case .mostTotalWeight: return "scalemass.fill"
        }
    }

    /// Map to equipment type (nil for mostTotalWeight)
    var equipmentType: WeightEquipmentType? {
        switch self {
        case .heaviestVest: return .weightedVest
        case .heaviestDumbbells: return .dumbbells
        case .heaviestBarbell: return .barbell
        case .heaviestAnkleWeights: return .ankleWeights
        case .heaviestWristWeights: return .wristWeights
        case .mostTotalWeight: return nil
        }
    }

    /// Create from equipment type
    static func from(_ equipmentType: WeightEquipmentType) -> AggregateWeightRecordType {
        switch equipmentType {
        case .weightedVest: return .heaviestVest
        case .dumbbells: return .heaviestDumbbells
        case .barbell: return .heaviestBarbell
        case .ankleWeights: return .heaviestAnkleWeights
        case .wristWeights: return .heaviestWristWeights
        }
    }
}

// MARK: - Weight Combo Key

/// Key structure for unique weight combo identification (equipment type + weight amount)
struct WeightComboKey: Codable, Hashable, Equatable {
    let equipmentType: WeightEquipmentType
    let weightValue: Double  // Per-item weight (not doubled for paired equipment)

    /// Canonical string key for storage/lookup
    var keyString: String {
        let weightStr = weightValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weightValue)
            : String(format: "%.1f", weightValue)
        return "\(equipmentType.rawValue)_\(weightStr)"
    }

    /// User-friendly display (e.g., "40 lb Vest")
    func displayName(unit: String) -> String {
        let weightStr = weightValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weightValue)
            : String(format: "%.1f", weightValue)
        return "\(weightStr) \(unit) \(equipmentType.shortDescription)"
    }

    /// Short display (e.g., "40 lb")
    func shortDisplayName(unit: String) -> String {
        let weightStr = weightValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weightValue)
            : String(format: "%.1f", weightValue)
        return "\(weightStr) \(unit)"
    }
}

// MARK: - Weight Personal Record Model

/// Weight-based personal record entry for a specific weight combo
@Model
class WeightPersonalRecord {
    var id: UUID
    var recordType: WeightRecordType
    var weightComboKey: String  // Stored as keyString for querying
    var equipmentType: WeightEquipmentType
    var weightValue: Double
    var value: Double           // The record value (duration, steps, pace, floors)
    var workoutId: UUID
    var achievedAt: Date
    var isCurrent: Bool
    var previousRecordId: UUID?

    // Metadata for display
    var workoutName: String
    var workoutDate: Date

    init(
        recordType: WeightRecordType,
        weightComboKey: WeightComboKey,
        value: Double,
        workoutId: UUID,
        achievedAt: Date = Date(),
        isCurrent: Bool = true,
        previousRecordId: UUID? = nil,
        workoutName: String,
        workoutDate: Date
    ) {
        self.id = UUID()
        self.recordType = recordType
        self.weightComboKey = weightComboKey.keyString
        self.equipmentType = weightComboKey.equipmentType
        self.weightValue = weightComboKey.weightValue
        self.value = value
        self.workoutId = workoutId
        self.achievedAt = achievedAt
        self.isCurrent = isCurrent
        self.previousRecordId = previousRecordId
        self.workoutName = workoutName
        self.workoutDate = workoutDate
    }

    /// Reconstruct the WeightComboKey
    var comboKey: WeightComboKey {
        WeightComboKey(equipmentType: equipmentType, weightValue: weightValue)
    }

    /// Formatted value for display
    func formattedValue(measurementSystem: MeasurementSystem) -> String {
        switch recordType {
        case .mostSteps, .mostFloors:
            return formatInteger(Int(value))
        case .longestDuration:
            return formatDuration(value)
        case .bestPace:
            return String(format: "%.1f/min", value)
        }
    }

    private func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatDuration(_ seconds: Double) -> String {
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

// MARK: - Aggregate Weight Record Model

/// Aggregate weight record (heaviest per equipment type, most total weight)
@Model
class AggregateWeightRecord {
    var id: UUID
    var recordType: AggregateWeightRecordType
    var value: Double           // Weight value
    var workoutId: UUID
    var achievedAt: Date
    var isCurrent: Bool
    var previousRecordId: UUID?
    var workoutName: String
    var workoutDate: Date

    init(
        recordType: AggregateWeightRecordType,
        value: Double,
        workoutId: UUID,
        achievedAt: Date = Date(),
        isCurrent: Bool = true,
        previousRecordId: UUID? = nil,
        workoutName: String,
        workoutDate: Date
    ) {
        self.id = UUID()
        self.recordType = recordType
        self.value = value
        self.workoutId = workoutId
        self.achievedAt = achievedAt
        self.isCurrent = isCurrent
        self.previousRecordId = previousRecordId
        self.workoutName = workoutName
        self.workoutDate = workoutDate
    }

    /// Formatted value for display
    func formattedValue(measurementSystem: MeasurementSystem) -> String {
        let unit = measurementSystem.weightAbbreviation
        let valueStr = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(valueStr) \(unit)"
    }
}

// MARK: - Result Types

/// Result of checking for weight PRs in a workout
struct WeightPersonalRecordResult {
    let recordType: WeightRecordType
    let weightComboKey: WeightComboKey
    let newValue: Double
    let previousValue: Double?
    let previousRecordId: UUID?
    let isNewRecord: Bool

    var improvement: Double? {
        guard let prev = previousValue else { return nil }
        return newValue - prev
    }

    var improvementPercentage: Double? {
        guard let prev = previousValue, prev > 0 else { return nil }
        return ((newValue - prev) / prev) * 100
    }
}

/// Result of checking for aggregate weight records
struct AggregateWeightRecordResult {
    let recordType: AggregateWeightRecordType
    let newValue: Double
    let previousValue: Double?
    let previousRecordId: UUID?
    let isNewRecord: Bool

    var improvement: Double? {
        guard let prev = previousValue else { return nil }
        return newValue - prev
    }

    var improvementPercentage: Double? {
        guard let prev = previousValue, prev > 0 else { return nil }
        return ((newValue - prev) / prev) * 100
    }
}
