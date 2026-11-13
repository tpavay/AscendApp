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
    /// The workout's steps, or nil when Health holds none: what the workout's own statistics summed
    /// to, else the steps Health counted over the workout's window (`HealthWorkoutStepRule`).
    let steps: Int?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let activeEnergyKilocalories: Int?
    let sourceName: String?
    /// `HKWorkoutActivityType.rawValue`, and the bundle of the app that wrote the workout. Carried
    /// only so a workout Ascend does not count can say what it was (`HealthWorkoutSkip`); never
    /// stored and never shown.
    let activityTypeRawValue: UInt?
    let sourceBundleIdentifier: String?

    init(
        uuid: UUID,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval? = nil,
        steps: Int? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        activeEnergyKilocalories: Int? = nil,
        sourceName: String? = nil,
        activityTypeRawValue: UInt? = nil,
        sourceBundleIdentifier: String? = nil
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
        self.activityTypeRawValue = activityTypeRawValue
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    /// The same workout with a different step count.
    func withSteps(_ steps: Int?) -> HealthWorkoutSnapshot {
        HealthWorkoutSnapshot(
            uuid: uuid,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            steps: steps,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeEnergyKilocalories: activeEnergyKilocalories,
            sourceName: sourceName,
            activityTypeRawValue: activityTypeRawValue,
            sourceBundleIdentifier: sourceBundleIdentifier
        )
    }
}

/// A stair workout Ascend read from Health and did not turn into a climb, and why.
///
/// It exists to be reported once (`HealthWorkoutSkipReporter`) so the way other watches and apps
/// label a stair stepper session shows up in the numbers. Nothing here is stored.
struct HealthWorkoutSkip: Equatable, Sendable {
    enum Reason: String, Sendable {
        /// Shorter than a second or longer than a day, so not a climb.
        case duration
        /// An Ascend live climb already covers its window. The live climb is the climb.
        case overlapsLiveClimb = "overlaps_live_climb"
    }

    let uuid: UUID
    let reason: Reason
    let activityTypeRawValue: UInt?
    let sourceBundleIdentifier: String?
    let duration: TimeInterval

    init(_ snapshot: HealthWorkoutSnapshot, reason: Reason) {
        uuid = snapshot.uuid
        self.reason = reason
        activityTypeRawValue = snapshot.activityTypeRawValue
        sourceBundleIdentifier = snapshot.sourceBundleIdentifier
        duration = snapshot.duration
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
