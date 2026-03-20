import Foundation
import SwiftData

@MainActor
@Observable
final class RoutineEditorViewModel {
    private var routineService: RoutineService?
    private var existingRoutine: Routine?
    private var didConfigure = false

    var name: String = ""
    var routineDescription: String = ""
    var intervals: [RoutineInterval] = []
    var defaultWeightConfiguration: WeightConfiguration = .empty
    var folderId: UUID?

    var draftLevel: Int = SettingsManager.shared.effectiveBaseLevel
    var draftDuration: TimeInterval = 120
    var draftStepType: RoutineStepTypeOption = .standard
    var editingIntervalId: UUID?
    var isAdvancedExpanded = false

    var isSaving = false
    var errorMessage: String?

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !intervals.isEmpty && !isSaving
    }

    var isEditingRoutine: Bool {
        existingRoutine != nil
    }

    var navigationTitle: String {
        isEditingRoutine ? "Edit Routine" : "New Routine"
    }

    var totalDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    var totalDurationFormatted: String {
        let totalMinutes = Int(totalDuration.rounded()) / 60
        return "\(totalMinutes) min"
    }

    var isEditingInterval: Bool {
        editingIntervalId != nil
    }

    var displayedIntervals: [RoutineInterval] {
        intervals.sorted { $0.order < $1.order }
    }

    var previewIntervals: [RoutineInterval] {
        guard let editingIntervalId else { return displayedIntervals }
        return displayedIntervals.filter { $0.id != editingIntervalId }
    }

    var previewGhostInterval: RoutineInterval? {
        draftInterval
    }

    var selectedInterval: RoutineInterval? {
        guard let editingIntervalId else { return nil }
        return displayedIntervals.first { $0.id == editingIntervalId }
    }

    var draftInterval: RoutineInterval? {
        guard draftDuration > 0 else { return nil }

        return RoutineInterval(
            duration: draftDuration,
            intensityType: .level,
            intensityValue: draftLevel,
            modifiers: draftStepType.modifiers,
            order: editingIndex ?? displayedIntervals.count
        )
    }

    private var editingIndex: Int? {
        guard let editingIntervalId else { return nil }
        return displayedIntervals.firstIndex { $0.id == editingIntervalId }
    }

    func configure(modelContext: ModelContext, routine: Routine? = nil, folderId: UUID? = nil) {
        guard !didConfigure else { return }
        didConfigure = true

        routineService = RoutineService(modelContext: modelContext)
        self.folderId = folderId

        if let routine {
            existingRoutine = routine
            name = routine.name
            routineDescription = routine.routineDescription
            intervals = routine.intervals.sorted { $0.order < $1.order }
            defaultWeightConfiguration = routine.defaultWeightConfiguration ?? .empty
            self.folderId = routine.folderId
            seedDraft(from: intervals.last)
            isAdvancedExpanded = !routineDescription.isEmpty || !defaultWeightConfiguration.isEmpty
        } else {
            seedDraft(from: nil)
        }
    }

    func selectInterval(_ interval: RoutineInterval) {
        editingIntervalId = interval.id
        draftLevel = interval.resolvedLevel
        draftDuration = interval.duration
        draftStepType = RoutineStepTypeOption.from(modifiers: interval.modifiers)
    }

    func cancelEditingInterval() {
        editingIntervalId = nil
        seedDraft(from: intervals.last)
    }

    func commitDraftInterval() {
        guard var draftInterval else { return }

        if let editingIndex {
            draftInterval.id = displayedIntervals[editingIndex].id
            draftInterval.order = editingIndex
            intervals[editingIndex] = draftInterval
            editingIntervalId = nil
        } else {
            draftInterval.order = displayedIntervals.count
            intervals.append(draftInterval)
        }

        reorderIntervals()
    }

    func deleteSelectedInterval() {
        guard let editingIndex else { return }
        intervals.remove(at: editingIndex)
        editingIntervalId = nil
        reorderIntervals()
        seedDraft(from: intervals.last)
    }

    func moveInterval(withId draggedId: UUID, before targetId: UUID) {
        guard draggedId != targetId,
              let sourceIndex = intervals.firstIndex(where: { $0.id == draggedId }),
              let destinationIndex = intervals.firstIndex(where: { $0.id == targetId }) else {
            return
        }

        let destination = sourceIndex < destinationIndex ? destinationIndex + 1 : destinationIndex
        intervals.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        reorderIntervals()
    }

    func save() throws -> Routine {
        guard let routineService, canSave else {
            throw RoutineEditorError.invalidData
        }

        isSaving = true
        errorMessage = nil

        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = routineDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let weightConfiguration = defaultWeightConfiguration.isEmpty ? nil : defaultWeightConfiguration

        if let existingRoutine {
            existingRoutine.name = trimmedName
            existingRoutine.routineDescription = trimmedDescription
            existingRoutine.intervals = intervals.sorted { $0.order < $1.order }
            existingRoutine.difficulty = nil
            existingRoutine.defaultWeightConfiguration = weightConfiguration
            try routineService.updateRoutine(existingRoutine)
            return existingRoutine
        }

        return try routineService.createRoutine(
            name: trimmedName,
            description: trimmedDescription,
            intervals: intervals.sorted { $0.order < $1.order },
            folderId: folderId,
            difficulty: nil,
            defaultWeightConfiguration: weightConfiguration
        )
    }

    private func reorderIntervals() {
        for index in intervals.indices {
            intervals[index].order = index
        }
    }

    private func seedDraft(from interval: RoutineInterval?) {
        if let interval {
            draftLevel = interval.resolvedLevel
            draftDuration = interval.duration
            draftStepType = RoutineStepTypeOption.from(modifiers: interval.modifiers)
        } else {
            draftLevel = SettingsManager.shared.effectiveBaseLevel
            draftDuration = 120
            draftStepType = .standard
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
