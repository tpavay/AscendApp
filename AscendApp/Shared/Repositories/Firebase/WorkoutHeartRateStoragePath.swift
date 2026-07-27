import Foundation

enum WorkoutHeartRateStoragePath {
    static func path(userId: String, workoutId: UUID) -> String {
        "users/\(userId)/workout_heart_rate/\(WorkoutDocumentID.canonicalString(for: workoutId)).json.gz"
    }
}
