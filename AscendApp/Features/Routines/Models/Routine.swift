import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID
    var name: String
    var routineDescription: String
    var sourceRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var folderId: UUID?
    var isArchived: Bool

    // Stored as JSON for reliable SwiftData serialization
    var intervalsData: Data?

    // Default weight configuration for this routine (stored as JSON)
    var defaultWeightConfigurationData: Data?

    // Template metadata (for built-in templates)
    var templateId: String?
    var difficulty: Int?
    var estimatedCalories: Int?

    // Computed property for source enum
    var source: RoutineSource {
        get { RoutineSource(rawValue: sourceRawValue) ?? .userCreated }
        set { sourceRawValue = newValue.rawValue }
    }

    // Computed property for intervals
    var intervals: [RoutineInterval] {
        get {
            guard let data = intervalsData else { return [] }
            return (try? JSONDecoder().decode([RoutineInterval].self, from: data)) ?? []
        }
        set {
            intervalsData = try? JSONEncoder().encode(newValue)
        }
    }

    // Computed property for default weight configuration
    var defaultWeightConfiguration: WeightConfiguration? {
        get {
            WeightConfiguration.decode(from: defaultWeightConfigurationData)
        }
        set {
            defaultWeightConfigurationData = newValue?.encoded
        }
    }

    /// Whether this routine has default weights configured
    var hasDefaultWeights: Bool {
        !(defaultWeightConfiguration?.isEmpty ?? true)
    }

    var totalDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    var totalDurationFormatted: String {
        let totalSeconds = Int(totalDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
        return "\(minutes) min"
    }

    var intervalCount: Int {
        intervals.count
    }

    var isBuiltIn: Bool {
        source == .builtin
    }

    init(
        id: UUID = UUID(),
        name: String,
        routineDescription: String = "",
        source: RoutineSource = .userCreated,
        intervals: [RoutineInterval] = [],
        folderId: UUID? = nil,
        templateId: String? = nil,
        difficulty: Int? = nil,
        estimatedCalories: Int? = nil,
        defaultWeightConfiguration: WeightConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.routineDescription = routineDescription
        self.sourceRawValue = source.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.folderId = folderId
        self.isArchived = false
        self.templateId = templateId
        self.difficulty = difficulty
        self.estimatedCalories = estimatedCalories
        self.intervals = intervals
        self.defaultWeightConfiguration = defaultWeightConfiguration
    }

    /// Creates a user copy of a built-in routine
    func createUserCopy() -> Routine {
        Routine(
            name: "\(name) (Copy)",
            routineDescription: routineDescription,
            source: .copiedFromBuiltin,
            intervals: intervals,
            templateId: templateId,
            difficulty: difficulty,
            estimatedCalories: estimatedCalories,
            defaultWeightConfiguration: defaultWeightConfiguration
        )
    }

    /// Resolves the effective weight configuration for a specific interval
    /// - Parameter interval: The interval to resolve weights for
    /// - Returns: The weight configuration to use (routine defaults filtered by interval override)
    func resolvedWeightConfiguration(for interval: RoutineInterval) -> WeightConfiguration? {
        guard let defaults = defaultWeightConfiguration, !defaults.isEmpty else {
            return nil
        }

        guard let override = interval.modifiers.weightOverride,
              let enabledTypes = override.enabledEquipmentTypes else {
            // No override = use routine defaults as-is
            return defaults
        }

        // Empty set means no weights for this interval
        if enabledTypes.isEmpty {
            return nil
        }

        // Apply override: filter defaults to only enabled types
        var resolved = defaults
        resolved.entries = defaults.entries.map { entry in
            var modified = entry
            modified.isEnabled = enabledTypes.contains(entry.equipmentType)
            return modified
        }
        return resolved.isEmpty ? nil : resolved
    }
}
