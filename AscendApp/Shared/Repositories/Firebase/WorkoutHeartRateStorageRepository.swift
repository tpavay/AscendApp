import Foundation
import CryptoKit
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
        let storagePath = WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId)
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
            seriesEndAt: timestamps.end,
            objectSchemaVersion: blob.schemaVersion,
            compressedByteCount: gzipData.count,
            sha256: SHA256.hash(data: gzipData).map { String(format: "%02x", $0) }.joined()
        )
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        let expectedPath = WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId)
        guard reference.storagePath == expectedPath else {
            throw WorkoutHeartRateSidecarError.invalidReference
        }

        do {
            let data = try await storage.reference()
                .child(expectedPath)
                .data(maxSize: Int64(WorkoutHeartRateSidecarValidator.maximumCompressedBytes))
            return try WorkoutHeartRateSidecarValidator.validate(
                compressedData: data,
                userId: userId,
                workoutId: workoutId,
                reference: reference
            )
        } catch let error as WorkoutHeartRateSidecarError {
            throw error
        } catch let error as NSError where error.domain == StorageErrorDomain {
            switch error.code {
            case StorageErrorCode.objectNotFound.rawValue:
                throw WorkoutHeartRateSidecarError.missing
            case StorageErrorCode.unauthorized.rawValue,
                 StorageErrorCode.unauthenticated.rawValue:
                throw WorkoutHeartRateSidecarError.forbidden
            case StorageErrorCode.downloadSizeExceeded.rawValue:
                throw WorkoutHeartRateSidecarError.oversized
            case StorageErrorCode.nonMatchingChecksum.rawValue:
                throw WorkoutHeartRateSidecarError.integrityMismatch
            default:
                throw WorkoutHeartRateSidecarError.transient
            }
        } catch {
            throw WorkoutHeartRateSidecarError.transient
        }
    }

    func deleteHeartRateSeriesIfPresent(
        userId: String,
        workoutId: UUID
    ) async throws {
        let storageRef = storage.reference().child(
            WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId)
        )
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
    func seriesBounds(for samples: [HeartRateDataPoint]) -> (start: Date, end: Date) {
        let start = samples.map(\.timestamp).min() ?? .distantPast
        let end = samples.map(\.timestamp).max() ?? start
        return (start, end)
    }
}
