import Foundation
@preconcurrency import FirebaseFirestore

final class WorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol, @unchecked Sendable {
    static let shared = WorkoutRemoteRepository()

    private let db = Firestore.firestore()

    private init() {}

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
        try await workoutDocumentReference(userId: userId, workoutId: workoutId).delete()
    }
}

private extension WorkoutRemoteRepository {
    func workoutDocumentReference(userId: String, workoutId: UUID) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("workouts")
            .document(workoutId.uuidString)
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
        [
            "storagePath": reference.storagePath,
            "encoding": reference.encoding,
            "sampleCount": reference.sampleCount,
            "seriesStartAt": Timestamp(date: reference.seriesStartAt),
            "seriesEndAt": Timestamp(date: reference.seriesEndAt)
        ]
    }
}
