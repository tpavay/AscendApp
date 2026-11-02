import Foundation

/// How a Health workout becomes a climb.
///
/// A climb with `source` `.appleHealth`, keyed by the workout's UUID in `healthKitUUID` - which is
/// both the dedupe key and the thing that travels with the climb through the cloud backup.
/// Everything the workout's own statistics said lands on it: exact steps, average and maximum
/// heart rate, active energy. A workout with no step count arrives with zero steps, which
/// `Workout.isMissingSteps` reads as absent and WorkoutDetailView answers with the Add steps
/// prompt.
@MainActor
enum HealthImportedClimb {
    static let workoutName = "Stair Stepper"

    static func makeWorkout(from record: HealthWorkoutRecord) -> Workout {
        makeWorkout(from: HealthWorkoutSnapshot(record: record))
    }

    static func makeWorkout(from snapshot: HealthWorkoutSnapshot) -> Workout {
        let steps = AppleHealthImportPolicy.importableSteps(snapshot.steps, duration: snapshot.duration) ?? 0

        let workout = Workout(
            name: workoutName,
            date: snapshot.startDate,
            duration: snapshot.duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps),
            avgHeartRate: snapshot.averageHeartRate,
            maxHeartRate: snapshot.maxHeartRate,
            caloriesBurned: snapshot.activeEnergyKilocalories,
            source: .appleHealth,
            healthKitUUID: snapshot.uuid.uuidString
        )
        // The same automatic check a typed climb faces, read once at creation: there is no earlier
        // verdict to preserve, so it does not go through the kill-switch-gated refresh.
        workout.leaderboardStatus = ClimbPacePolicy.leaderboardStatus(
            origin: .healthImport,
            steps: steps,
            duration: snapshot.duration
        )
        return workout
    }
}

extension HealthWorkoutSnapshot {
    init(record: HealthWorkoutRecord) {
        self.init(
            uuid: UUID(uuidString: record.workoutUUID) ?? UUID(),
            startDate: record.startDate,
            endDate: record.endDate,
            duration: record.durationSeconds,
            steps: record.steps,
            averageHeartRate: record.averageHeartRate,
            maxHeartRate: record.maxHeartRate,
            activeEnergyKilocalories: record.activeEnergyKilocalories,
            sourceName: record.sourceName
        )
    }
}
