import Foundation

protocol WorkoutRemoteRepositoryProtocol: Sendable {
    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord]

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
