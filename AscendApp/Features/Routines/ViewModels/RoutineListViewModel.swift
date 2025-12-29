import Foundation
import SwiftData

@MainActor
@Observable
final class RoutineListViewModel {
    private var routineService: RoutineService?

    var builtInRoutines: [Routine] = []
    var userRoutines: [Routine] = []
    var folders: [RoutineFolder] = []
    var isLoading = false
    var errorMessage: String?

    // Filter/sort state
    var searchText: String = ""
    var selectedFolderId: UUID?

    var filteredUserRoutines: [Routine] {
        var routines = userRoutines

        if let folderId = selectedFolderId {
            routines = routines.filter { $0.folderId == folderId }
        }

        if !searchText.isEmpty {
            routines = routines.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return routines
    }

    var filteredBuiltInRoutines: [Routine] {
        if searchText.isEmpty {
            return builtInRoutines
        }
        return builtInRoutines.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
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
            folders = try service.getAllFolders()
        } catch {
            errorMessage = "Failed to load routines: \(error.localizedDescription)"
        }

        isLoading = false
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

    /// Create a new folder
    func createFolder(name: String) {
        guard let service = routineService else { return }

        do {
            let folder = try service.createFolder(name: name)
            folders.append(folder)
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }

    /// Move routine to a folder
    func moveRoutineToFolder(_ routine: Routine, folderId: UUID?) {
        guard let service = routineService else { return }

        do {
            try service.moveRoutineToFolder(routine, folderId: folderId)
            // Refresh the list
            loadRoutines()
        } catch {
            errorMessage = "Failed to move routine: \(error.localizedDescription)"
        }
    }

    /// Refresh a single routine after edits
    func refreshRoutine(_ routineId: UUID) {
        guard let service = routineService else { return }

        do {
            if let updatedRoutine = try service.getRoutine(by: routineId) {
                if updatedRoutine.source == .builtin {
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
