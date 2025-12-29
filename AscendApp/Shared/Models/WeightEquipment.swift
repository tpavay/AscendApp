//
//  WeightEquipment.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/29/25.
//

import Foundation

/// Types of weight equipment that can be used during workouts
enum WeightEquipmentType: String, Codable, CaseIterable, Identifiable {
    case weightedVest = "weighted_vest"
    case dumbbells = "dumbbells"
    case barbell = "barbell"
    case ankleWeights = "ankle_weights"
    case wristWeights = "wrist_weights"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightedVest: return "Weighted Vest"
        case .dumbbells: return "Dumbbells"
        case .barbell: return "Barbell"
        case .ankleWeights: return "Ankle Weights"
        case .wristWeights: return "Wrist Weights"
        }
    }

    /// Icon asset name for this equipment type
    var iconName: String {
        switch self {
        case .weightedVest: return "weight-vest"
        case .dumbbells: return "weight-dumbbells"
        case .barbell: return "weight-barbell"
        case .ankleWeights: return "weight-ankle"
        case .wristWeights: return "weight-wrist"
        }
    }

    /// Whether this equipment type comes in pairs (ankle weights, wrist weights)
    var isPaired: Bool {
        switch self {
        case .ankleWeights, .wristWeights:
            return true
        case .weightedVest, .dumbbells, .barbell:
            return false
        }
    }

    /// Description for how weight is measured
    var weightDescription: String {
        isPaired ? "each" : "total"
    }

    /// Short description for display in compact contexts
    var shortDescription: String {
        switch self {
        case .weightedVest: return "Vest"
        case .dumbbells: return "Dumbbells"
        case .barbell: return "Barbell"
        case .ankleWeights: return "Ankle"
        case .wristWeights: return "Wrist"
        }
    }
}

/// Represents a single weight equipment entry with its configured weight
struct WeightEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var equipmentType: WeightEquipmentType
    var weightValue: Double  // Per-item weight for paired equipment, total for non-paired
    var isEnabled: Bool

    init(id: UUID = UUID(), equipmentType: WeightEquipmentType, weightValue: Double, isEnabled: Bool = true) {
        self.id = id
        self.equipmentType = equipmentType
        self.weightValue = weightValue
        self.isEnabled = isEnabled
    }

    /// Total weight including both items for paired equipment
    var totalWeight: Double {
        equipmentType.isPaired ? weightValue * 2 : weightValue
    }

    /// Formatted weight string for display (e.g., "20 lb" or "5 lb each")
    func formattedWeight(unit: String) -> String {
        let valueString = weightValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weightValue)
            : String(format: "%.1f", weightValue)

        if equipmentType.isPaired {
            return "\(valueString) \(unit) each"
        } else {
            return "\(valueString) \(unit)"
        }
    }

    /// Formatted total weight string (e.g., "10 lb total" for paired items)
    func formattedTotalWeight(unit: String) -> String {
        let total = totalWeight
        let valueString = total.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", total)
            : String(format: "%.1f", total)
        return "\(valueString) \(unit)"
    }
}

/// Complete weight configuration for a workout or routine
struct WeightConfiguration: Codable, Equatable {
    var entries: [WeightEntry]

    init(entries: [WeightEntry] = []) {
        self.entries = entries
    }

    /// Whether this configuration has no enabled entries
    var isEmpty: Bool {
        entries.isEmpty || entries.allSatisfy { !$0.isEnabled }
    }

    /// Total combined weight from all enabled entries
    var totalWeight: Double {
        entries.filter { $0.isEnabled }.reduce(0) { $0 + $1.totalWeight }
    }

    /// List of equipment types that are enabled
    var activeEquipmentTypes: [WeightEquipmentType] {
        entries.filter { $0.isEnabled }.map { $0.equipmentType }
    }

    /// Get entry for a specific equipment type
    func entry(for type: WeightEquipmentType) -> WeightEntry? {
        entries.first { $0.equipmentType == type }
    }

    /// Check if a specific equipment type is enabled
    func isEnabled(_ type: WeightEquipmentType) -> Bool {
        entries.first { $0.equipmentType == type }?.isEnabled ?? false
    }

    /// Empty configuration constant
    static let empty = WeightConfiguration(entries: [])

    /// Create a configuration with all equipment types pre-populated but disabled
    static func allTypes() -> WeightConfiguration {
        WeightConfiguration(entries: WeightEquipmentType.allCases.map { type in
            WeightEntry(equipmentType: type, weightValue: 0, isEnabled: false)
        })
    }
}

/// Override settings for interval-specific weight configuration
struct IntervalWeightOverride: Codable, Equatable {
    /// Equipment types enabled for this specific interval.
    /// - nil: Use routine defaults (inherit from routine)
    /// - empty set: No weights for this interval
    /// - populated set: Only these equipment types are enabled
    var enabledEquipmentTypes: Set<WeightEquipmentType>?

    init(enabledEquipmentTypes: Set<WeightEquipmentType>? = nil) {
        self.enabledEquipmentTypes = enabledEquipmentTypes
    }

    /// Whether this interval uses routine defaults
    var usesRoutineDefaults: Bool {
        enabledEquipmentTypes == nil
    }

    /// Override that uses routine defaults
    static let useDefaults = IntervalWeightOverride(enabledEquipmentTypes: nil)

    /// Override that disables all weights
    static let noWeights = IntervalWeightOverride(enabledEquipmentTypes: [])
}

// MARK: - WeightConfiguration Encoding Extensions

extension WeightConfiguration {
    /// Encode to Data for storage
    var encoded: Data? {
        try? JSONEncoder().encode(self)
    }

    /// Decode from Data
    static func decode(from data: Data?) -> WeightConfiguration? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode(WeightConfiguration.self, from: data)
    }
}
