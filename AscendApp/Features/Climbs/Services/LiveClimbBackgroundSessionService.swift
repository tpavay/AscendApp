import Foundation
@preconcurrency import HealthKit
import UIKit

@MainActor
final class LiveClimbBackgroundSessionService: NSObject {
    static let shared = LiveClimbBackgroundSessionService()

    private let healthStore: HKHealthStore
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: AnyObject?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var lastBuilderDataDiagnosticAt: Date?

    private(set) var lastFailureMessage: String?

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
        super.init()
    }

    func start(at startedAt: Date = Date()) {
        AppDiagnosticsRecorder.shared.record(
            "headphone_background_session_start_requested",
            details: ["started_at_unix": String(Int(startedAt.timeIntervalSince1970))]
        )
        beginBackgroundTask()
        startWorkoutSessionIfAvailable(at: startedAt)
    }

    func stop(at endedAt: Date = Date()) {
        AppDiagnosticsRecorder.shared.record(
            "headphone_background_session_stop_requested",
            details: ["ended_at_unix": String(Int(endedAt.timeIntervalSince1970))]
        )
        if let workoutSession {
            workoutSession.stopActivity(with: endedAt)
            workoutSession.end()
        }

        workoutSession?.delegate = nil
        workoutSession = nil
        lastBuilderDataDiagnosticAt = nil
        if #available(iOS 26.0, *) {
            stopWorkoutBuilder(at: endedAt)
        }
        endBackgroundTask()
    }

    func recoverActiveWorkoutSessionIfAvailable() async {
        guard #available(iOS 26.0, *),
              workoutSession == nil,
              HKHealthStore.isHealthDataAvailable() else {
            return
        }

        do {
            let session = try await recoverActiveWorkoutSession()
            guard let session else {
                AppDiagnosticsRecorder.shared.record("hk_workout_session_recovery_none")
                return
            }

            attachRecoveredWorkoutSession(session)
        } catch {
            lastFailureMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "hk_workout_session_recovery_failed",
                level: .error,
                details: ["error": error.localizedDescription]
            )
        }
    }

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Live Climb") { [weak self] in
            Task { @MainActor in
                self?.lastFailureMessage = "Background task expired before workout processing took over."
                AppDiagnosticsRecorder.shared.record(
                    "headphone_background_task_expired",
                    level: .warning
                )
                self?.endBackgroundTask()
            }
        }
        AppDiagnosticsRecorder.shared.record("headphone_background_task_started")
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }

        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        AppDiagnosticsRecorder.shared.record("headphone_background_task_ended")
    }

    private func startWorkoutSessionIfAvailable(at startedAt: Date) {
        if workoutSession != nil {
            AppDiagnosticsRecorder.shared.record(
                "hk_workout_session_unavailable",
                level: .warning,
                details: ["reason": "already_running"]
            )
            endBackgroundTask()
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            AppDiagnosticsRecorder.shared.record(
                "hk_workout_session_unavailable",
                level: .warning,
                details: ["reason": "health_data_unavailable"]
            )
            return
        }

        guard #available(iOS 26.0, *) else {
            AppDiagnosticsRecorder.shared.record(
                "hk_workout_session_unavailable",
                details: ["reason": "ios_version_below_26"]
            )
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
            session.delegate = self
            workoutSession = session
            configureLiveWorkoutBuilderIfAvailable(
                for: session,
                configuration: configuration,
                startedAt: startedAt
            )
            session.prepare()
            session.startActivity(with: startedAt)
            lastFailureMessage = nil
            AppDiagnosticsRecorder.shared.record("hk_workout_session_start_requested")
        } catch {
            lastFailureMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "hk_workout_session_start_failed",
                level: .error,
                details: ["error": error.localizedDescription]
            )
        }
    }

    @available(iOS 26.0, *)
    private func configureLiveWorkoutBuilderIfAvailable(
        for session: HKWorkoutSession,
        configuration: HKWorkoutConfiguration,
        startedAt: Date
    ) {
        let builder = session.associatedWorkoutBuilder()
        builder.delegate = self
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        workoutBuilder = builder
        lastBuilderDataDiagnosticAt = nil

        builder.beginCollection(withStart: startedAt) { success, error in
            Task { @MainActor in
                if let error {
                    self.lastFailureMessage = error.localizedDescription
                    AppDiagnosticsRecorder.shared.record(
                        "hk_live_workout_builder_begin_failed",
                        level: .error,
                        details: ["error": error.localizedDescription]
                    )
                } else {
                    AppDiagnosticsRecorder.shared.record(
                        "hk_live_workout_builder_begin_completed",
                        details: ["success": success ? "true" : "false"]
                    )
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func stopWorkoutBuilder(at endedAt: Date) {
        guard let builder = workoutBuilder as? HKLiveWorkoutBuilder else { return }

        builder.delegate = nil
        workoutBuilder = nil
        lastBuilderDataDiagnosticAt = nil
        builder.endCollection(withEnd: endedAt) { success, error in
            builder.discardWorkout()
            Task { @MainActor in
                if let error {
                    self.lastFailureMessage = error.localizedDescription
                    AppDiagnosticsRecorder.shared.record(
                        "hk_live_workout_builder_end_failed",
                        level: .error,
                        details: ["error": error.localizedDescription]
                    )
                } else {
                    AppDiagnosticsRecorder.shared.record(
                        "hk_live_workout_builder_discarded",
                        details: ["end_success": success ? "true" : "false"]
                    )
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func recoverActiveWorkoutSession() async throws -> HKWorkoutSession? {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: session)
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func attachRecoveredWorkoutSession(_ session: HKWorkoutSession) {
        session.delegate = self
        workoutSession = session

        let configuration = session.workoutConfiguration
        let builder = session.associatedWorkoutBuilder()
        builder.delegate = self
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        workoutBuilder = builder
        lastBuilderDataDiagnosticAt = nil
        lastFailureMessage = nil

        AppDiagnosticsRecorder.shared.record(
            "hk_workout_session_recovered",
            level: .warning,
            details: [
                "state": session.state.diagnosticName,
                "start_date_unix": session.startDate.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
            ]
        )
    }
}

extension LiveClimbBackgroundSessionService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            AppDiagnosticsRecorder.shared.record(
                "hk_workout_session_state_changed",
                details: [
                    "from_state": fromState.diagnosticName,
                    "to_state": toState.diagnosticName
                ]
            )
            switch toState {
            case .running:
                endBackgroundTask()
            case .ended:
                if self.workoutSession === workoutSession {
                    self.workoutSession?.delegate = nil
                    self.workoutSession = nil
                }
                if #available(iOS 26.0, *) {
                    stopWorkoutBuilder(at: date)
                }
                endBackgroundTask()
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            lastFailureMessage = error.localizedDescription
            AppDiagnosticsRecorder.shared.record(
                "hk_workout_session_failed",
                level: .error,
                details: ["error": error.localizedDescription]
            )
            if self.workoutSession === workoutSession {
                self.workoutSession?.delegate = nil
                self.workoutSession = nil
            }
            if #available(iOS 26.0, *) {
                stopWorkoutBuilder(at: Date())
            }
            endBackgroundTask()
        }
    }
}

@available(iOS 26.0, *)
extension LiveClimbBackgroundSessionService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {
        Task { @MainActor in
            AppDiagnosticsRecorder.shared.record(
                "hk_live_workout_builder_event_collected",
                details: ["elapsed_seconds": String(Int(workoutBuilder.elapsedTime.rounded(.down)))]
            )
        }
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            let now = Date()
            if let lastBuilderDataDiagnosticAt,
               now.timeIntervalSince(lastBuilderDataDiagnosticAt) < 30 {
                return
            }
            self.lastBuilderDataDiagnosticAt = now
            AppDiagnosticsRecorder.shared.record(
                "hk_live_workout_builder_data_collected",
                details: [
                    "type_count": String(collectedTypes.count),
                    "elapsed_seconds": String(Int(workoutBuilder.elapsedTime.rounded(.down)))
                ]
            )
        }
    }
}

private extension HKWorkoutSessionState {
    var diagnosticName: String {
        switch self {
        case .notStarted:
            return "not_started"
        case .prepared:
            return "prepared"
        case .running:
            return "running"
        case .paused:
            return "paused"
        case .ended:
            return "ended"
        case .stopped:
            return "stopped"
        @unknown default:
            return "unknown"
        }
    }
}
