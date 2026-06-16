import Foundation

enum AppleHealthWorkoutEnrichmentPolicy: CaseIterable {
    case inAppSensorWorkout

    static let inAppSessionPolicies: [AppleHealthWorkoutEnrichmentPolicy] = [
        .inAppSensorWorkout
    ]

    func isEligible(_ workout: Workout, hasAppleHealthLink: Bool) -> Bool {
        guard !hasAppleHealthLink else { return false }

        switch self {
        case .inAppSensorWorkout:
            return workout.isInAppSensorWorkout
        }
    }

    func matchScore(workout: Workout, sample: HealthKitWorkoutSample) -> Double? {
        let workoutDuration = max(workout.duration, 1)
        let workoutStart = workout.date
        let workoutEnd = workoutStart.addingTimeInterval(workoutDuration)
        let overlapStart = max(workoutStart, sample.startDate)
        let overlapEnd = min(workoutEnd, sample.endDate)
        let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
        guard overlapDuration > 0 else { return nil }

        let overlapRatio = overlapDuration / workoutDuration
        guard overlapRatio >= minimumOverlapRatio else { return nil }

        let startDelta = abs(sample.startDate.timeIntervalSince(workoutStart))
        guard startDelta <= maximumStartDelta else { return nil }

        return (overlapRatio * 100) - min(startDelta / 60, maximumStartDelta / 60)
    }

    func metricWindow(for workout: Workout, sample: HealthKitWorkoutSample) -> ClosedRange<Date>? {
        let workoutStart = workout.date
        let workoutEnd = workout.date.addingTimeInterval(max(workout.duration, 1))
        let start = max(workoutStart, sample.startDate)
        let end = min(workoutEnd, sample.endDate)

        guard end > start else { return nil }
        return start...end
    }

    private var minimumOverlapRatio: Double {
        switch self {
        case .inAppSensorWorkout:
            return 0.70
        }
    }

    private var maximumStartDelta: TimeInterval {
        switch self {
        case .inAppSensorWorkout:
            return 15 * 60
        }
    }
}
