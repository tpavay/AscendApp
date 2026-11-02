import Foundation

/// One Apple Health stair workout as HealthKit described it, with no HealthKit type in sight.
///
/// The seam between the framework and everything that decides what to do with a workout: the
/// real reader builds these from an `HKWorkout`, and a test builds them by hand, so the import
/// rules run without a device or a Health database.
struct HealthWorkoutSnapshot: Equatable, Sendable {
    let uuid: UUID
    let startDate: Date
    let endDate: Date
    /// Seconds of the workout's own timeline, not `end - start`: a paused workout is shorter than
    /// the span it covers.
    let duration: TimeInterval
    /// Exactly what the workout's statistics summed to, or nil when Health recorded no steps.
    let steps: Int?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let activeEnergyKilocalories: Int?
    let sourceName: String?

    init(
        uuid: UUID,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval? = nil,
        steps: Int? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        activeEnergyKilocalories: Int? = nil,
        sourceName: String? = nil
    ) {
        self.uuid = uuid
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration ?? endDate.timeIntervalSince(startDate)
        self.steps = steps
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.sourceName = sourceName
    }
}

/// What a read of Health found since the last anchor.
struct HealthWorkoutChanges: Equatable, Sendable {
    /// Workouts added since the anchor. A workout deleted in Health is deliberately not reported:
    /// the climb it became is the climber's data and stays.
    var added: [HealthWorkoutSnapshot]
    /// The anchor to resume from next time, in whatever encoding the reader chose.
    var anchorData: Data?
}
