import Foundation
import SwiftData

/// The optional half of a hand-logged climb: everything the climber may add after the two numbers
/// that make it one.
struct LoggedClimbDetails: Equatable, Sendable {
    var effortRating: Double?
    var averageHeartRate: Int?
    var note: String = ""
}

/// Turns a validated Log a climb entry into a saved `Workout`, through the same pipeline every
/// recorded climb takes.
///
/// A hand-logged climb counts toward the streak, the weekly target, gear, history, personal
/// records and - when the pace check clears it - the leaderboards, so it has to reach every one
/// of them the way a Live Climb does: inserted, saved, then announced through
/// `WorkoutMutationHandler.workoutsDidChange`, which is what refreshes the local standings, the
/// Best Effort cache and Home, and queues the cloud backup. Nothing here writes to Firestore
/// directly.
///
/// The pace check runs inside `makeWorkout`, before the leaderboard snapshot is taken, so the
/// device's record of the verdict and the overlay it draws from agree from the first frame. The
/// server derives the same verdict again from the stored evidence and never reads this one.
@MainActor
enum LoggedClimbService {
    /// What a logged climb is called. The date already says when; the name only says what.
    static let workoutName = "Stair Stepper"

    /// Builds the workout for a climb that passed validation, or nil when it did not.
    ///
    /// Returns nil rather than building a climb the cloud would refuse: the caller has already
    /// shown the climber why, and an unsaveable `Workout` must never reach the store.
    static func makeWorkout(
        input: LoggedClimbInput,
        details: LoggedClimbDetails,
        photos: [Photo] = [],
        now: Date = Date()
    ) -> Workout? {
        guard case .ready = LoggedClimbValidation.validate(input, now: now),
              let steps = input.steps,
              let floors = input.floors,
              let duration = input.duration else {
            return nil
        }

        let workout = Workout(
            name: workoutName,
            date: input.date,
            duration: duration,
            steps: steps,
            floors: floors,
            notes: details.note.trimmingCharacters(in: .whitespacesAndNewlines),
            avgHeartRate: details.averageHeartRate,
            effortRating: details.effortRating,
            source: .manual,
            photos: photos
        )
        workout.refreshLeaderboardStatus()
        return workout
    }

    /// Inserts and saves the workout, then announces it so every derived surface catches up.
    static func save(_ workout: Workout, modelContext: ModelContext) throws {
        modelContext.insert(workout)
        try modelContext.save()
        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: .created([LeaderboardWorkoutSnapshot(workout: workout)]),
            newWorkouts: [workout],
            changedWorkouts: [workout]
        )
    }
}
