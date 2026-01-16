import Foundation
import SwiftData

// MARK: - Folder Group Model

struct RoutineFolderGroup: Identifiable {
    let id: String
    let folder: RoutineFolder?
    let routines: [Routine]

    init(folder: RoutineFolder?, routines: [Routine]) {
        self.id = folder?.id.uuidString ?? "unfiled"
        self.folder = folder
        self.routines = routines
    }

    var isUnfiled: Bool {
        folder == nil
    }

    var name: String {
        folder?.name ?? "Unfiled"
    }
}

// MARK: - View Model

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

    // My Routines folder position (0 = first, persisted in UserDefaults)
    var myRoutinesOrder: Int {
        get { UserDefaults.standard.integer(forKey: "myRoutinesOrder") }
        set { UserDefaults.standard.set(newValue, forKey: "myRoutinesOrder") }
    }

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

    /// Groups user routines by folder for organized display
    var routinesByFolder: [RoutineFolderGroup] {
        var grouped: [UUID?: [Routine]] = [:]

        // Initialize with nil key for unfiled routines
        grouped[nil] = []

        // Group routines by folderId
        for routine in userRoutines {
            if grouped[routine.folderId] != nil {
                grouped[routine.folderId]?.append(routine)
            } else {
                grouped[routine.folderId] = [routine]
            }
        }

        // Build result array with My Routines at the correct position
        var result: [RoutineFolderGroup] = []

        // Prepare My Routines group
        var myRoutinesGroup: RoutineFolderGroup?
        if let unfiled = grouped[nil], !unfiled.isEmpty {
            let sortedRoutines = unfiled.sorted { $0.order < $1.order }
            myRoutinesGroup = RoutineFolderGroup(folder: nil, routines: sortedRoutines)
        }

        // Get sorted folders
        let sortedFolders = folders.sorted { $0.order < $1.order }

        // Insert groups respecting myRoutinesOrder position
        var folderIndex = 0
        for position in 0...(sortedFolders.count) {
            // Check if My Routines should be inserted at this position
            if let group = myRoutinesGroup, position == myRoutinesOrder {
                result.append(group)
                myRoutinesGroup = nil // Mark as inserted
            }

            // Add the next folder if available
            if folderIndex < sortedFolders.count {
                let folder = sortedFolders[folderIndex]
                if let routines = grouped[folder.id] {
                    let sortedRoutines = routines.sorted { $0.order < $1.order }
                    result.append(RoutineFolderGroup(folder: folder, routines: sortedRoutines))
                } else {
                    result.append(RoutineFolderGroup(folder: folder, routines: []))
                }
                folderIndex += 1
            }
        }

        // If My Routines wasn't inserted (position beyond array), append at end
        if let group = myRoutinesGroup {
            result.append(group)
        }

        return result
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

    /// Delete a folder (moves routines to My Routines)
    func deleteFolder(_ folder: RoutineFolder) {
        guard let service = routineService else { return }

        do {
            try service.deleteFolder(folder)
            folders.removeAll { $0.id == folder.id }
            // Reload to reflect routines moved to My Routines
            loadRoutines()
        } catch {
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
        }
    }

    /// Rename a folder
    func renameFolder(_ folder: RoutineFolder, newName: String) {
        guard let service = routineService else { return }

        do {
            try service.renameFolder(folder, newName: newName)
            // Update local state
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index].name = newName
            }
        } catch {
            errorMessage = "Failed to rename folder: \(error.localizedDescription)"
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

    /// Save the order of folders after reordering
    func saveFolderOrder(_ reorderedFolders: [RoutineFolder]) {
        guard let service = routineService else { return }

        // Update local state
        folders = reorderedFolders

        // Update order values and persist
        for (index, folder) in folders.enumerated() {
            folder.order = index
        }

        do {
            try service.saveFolderOrder(folders)
        } catch {
            errorMessage = "Failed to save folder order: \(error.localizedDescription)"
        }
    }

    /// Save the order of folders and My Routines position after reordering
    func saveFolderOrder(_ reorderedFolders: [RoutineFolder], myRoutinesPosition: Int) {
        guard let service = routineService else { return }

        // Update local state
        folders = reorderedFolders
        myRoutinesOrder = myRoutinesPosition

        // Update order values and persist
        for (index, folder) in folders.enumerated() {
            folder.order = index
        }

        do {
            try service.saveFolderOrder(folders)
        } catch {
            errorMessage = "Failed to save folder order: \(error.localizedDescription)"
        }
    }

    /// Reorder folders by moving one folder before another
    func reorderFolder(from sourceId: String, to destinationId: String) {
        guard let service = routineService else { return }

        // Don't reorder if source is "unfiled"
        guard sourceId != "unfiled" else { return }

        // Find the source folder
        guard let sourceUUID = UUID(uuidString: sourceId),
              let sourceIndex = folders.firstIndex(where: { $0.id == sourceUUID }) else { return }

        // Find destination index
        let destinationIndex: Int
        if destinationId == "unfiled" {
            destinationIndex = 0
        } else if let destUUID = UUID(uuidString: destinationId),
                  let destIdx = folders.firstIndex(where: { $0.id == destUUID }) {
            destinationIndex = destIdx
        } else {
            return
        }

        // Move the folder
        let folder = folders.remove(at: sourceIndex)
        let newIndex = sourceIndex < destinationIndex ? destinationIndex : destinationIndex
        folders.insert(folder, at: newIndex)

        // Update order values
        for (index, folder) in folders.enumerated() {
            folder.order = index
        }

        do {
            try service.saveFolderOrder(folders)
        } catch {
            errorMessage = "Failed to reorder folders: \(error.localizedDescription)"
        }
    }

    /// Reorder routines within a folder with animation and persistence
    func reorderRoutine(from sourceId: UUID, to destinationId: UUID, inFolder folderId: UUID?) {
        guard let service = routineService else { return }

        // Get routines in this specific folder
        let routinesInFolder = userRoutines.filter { $0.folderId == folderId }

        // Find source and destination indices within the folder's routines
        guard let sourceIndex = routinesInFolder.firstIndex(where: { $0.id == sourceId }),
              let destinationIndex = routinesInFolder.firstIndex(where: { $0.id == destinationId }) else { return }

        // Create a mutable copy of folder routines for reordering
        var reorderedRoutines = routinesInFolder
        let movedRoutine = reorderedRoutines.remove(at: sourceIndex)
        reorderedRoutines.insert(movedRoutine, at: destinationIndex)

        // Update order values
        for (index, routine) in reorderedRoutines.enumerated() {
            routine.order = index
        }

        // Update the main userRoutines array to reflect new order
        // First, remove all routines from this folder
        userRoutines.removeAll { $0.folderId == folderId }
        // Then add back the reordered routines
        userRoutines.append(contentsOf: reorderedRoutines)

        // Persist the order
        do {
            try service.saveRoutineOrder(reorderedRoutines)
        } catch {
            errorMessage = "Failed to save routine order: \(error.localizedDescription)"
        }
    }

    /// Save the order of routines after reordering via List onMove
    func saveRoutineOrder(_ reorderedRoutines: [Routine]) {
        guard let service = routineService else { return }

        // Get the folderId from the first routine (all should be in same folder)
        let folderId = reorderedRoutines.first?.folderId

        // Update the main userRoutines array to reflect new order
        userRoutines.removeAll { $0.folderId == folderId }
        userRoutines.append(contentsOf: reorderedRoutines)

        // Persist the order
        do {
            try service.saveRoutineOrder(reorderedRoutines)
        } catch {
            errorMessage = "Failed to save routine order: \(error.localizedDescription)"
        }
    }
}
