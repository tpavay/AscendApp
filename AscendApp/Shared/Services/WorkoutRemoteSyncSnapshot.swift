import Foundation

struct WorkoutRemoteSyncSnapshot: Sendable {
    let workoutId: UUID
    let userId: String
    let createdAt: Date
    let lastModifiedAt: Date
    let document: FirestoreWorkoutDocument
    let heartRateBlob: WorkoutHeartRateStorageBlob?
    let previousHeartRateSeriesStoragePath: String?
}
