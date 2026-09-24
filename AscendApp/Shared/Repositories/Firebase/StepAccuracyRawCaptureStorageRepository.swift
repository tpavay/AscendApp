import Foundation
import FirebaseStorage

enum StepAccuracyRawCaptureError: LocalizedError {
    /// The gzip-compressed payload still exceeds `maximumCompressedBytes` despite the sample-
    /// count cap in `HeadphoneMotionRawCaptureLimits` and the quantized sample shape, which keep a
    /// full-cap capture near a third of the bound (see `maximumSampleCount`). Uploading is
    /// skipped rather than fighting `storage.rules`' own size cap.
    case oversized

    var errorDescription: String? {
        switch self {
        case .oversized:
            return "The step-accuracy raw capture is too large to upload."
        }
    }
}

/// Uploads step-accuracy raw motion captures to Firebase Storage, modeled directly on
/// `WorkoutHeartRateStorageRepository`: JSON-encode, gzip, upload. There is no download path -
/// see `StepAccuracyRawCaptureStorageRepositoryProtocol`.
final class StepAccuracyRawCaptureStorageRepository: StepAccuracyRawCaptureStorageRepositoryProtocol, @unchecked Sendable {
    static let shared = StepAccuracyRawCaptureStorageRepository()

    /// Matches `WorkoutHeartRateSidecarValidator.maximumCompressedBytes` - the same order of
    /// magnitude bound already proven sensible for a per-workout debug blob in this app.
    static let maximumCompressedBytes = 5 * 1024 * 1024

    private let storage = Storage.storage()

    private init() {}

    func uploadRawCapture(
        userId: String,
        workoutId: UUID,
        blob: StepAccuracyRawCaptureBlob
    ) async throws {
        let encodedBlob = try JSONEncoder().encode(blob)
        let gzipData = try GzipCodec.compress(encodedBlob)
        guard gzipData.count <= Self.maximumCompressedBytes else {
            throw StepAccuracyRawCaptureError.oversized
        }

        let storagePath = StepAccuracyRawCaptureStoragePath.path(userId: userId, workoutId: workoutId)
        let storageRef = storage.reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "application/gzip"

        _ = try await storageRef.putDataAsync(gzipData, metadata: metadata)
    }
}
