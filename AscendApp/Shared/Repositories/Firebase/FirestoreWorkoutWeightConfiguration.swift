import Foundation

struct FirestoreWorkoutWeightConfiguration: Codable, Equatable, Sendable {
    let entries: [FirestoreWorkoutWeightEntry]

    init(entries: [FirestoreWorkoutWeightEntry]) {
        self.entries = entries
    }
}
