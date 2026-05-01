//
//  HealthKitWorkoutReader.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import HealthKit

struct HealthKitWorkoutDiscoveryResult {
    let addedSamples: [HealthKitWorkoutSample]
    let deletedExternalRecordIDs: [String]
    let anchorData: Data?
}

@MainActor
protocol HealthKitWorkoutReading {
    var isHealthDataAvailable: Bool { get }
    func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws -> HealthKitWorkoutDiscoveryResult
    func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout?
    func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws -> [HealthKitWorkoutSample]
}

@MainActor
final class HealthKitWorkoutReader: HealthKitWorkoutReading {
    static let shared = HealthKitWorkoutReader()

    private let healthStore: HKHealthStore

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws -> HealthKitWorkoutDiscoveryResult {
        guard isHealthDataAvailable else {
            return HealthKitWorkoutDiscoveryResult(
                addedSamples: [],
                deletedExternalRecordIDs: [],
                anchorData: anchorData
            )
        }

        let anchor = HealthKitSyncState.unarchiveAnchor(from: anchorData)
        let predicate = Self.stairWorkoutPredicate()
        let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: healthStore)
        let addedSamples = result.addedSamples.map(Self.makeSample(from:))
        let deletedExternalRecordIDs = result.deletedObjects.map { $0.uuid.uuidString }
        let newAnchorData = HealthKitSyncState.archive(anchor: result.newAnchor)

        return HealthKitWorkoutDiscoveryResult(
            addedSamples: addedSamples,
            deletedExternalRecordIDs: deletedExternalRecordIDs,
            anchorData: newAnchorData
        )
    }

    func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout? {
        guard isHealthDataAvailable, let uuid = UUID(uuidString: externalRecordID) else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: uuid),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }

            healthStore.execute(query)
        }
    }

    func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws -> [HealthKitWorkoutSample] {
        guard isHealthDataAvailable else { return [] }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: dateRange.lowerBound,
            end: dateRange.upperBound,
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [Self.stairWorkoutPredicate(), datePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts.map(Self.makeSample(from:)))
            }

            healthStore.execute(query)
        }
    }

    nonisolated static func stairWorkoutPredicate() -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .stairClimbing),
            HKQuery.predicateForWorkouts(with: .stepTraining)
        ])
    }

    nonisolated private static func makeSample(from workout: HKWorkout) -> HealthKitWorkoutSample {
        HealthKitWorkoutSample(
            externalRecordID: workout.uuid.uuidString,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            sourceName: workout.sourceRevision.source.name,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            deviceModel: workout.device?.name
        )
    }
}
