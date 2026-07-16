import Foundation

struct WorkoutHeartRateStorageBlob: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let workoutId: String
    let samples: [HeartRateDataPoint]

    init(
        schemaVersion: Int = WorkoutHeartRateStorageBlob.currentSchemaVersion,
        workoutId: String,
        samples: [HeartRateDataPoint]
    ) {
        self.schemaVersion = schemaVersion
        self.workoutId = workoutId
        self.samples = samples
    }
}
