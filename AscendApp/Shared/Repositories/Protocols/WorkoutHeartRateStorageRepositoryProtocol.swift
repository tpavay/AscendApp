import Foundation

protocol WorkoutHeartRateStorageRepositoryProtocol: Sendable {
    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob

    func deleteHeartRateSeriesIfPresent(
        userId: String,
        workoutId: UUID
    ) async throws
}
