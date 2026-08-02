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
    var templateVersion: Int?
    var difficulty: Int?
    var estimatedCalories: Int?
    var isFeaturedTemplate: Bool = false
    var templateDisplayOrder: Int = 0
    var templateFeaturedOrder: Int?
    var browseSectionRawValuesData: Data?

    // Completion tracking
    var completionCount: Int = 0
    var lastCompletedAt: Date?

    // Order within folder for drag-and-drop reordering
    var order: Int = 0

    // MARK: - Cloud backup state
    //
    // Kept on the routine itself rather than in a side queue, for the same
    // reason `Workout` does it: the routine stays the editing surface and the
    // source of truth, and the pending work travels with the record it
    // describes. Pending *deletions* are the exception - they outlive the row,
    // so they live on `PendingRoutineDeletion`.

    var ownerUserId: String?
    var lastRemoteSyncAt: Date?
    var lastRemoteSyncError: String?
    var remoteSyncStatusRawValue: String = RoutineRemoteSyncStatus.pendingUpsert.rawValue

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

    var averageIntensityTier: IntensityTier {
        guard !intervals.isEmpty else { return .minimal }

        let weightedLevels = intervals.reduce(into: (total: 0.0, duration: 0.0)) { result, interval in
            result.total += Double(interval.resolvedLevel) * interval.duration
            result.duration += interval.duration
        }

        guard weightedLevels.duration > 0 else { return .minimal }
        let averageLevel = Int((weightedLevels.total / weightedLevels.duration).rounded())
        return IntensityTier.from(level: averageLevel)
    }

    var levelRange: ClosedRange<Int>? {
        let levels = intervals.map(\.resolvedLevel)
        guard let minimum = levels.min(),
              let maximum = levels.max() else {
            return nil
        }
        return minimum...maximum
    }

    var levelRangeDisplay: String {
        guard let levelRange else { return "Level -" }

        if levelRange.lowerBound == levelRange.upperBound {
            return "Level \(levelRange.lowerBound)"
        }

        return "Level \(levelRange.lowerBound)-\(levelRange.upperBound)"
    }

    var isBuiltIn: Bool {
        source.isTemplate
    }

    var browseSections: [BuiltInRoutineBrowseSection] {
        get {
            guard let browseSectionRawValuesData,
                  let rawValues = try? JSONDecoder().decode([String].self, from: browseSectionRawValuesData) else {
                return []
            }

            return rawValues.compactMap(BuiltInRoutineBrowseSection.init(rawValue:))
        }
        set {
            browseSectionRawValuesData = try? JSONEncoder().encode(newValue.map(\.rawValue))
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        routineDescription: String = "",
        source: RoutineSource = .userCreated,
        intervals: [RoutineInterval] = [],
        folderId: UUID? = nil,
        templateId: String? = nil,
        templateVersion: Int? = nil,
        difficulty: Int? = nil,
        estimatedCalories: Int? = nil,
        defaultWeightConfiguration: WeightConfiguration? = nil,
        browseSections: [BuiltInRoutineBrowseSection] = [],
        isFeaturedTemplate: Bool = false,
        templateDisplayOrder: Int = 0,
        templateFeaturedOrder: Int? = nil
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
        self.templateVersion = templateVersion
        self.difficulty = difficulty
        self.estimatedCalories = estimatedCalories
        self.isFeaturedTemplate = isFeaturedTemplate
        self.templateDisplayOrder = templateDisplayOrder
        self.templateFeaturedOrder = templateFeaturedOrder
        self.intervals = intervals
        self.defaultWeightConfiguration = defaultWeightConfiguration
        self.browseSections = browseSections
        self.ownerUserId = nil
        self.lastRemoteSyncAt = nil
        self.lastRemoteSyncError = nil
        self.remoteSyncStatusRawValue = RoutineRemoteSyncStatus.pendingUpsert.rawValue
    }

    var remoteSyncStatus: RoutineRemoteSyncStatus {
        get { RoutineRemoteSyncStatus(rawValue: remoteSyncStatusRawValue) ?? .pendingUpsert }
        set { remoteSyncStatusRawValue = newValue.rawValue }
    }

    /// Whether this routine is the climber's own work, and therefore worth
    /// backing up. Catalog templates are server-owned content every device
    /// re-derives from `routine_templates`; uploading one would be writing our
    /// own content back to us under the climber's uid, and `firestore.rules`
    /// rejects it.
    var isUserAuthored: Bool {
        !source.isTemplate
    }

    func markPendingRemoteUpsert(ownerUserId: String, modifiedAt: Date = Date()) {
        self.ownerUserId = ownerUserId
        updatedAt = modifiedAt
        remoteSyncStatus = .pendingUpsert
        lastRemoteSyncError = nil
    }

    func markRemoteSyncSucceeded(syncedAt: Date = Date()) {
        lastRemoteSyncAt = syncedAt
        remoteSyncStatus = .synced
        lastRemoteSyncError = nil
    }

    func markRemoteSyncFailed(_ errorMessage: String) {
        remoteSyncStatus = .failed
        lastRemoteSyncError = errorMessage
    }

    func markRemoteSyncRejected(_ errorMessage: String) {
        remoteSyncStatus = .rejected
        lastRemoteSyncError = errorMessage
    }

    /// Creates a user copy of a built-in routine
    func createUserCopy() -> Routine {
        Routine(
            name: "\(name) (Copy)",
            routineDescription: routineDescription,
            source: .copiedFromBuiltin,
            intervals: intervals,
            templateId: templateId,
            templateVersion: templateVersion,
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
