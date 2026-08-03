import Foundation

/// Why a record can never be backed up as it stands.
///
/// Every case is a bound `firestore.rules` also enforces, so every case means
/// the server would answer a bare `PERMISSION_DENIED` - a refusal that never
/// becomes an acceptance no matter how often it is retried. The coordinator
/// turns these into `.rejected`, not `.failed`.
enum RoutineSyncError: LocalizedError, Equatable {
    case missingOwner
    case notUserAuthored
    case tooManyIntervals(count: Int, limit: Int)
    case emptyName
    case nameTooLong(count: Int, limit: Int)
    case descriptionTooLong(count: Int, limit: Int)
    case difficultyOutOfRange(value: Int, minimum: Int, maximum: Int)
    case emptyTemplateId
    case templateIdTooLong(count: Int, limit: Int)
    case negativeTemplateVersion(value: Int)
    case negativeEstimatedCalories(value: Int)
    case tooManyWeightEntries(count: Int, limit: Int)
    case duplicateWeightEquipmentTypes(count: Int, distinct: Int)
    case negativeWeightValue(equipmentType: String)

    var errorDescription: String? {
        switch self {
        case .missingOwner:
            return "Routine has no owner, so it cannot be backed up."
        case .notUserAuthored:
            return "Catalog routines are server-owned content and are never backed up."
        case let .tooManyIntervals(count, limit):
            return "Routine has \(count) intervals; the backup accepts at most \(limit)."
        case .emptyName:
            return "The backup needs a name, and this record has none."
        case let .nameTooLong(count, limit):
            return "Name is \(count) characters; the backup accepts at most \(limit)."
        case let .descriptionTooLong(count, limit):
            return "Description is \(count) characters; the backup accepts at most \(limit)."
        case let .difficultyOutOfRange(value, minimum, maximum):
            return "Difficulty is \(value); the backup accepts \(minimum) through \(maximum)."
        case .emptyTemplateId:
            return "The routine names a template with an empty id, which the backup refuses."
        case let .templateIdTooLong(count, limit):
            return "Template id is \(count) characters; the backup accepts at most \(limit)."
        case let .negativeTemplateVersion(value):
            return "Template version is \(value); the backup accepts no negative version."
        case let .negativeEstimatedCalories(value):
            return "Estimated calories is \(value); the backup accepts no negative estimate."
        case let .tooManyWeightEntries(count, limit):
            return "Routine carries \(count) weight entries; the backup accepts at most \(limit)."
        case let .duplicateWeightEquipmentTypes(count, distinct):
            return "Routine carries \(count) weight entries across only \(distinct) equipment types."
        case let .negativeWeightValue(equipmentType):
            return "The \(equipmentType) weight is negative, which the backup refuses."
        }
    }

    /// What a rejection may say out loud.
    ///
    /// Sizes and reasons only - never the name or the description themselves,
    /// which are the climber's own words.
    var diagnosticDetails: [String: String] {
        switch self {
        case .missingOwner:
            return ["reason": "missing_owner"]
        case .notUserAuthored:
            return ["reason": "not_user_authored"]
        case let .tooManyIntervals(count, limit):
            return ["reason": "too_many_intervals", "actual": "\(count)", "permitted": "\(limit)"]
        case .emptyName:
            return ["reason": "empty_name", "actual": "0", "permitted": "1"]
        case let .nameTooLong(count, limit):
            return ["reason": "name_too_long", "actual": "\(count)", "permitted": "\(limit)"]
        case let .descriptionTooLong(count, limit):
            return ["reason": "description_too_long", "actual": "\(count)", "permitted": "\(limit)"]
        case let .difficultyOutOfRange(value, minimum, maximum):
            return [
                "reason": "difficulty_out_of_range",
                "actual": "\(value)",
                "permitted": "\(minimum)...\(maximum)"
            ]
        case .emptyTemplateId:
            return ["reason": "empty_template_id", "actual": "0", "permitted": "1"]
        case let .templateIdTooLong(count, limit):
            return ["reason": "template_id_too_long", "actual": "\(count)", "permitted": "\(limit)"]
        case let .negativeTemplateVersion(value):
            return ["reason": "negative_template_version", "actual": "\(value)", "permitted": "0"]
        case let .negativeEstimatedCalories(value):
            return ["reason": "negative_estimated_calories", "actual": "\(value)", "permitted": "0"]
        case let .tooManyWeightEntries(count, limit):
            return ["reason": "too_many_weight_entries", "actual": "\(count)", "permitted": "\(limit)"]
        case let .duplicateWeightEquipmentTypes(count, distinct):
            return [
                "reason": "duplicate_weight_equipment_types",
                "actual": "\(count)",
                "permitted": "\(distinct)"
            ]
        case let .negativeWeightValue(equipmentType):
            return ["reason": "negative_weight_value", "equipment_type": equipmentType]
        }
    }
}

/// Turns a local `Routine` / `RoutineFolder` into the document that is uploaded,
/// and applies a downloaded document back onto a local record.
///
/// Pure and free of SwiftData fetches on purpose: the mapping is the part most
/// likely to silently drop a field, and it is only worth trusting if a test can
/// exercise it without a store or a backend.
enum RoutineRemoteSyncMapper {
    static func document(for routine: Routine) throws -> FirestoreUserRoutineDocument {
        guard let ownerUserId = routine.ownerUserId, !ownerUserId.isEmpty else {
            throw RoutineSyncError.missingOwner
        }
        guard routine.isUserAuthored else {
            throw RoutineSyncError.notUserAuthored
        }

        try validateName(routine.name, limit: FirestoreUserRoutineDocument.maxNameLength)

        let descriptionLength = length(of: routine.routineDescription)
        guard descriptionLength <= FirestoreUserRoutineDocument.maxDescriptionLength else {
            throw RoutineSyncError.descriptionTooLong(
                count: descriptionLength,
                limit: FirestoreUserRoutineDocument.maxDescriptionLength
            )
        }

        let intervals = routine.intervals
        guard intervals.count <= FirestoreUserRoutineDocument.maxIntervals else {
            throw RoutineSyncError.tooManyIntervals(
                count: intervals.count,
                limit: FirestoreUserRoutineDocument.maxIntervals
            )
        }

        try validateTemplateIdentity(
            templateId: routine.templateId,
            templateVersion: routine.templateVersion
        )
        try validateMetadata(
            difficulty: routine.difficulty,
            estimatedCalories: routine.estimatedCalories
        )

        let defaultWeightConfiguration = weightConfiguration(from: routine.defaultWeightConfiguration)
        try validateWeightConfiguration(defaultWeightConfiguration)

        return FirestoreUserRoutineDocument(
            userId: ownerUserId,
            name: routine.name,
            description: routine.routineDescription,
            source: routine.sourceRawValue,
            intervals: intervals.map(interval(from:)),
            folderId: routine.folderId?.uuidString,
            isArchived: routine.isArchived,
            order: max(0, routine.order),
            templateId: routine.templateId,
            templateVersion: routine.templateVersion,
            difficulty: routine.difficulty,
            estimatedCalories: routine.estimatedCalories,
            defaultWeightConfiguration: defaultWeightConfiguration,
            completionCount: max(0, routine.completionCount),
            lastCompletedAt: routine.lastCompletedAt,
            createdAt: routine.createdAt,
            updatedAt: routine.updatedAt
        )
    }

    static func document(for folder: RoutineFolder) throws -> FirestoreRoutineFolderDocument {
        guard let ownerUserId = folder.ownerUserId, !ownerUserId.isEmpty else {
            throw RoutineSyncError.missingOwner
        }

        try validateName(folder.name, limit: FirestoreRoutineFolderDocument.maxNameLength)

        return FirestoreRoutineFolderDocument(
            userId: ownerUserId,
            name: folder.name,
            colorHex: folder.colorHex,
            order: max(0, folder.order),
            createdAt: folder.createdAt,
            updatedAt: folder.effectiveUpdatedAt
        )
    }

    static func makeRoutine(
        from document: FirestoreUserRoutineDocument,
        routineId: UUID,
        userId: String
    ) -> Routine {
        let routine = Routine(id: routineId, name: document.name)
        apply(document, to: routine, userId: userId)
        return routine
    }

    static func apply(
        _ document: FirestoreUserRoutineDocument,
        to routine: Routine,
        userId: String
    ) {
        routine.name = document.name
        routine.routineDescription = document.description
        routine.sourceRawValue = document.source
        routine.intervals = document.intervals.compactMap(interval(from:))
        routine.folderId = document.folderId.flatMap(UUID.init(uuidString:))
        routine.isArchived = document.isArchived
        routine.order = document.order
        routine.templateId = document.templateId
        routine.templateVersion = document.templateVersion
        routine.difficulty = document.difficulty
        routine.estimatedCalories = document.estimatedCalories
        routine.defaultWeightConfiguration = weightConfiguration(from: document.defaultWeightConfiguration)
        routine.completionCount = document.completionCount
        routine.lastCompletedAt = document.lastCompletedAt
        routine.createdAt = document.createdAt
        routine.updatedAt = document.updatedAt
        routine.ownerUserId = userId
        routine.lastRemoteSyncAt = Date()
        routine.remoteSyncStatus = .synced
        routine.lastRemoteSyncError = nil
    }

    static func makeFolder(
        from document: FirestoreRoutineFolderDocument,
        folderId: UUID,
        userId: String
    ) -> RoutineFolder {
        let folder = RoutineFolder(id: folderId, name: document.name)
        apply(document, to: folder, userId: userId)
        return folder
    }

    static func apply(
        _ document: FirestoreRoutineFolderDocument,
        to folder: RoutineFolder,
        userId: String
    ) {
        folder.name = document.name
        folder.colorHex = document.colorHex
        folder.order = document.order
        folder.createdAt = document.createdAt
        folder.updatedAt = document.updatedAt
        folder.ownerUserId = userId
        folder.lastRemoteSyncAt = Date()
        folder.remoteSyncStatus = .synced
        folder.lastRemoteSyncError = nil
    }

    // MARK: - Field bounds

    /// Rules count a string in Unicode scalars, so the client has to count the
    /// same way. Swift's `count` measures grapheme clusters, which reads a
    /// family emoji as one character where the server reads several.
    static func length(of text: String) -> Int {
        text.unicodeScalars.count
    }

    private static func validateName(_ name: String, limit: Int) throws {
        let nameLength = length(of: name)
        guard nameLength > 0 else { throw RoutineSyncError.emptyName }
        guard nameLength <= limit else {
            throw RoutineSyncError.nameTooLong(count: nameLength, limit: limit)
        }
    }

    /// A copied catalog template carries the published template's identity and
    /// metadata through untouched, and nothing bounds what `routine_templates`
    /// publishes - so these are bounds a climber reaches by tapping Copy rather
    /// than by editing anything.
    private static func validateTemplateIdentity(
        templateId: String?,
        templateVersion: Int?
    ) throws {
        if let templateId {
            let templateIdLength = length(of: templateId)
            guard templateIdLength > 0 else { throw RoutineSyncError.emptyTemplateId }
            guard templateIdLength <= FirestoreUserRoutineDocument.maxTemplateIdLength else {
                throw RoutineSyncError.templateIdTooLong(
                    count: templateIdLength,
                    limit: FirestoreUserRoutineDocument.maxTemplateIdLength
                )
            }
        }

        if let templateVersion, templateVersion < 0 {
            throw RoutineSyncError.negativeTemplateVersion(value: templateVersion)
        }
    }

    private static func validateMetadata(difficulty: Int?, estimatedCalories: Int?) throws {
        if let difficulty,
           difficulty < FirestoreUserRoutineDocument.minDifficulty ||
            difficulty > FirestoreUserRoutineDocument.maxDifficulty {
            throw RoutineSyncError.difficultyOutOfRange(
                value: difficulty,
                minimum: FirestoreUserRoutineDocument.minDifficulty,
                maximum: FirestoreUserRoutineDocument.maxDifficulty
            )
        }

        if let estimatedCalories, estimatedCalories < 0 {
            throw RoutineSyncError.negativeEstimatedCalories(value: estimatedCalories)
        }
    }

    /// Mirrors `isValidWorkoutWeightEntryList`: at most five entries, one per
    /// equipment type, none of them carrying a negative weight.
    private static func validateWeightConfiguration(
        _ configuration: FirestoreWorkoutWeightConfiguration?
    ) throws {
        guard let configuration else { return }

        let entries = configuration.entries
        guard entries.count <= FirestoreWorkoutWeightConfiguration.maxEntries else {
            throw RoutineSyncError.tooManyWeightEntries(
                count: entries.count,
                limit: FirestoreWorkoutWeightConfiguration.maxEntries
            )
        }

        let distinctEquipmentTypes = Set(entries.map(\.equipmentType))
        guard distinctEquipmentTypes.count == entries.count else {
            throw RoutineSyncError.duplicateWeightEquipmentTypes(
                count: entries.count,
                distinct: distinctEquipmentTypes.count
            )
        }

        if let negativeEntry = entries.first(where: { $0.weightValue < 0 }) {
            throw RoutineSyncError.negativeWeightValue(equipmentType: negativeEntry.equipmentType)
        }
    }

    // MARK: - Interval mapping

    static func interval(from interval: RoutineInterval) -> FirestoreRoutineInterval {
        let modifiers = interval.modifiers

        return FirestoreRoutineInterval(
            id: interval.id.uuidString,
            durationSeconds: interval.duration,
            intensityType: interval.intensityType.rawValue,
            intensityValue: interval.intensityValue,
            order: interval.order,
            sidewaysDirection: modifiers.sidewaysDirection?.rawValue,
            skipStep: modifiers.skipStep,
            backwardStep: modifiers.backwardStep,
            holdingBars: modifiers.holdingBars,
            // Absent, empty and populated are three different instructions, so
            // the optionality has to survive the round trip rather than
            // collapsing "inherit the routine defaults" into "no weights".
            weightOverrideEquipmentTypes: modifiers.weightOverride?.enabledEquipmentTypes
                .map { $0.map(\.rawValue).sorted() }
        )
    }

    static func interval(from document: FirestoreRoutineInterval) -> RoutineInterval? {
        guard let id = UUID(uuidString: document.id),
              let intensityType = IntensityType(rawValue: document.intensityType) else {
            return nil
        }

        let equipmentTypes = document.weightOverrideEquipmentTypes
            .map { Set($0.compactMap(WeightEquipmentType.init(rawValue:))) }

        return RoutineInterval(
            id: id,
            duration: document.durationSeconds,
            intensityType: intensityType,
            intensityValue: document.intensityValue,
            modifiers: IntervalModifiers(
                sidewaysDirection: document.sidewaysDirection.flatMap(SidewaysDirection.init(rawValue:)),
                skipStep: document.skipStep ?? false,
                backwardStep: document.backwardStep ?? false,
                holdingBars: document.holdingBars ?? false,
                weightOverride: equipmentTypes.map(IntervalWeightOverride.init(enabledEquipmentTypes:))
            ),
            order: document.order
        )
    }

    // MARK: - Weight configuration mapping

    static func weightConfiguration(
        from configuration: WeightConfiguration?
    ) -> FirestoreWorkoutWeightConfiguration? {
        guard let configuration, !configuration.entries.isEmpty else { return nil }

        return FirestoreWorkoutWeightConfiguration(
            entries: configuration.entries.map { entry in
                FirestoreWorkoutWeightEntry(
                    id: entry.id.uuidString,
                    equipmentType: entry.equipmentType.rawValue,
                    weightValue: entry.weightValue,
                    isEnabled: entry.isEnabled
                )
            }
        )
    }

    static func weightConfiguration(
        from configuration: FirestoreWorkoutWeightConfiguration?
    ) -> WeightConfiguration? {
        guard let configuration else { return nil }

        let entries = configuration.entries.compactMap { entry -> WeightEntry? in
            guard let id = UUID(uuidString: entry.id),
                  let equipmentType = WeightEquipmentType(rawValue: entry.equipmentType) else {
                return nil
            }

            return WeightEntry(
                id: id,
                equipmentType: equipmentType,
                weightValue: entry.weightValue,
                isEnabled: entry.isEnabled
            )
        }

        return entries.isEmpty ? nil : WeightConfiguration(entries: entries)
    }
}
