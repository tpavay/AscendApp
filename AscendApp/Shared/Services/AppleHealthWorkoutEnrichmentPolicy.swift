import Foundation

enum AppleHealthWorkoutEnrichmentPolicy: CaseIterable {
    case liveClimb
    case routine

    static let inAppSessionPolicies: [AppleHealthWorkoutEnrichmentPolicy] = [
        .liveClimb,
        .routine
    ]

    func isEligible(_ workout: Workout, hasAppleHealthLink: Bool) -> Bool {
        guard !hasAppleHealthLink else { return false }

        switch self {
        case .liveClimb:
            return workout.isLiveClimbAttemptWorkout
        case .routine:
            return workout.hasRoutineParticipation
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
        case .liveClimb, .routine:
            return 0.70
        }
    }

    private var maximumStartDelta: TimeInterval {
        switch self {
        case .liveClimb, .routine:
            return 15 * 60
        }
    }
}

private extension Workout {
    var hasRoutineParticipation: Bool {
        participations.contains { participation in
            switch participation.contextType {
            case .routine, .routineTemplate:
                return true
            case .climbAttempt, .challenge, .groupChallenge, .programSession, .achievement:
                return false
            }
        }
    }
}
