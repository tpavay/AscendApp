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
    /// Always sorted by `order`, and `order` is always the index. Every mutation restamps it.
    private(set) var intervals: [RoutineInterval] = []
    var defaultWeightConfiguration: WeightConfiguration = .empty
    var folderId: UUID?

    var selectedIntervalId: UUID?
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

    var stats: RoutineEditorStats {
        RoutineEditorStats(intervals: intervals)
    }

    var selectedIndex: Int? {
        guard let selectedIntervalId else { return nil }
        return intervals.firstIndex { $0.id == selectedIntervalId }
    }

    var selectedInterval: RoutineInterval? {
        guard let selectedIndex else { return nil }
        return intervals[selectedIndex]
    }

    var selectedStepType: RoutineStepTypeOption {
        guard let selectedInterval else { return .standard }
        return RoutineStepTypeOption.from(modifiers: selectedInterval.modifiers)
    }

    func configure(modelContext: ModelContext, routine: Routine? = nil, folderId: UUID? = nil) {
        guard !didConfigure else { return }
        didConfigure = true

        routineService = RoutineService(modelContext: modelContext)
        self.folderId = folderId

        guard let routine else { return }

        existingRoutine = routine
        name = routine.name
        routineDescription = routine.routineDescription
        intervals = routine.intervals.sorted { $0.order < $1.order }
        defaultWeightConfiguration = routine.defaultWeightConfiguration ?? .empty
        self.folderId = routine.folderId
        isAdvancedExpanded = !routineDescription.isEmpty || !defaultWeightConfiguration.isEmpty
        restampOrder()
        selectedIntervalId = intervals.first?.id
    }

    // MARK: - Authoring

    func select(intervalWithId id: UUID?) {
        selectedIntervalId = id
    }

    /// Tapping + lands a Standard block at level 1, ready to drag. There is no creator sheet.
    func addInterval() {
        let interval = RoutineInterval(
            duration: 120,
            intensityType: .level,
            intensityValue: RoutineIntervalScale.levelRange.lowerBound,
            modifiers: RoutineStepTypeOption.standard.modifiers,
            order: intervals.count
        )

        intervals.append(interval)
        restampOrder()
        selectedIntervalId = interval.id
    }

    func setLevel(_ level: Int, forIntervalWithId id: UUID) {
        guard let index = intervals.firstIndex(where: { $0.id == id }) else { return }

        let clamped = SPMMappingService.clampedLevel(level)
        guard intervals[index].intensityValue != clamped || intervals[index].intensityType != .level else {
            return
        }

        intervals[index].intensityType = .level
        intervals[index].intensityValue = clamped
    }

    func adjustLevel(by delta: Int, forIntervalWithId id: UUID) {
        guard let interval = intervals.first(where: { $0.id == id }) else { return }
        setLevel(interval.resolvedLevel + delta, forIntervalWithId: id)
    }

    func setDuration(_ duration: TimeInterval, forIntervalWithId id: UUID) {
        guard let index = intervals.firstIndex(where: { $0.id == id }) else { return }

        let snapped = RoutineIntervalScale.snappedDuration(duration)
        guard intervals[index].duration != snapped else { return }

        intervals[index].duration = snapped
    }

    func adjustDuration(bySteps steps: Int, forIntervalWithId id: UUID) {
        guard let interval = intervals.first(where: { $0.id == id }) else { return }
        let delta = Double(steps) * RoutineIntervalScale.durationStep
        setDuration(interval.duration + delta, forIntervalWithId: id)
    }

    func setStepType(_ stepType: RoutineStepTypeOption, forIntervalWithId id: UUID) {
        guard let index = intervals.firstIndex(where: { $0.id == id }) else { return }
        intervals[index].modifiers = stepType.modifiers
    }

    /// VoiceOver reaches the step type through a rotor action rather than the menu below the
    /// timeline, so it steps through the five options in order.
    func cycleStepType(forIntervalWithId id: UUID) {
        guard let interval = intervals.first(where: { $0.id == id }) else { return }

        let options = RoutineStepTypeOption.allCases
        let current = RoutineStepTypeOption.from(modifiers: interval.modifiers)
        let currentIndex = options.firstIndex(of: current) ?? 0
        let next = options[(currentIndex + 1) % options.count]

        setStepType(next, forIntervalWithId: id)
    }

    func deleteInterval(withId id: UUID) {
        guard let index = intervals.firstIndex(where: { $0.id == id }) else { return }

        intervals.remove(at: index)
        restampOrder()

        guard !intervals.isEmpty else {
            selectedIntervalId = nil
            return
        }

        // Selection lands on the neighbour that took the deleted block's place.
        selectedIntervalId = intervals[min(index, intervals.count - 1)].id
    }

    /// `destinationIndex` is an index into the list with the moved interval already removed,
    /// which is what the timeline's hit testing produces.
    func moveInterval(fromIndex sourceIndex: Int, toIndex destinationIndex: Int) {
        guard intervals.indices.contains(sourceIndex) else { return }

        let clampedDestination = min(max(destinationIndex, 0), intervals.count - 1)
        guard clampedDestination != sourceIndex else { return }

        let interval = intervals.remove(at: sourceIndex)
        intervals.insert(interval, at: clampedDestination)
        restampOrder()
    }

    func moveSelectedInterval(by offset: Int) {
        guard let selectedIndex else { return }
        moveInterval(fromIndex: selectedIndex, toIndex: selectedIndex + offset)
    }

    // MARK: - Saving

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
            existingRoutine.intervals = intervals
            existingRoutine.difficulty = nil
            existingRoutine.defaultWeightConfiguration = weightConfiguration
            try routineService.updateRoutine(existingRoutine)
            return existingRoutine
        }

        return try routineService.createRoutine(
            name: trimmedName,
            description: trimmedDescription,
            intervals: intervals,
            folderId: folderId,
            difficulty: nil,
            defaultWeightConfiguration: weightConfiguration
        )
    }

    private func restampOrder() {
        for index in intervals.indices {
            intervals[index].order = index
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
