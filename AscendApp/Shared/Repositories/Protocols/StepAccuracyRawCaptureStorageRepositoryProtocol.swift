import Foundation

protocol StepAccuracyRawCaptureStorageRepositoryProtocol: Sendable {
    /// Uploads a raw capture. Fire-and-forget from the caller's perspective - there is no
    /// download or reference-tracking path in the app, because nothing in Ascend reads this data
    /// back; it exists purely for the captain's own offline debugging in the Storage console.
    func uploadRawCapture(
        userId: String,
        workoutId: UUID,
        blob: StepAccuracyRawCaptureBlob
    ) async throws
}
