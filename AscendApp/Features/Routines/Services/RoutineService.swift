import Foundation
import SwiftData

/// Service for managing routine CRUD operations
@MainActor
final class RoutineService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch Operations

    /// Fetches all non-archived routines
    func getAllRoutines() throws -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches only user-created routines (not built-in)
    func getUserRoutines() throws -> [Routine] {
        let builtinRaw = RoutineSource.builtin.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived && $0.sourceRawValue != builtinRaw
            },
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches only built-in routines
    func getBuiltInRoutines() throws -> [Routine] {
        let builtinRaw = RoutineSource.builtin.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived && $0.sourceRawValue == builtinRaw
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches routines in a specific folder
    func getRoutinesInFolder(_ folderId: UUID?) throws -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived && $0.folderId == folderId
            },
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches a single routine by ID
    func getRoutine(by id: UUID) throws -> Routine? {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Create/Update Operations

    /// Creates a new user routine
    @discardableResult
    func createRoutine(
        name: String,
        description: String = "",
        intervals: [RoutineInterval],
        folderId: UUID? = nil,
        difficulty: Int? = nil,
        defaultWeightConfiguration: WeightConfiguration? = nil
    ) throws -> Routine {
        let routine = Routine(
            name: name,
            routineDescription: description,
            source: .userCreated,
            intervals: intervals,
            folderId: folderId,
            difficulty: difficulty,
            defaultWeightConfiguration: defaultWeightConfiguration
        )
        modelContext.insert(routine)
        try modelContext.save()
        return routine
    }

    /// Updates an existing routine
    func updateRoutine(_ routine: Routine) throws {
        routine.updatedAt = Date()
        try modelContext.save()
    }

    /// Creates a user copy of a built-in routine
    @discardableResult
    func copyBuiltInRoutine(_ routine: Routine) throws -> Routine {
        let copy = routine.createUserCopy()
        modelContext.insert(copy)
        try modelContext.save()
        return copy
    }

    // MARK: - Delete Operations

    /// Archives a routine (soft delete)
    func archiveRoutine(_ routine: Routine) throws {
        routine.isArchived = true
        routine.updatedAt = Date()
        try modelContext.save()
    }

    /// Permanently deletes a routine
    func deleteRoutine(_ routine: Routine) throws {
        modelContext.delete(routine)
        try modelContext.save()
    }

    // MARK: - Folder Operations

    /// Fetches all folders
    func getAllFolders() throws -> [RoutineFolder] {
        let descriptor = FetchDescriptor<RoutineFolder>(
            sortBy: [SortDescriptor(\.order)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Creates a new folder
    @discardableResult
    func createFolder(name: String, colorHex: String? = nil) throws -> RoutineFolder {
        let folders = try getAllFolders()
        let folder = RoutineFolder(
            name: name,
            colorHex: colorHex,
            order: folders.count
        )
        modelContext.insert(folder)
        try modelContext.save()
        return folder
    }

    /// Moves a routine to a folder
    func moveRoutineToFolder(_ routine: Routine, folderId: UUID?) throws {
        routine.folderId = folderId
        routine.updatedAt = Date()
        try modelContext.save()
    }

    /// Deletes a folder
    func deleteFolder(_ folder: RoutineFolder) throws {
        // Move all routines in this folder to no folder
        let routinesInFolder = try getRoutinesInFolder(folder.id)
        for routine in routinesInFolder {
            routine.folderId = nil
        }
        modelContext.delete(folder)
        try modelContext.save()
    }

    /// Renames a folder
    func renameFolder(_ folder: RoutineFolder, newName: String) throws {
        folder.name = newName
        try modelContext.save()
    }

    /// Saves the order of folders
    func saveFolderOrder(_ folders: [RoutineFolder]) throws {
        for (index, folder) in folders.enumerated() {
            folder.order = index
        }
        try modelContext.save()
    }

    /// Saves the order of routines within a folder
    func saveRoutineOrder(_ routines: [Routine]) throws {
        for (index, routine) in routines.enumerated() {
            routine.order = index
        }
        try modelContext.save()
    }

    // MARK: - Built-in Template Initialization

    /// Ensures built-in routines exist in the database (call on app launch)
    func ensureBuiltInRoutinesExist() throws {
        let builtinRaw = RoutineSource.builtin.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.sourceRawValue == builtinRaw }
        )
        let existingBuiltIns = try modelContext.fetch(descriptor)
        let existingTemplateIds = Set(existingBuiltIns.compactMap { $0.templateId })

        for template in BuiltInRoutines.templates {
            guard let templateId = template.templateId,
                  !existingTemplateIds.contains(templateId) else { continue }
            modelContext.insert(template)
        }

        try modelContext.save()
    }

    /// Returns the count of user routines
    func getUserRoutineCount() throws -> Int {
        let builtinRaw = RoutineSource.builtin.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived && $0.sourceRawValue != builtinRaw
            }
        )
        return try modelContext.fetchCount(descriptor)
    }

    /// Returns the total count of all non-archived routines
    func getTotalRoutineCount() throws -> Int {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { !$0.isArchived }
        )
        return try modelContext.fetchCount(descriptor)
    }
}
