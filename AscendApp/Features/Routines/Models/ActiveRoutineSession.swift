import Foundation

/// Tracks the state of an active guided workout session (not persisted)
struct ActiveRoutineSession {
    let routine: Routine
    let startedAt: Date

    var currentIntervalIndex: Int = 0
    var elapsedTimeInCurrentInterval: TimeInterval = 0
    var totalElapsedTime: TimeInterval = 0
    var isPaused: Bool = false
    var pausedAt: Date?

    // Actual performance tracking (for future analytics)
    var intervalCompletions: [UUID: IntervalCompletion] = [:]

    var currentInterval: RoutineInterval? {
        let intervals = routine.intervals
        guard currentIntervalIndex < intervals.count else { return nil }
        return intervals[currentIntervalIndex]
    }

    var nextInterval: RoutineInterval? {
        let intervals = routine.intervals
        let nextIndex = currentIntervalIndex + 1
        guard nextIndex < intervals.count else { return nil }
        return intervals[nextIndex]
    }

    var remainingTimeInCurrentInterval: TimeInterval {
        guard let interval = currentInterval else { return 0 }
        return max(0, interval.duration - elapsedTimeInCurrentInterval)
    }

    var totalRemainingTime: TimeInterval {
        max(0, routine.totalDuration - totalElapsedTime)
    }

    var progress: Double {
        guard routine.totalDuration > 0 else { return 0 }
        return min(1.0, totalElapsedTime / routine.totalDuration)
    }

    var isComplete: Bool {
        currentIntervalIndex >= routine.intervals.count
    }

    var isNearIntervalEnd: Bool {
        remainingTimeInCurrentInterval <= 5 && remainingTimeInCurrentInterval > 0
    }

    var completedIntervalsCount: Int {
        currentIntervalIndex
    }

    var completionPercentage: Double {
        guard routine.intervalCount > 0 else { return 0 }
        let partialProgress = currentInterval != nil ? (elapsedTimeInCurrentInterval / (currentInterval?.duration ?? 1)) : 0
        return (Double(completedIntervalsCount) + partialProgress) / Double(routine.intervalCount)
    }
}

/// Tracks completion data for a single interval
struct IntervalCompletion: Codable {
    let intervalId: UUID
    let startedAt: Date
    let completedAt: Date?
    let skipped: Bool
}
