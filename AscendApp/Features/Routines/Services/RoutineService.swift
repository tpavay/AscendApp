import FirebaseAuth
import Foundation
import SwiftData

/// Service for managing routine CRUD operations.
///
/// Every mutation here is also the entry point to the cloud backup: it marks
/// the record pending and kicks `RoutineSyncCoordinator`. Nothing in this file
/// talks to Firestore directly, which is what lets an upload survive being
/// interrupted - the pending state is on disk before the network is touched.
@MainActor
final class RoutineService {
    private let modelContext: ModelContext
    private let templateRepository: RoutineTemplateRepository
    private let syncCoordinator: RoutineSyncCoordinator
    private let currentUserId: () -> String?

    init(
        modelContext: ModelContext,
        templateRepository: RoutineTemplateRepository = FirestoreRoutineTemplateRepository.shared,
        syncCoordinator: RoutineSyncCoordinator = .shared,
        currentUserId: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.modelContext = modelContext
        self.templateRepository = templateRepository
        self.syncCoordinator = syncCoordinator
        self.currentUserId = currentUserId
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
        let remoteTemplateRaw = RoutineSource.remoteTemplate.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived &&
                $0.sourceRawValue != builtinRaw &&
                $0.sourceRawValue != remoteTemplateRaw
            },
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches read-only template routines, including bundled and remote-managed templates.
    func getBuiltInRoutines() throws -> [Routine] {
        let builtinRaw = RoutineSource.builtin.rawValue
        let remoteTemplateRaw = RoutineSource.remoteTemplate.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived &&
                ($0.sourceRawValue == builtinRaw || $0.sourceRawValue == remoteTemplateRaw)
            },
            sortBy: [SortDescriptor(\.templateDisplayOrder), SortDescriptor(\.name)]
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
        markPendingBackup(routine)
        try modelContext.save()
        kickBackup()
        return routine
    }

    /// Updates an existing routine
    func updateRoutine(_ routine: Routine) throws {
        routine.updatedAt = Date()
        markPendingBackup(routine, modifiedAt: routine.updatedAt)
        try modelContext.save()
        kickBackup()
    }

    /// Records that the climber finished a session of this routine.
    ///
    /// Whether a session counts as a completion is the live session's call, not
    /// this one's. What this owns is the write: the counters are backed-up
    /// document fields, so a completion has to mark the routine pending like any
    /// other edit. Writing them straight onto the model leaves a routine that is
    /// completed for years and restores with a count of zero.
    func recordCompletion(for routine: Routine, completedAt: Date = Date()) throws {
        routine.completionCount += 1
        routine.lastCompletedAt = completedAt
        markPendingBackup(routine, modifiedAt: completedAt)
        try modelContext.save()
        kickBackup()
    }

    /// Creates a user copy of a built-in routine
    @discardableResult
    func copyBuiltInRoutine(_ routine: Routine) throws -> Routine {
        let copy = routine.createUserCopy()
        modelContext.insert(copy)
        markPendingBackup(copy)
        try modelContext.save()
        kickBackup()
        return copy
    }

    func savedCopy(templateId: String) throws -> Routine? {
        let copiedRaw = RoutineSource.copiedFromBuiltin.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived &&
                $0.sourceRawValue == copiedRaw &&
                $0.templateId == templateId
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func toggleSavedCopy(for routine: Routine) throws -> Bool {
        guard let templateId = routine.templateId else { return false }

        if let existingCopy = try savedCopy(templateId: templateId) {
            try archiveRoutine(existingCopy)
            return false
        }

        _ = try copyBuiltInRoutine(routine)
        return true
    }

    // MARK: - Delete Operations

    /// Archives a routine (soft delete)
    ///
    /// The backup is updated rather than removed: archiving is a content
    /// change, and a restore has to bring the routine back archived rather than
    /// resurrecting it into the climber's list.
    func archiveRoutine(_ routine: Routine) throws {
        routine.isArchived = true
        routine.updatedAt = Date()
        markPendingBackup(routine, modifiedAt: routine.updatedAt)
        try modelContext.save()
        kickBackup()
    }

    /// Permanently deletes a routine, locally and in the cloud backup.
    ///
    /// The tombstone is written in the same transaction as the local delete.
    /// Doing it the other way round - delete now, remember later - is how a
    /// crash between the two leaves a routine that comes back on the next
    /// restore.
    func deleteRoutine(_ routine: Routine) throws {
        try syncCoordinator.enqueuePendingDeletion(
            recordId: routine.id,
            kind: .routine,
            ownerUserId: routine.ownerUserId ?? currentUserId(),
            modelContext: modelContext
        )
        modelContext.delete(routine)
        try modelContext.save()
        kickBackup()
    }

    // MARK: - Folder Operations

    @discardableResult
    func createFolder(
        name: String,
        colorHex: String? = nil,
        order: Int = 0
    ) throws -> RoutineFolder {
        let folder = RoutineFolder(name: name, colorHex: colorHex, order: order)
        modelContext.insert(folder)
        markPendingBackup(folder)
        try modelContext.save()
        kickBackup()
        return folder
    }

    func updateFolder(_ folder: RoutineFolder) throws {
        let modifiedAt = Date()
        folder.updatedAt = modifiedAt
        markPendingBackup(folder, modifiedAt: modifiedAt)
        try modelContext.save()
        kickBackup()
    }

    func deleteFolder(_ folder: RoutineFolder) throws {
        try syncCoordinator.enqueuePendingDeletion(
            recordId: folder.id,
            kind: .folder,
            ownerUserId: folder.ownerUserId ?? currentUserId(),
            modelContext: modelContext
        )
        modelContext.delete(folder)
        try modelContext.save()
        kickBackup()
    }

    func getAllFolders() throws -> [RoutineFolder] {
        try modelContext.fetch(
            FetchDescriptor<RoutineFolder>(sortBy: [SortDescriptor(\.order), SortDescriptor(\.name)])
        )
    }

    // MARK: - Cloud Backup

    /// Flags a routine for upload. Templates are skipped: they are server-owned
    /// catalog content, and `firestore.rules` refuses to store one under a
    /// climber's uid.
    private func markPendingBackup(_ routine: Routine, modifiedAt: Date = Date()) {
        guard routine.isUserAuthored, let userId = routine.ownerUserId ?? currentUserId() else {
            return
        }

        routine.markPendingRemoteUpsert(ownerUserId: userId, modifiedAt: modifiedAt)
    }

    private func markPendingBackup(_ folder: RoutineFolder, modifiedAt: Date = Date()) {
        guard let userId = folder.ownerUserId ?? currentUserId() else { return }

        folder.markPendingRemoteUpsert(ownerUserId: userId, modifiedAt: modifiedAt)
    }

    /// Backup is mutation-driven, not deferred to the next launch, so a routine
    /// the climber just built is safe before they close the app.
    private func kickBackup() {
        guard let userId = currentUserId() else { return }

        let modelContext = modelContext
        let syncCoordinator = syncCoordinator
        Task { @MainActor in
            await syncCoordinator.processPendingRoutines(
                modelContext: modelContext,
                currentUserId: userId
            )
        }
    }

    // MARK: - Built-in Template Initialization

    /// Ensures built-in routines exist in the database (call on app launch)
    func ensureBuiltInRoutinesExist() throws {
        let baseLevel = SettingsManager.shared.effectiveBaseLevel
        let resolvedTemplates = BuiltInRoutines.resolvedTemplates(for: baseLevel)
        let expectedTemplateIds = Set(resolvedTemplates.compactMap(\.templateId))
        let builtinRaw = RoutineSource.builtin.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.sourceRawValue == builtinRaw }
        )
        let existingBuiltIns = try modelContext.fetch(descriptor)
        let existingByTemplateId = existingBuiltIns.reduce(into: [String: Routine]()) { result, routine in
            guard let templateId = routine.templateId else { return }
            result[templateId] = routine
        }
        var didChange = false

        for existingRoutine in existingBuiltIns where !expectedTemplateIds.contains(existingRoutine.templateId ?? "") {
            modelContext.delete(existingRoutine)
            didChange = true
        }

        for template in resolvedTemplates {
            guard let templateId = template.templateId else { continue }

            if let existingRoutine = existingByTemplateId[templateId] {
                didChange = updateTemplateRoutine(
                    existingRoutine,
                    using: template,
                    expectedSource: .builtin
                ) || didChange
            } else {
                modelContext.insert(template)
                didChange = true
            }
        }

        if didChange {
            try modelContext.save()
        }
    }

    func refreshRemoteRoutineTemplates() async throws {
        let baseLevel = SettingsManager.shared.effectiveBaseLevel
        let remoteTemplates = try await templateRepository.fetchPublishedTemplates()
        let resolvedTemplates = remoteTemplates.map { $0.resolvedRoutine(baseLevel: baseLevel) }
        let expectedTemplateIds = Set(resolvedTemplates.compactMap(\.templateId))
        let remoteTemplateRaw = RoutineSource.remoteTemplate.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.sourceRawValue == remoteTemplateRaw }
        )
        let existingRemoteTemplates = try modelContext.fetch(descriptor)
        let existingByTemplateId = existingRemoteTemplates.reduce(into: [String: Routine]()) { result, routine in
            guard let templateId = routine.templateId else { return }
            result[templateId] = routine
        }
        var didChange = false

        for existingRoutine in existingRemoteTemplates where !expectedTemplateIds.contains(existingRoutine.templateId ?? "") {
            modelContext.delete(existingRoutine)
            didChange = true
        }

        for template in resolvedTemplates {
            guard let templateId = template.templateId else { continue }

            if let existingRoutine = existingByTemplateId[templateId] {
                didChange = updateTemplateRoutine(
                    existingRoutine,
                    using: template,
                    expectedSource: .remoteTemplate
                ) || didChange
            } else {
                modelContext.insert(template)
                didChange = true
            }
        }

        if didChange {
            try modelContext.save()
        }
    }

    /// Returns the count of user routines
    func getUserRoutineCount() throws -> Int {
        let builtinRaw = RoutineSource.builtin.rawValue
        let remoteTemplateRaw = RoutineSource.remoteTemplate.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate {
                !$0.isArchived &&
                $0.sourceRawValue != builtinRaw &&
                $0.sourceRawValue != remoteTemplateRaw
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

    @discardableResult
    private func updateTemplateRoutine(
        _ routine: Routine,
        using template: Routine,
        expectedSource: RoutineSource
    ) -> Bool {
        var didChange = false

        if routine.name != template.name {
            routine.name = template.name
            didChange = true
        }

        if routine.routineDescription != template.routineDescription {
            routine.routineDescription = template.routineDescription
            didChange = true
        }

        if routine.intervals != template.intervals {
            routine.intervals = template.intervals
            didChange = true
        }

        if routine.difficulty != template.difficulty {
            routine.difficulty = template.difficulty
            didChange = true
        }

        if routine.estimatedCalories != template.estimatedCalories {
            routine.estimatedCalories = template.estimatedCalories
            didChange = true
        }

        if routine.templateVersion != template.templateVersion {
            routine.templateVersion = template.templateVersion
            didChange = true
        }

        if routine.browseSections != template.browseSections {
            routine.browseSections = template.browseSections
            didChange = true
        }

        if routine.isFeaturedTemplate != template.isFeaturedTemplate {
            routine.isFeaturedTemplate = template.isFeaturedTemplate
            didChange = true
        }

        if routine.templateDisplayOrder != template.templateDisplayOrder {
            routine.templateDisplayOrder = template.templateDisplayOrder
            didChange = true
        }

        if routine.templateFeaturedOrder != template.templateFeaturedOrder {
            routine.templateFeaturedOrder = template.templateFeaturedOrder
            didChange = true
        }

        if routine.defaultWeightConfigurationData != template.defaultWeightConfigurationData {
            routine.defaultWeightConfigurationData = template.defaultWeightConfigurationData
            didChange = true
        }

        if routine.isArchived {
            routine.isArchived = false
            didChange = true
        }

        if routine.source != expectedSource {
            routine.source = expectedSource
            didChange = true
        }

        if didChange {
            routine.updatedAt = Date()
        }

        return didChange
    }
}
