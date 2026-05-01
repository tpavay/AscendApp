//
//  HealthKitBackgroundSyncManager.swift
//  AscendApp
//
//  Created by Codex on 4/20/26.
//

import Foundation
import HealthKit

@MainActor
final class HealthKitBackgroundSyncManager {
    static let shared = HealthKitBackgroundSyncManager()

    private let healthStore: HKHealthStore
    private var observerQuery: HKObserverQuery?
    private var isObserving = false

    private init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func updateObservation(enabled: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        if enabled {
            guard !isObserving else { return }

            let query = HKObserverQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HealthKitWorkoutReader.stairWorkoutPredicate()
            ) { _, completionHandler, error in
                guard error == nil else {
                    completionHandler()
                    return
                }

                let deliveryCompletion = HealthKitObserverDeliveryCompletion(completionHandler)
                Task {
                    defer { deliveryCompletion.complete() }
                    await WorkoutImportCoordinator.shared.refreshPendingImports(trigger: .backgroundObserver)
                }
            }

            observerQuery = query
            healthStore.execute(query)
            try? await enableBackgroundDelivery()
            isObserving = true
        } else {
            if let observerQuery {
                healthStore.stop(observerQuery)
                self.observerQuery = nil
            }

            try? await disableBackgroundDelivery()
            isObserving = false
        }
    }

    private func enableBackgroundDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.enableBackgroundDelivery(
                for: HKObjectType.workoutType(),
                frequency: .immediate
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BackgroundDeliveryError.enableFailed)
                }
            }
        }
    }

    private func disableBackgroundDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.disableBackgroundDelivery(for: HKObjectType.workoutType()) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BackgroundDeliveryError.disableFailed)
                }
            }
        }
    }
}

private extension HealthKitBackgroundSyncManager {
    enum BackgroundDeliveryError: Error {
        case enableFailed
        case disableFailed
    }
}

private final class HealthKitObserverDeliveryCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completionHandler: (() -> Void)?

    init(_ completionHandler: @escaping () -> Void) {
        self.completionHandler = completionHandler
    }

    func complete() {
        lock.lock()
        let completionHandler = completionHandler
        self.completionHandler = nil
        lock.unlock()

        completionHandler?()
    }
}
