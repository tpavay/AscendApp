import Foundation
import SwiftData

/// Where one Apple Health stair workout stands with Ascend.
///
/// The ledger behind Apple Health import. One row per HealthKit workout UUID, written the first
/// time Ascend sees the workout and kept for good, because "never import the same workout twice"
/// and "a skipped workout never comes back" are both statements about a workout Ascend has already
/// met. A workout deleted in Apple Health keeps its row and its climb: the climb is the climber's
/// data.
///
/// Stored as raw values so the Imports screen and the badge can filter on them in a
/// `#Predicate`. The numbers a row carries are what Health said when it was discovered, so the
/// Not imported list renders with no HealthKit read; `AppleHealthImportService` re-reads the
/// workout at the moment it imports, because a watch can write its statistics after the workout.
@Model
final class HealthWorkoutRecord {
    /// The HealthKit workout's UUID string. The identity everything else is keyed by; a row never
    /// changes it. Not `@Attribute(.unique)` (CloudKit-compatible store), so the service dedupes.
    var workoutUUID: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var durationSeconds: Double = 0
    /// Exact steps from the workout's own statistics, or nil when Health recorded none.
    var steps: Int?
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var activeEnergyKilocalories: Int?
    /// The app or device that wrote the workout, for diagnostics only. Never shown or synced.
    var sourceName: String?
    var stateRawValue: String = HealthWorkoutImportState.notImported.rawValue
    /// The `Workout.id` of the climb this row became. Set while `state` is `imported`.
    var importedWorkoutID: UUID?
    var discoveredAt: Date = Date()
    var resolvedAt: Date?
    /// An automatic import the Home strip has not yet been shown for. Cleared when the climber
    /// opens the quick edit, finishes it, or the strip times out.
    var homeNoticePending: Bool = false

    var state: HealthWorkoutImportState {
        get { HealthWorkoutImportState(rawValue: stateRawValue) ?? .notImported }
        set { stateRawValue = newValue.rawValue }
    }

    init(snapshot: HealthWorkoutSnapshot, discoveredAt: Date = Date()) {
        self.workoutUUID = snapshot.uuid.uuidString
        self.startDate = snapshot.startDate
        self.endDate = snapshot.endDate
        self.durationSeconds = snapshot.duration
        self.steps = snapshot.steps
        self.averageHeartRate = snapshot.averageHeartRate
        self.maxHeartRate = snapshot.maxHeartRate
        self.activeEnergyKilocalories = snapshot.activeEnergyKilocalories
        self.sourceName = snapshot.sourceName
        self.discoveredAt = discoveredAt
    }

    /// Refreshes the numbers from a newer read of the same workout. Identity and state are never
    /// touched.
    func updateMeasurements(from snapshot: HealthWorkoutSnapshot) {
        startDate = snapshot.startDate
        endDate = snapshot.endDate
        durationSeconds = snapshot.duration
        steps = snapshot.steps
        averageHeartRate = snapshot.averageHeartRate
        maxHeartRate = snapshot.maxHeartRate
        activeEnergyKilocalories = snapshot.activeEnergyKilocalories
    }

    var window: ClosedRange<Date> { startDate...max(startDate, endDate) }
}

/// Where a Health workout stands.
enum HealthWorkoutImportState: String, CaseIterable, Sendable {
    /// Waiting in the Imports list for the climber, or for auto-import to take it.
    case notImported = "not_imported"
    /// Became a climb. `HealthWorkoutRecord.importedWorkoutID` names it.
    case imported
    /// The climber declined it, or removed the climb it became. Never imports again, in either
    /// mode.
    case skipped
    /// An Ascend live climb already covers this workout's window, so it is not a second climb.
    /// Kept out of Imports and out of every count. This is the named hook for the overlap merge
    /// (HANDOFF 5.2): the live climb takes the workout's heart rate and calories, and the extra
    /// minutes prompt, from this row. Nothing reads or resolves it yet.
    case overlapsLiveClimb = "overlaps_live_climb"
}
