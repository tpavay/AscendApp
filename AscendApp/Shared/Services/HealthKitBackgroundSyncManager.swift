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

    /// HealthKit does not guarantee these completion handlers ever fire - on a simulator with no
    /// Health authorization, `disableBackgroundDelivery` reliably does not. An unbounded
    /// continuation there is not a slow call, it is a permanent one: it suspends the shared
    /// refresh task forever, `WorkoutImportCoordinator.refreshTask` is never cleared, and every
    /// later refresh coalesces onto a task that can never finish. Cancellation cannot rescue it
    /// either, because a continuation is not a cancellation point. Bounding it is what keeps the
    /// import system's completion and cancellation guarantees true.
    private static let backgroundDeliveryTimeout: Duration = .seconds(10)

    private func enableBackgroundDelivery() async throws {
        try await withBoundedCompletion { [healthStore] completion in
            healthStore.enableBackgroundDelivery(
                for: HKObjectType.workoutType(),
                frequency: .immediate,
                withCompletion: completion
            )
        }
    }

    private func disableBackgroundDelivery() async throws {
        try await withBoundedCompletion { [healthStore] completion in
            healthStore.disableBackgroundDelivery(
                for: HKObjectType.workoutType(),
                withCompletion: completion
            )
        }
    }

    private func withBoundedCompletion(
        _ request: (@escaping @Sendable (Bool, (any Error)?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumer = HealthKitOneShotResumer(continuation)

            request { success, error in
                if let error {
                    resumer.resume(throwing: error)
                } else if success {
                    resumer.resume()
                } else {
                    resumer.resume(throwing: BackgroundDeliveryError.requestFailed)
                }
            }

            Task.detached {
                try? await Task.sleep(for: Self.backgroundDeliveryTimeout)
                resumer.resume(throwing: BackgroundDeliveryError.timedOut)
            }
        }
    }
}

private extension HealthKitBackgroundSyncManager {
    enum BackgroundDeliveryError: Error {
        case requestFailed
        case timedOut
    }
}

/// Resumes a continuation exactly once, whichever of the HealthKit callback and the timeout wins.
private final class HealthKitOneShotResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        take()?.resume()
    }

    func resume(throwing error: any Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }

        let continuation = self.continuation
        self.continuation = nil
        return continuation
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
