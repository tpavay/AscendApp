import CryptoKit
import Foundation

enum WorkoutHeartRateSidecarValidator {
    static let maximumCompressedBytes = 5 * 1024 * 1024

    /// Firestore quantises reference bounds to whole nanoseconds through `Timestamp`, while the
    /// sidecar blob round-trips its sample timestamps as full-precision doubles. The two endpoints
    /// can therefore only ever agree to within that quantisation.
    static let boundsToleranceSeconds: TimeInterval = 0.001

    static func validatedStoragePath(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) throws -> String {
        let expectedPath = WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId)
        guard reference.storagePath == expectedPath else {
            throw WorkoutHeartRateSidecarError.invalidReference
        }
        return expectedPath
    }

    static func validate(
        compressedData: Data,
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) throws -> WorkoutHeartRateStorageBlob {
        _ = try validatedStoragePath(
            userId: userId,
            workoutId: workoutId,
            reference: reference
        )
        guard reference.encoding == FirestoreWorkoutHeartRateSeriesReference.defaultEncoding else {
            throw WorkoutHeartRateSidecarError.unsupportedEncoding
        }
        guard compressedData.isEmpty == false else {
            throw WorkoutHeartRateSidecarError.malformed
        }
        guard compressedData.count <= maximumCompressedBytes else {
            throw WorkoutHeartRateSidecarError.oversized
        }
        guard reference.compressedByteCount.map({ $0 == compressedData.count }) ?? true else {
            throw WorkoutHeartRateSidecarError.integrityMismatch
        }

        if let expectedHash = reference.sha256 {
            let actualHash = SHA256.hash(data: compressedData)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actualHash == expectedHash else {
                throw WorkoutHeartRateSidecarError.integrityMismatch
            }
        }

        let blob: WorkoutHeartRateStorageBlob
        do {
            let data = try GzipCodec.decompress(compressedData)
            blob = try JSONDecoder().decode(WorkoutHeartRateStorageBlob.self, from: data)
        } catch {
            throw WorkoutHeartRateSidecarError.malformed
        }

        guard blob.schemaVersion == WorkoutHeartRateStorageBlob.currentSchemaVersion,
              reference.objectSchemaVersion.map({ $0 == blob.schemaVersion }) ?? true,
              WorkoutDocumentID.canonicalString(from: blob.workoutId) ==
                WorkoutDocumentID.canonicalString(for: workoutId),
              blob.samples.count == reference.sampleCount,
              blob.samples.isEmpty == false,
              blob.samples.allSatisfy(WorkoutHeartRatePlausibility.isPlausibleSample) else {
            throw WorkoutHeartRateSidecarError.malformed
        }

        let orderedSamples = blob.samples.sorted { $0.timestamp < $1.timestamp }
        guard let firstTimestamp = orderedSamples.first?.timestamp,
              let lastTimestamp = orderedSamples.last?.timestamp,
              abs(firstTimestamp.timeIntervalSince(reference.seriesStartAt)) <= boundsToleranceSeconds,
              abs(lastTimestamp.timeIntervalSince(reference.seriesEndAt)) <= boundsToleranceSeconds else {
            throw WorkoutHeartRateSidecarError.integrityMismatch
        }

        return WorkoutHeartRateStorageBlob(
            schemaVersion: blob.schemaVersion,
            workoutId: WorkoutDocumentID.canonicalString(for: workoutId),
            samples: orderedSamples
        )
    }
}
