import Foundation
import HealthKit
import UIKit

@MainActor
final class LiveClimbBackgroundSessionService {
    private let healthStore: HKHealthStore
    private var workoutSession: HKWorkoutSession?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private(set) var lastFailureMessage: String?

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func start(at startedAt: Date = Date()) {
        beginBackgroundTask()
        startWorkoutSessionIfAvailable(at: startedAt)
    }

    func pause() {
        if #available(iOS 26.0, *), let workoutSession {
            workoutSession.pause()
        }
    }

    func resume() {
        beginBackgroundTask()

        if #available(iOS 26.0, *), let workoutSession {
            workoutSession.resume()
        }
    }

    func stop(at endedAt: Date = Date()) {
        if #available(iOS 26.0, *), let workoutSession {
            workoutSession.stopActivity(with: endedAt)
            workoutSession.end()
        }

        workoutSession = nil
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Live Climb") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }

        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func startWorkoutSessionIfAvailable(at startedAt: Date) {
        guard workoutSession == nil,
              HKHealthStore.isHealthDataAvailable() else {
            return
        }

        guard #available(iOS 26.0, *) else {
            return
        }

        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .stairClimbing
            configuration.locationType = .indoor

            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            workoutSession = session
            session.prepare()
            session.startActivity(with: startedAt)
            lastFailureMessage = nil
        } catch {
            lastFailureMessage = error.localizedDescription
        }
    }
}
