import Foundation
@preconcurrency import FirebaseFirestore

final class FirestoreUserRoutineRemoteRepository: UserRoutineRemoteRepositoryProtocol, @unchecked Sendable {
    static let shared = FirestoreUserRoutineRemoteRepository()

    private let db = Firestore.firestore()

    private init() {}

    func fetchRoutines(userId: String) async throws -> [RemoteUserRoutineRecord] {
        let snapshot = try await routineCollectionReference(userId: userId).getDocuments()
        return decodeRoutineRecords(
            from: snapshot.documents.map { (id: $0.documentID, data: $0.data()) }
        )
    }

    func fetchFolders(userId: String) async throws -> [RemoteRoutineFolderRecord] {
        let snapshot = try await folderCollectionReference(userId: userId).getDocuments()
        return decodeFolderRecords(
            from: snapshot.documents.map { (id: $0.documentID, data: $0.data()) }
        )
    }

    /// Decodes each backup independently.
    ///
    /// One routine written by a build whose shape this one cannot read must
    /// cost only that routine, never zero the whole restore - the same rule the
    /// workout restore learned. A document that will not decode is skipped with
    /// a diagnostic and every other one is returned. Kept separate from the
    /// Firestore fetch so the resilience is testable without a live backend.
    func decodeRoutineRecords(
        from documents: [(id: String, data: [String: Any])],
        diagnostics: AppDiagnosticsRecorder = .shared
    ) -> [RemoteUserRoutineRecord] {
        documents.compactMap { document in
            guard let routineId = UUID(uuidString: document.id) else { return nil }

            do {
                return RemoteUserRoutineRecord(
                    routineId: routineId,
                    document: try routineDocument(from: document.data)
                )
            } catch {
                recordDecodeFailure("routine_backup_decode_failed", id: document.id, error: error, diagnostics: diagnostics)
                return nil
            }
        }
    }

    func decodeFolderRecords(
        from documents: [(id: String, data: [String: Any])],
        diagnostics: AppDiagnosticsRecorder = .shared
    ) -> [RemoteRoutineFolderRecord] {
        documents.compactMap { document in
            guard let folderId = UUID(uuidString: document.id) else { return nil }

            do {
                return RemoteRoutineFolderRecord(
                    folderId: folderId,
                    document: try folderDocument(from: document.data)
                )
            } catch {
                recordDecodeFailure("routine_folder_backup_decode_failed", id: document.id, error: error, diagnostics: diagnostics)
                return nil
            }
        }
    }

    func upsertRoutine(
        userId: String,
        routineId: UUID,
        document: FirestoreUserRoutineDocument
    ) async throws {
        try await routineDocumentReference(userId: userId, routineId: routineId)
            .setData(firestoreData(for: document))
    }

    func upsertFolder(
        userId: String,
        folderId: UUID,
        document: FirestoreRoutineFolderDocument
    ) async throws {
        try await folderDocumentReference(userId: userId, folderId: folderId)
            .setData(firestoreData(for: document))
    }

    func deleteRoutine(userId: String, routineId: UUID) async throws {
        try await routineDocumentReference(userId: userId, routineId: routineId).delete()
    }

    func deleteFolder(userId: String, folderId: UUID) async throws {
        try await folderDocumentReference(userId: userId, folderId: folderId).delete()
    }
}

private extension FirestoreUserRoutineRemoteRepository {
    func routineCollectionReference(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("routines")
    }

    func folderCollectionReference(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("routine_folders")
    }

    /// `UUID.uuidString` is already the uppercase spelling `firestore.rules`
    /// requires, so there is exactly one document id per record and no case
    /// variant can fork one routine into two documents.
    func routineDocumentReference(userId: String, routineId: UUID) -> DocumentReference {
        routineCollectionReference(userId: userId).document(routineId.uuidString)
    }

    func folderDocumentReference(userId: String, folderId: UUID) -> DocumentReference {
        folderCollectionReference(userId: userId).document(folderId.uuidString)
    }

    func recordDecodeFailure(
        _ name: String,
        id: String,
        error: Error,
        diagnostics: AppDiagnosticsRecorder
    ) {
        diagnostics.record(
            name,
            level: .warning,
            details: [
                "record_id": id,
                "reason": decodeFailureReason(error)
            ]
        )
    }

    func decodeFailureReason(_ error: Error) -> String {
        if case let UserRoutineRemoteRepositoryDecodingError.missingField(field) = error {
            return "missing_field:\(field)"
        }
        return String(describing: type(of: error))
    }

    // MARK: - Encoding

    func firestoreData(for document: FirestoreUserRoutineDocument) -> [String: Any] {
        var data: [String: Any] = [
            "userId": document.userId,
            "schemaVersion": document.schemaVersion,
            "name": document.name,
            "description": document.description,
            "source": document.source,
            "intervals": document.intervals.map(firestoreInterval(_:)),
            "isArchived": document.isArchived,
            "order": document.order,
            "completionCount": document.completionCount,
            "createdAt": Timestamp(date: document.createdAt),
            "updatedAt": Timestamp(date: document.updatedAt)
        ]

        if let folderId = document.folderId {
            data["folderId"] = folderId
        }
        if let templateId = document.templateId {
            data["templateId"] = templateId
        }
        if let templateVersion = document.templateVersion {
            data["templateVersion"] = templateVersion
        }
        if let difficulty = document.difficulty {
            data["difficulty"] = difficulty
        }
        if let estimatedCalories = document.estimatedCalories {
            data["estimatedCalories"] = estimatedCalories
        }
        if let defaultWeightConfiguration = document.defaultWeightConfiguration {
            data["defaultWeightConfiguration"] = [
                "entries": defaultWeightConfiguration.entries.map { entry in
                    [
                        "id": entry.id,
                        "equipmentType": entry.equipmentType,
                        "weightValue": entry.weightValue,
                        "isEnabled": entry.isEnabled
                    ]
                }
            ]
        }
        if let lastCompletedAt = document.lastCompletedAt {
            data["lastCompletedAt"] = Timestamp(date: lastCompletedAt)
        }

        return data
    }

    func firestoreData(for document: FirestoreRoutineFolderDocument) -> [String: Any] {
        var data: [String: Any] = [
            "userId": document.userId,
            "schemaVersion": document.schemaVersion,
            "name": document.name,
            "order": document.order,
            "createdAt": Timestamp(date: document.createdAt),
            "updatedAt": Timestamp(date: document.updatedAt)
        ]

        if let colorHex = document.colorHex {
            data["colorHex"] = colorHex
        }

        return data
    }

    func firestoreInterval(_ interval: FirestoreRoutineInterval) -> [String: Any] {
        var data: [String: Any] = [
            "id": interval.id,
            "durationSeconds": interval.durationSeconds,
            "intensityType": interval.intensityType,
            "intensityValue": interval.intensityValue,
            "order": interval.order
        ]

        if let sidewaysDirection = interval.sidewaysDirection {
            data["sidewaysDirection"] = sidewaysDirection
        }
        if let skipStep = interval.skipStep {
            data["skipStep"] = skipStep
        }
        if let backwardStep = interval.backwardStep {
            data["backwardStep"] = backwardStep
        }
        if let holdingBars = interval.holdingBars {
            data["holdingBars"] = holdingBars
        }
        if let weightOverrideEquipmentTypes = interval.weightOverrideEquipmentTypes {
            data["weightOverrideEquipmentTypes"] = weightOverrideEquipmentTypes
        }

        return data
    }

    // MARK: - Decoding

    func routineDocument(from data: [String: Any]) throws -> FirestoreUserRoutineDocument {
        FirestoreUserRoutineDocument(
            userId: try stringValue("userId", in: data),
            schemaVersion: optionalIntValue("schemaVersion", in: data)
                ?? FirestoreUserRoutineDocument.currentSchemaVersion,
            name: try stringValue("name", in: data),
            description: try stringValue("description", in: data),
            source: try stringValue("source", in: data),
            intervals: intervals(from: data["intervals"]),
            folderId: data["folderId"] as? String,
            isArchived: try boolValue("isArchived", in: data),
            order: try intValue("order", in: data),
            templateId: data["templateId"] as? String,
            templateVersion: optionalIntValue("templateVersion", in: data),
            difficulty: optionalIntValue("difficulty", in: data),
            estimatedCalories: optionalIntValue("estimatedCalories", in: data),
            defaultWeightConfiguration: try weightConfiguration(from: data["defaultWeightConfiguration"]),
            completionCount: optionalIntValue("completionCount", in: data) ?? 0,
            lastCompletedAt: optionalDateValue("lastCompletedAt", in: data),
            createdAt: try dateValue("createdAt", in: data),
            updatedAt: try dateValue("updatedAt", in: data)
        )
    }

    func folderDocument(from data: [String: Any]) throws -> FirestoreRoutineFolderDocument {
        FirestoreRoutineFolderDocument(
            userId: try stringValue("userId", in: data),
            schemaVersion: optionalIntValue("schemaVersion", in: data)
                ?? FirestoreRoutineFolderDocument.currentSchemaVersion,
            name: try stringValue("name", in: data),
            colorHex: data["colorHex"] as? String,
            order: try intValue("order", in: data),
            createdAt: try dateValue("createdAt", in: data),
            updatedAt: try dateValue("updatedAt", in: data)
        )
    }

    /// Interval bodies are the one part of the document `firestore.rules`
    /// cannot validate element by element - the expression budget will not
    /// stretch to it - so this is where a malformed interval is caught. An
    /// interval that will not read is dropped rather than failing the whole
    /// routine: a routine restored one interval short is repairable by the
    /// climber, a routine that never restores is not.
    func intervals(from value: Any?) -> [FirestoreRoutineInterval] {
        guard let items = value as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let durationSeconds = optionalDoubleValue("durationSeconds", in: item),
                  let intensityType = item["intensityType"] as? String,
                  let intensityValue = optionalIntValue("intensityValue", in: item),
                  let order = optionalIntValue("order", in: item) else {
                return nil
            }

            return FirestoreRoutineInterval(
                id: id,
                durationSeconds: durationSeconds,
                intensityType: intensityType,
                intensityValue: intensityValue,
                order: order,
                sidewaysDirection: item["sidewaysDirection"] as? String,
                skipStep: item["skipStep"] as? Bool,
                backwardStep: item["backwardStep"] as? Bool,
                holdingBars: item["holdingBars"] as? Bool,
                weightOverrideEquipmentTypes: item["weightOverrideEquipmentTypes"] as? [String]
            )
        }
    }

    func weightConfiguration(from value: Any?) throws -> FirestoreWorkoutWeightConfiguration? {
        guard let data = value as? [String: Any],
              let entries = data["entries"] as? [[String: Any]] else {
            return nil
        }

        return FirestoreWorkoutWeightConfiguration(
            entries: try entries.map { entry in
                FirestoreWorkoutWeightEntry(
                    id: try stringValue("id", in: entry),
                    equipmentType: try stringValue("equipmentType", in: entry),
                    weightValue: try doubleValue("weightValue", in: entry),
                    isEnabled: (entry["isEnabled"] as? Bool) ?? true
                )
            }
        )
    }

    func stringValue(_ key: String, in data: [String: Any]) throws -> String {
        guard let value = data[key] as? String else {
            throw UserRoutineRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func boolValue(_ key: String, in data: [String: Any]) throws -> Bool {
        if let value = data[key] as? Bool { return value }
        if let value = data[key] as? NSNumber { return value.boolValue }
        throw UserRoutineRemoteRepositoryDecodingError.missingField(key)
    }

    func intValue(_ key: String, in data: [String: Any]) throws -> Int {
        guard let value = optionalIntValue(key, in: data) else {
            throw UserRoutineRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func optionalIntValue(_ key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? NSNumber { return value.intValue }
        return nil
    }

    func doubleValue(_ key: String, in data: [String: Any]) throws -> Double {
        guard let value = optionalDoubleValue(key, in: data) else {
            throw UserRoutineRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func optionalDoubleValue(_ key: String, in data: [String: Any]) -> Double? {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? Int { return Double(value) }
        if let value = data[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    func dateValue(_ key: String, in data: [String: Any]) throws -> Date {
        guard let value = optionalDateValue(key, in: data) else {
            throw UserRoutineRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func optionalDateValue(_ key: String, in data: [String: Any]) -> Date? {
        if let timestamp = data[key] as? Timestamp { return timestamp.dateValue() }
        if let date = data[key] as? Date { return date }
        return nil
    }
}

enum UserRoutineRemoteRepositoryDecodingError: Error, Equatable {
    case missingField(String)
}
