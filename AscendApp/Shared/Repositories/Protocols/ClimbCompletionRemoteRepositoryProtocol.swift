import Foundation

/// One row of the server-derived `users/{uid}/landmarkResults` projection - the
/// authoritative completed-climb source that `ClimbCompletionRepository` reads
/// behind its cache. Derived by the `onWorkoutWritten` Cloud Function FROM the
/// canonical private workouts; the client only ever reads it.
struct RemoteLandmarkResult: Equatable, Sendable {
    let climbId: String
    let completed: Bool
    let firstCompletedAt: Date
    let latestCompletedAt: Date
    let attemptCount: Int
    let bestWorkoutId: String?
    let bestElapsedSeconds: Int?
}

/// The transport behind `ClimbCompletionRepository`. Injectable so the
/// repository's reconcile/refresh is testable without a live Firestore.
protocol ClimbCompletionRemoteRepositoryProtocol: Sendable {
    func fetchLandmarkResults(userId: String) async throws -> [RemoteLandmarkResult]
}
