import Foundation
import SwiftData

// MARK: - View Model

@MainActor
@Observable
final class RoutineListViewModel {
    private var routineService: RoutineService?
    private var hasAttemptedRemoteTemplateRefresh = false

    var builtInRoutines: [Routine] = []
    var userRoutines: [Routine] = []
    var isLoading = false
    var errorMessage: String?

    // Filter/sort state
    var searchText: String = ""

    var filteredUserRoutines: [Routine] {
        var routines = userRoutines

        if !searchText.isEmpty {
            routines = routines.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return routines
    }

    var filteredBuiltInRoutines: [Routine] {
        filteredTemplateRoutines()
    }

    var filteredFeaturedBuiltInRoutines: [Routine] {
        filteredTemplateRoutines { $0.isFeaturedTemplate }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.templateFeaturedOrder ?? lhs.templateDisplayOrder
                let rhsOrder = rhs.templateFeaturedOrder ?? rhs.templateDisplayOrder

                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func filteredBuiltInRoutines(in section: BuiltInRoutineBrowseSection) -> [Routine] {
        filteredTemplateRoutines { $0.browseSections.contains(section) }
    }

    var filteredMyRoutines: [Routine] {
        let routines: [Routine]
        if searchText.isEmpty {
            routines = userRoutines
        } else {
            routines = userRoutines.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return routines.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    var hasMyRoutines: Bool {
        !filteredMyRoutines.isEmpty
    }

    var hasAnyRoutines: Bool {
        !builtInRoutines.isEmpty || !userRoutines.isEmpty
    }

    var userRoutineCount: Int {
        userRoutines.count
    }

    var totalRoutineCount: Int {
        builtInRoutines.count + userRoutines.count
    }

    /// Configure the view model with a model context
    func configure(modelContext: ModelContext) {
        self.routineService = RoutineService(modelContext: modelContext)
    }

    /// Load all routines
    func loadRoutines() {
        guard let service = routineService else { return }

        isLoading = true
        errorMessage = nil

        do {
            try service.ensureBuiltInRoutinesExist()

            builtInRoutines = try service.getBuiltInRoutines()
            userRoutines = try service.getUserRoutines()
        } catch {
            errorMessage = "Failed to load routines: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func refreshRemoteRoutineTemplates() async {
        guard let service = routineService,
              !hasAttemptedRemoteTemplateRefresh else { return }

        hasAttemptedRemoteTemplateRefresh = true

        do {
            try await service.refreshRemoteRoutineTemplates()
            loadRoutines()
        } catch {
            debugLog("Failed to refresh remote routine templates: \(error)")
        }
    }

    /// Copy a built-in routine to user routines
    func copyBuiltInRoutine(_ routine: Routine) {
        guard let service = routineService else { return }

        do {
            let copy = try service.copyBuiltInRoutine(routine)
            userRoutines.insert(copy, at: 0)
        } catch {
            errorMessage = "Failed to copy routine: \(error.localizedDescription)"
        }
    }

    func isRoutineSaved(_ routine: Routine) -> Bool {
        guard let templateId = routine.templateId else { return false }
        return userRoutines.contains {
            !$0.isArchived &&
            $0.source == .copiedFromBuiltin &&
            $0.templateId == templateId
        }
    }

    func toggleSavedRoutine(_ routine: Routine) {
        guard let service = routineService else { return }

        do {
            _ = try service.toggleSavedCopy(for: routine)
            loadRoutines()
        } catch {
            errorMessage = "Failed to update saved routine: \(error.localizedDescription)"
        }
    }

    private func filteredTemplateRoutines(
        _ include: (Routine) -> Bool = { _ in true }
    ) -> [Routine] {
        let routines: [Routine]
        if searchText.isEmpty {
            routines = builtInRoutines
        } else {
            routines = builtInRoutines.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return routines
            .filter(include)
            .sorted { lhs, rhs in
                if lhs.templateDisplayOrder != rhs.templateDisplayOrder {
                    return lhs.templateDisplayOrder < rhs.templateDisplayOrder
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// Delete (archive) a user routine
    func deleteRoutine(_ routine: Routine) {
        guard let service = routineService else { return }

        do {
            try service.archiveRoutine(routine)
            userRoutines.removeAll { $0.id == routine.id }
        } catch {
            errorMessage = "Failed to delete routine: \(error.localizedDescription)"
        }
    }

    /// Refresh a single routine after edits
    func refreshRoutine(_ routineId: UUID) {
        guard let service = routineService else { return }

        do {
            if let updatedRoutine = try service.getRoutine(by: routineId) {
                if updatedRoutine.source.isTemplate {
                    if let index = builtInRoutines.firstIndex(where: { $0.id == routineId }) {
                        builtInRoutines[index] = updatedRoutine
                    }
                } else {
                    if let index = userRoutines.firstIndex(where: { $0.id == routineId }) {
                        userRoutines[index] = updatedRoutine
                    }
                }
            }
        } catch {
            errorMessage = "Failed to refresh routine: \(error.localizedDescription)"
        }
    }
}
