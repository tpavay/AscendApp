import CryptoKit
import Foundation

enum WorkoutHeartRateSidecarValidator {
    static let maximumCompressedBytes = 5 * 1024 * 1024

    static func validate(
        compressedData: Data,
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) throws -> WorkoutHeartRateStorageBlob {
        let expectedPath = WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId)
        guard reference.storagePath == expectedPath else {
            throw WorkoutHeartRateSidecarError.invalidReference
        }
        guard reference.encoding == FirestoreWorkoutHeartRateSeriesReference.defaultEncoding else {
            throw WorkoutHeartRateSidecarError.unsupportedEncoding
        }
        guard compressedData.isEmpty == false,
              compressedData.count <= maximumCompressedBytes else {
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
              blob.samples.allSatisfy({
                  $0.heartRate > 0 &&
                    $0.heartRate <= 400 &&
                    $0.timestamp.timeIntervalSinceReferenceDate.isFinite
              }) else {
            throw WorkoutHeartRateSidecarError.malformed
        }

        let orderedSamples = blob.samples.sorted { $0.timestamp < $1.timestamp }
        guard orderedSamples.first?.timestamp == reference.seriesStartAt,
              orderedSamples.last?.timestamp == reference.seriesEndAt else {
            throw WorkoutHeartRateSidecarError.integrityMismatch
        }

        return WorkoutHeartRateStorageBlob(
            schemaVersion: blob.schemaVersion,
            workoutId: WorkoutDocumentID.canonicalString(for: workoutId),
            samples: orderedSamples
        )
    }
}
