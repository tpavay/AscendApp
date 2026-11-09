import Foundation
import HealthKit

/// The one handle on Apple Health's workout records.
///
/// A protocol so the import rules run against a fake in tests and on a machine with no Health
/// database. The real reader is read-only: Ascend never writes a workout to Health.
@MainActor
protocol HealthWorkoutReading: AnyObject, Sendable {
    var isHealthDataAvailable: Bool { get }

    /// The stair workouts added since `anchorData`, starting on or after `earliest`.
    ///
    /// A nil anchor reads everything from `earliest`, which is how the first pass after
    /// connecting finds what is already there.
    func changes(since anchorData: Data?, startingOnOrAfter earliest: Date) async throws -> HealthWorkoutChanges

    /// A fresh read of one workout, or nil when Health no longer has it.
    func snapshot(for uuid: UUID) async throws -> HealthWorkoutSnapshot?

    /// The steps Health counted between two moments, summed across every source that wrote them
    /// and de-duplicated where a watch and a phone overlap, or nil when it holds none.
    ///
    /// The second half of the step rule (`HealthWorkoutStepRule`): a stair workout that carries no
    /// steps of its own takes the steps Health counted while it ran.
    func stepCount(from start: Date, to end: Date) async throws -> Int?

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

    /// The activity types a stair stepper session arrives under: stair stepper machines
    /// (`stairClimbing`), stair workouts (`stairs`), and `stepTraining`, which is where some
    /// watches and apps file the same machine. Every other activity type is somebody else's
    /// workout and is never read.
    ///
    /// Growing this list means changing `AppleHealthImportSettings.anchorScope` too: a stored
    /// anchor says "nothing new" only about the types the read that produced it asked for.
    nonisolated static var stairActivityTypes: [HKWorkoutActivityType] {
        [.stairClimbing, .stairs, .stepTraining]
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

    func stepCount(from start: Date, to end: Date) async throws -> Int? {
        guard isHealthDataAvailable, end > start else { return nil }

        // A cumulative sum, so two sources that counted the same steps - a watch and the phone in
        // a pocket - are merged by Health and never added together.
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(.stepCount),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end)
            ),
            options: .cumulativeSum
        )
        do {
            let sum = try await descriptor.result(for: healthStore)?
                .sumQuantity()?.doubleValue(for: .count())
            return sum.flatMap(Self.wholeNumber)
        } catch let error as HKError where error.code == .errorNoData {
            // Health's way of saying the window holds no step samples.
            return nil
        }
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
    /// sources that wrote to it. A statistic Health did not collect reads as nil, never as zero.
    /// Steps that are nil here are looked for once more, over the workout's window
    /// (`HealthWorkoutStepRule`), before the workout is filed anywhere.
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
            sourceName: workout.sourceRevision.source.name,
            activityTypeRawValue: workout.workoutActivityType.rawValue,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier
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
