import Foundation
import SwiftData

@MainActor
@Observable
final class RoutineEditorViewModel {
    private var routineService: RoutineService?
    private var existingRoutine: Routine?

    // Form state
    var name: String = ""
    var routineDescription: String = ""
    var intervals: [RoutineInterval] = []
    var difficulty: Int? = nil
    var defaultWeightConfiguration: WeightConfiguration = .empty
    var folderId: UUID? = nil

    // UI state
    var isSaving = false
    var errorMessage: String?

    // Validation
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !intervals.isEmpty
    }

    var canSave: Bool {
        isValid && !isSaving
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

    var isEditing: Bool {
        existingRoutine != nil
    }

    var navigationTitle: String {
        isEditing ? "Edit Routine" : "New Routine"
    }

    /// Configure the view model with a model context and optional existing routine
    func configure(modelContext: ModelContext, routine: Routine? = nil, folderId: UUID? = nil) {
        self.routineService = RoutineService(modelContext: modelContext)
        self.folderId = folderId

        if let routine = routine {
            self.existingRoutine = routine
            self.name = routine.name
            self.routineDescription = routine.routineDescription
            self.intervals = routine.intervals
            self.difficulty = routine.difficulty
            self.defaultWeightConfiguration = routine.defaultWeightConfiguration ?? .empty
            self.folderId = routine.folderId
        }
    }

    // MARK: - Interval Management

    func addInterval() {
        let newInterval = RoutineInterval(
            duration: 60,
            intensityType: .level,
            intensityValue: 8,
            modifiers: .none,
            order: intervals.count
        )
        intervals.append(newInterval)
    }

    func addInterval(_ interval: RoutineInterval) {
        var newInterval = interval
        newInterval.order = intervals.count
        intervals.append(newInterval)
    }

    func updateInterval(at index: Int, with interval: RoutineInterval) {
        guard intervals.indices.contains(index) else { return }
        var updatedInterval = interval
        updatedInterval.order = index
        intervals[index] = updatedInterval
    }

    func deleteInterval(at index: Int) {
        guard intervals.indices.contains(index) else { return }
        intervals.remove(at: index)
        reorderIntervals()
    }

    func deleteIntervals(at offsets: IndexSet) {
        intervals.remove(atOffsets: offsets)
        reorderIntervals()
    }

    func moveInterval(from source: IndexSet, to destination: Int) {
        intervals.move(fromOffsets: source, toOffset: destination)
        reorderIntervals()
    }

    func duplicateInterval(at index: Int) {
        guard intervals.indices.contains(index) else { return }
        var copy = intervals[index]
        copy.id = UUID()
        copy.order = intervals.count
        intervals.append(copy)
    }

    private func reorderIntervals() {
        for index in intervals.indices {
            intervals[index].order = index
        }
    }

    // MARK: - Save

    func save() throws -> Routine {
        guard let service = routineService, isValid else {
            throw RoutineEditorError.invalidData
        }

        isSaving = true
        errorMessage = nil

        defer { isSaving = false }

        // Only include weight config if it has entries
        let weights = defaultWeightConfiguration.isEmpty ? nil : defaultWeightConfiguration

        if let existing = existingRoutine {
            // Update existing routine
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.routineDescription = routineDescription.trimmingCharacters(in: .whitespaces)
            existing.intervals = intervals
            existing.difficulty = difficulty
            existing.defaultWeightConfiguration = weights
            try service.updateRoutine(existing)
            return existing
        } else {
            // Create new routine
            let routine = try service.createRoutine(
                name: name.trimmingCharacters(in: .whitespaces),
                description: routineDescription.trimmingCharacters(in: .whitespaces),
                intervals: intervals,
                folderId: folderId,
                difficulty: difficulty,
                defaultWeightConfiguration: weights
            )
            return routine
        }
    }
}

enum RoutineEditorError: LocalizedError {
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Please provide a name and at least one interval."
        }
    }
}
