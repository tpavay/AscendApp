import Foundation

/// Says, once, that Ascend read a stair workout from Health and did not count it.
///
/// A watch or an app decides which Apple activity type its stair stepper session is saved under,
/// and Ascend only learns those mappings from what real climbers' workouts look like. So every
/// workout a read sees and passes over is reported with what it was, who wrote it and roughly how
/// long it ran - never its date, its numbers or its identifier.
@MainActor
protocol HealthWorkoutSkipReporting: AnyObject {
    func report(_ skip: HealthWorkoutSkip)
}

@MainActor
final class HealthWorkoutSkipReporter: HealthWorkoutSkipReporting {
    static let shared = HealthWorkoutSkipReporter()

    private let track: @MainActor (any TelemetryEvent) -> Void
    /// The same history is read by more than one screen in a session - 06b, then 07a, then the
    /// import itself - and each workout is one event, not three.
    private var reported: Set<UUID> = []

    init(track: @escaping @MainActor (any TelemetryEvent) -> Void = { TelemetryManager.shared.track($0) }) {
        self.track = track
    }

    func report(_ skip: HealthWorkoutSkip) {
        guard reported.insert(skip.uuid).inserted else { return }
        track(AppleHealthImportAnalyticsEvent.workoutSkipped(skip))
    }
}
