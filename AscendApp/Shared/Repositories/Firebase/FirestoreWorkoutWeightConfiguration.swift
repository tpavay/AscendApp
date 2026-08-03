import Foundation

/// The Firestore spelling of `WeightConfiguration`.
///
/// Named for the workout document that introduced it, but shared with the user
/// routine document's `defaultWeightConfiguration`, which stores the identical
/// shape and is validated by the same `isValidWorkoutWeightConfiguration` rule.
/// One spelling, one validator, one decoder.
struct FirestoreWorkoutWeightConfiguration: Codable, Equatable, Sendable {
    /// The most entries one configuration may store, mirroring
    /// `isValidWorkoutWeightEntryList` in `firestore.rules`. The rule also
    /// requires the equipment types across those entries to be distinct.
    static let maxEntries = 5

    let entries: [FirestoreWorkoutWeightEntry]

    init(entries: [FirestoreWorkoutWeightEntry]) {
        self.entries = entries
    }
}
