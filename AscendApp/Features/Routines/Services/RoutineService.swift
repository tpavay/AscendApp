import Foundation
import SwiftData

/// Service for managing routine CRUD operations
@MainActor
final class RoutineService {
    private let modelContext: ModelContext
    private let templateRepository: RoutineTemplateRepository

    init(
        modelContext: ModelContext,
        templateRepository: RoutineTemplateRepository = FirestoreRoutineTemplateRepository.shared
    ) {
        self.modelContext = modelContext
        self.templateRepository = templateRepository
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
