import Foundation

struct RemoteWorkoutRecord: Equatable, Sendable {
    let workoutId: UUID
    let document: FirestoreWorkoutDocument
}
