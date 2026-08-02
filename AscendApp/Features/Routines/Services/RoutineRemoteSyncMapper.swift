import Foundation

enum RoutineSyncError: LocalizedError, Equatable {
    case missingOwner
    case notUserAuthored
    case tooManyIntervals(count: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .missingOwner:
            return "Routine has no owner, so it cannot be backed up."
        case .notUserAuthored:
            return "Catalog routines are server-owned content and are never backed up."
        case let .tooManyIntervals(count, limit):
            return "Routine has \(count) intervals; the backup accepts at most \(limit)."
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

        let intervals = routine.intervals
        guard intervals.count <= FirestoreUserRoutineDocument.maxIntervals else {
            throw RoutineSyncError.tooManyIntervals(
                count: intervals.count,
                limit: FirestoreUserRoutineDocument.maxIntervals
            )
        }

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
            defaultWeightConfiguration: weightConfiguration(from: routine.defaultWeightConfiguration),
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
