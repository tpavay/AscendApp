import Foundation
import FirebaseStorage

final class WorkoutHeartRateStorageRepository: WorkoutHeartRateStorageRepositoryProtocol, @unchecked Sendable {
    static let shared = WorkoutHeartRateStorageRepository()

    private let storage = Storage.storage()

    private init() {}

    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        let storagePath = storagePath(userId: userId, workoutId: workoutId)
        let storageRef = storage.reference().child(storagePath)

        let encodedBlob = try JSONEncoder().encode(blob)
        let gzipData = try GzipCodec.compress(encodedBlob)
        let metadata = StorageMetadata()
        metadata.contentType = "application/gzip"

        let _ = try await storageRef.putDataAsync(gzipData, metadata: metadata)

        let timestamps = seriesBounds(for: blob.samples)
        return FirestoreWorkoutHeartRateSeriesReference(
            storagePath: storagePath,
            sampleCount: blob.samples.count,
            seriesStartAt: timestamps.start,
            seriesEndAt: timestamps.end
        )
    }

    func deleteHeartRateSeriesIfPresent(
        userId: String,
        workoutId: UUID
    ) async throws {
        let storageRef = storage.reference().child(storagePath(userId: userId, workoutId: workoutId))
        do {
            try await storageRef.delete()
        } catch let error as NSError {
            if error.domain == StorageErrorDomain,
               error.code == StorageErrorCode.objectNotFound.rawValue {
                return
            }
            throw error
        }
    }
}

private extension WorkoutHeartRateStorageRepository {
    func storagePath(userId: String, workoutId: UUID) -> String {
        "users/\(userId)/workout_heart_rate/\(workoutId.uuidString).json.gz"
    }

    func seriesBounds(for samples: [HeartRateDataPoint]) -> (start: Date, end: Date) {
        let start = samples.map(\.timestamp).min() ?? .distantPast
        let end = samples.map(\.timestamp).max() ?? start
        return (start, end)
    }
}
