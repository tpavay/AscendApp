import Foundation
import HealthKit

/// The one handle on Apple Health's workout records.
///
/// A protocol so the import rules run against a fake in tests and on a machine with no Health
/// database. The real reader is read-only: Ascend never writes a workout to Health.
@MainActor
protocol HealthWorkoutReading: AnyObject {
    var isHealthDataAvailable: Bool { get }

    /// The stair workouts added since `anchorData`, starting on or after `earliest`.
    ///
    /// A nil anchor reads everything from `earliest`, which is how the first pass after
    /// connecting finds what is already there.
    func changes(since anchorData: Data?, startingOnOrAfter earliest: Date) async throws -> HealthWorkoutChanges

    /// A fresh read of one workout, or nil when Health no longer has it.
    func snapshot(for uuid: UUID) async throws -> HealthWorkoutSnapshot?

    /// Registers for new workouts, including while the app is not running.
    ///
    /// `onChange` runs on the main actor for every notification and receives the completion
    /// handler HealthKit is waiting on. The handler must be called exactly once per
    /// notification, whatever happened: HealthKit stops delivering until it is.
    func startObserving(onChange: @escaping @MainActor (_ completion: @escaping @Sendable () -> Void) -> Void)

    func stopObserving()
}

/// A one-shot HealthKit completion handler, safe to carry across the actor hop.
///
/// `HKObserverQueryCompletionHandler` is thread-safe by Apple's documentation but not `Sendable`;
/// the box states that once, and refuses a second call, because a handler invoked twice is
/// undefined.
private final class ObserverCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: HKObserverQueryCompletionHandler?

    init(_ handler: @escaping HKObserverQueryCompletionHandler) {
        self.handler = handler
    }

    func callAsFunction() {
        lock.lock()
        let pending = handler
        handler = nil
        lock.unlock()
        pending?()
    }
}

@MainActor
final class HealthKitWorkoutReader: HealthWorkoutReading {
    static let shared = HealthKitWorkoutReader()

    private let healthStore: HKHealthStore
    private var observerQuery: HKObserverQuery?

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    /// Stair stepper machines (`stairClimbing`) and stair workouts (`stairs`). Every other
    /// activity type is somebody else's workout and is never read.
    nonisolated static var stairActivityTypes: [HKWorkoutActivityType] {
        [.stairClimbing, .stairs]
    }

    nonisolated static func stairWorkoutPredicate() -> NSPredicate {
        NSCompoundPredicate(
            orPredicateWithSubpredicates: stairActivityTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        )
    }

    func changes(since anchorData: Data?, startingOnOrAfter earliest: Date) async throws -> HealthWorkoutChanges {
        guard isHealthDataAvailable else {
            return HealthWorkoutChanges(added: [], anchorData: anchorData)
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Self.stairWorkoutPredicate(),
            HKQuery.predicateForSamples(withStart: earliest, end: nil)
        ])
        let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            anchor: Self.unarchive(anchorData)
        )
        let result = try await descriptor.result(for: healthStore)
        return HealthWorkoutChanges(
            added: result.addedSamples.map(Self.snapshot(from:)),
            anchorData: Self.archive(result.newAnchor)
        )
    }

    func snapshot(for uuid: UUID) async throws -> HealthWorkoutSnapshot? {
        guard isHealthDataAvailable else { return nil }

        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
            sortDescriptors: [],
            limit: 1
        )
        return try await descriptor.result(for: healthStore).first.map(Self.snapshot(from:))
    }

    func startObserving(onChange: @escaping @MainActor (_ completion: @escaping @Sendable () -> Void) -> Void) {
        guard isHealthDataAvailable, observerQuery == nil else { return }

        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(
            sampleType: workoutType,
            predicate: Self.stairWorkoutPredicate()
        ) { _, completionHandler, error in
            let completion = ObserverCompletion(completionHandler)
            // An error means HealthKit has nothing to say. It still waits for the handler.
            guard error == nil else {
                completion()
                return
            }
            Task { @MainActor in
                onChange { completion() }
            }
        }
        healthStore.execute(query)
        observerQuery = query

        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
    }

    func stopObserving() {
        if let observerQuery {
            healthStore.stop(observerQuery)
        }
        observerQuery = nil
        healthStore.disableBackgroundDelivery(for: HKObjectType.workoutType()) { _, _ in }
    }

    // MARK: - Mapping

    /// A workout's numbers come from its own statistics, which are de-duplicated across the
    /// sources that wrote to it. A statistic Health did not collect reads as nil, never as zero:
    /// an imported climb with no steps asks the climber for them instead of claiming none.
    nonisolated static func snapshot(from workout: HKWorkout) -> HealthWorkoutSnapshot {
        let countUnit = HKUnit.count()
        let beatsPerMinute = countUnit.unitDivided(by: .minute())

        let steps = workout.statistics(for: HKQuantityType(.stepCount))?
            .sumQuantity()?.doubleValue(for: countUnit)
        let averageHeartRate = workout.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: beatsPerMinute)
        let maxHeartRate = workout.statistics(for: HKQuantityType(.heartRate))?
            .maximumQuantity()?.doubleValue(for: beatsPerMinute)
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        return HealthWorkoutSnapshot(
            uuid: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            steps: steps.flatMap(Self.wholeNumber),
            averageHeartRate: averageHeartRate.flatMap(Self.wholeNumber),
            maxHeartRate: maxHeartRate.flatMap(Self.wholeNumber),
            activeEnergyKilocalories: energy.flatMap(Self.wholeNumber),
            sourceName: workout.sourceRevision.source.name
        )
    }

    private nonisolated static func wholeNumber(_ value: Double) -> Int? {
        guard value.isFinite, value > 0, value < Double(Int32.max) else { return nil }
        return Int(value.rounded())
    }

    // MARK: - Anchors

    nonisolated static func archive(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    nonisolated static func unarchive(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}
