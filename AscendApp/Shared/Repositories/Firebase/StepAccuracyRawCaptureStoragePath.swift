import Foundation

enum StepAccuracyRawCaptureStoragePath {
    static func path(userId: String, workoutId: UUID) -> String {
        "users/\(userId)/step_accuracy_debug/\(WorkoutDocumentID.canonicalString(for: workoutId)).json.gz"
    }
}
