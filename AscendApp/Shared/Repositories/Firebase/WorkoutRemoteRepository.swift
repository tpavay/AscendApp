import Foundation
@preconcurrency import FirebaseFirestore

final class WorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol, @unchecked Sendable {
    static let shared = WorkoutRemoteRepository()

    private let db = Firestore.firestore()

    private init() {}

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        let snapshot = try await workoutCollectionReference(userId: userId).getDocuments()
        return decodeRecords(
            from: snapshot.documents.map { (id: $0.documentID, data: $0.data()) }
        )
    }

    /// Decodes each raw backup independently. One un-decodable document (a missing or mistyped
    /// field) must cost only that record, never zero the whole restore, so a bad row is skipped
    /// with a diagnostic and every document that decodes is returned. Documents are grouped by
    /// canonical id once, so the case-variant diagnostic and the surviving record are decided
    /// from the same grouping and cannot disagree. Kept separate from the Firestore fetch so the
    /// resilience is testable without a live backend.
    func decodeRecords(
        from documents: [(id: String, data: [String: Any])],
        diagnostics: AppDiagnosticsRecorder = .shared
    ) -> [RemoteWorkoutRecord] {
        let identified = documents.compactMap { document -> (canonicalID: String, id: String, data: [String: Any])? in
            guard let canonicalID = WorkoutDocumentID.canonicalString(from: document.id) else {
                return nil
            }
            return (canonicalID, document.id, document.data)
        }

        return Dictionary(grouping: identified, by: \.canonicalID)
            .sorted { $0.key < $1.key }
            .compactMap { canonicalID, group in
                recordCaseVariantDuplicateIfNeeded(
                    canonicalID: canonicalID,
                    sourceIDs: group.map(\.id),
                    diagnostics: diagnostics
                )
                return survivingRecord(in: group, diagnostics: diagnostics)
            }
    }

    private func recordCaseVariantDuplicateIfNeeded(
        canonicalID: String,
        sourceIDs: [String],
        diagnostics: AppDiagnosticsRecorder
    ) {
        let distinctSourceIDs = Set(sourceIDs)
        guard distinctSourceIDs.count > 1 else { return }

        diagnostics.record(
            "workout_backup_case_variant_duplicate",
            level: .error,
            details: [
                "canonical_workout_id": canonicalID,
                "document_ids": distinctSourceIDs.sorted().joined(separator: ",")
            ]
        )
    }

    /// Picks the one backup to restore for a canonical workout id: newest payload wins, and the
    /// canonical spelling breaks a tie so a stale alias cannot outrank the document the app writes.
    private func survivingRecord(
        in group: [(canonicalID: String, id: String, data: [String: Any])],
        diagnostics: AppDiagnosticsRecorder
    ) -> RemoteWorkoutRecord? {
        var selected: (sourceID: String, record: RemoteWorkoutRecord)?

        for document in group {
            guard let workoutId = UUID(uuidString: document.id) else { continue }

            let decoded: FirestoreWorkoutDocument
            do {
                decoded = try firestoreDocument(from: document.data)
            } catch {
                diagnostics.record(
                    "workout_backup_decode_failed",
                    level: .warning,
                    details: [
                        "workout_id": document.id,
                        "reason": decodeFailureReason(error)
                    ]
                )
                continue
            }

            let candidate = (
                sourceID: document.id,
                record: RemoteWorkoutRecord(workoutId: workoutId, document: decoded)
            )
            guard let existing = selected else {
                selected = candidate
                continue
            }

            if candidate.record.document.updatedAt > existing.record.document.updatedAt ||
                (
                    candidate.record.document.updatedAt == existing.record.document.updatedAt &&
                    WorkoutDocumentID.isCanonical(candidate.sourceID) &&
                    !WorkoutDocumentID.isCanonical(existing.sourceID)
                ) {
                selected = candidate
            }
        }

        return selected?.record
    }

    private func decodeFailureReason(_ error: Error) -> String {
        if case let WorkoutRemoteRepositoryDecodingError.missingField(field) = error {
            return "missing_field:\(field)"
        }
        return String(describing: type(of: error))
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {
        let docRef = workoutDocumentReference(userId: userId, workoutId: workoutId)
        try await docRef.setData(firestoreData(for: document))
    }

    func deleteWorkout(
        userId: String,
        workoutId: UUID
    ) async throws {
        let collection = workoutCollectionReference(userId: userId)
        let batch = db.batch()
        batch.deleteDocument(workoutDocumentReference(userId: userId, workoutId: workoutId))
        for alias in WorkoutDocumentID.aliasStrings(for: workoutId) {
            batch.deleteDocument(collection.document(alias))
        }
        try await batch.commit()
    }
}

private extension WorkoutRemoteRepository {
    func workoutCollectionReference(userId: String) -> CollectionReference {
        db.collection("users")
            .document(userId)
            .collection("workouts")
    }

    func workoutDocumentReference(userId: String, workoutId: UUID) -> DocumentReference {
        workoutCollectionReference(userId: userId)
            .document(WorkoutDocumentID.canonicalString(for: workoutId))
    }

    func firestoreData(for document: FirestoreWorkoutDocument) -> [String: Any] {
        var data: [String: Any] = [
            "userId": document.userId,
            "schemaVersion": document.schemaVersion,
            "name": document.name,
            "startedAt": Timestamp(date: document.startedAt),
            "durationSeconds": document.durationSeconds,
            "steps": document.steps,
            "floors": document.floors,
            "stepsPerFloor": document.stepsPerFloor,
            "notes": document.notes,
            "source": document.source,
            "integrityLevel": document.integrityLevel,
            "createdAt": Timestamp(date: document.createdAt),
            "updatedAt": Timestamp(date: document.updatedAt)
        ]

        if let climbId = document.climbId {
            data["climbId"] = climbId
        }

        if let avgHeartRateBpm = document.avgHeartRateBpm {
            data["avgHeartRateBpm"] = avgHeartRateBpm
        }
        if let maxHeartRateBpm = document.maxHeartRateBpm {
            data["maxHeartRateBpm"] = maxHeartRateBpm
        }
        if let caloriesBurned = document.caloriesBurned {
            data["caloriesBurned"] = caloriesBurned
        }
        if let effortRating = document.effortRating {
            data["effortRating"] = effortRating
        }
        if let averageMETs = document.averageMETs {
            data["averageMETs"] = averageMETs
        }
        if let deviceModel = document.deviceModel {
            data["deviceModel"] = deviceModel
        }
        if let sourceMetadata = document.sourceMetadata {
            data["sourceMetadata"] = sourceMetadata
        }
        if let healthKitUUID = document.healthKitUUID {
            data["healthKitUUID"] = healthKitUUID
        }
        if let hevyWorkoutId = document.hevyWorkoutId {
            data["hevyWorkoutId"] = hevyWorkoutId
        }
        if let media = document.media {
            data["media"] = media.map(firestoreMediaItem(_:))
        }
        if let highlightedMediaId = document.highlightedMediaId {
            data["highlightedMediaId"] = highlightedMediaId
        }
        if let weightConfiguration = document.weightConfiguration {
            data["weightConfiguration"] = firestoreWeightConfiguration(weightConfiguration)
        }
        if let heartRateSeries = document.heartRateSeries {
            data["heartRateSeries"] = firestoreHeartRateSeriesReference(heartRateSeries)
        }
        if let participations = document.participations {
            data["participations"] = participations.map(firestoreParticipation(_:))
        }

        return data
    }

    func firestoreMediaItem(_ item: FirestoreWorkoutMediaItem) -> [String: Any] {
        var data: [String: Any] = [
            "id": item.id,
            "url": item.url,
            "uploadedAt": Timestamp(date: item.uploadedAt),
            "type": item.type
        ]
        if let durationSeconds = item.durationSeconds {
            data["durationSeconds"] = durationSeconds
        }
        return data
    }

    func firestoreWeightConfiguration(_ config: FirestoreWorkoutWeightConfiguration) -> [String: Any] {
        [
            "entries": config.entries.map { entry in
                [
                    "id": entry.id,
                    "equipmentType": entry.equipmentType,
                    "weightValue": entry.weightValue,
                    "isEnabled": entry.isEnabled
                ]
            }
        ]
    }

    func firestoreHeartRateSeriesReference(
        _ reference: FirestoreWorkoutHeartRateSeriesReference
    ) -> [String: Any] {
        var data: [String: Any] = [
            "storagePath": reference.storagePath,
            "encoding": reference.encoding,
            "sampleCount": reference.sampleCount,
            "seriesStartAt": Timestamp(date: reference.seriesStartAt),
            "seriesEndAt": Timestamp(date: reference.seriesEndAt)
        ]
        if let objectSchemaVersion = reference.objectSchemaVersion {
            data["objectSchemaVersion"] = objectSchemaVersion
        }
        if let compressedByteCount = reference.compressedByteCount {
            data["compressedByteCount"] = compressedByteCount
        }
        if let sha256 = reference.sha256 {
            data["sha256"] = sha256
        }
        return data
    }

    func firestoreParticipation(_ participation: FirestoreWorkoutParticipation) -> [String: Any] {
        [
            "id": participation.id,
            "workoutId": participation.workoutId,
            "userId": participation.userId,
            "contextType": participation.contextType,
            "contextId": participation.contextId,
            "contextVersion": participation.contextVersion,
            "rulesVersion": participation.rulesVersion,
            "role": participation.role,
            "leaderboardEligible": participation.leaderboardEligible,
            "verificationTier": participation.verificationTier,
            "metricsSnapshot": firestoreParticipationMetricsSnapshot(participation.metricsSnapshot),
            "createdAt": Timestamp(date: participation.createdAt)
        ]
    }

    func firestoreParticipationMetricsSnapshot(
        _ snapshot: FirestoreWorkoutParticipationMetricsSnapshot
    ) -> [String: Any] {
        [
            "startedAt": Timestamp(date: snapshot.startedAt),
            "durationSeconds": snapshot.durationSeconds,
            "steps": snapshot.steps,
            "floors": snapshot.floors,
            "stepsPerMinute": snapshot.stepsPerMinute
        ]
    }

    func firestoreDocument(from data: [String: Any]) throws -> FirestoreWorkoutDocument {
        FirestoreWorkoutDocument(
            userId: try stringValue("userId", in: data),
            schemaVersion: optionalIntValue("schemaVersion", in: data) ?? FirestoreWorkoutDocument.currentSchemaVersion,
            name: try stringValue("name", in: data),
            startedAt: try dateValue("startedAt", in: data),
            durationSeconds: try doubleValue("durationSeconds", in: data),
            steps: try intValue("steps", in: data),
            floors: try intValue("floors", in: data),
            stepsPerFloor: try intValue("stepsPerFloor", in: data),
            notes: try stringValue("notes", in: data),
            source: try stringValue("source", in: data),
            climbId: data["climbId"] as? String,
            integrityLevel: try stringValue("integrityLevel", in: data),
            createdAt: try dateValue("createdAt", in: data),
            updatedAt: try dateValue("updatedAt", in: data),
            avgHeartRateBpm: optionalIntValue("avgHeartRateBpm", in: data),
            maxHeartRateBpm: optionalIntValue("maxHeartRateBpm", in: data),
            caloriesBurned: optionalIntValue("caloriesBurned", in: data),
            effortRating: optionalDoubleValue("effortRating", in: data),
            averageMETs: optionalDoubleValue("averageMETs", in: data),
            deviceModel: data["deviceModel"] as? String,
            sourceMetadata: data["sourceMetadata"] as? String,
            healthKitUUID: data["healthKitUUID"] as? String,
            hevyWorkoutId: data["hevyWorkoutId"] as? String,
            media: try firestoreMediaItems(from: data["media"]),
            highlightedMediaId: data["highlightedMediaId"] as? String,
            weightConfiguration: try firestoreWeightConfiguration(from: data["weightConfiguration"]),
            heartRateSeries: try firestoreHeartRateSeriesReference(from: data["heartRateSeries"]),
            participations: try firestoreParticipations(from: data["participations"])
        )
    }

    func firestoreMediaItems(from value: Any?) throws -> [FirestoreWorkoutMediaItem]? {
        guard let items = value as? [[String: Any]] else { return nil }
        return try items.map { item in
            FirestoreWorkoutMediaItem(
                id: try stringValue("id", in: item),
                url: try stringValue("url", in: item),
                uploadedAt: try dateValue("uploadedAt", in: item),
                type: try stringValue("type", in: item),
                durationSeconds: optionalDoubleValue("durationSeconds", in: item)
            )
        }
    }

    func firestoreWeightConfiguration(from value: Any?) throws -> FirestoreWorkoutWeightConfiguration? {
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
                    isEnabled: optionalBoolValue("isEnabled", in: entry) ?? true
                )
            }
        )
    }

    func firestoreHeartRateSeriesReference(from value: Any?) throws -> FirestoreWorkoutHeartRateSeriesReference? {
        guard let data = value as? [String: Any] else { return nil }
        let objectSchemaVersion = data["objectSchemaVersion"] == nil
            ? nil
            : try intValue("objectSchemaVersion", in: data)
        let compressedByteCount = data["compressedByteCount"] == nil
            ? nil
            : try intValue("compressedByteCount", in: data)
        let sha256 = data["sha256"] == nil
            ? nil
            : try stringValue("sha256", in: data)

        return FirestoreWorkoutHeartRateSeriesReference(
            storagePath: try stringValue("storagePath", in: data),
            encoding: try stringValue("encoding", in: data),
            sampleCount: try intValue("sampleCount", in: data),
            seriesStartAt: try dateValue("seriesStartAt", in: data),
            seriesEndAt: try dateValue("seriesEndAt", in: data),
            objectSchemaVersion: objectSchemaVersion,
            compressedByteCount: compressedByteCount,
            sha256: sha256
        )
    }

    func firestoreParticipations(from value: Any?) throws -> [FirestoreWorkoutParticipation]? {
        guard let participations = value as? [[String: Any]] else { return nil }
        return try participations.map { participation in
            FirestoreWorkoutParticipation(
                id: try stringValue("id", in: participation),
                workoutId: try stringValue("workoutId", in: participation),
                userId: try stringValue("userId", in: participation),
                contextType: try stringValue("contextType", in: participation),
                contextId: try stringValue("contextId", in: participation),
                contextVersion: try intValue("contextVersion", in: participation),
                rulesVersion: try intValue("rulesVersion", in: participation),
                role: try stringValue("role", in: participation),
                leaderboardEligible: try boolValue("leaderboardEligible", in: participation),
                verificationTier: try stringValue("verificationTier", in: participation),
                metricsSnapshot: try firestoreParticipationMetricsSnapshot(from: participation["metricsSnapshot"]),
                createdAt: try dateValue("createdAt", in: participation)
            )
        }
    }

    func firestoreParticipationMetricsSnapshot(from value: Any?) throws -> FirestoreWorkoutParticipationMetricsSnapshot {
        guard let data = value as? [String: Any] else {
            throw WorkoutRemoteRepositoryDecodingError.missingField("metricsSnapshot")
        }

        return FirestoreWorkoutParticipationMetricsSnapshot(
            startedAt: try dateValue("startedAt", in: data),
            durationSeconds: try doubleValue("durationSeconds", in: data),
            steps: try intValue("steps", in: data),
            floors: try intValue("floors", in: data),
            stepsPerMinute: try doubleValue("stepsPerMinute", in: data)
        )
    }

    func stringValue(_ key: String, in data: [String: Any]) throws -> String {
        guard let value = data[key] as? String else {
            throw WorkoutRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func intValue(_ key: String, in data: [String: Any]) throws -> Int {
        guard let value = optionalIntValue(key, in: data) else {
            throw WorkoutRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func optionalIntValue(_ key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int {
            return value
        }
        if let value = data[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    func doubleValue(_ key: String, in data: [String: Any]) throws -> Double {
        guard let value = optionalDoubleValue(key, in: data) else {
            throw WorkoutRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func optionalDoubleValue(_ key: String, in data: [String: Any]) -> Double? {
        if let value = data[key] as? Double {
            return value
        }
        if let value = data[key] as? Int {
            return Double(value)
        }
        if let value = data[key] as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    func boolValue(_ key: String, in data: [String: Any]) throws -> Bool {
        guard let value = optionalBoolValue(key, in: data) else {
            throw WorkoutRemoteRepositoryDecodingError.missingField(key)
        }
        return value
    }

    func optionalBoolValue(_ key: String, in data: [String: Any]) -> Bool? {
        if let value = data[key] as? Bool {
            return value
        }
        if let value = data[key] as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    func dateValue(_ key: String, in data: [String: Any]) throws -> Date {
        if let timestamp = data[key] as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = data[key] as? Date {
            return date
        }
        throw WorkoutRemoteRepositoryDecodingError.missingField(key)
    }
}

enum WorkoutRemoteRepositoryDecodingError: Error, Equatable {
    case missingField(String)
}
