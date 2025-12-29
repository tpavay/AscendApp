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
        estimatedCalories: Int? = nil
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
            estimatedCalories: estimatedCalories
        )
    }
}
