import Foundation

/// The Firestore spelling of `WeightConfiguration`.
///
/// Named for the workout document that introduced it, but shared with the user
/// routine document's `defaultWeightConfiguration`, which stores the identical
/// shape and is validated by the same `isValidWorkoutWeightConfiguration` rule.
/// One spelling, one validator, one decoder.
struct FirestoreWorkoutWeightConfiguration: Codable, Equatable, Sendable {
    let entries: [FirestoreWorkoutWeightEntry]

    init(entries: [FirestoreWorkoutWeightEntry]) {
        self.entries = entries
    }
}
