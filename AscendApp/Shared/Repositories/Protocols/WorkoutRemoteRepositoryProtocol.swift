import Foundation

protocol WorkoutRemoteRepositoryProtocol: Sendable {
    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws

    func deleteWorkout(
        userId: String,
        workoutId: UUID
    ) async throws
}
