import Foundation

protocol WorkoutHeartRateStorageRepositoryProtocol: Sendable {
    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference

    func deleteHeartRateSeriesIfPresent(
        userId: String,
        workoutId: UUID
    ) async throws
}
