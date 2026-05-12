@preconcurrency import CoreMotion
import Foundation
import Observation

enum HeadphoneMotionSessionStatus: Equatable {
    case idle
    case waitingForMotion
    case recording
    case paused
    case stopping
    case finished
    case failed(String)

    var isRecording: Bool {
        switch self {
        case .waitingForMotion, .recording:
            return true
        case .idle, .paused, .stopping, .finished, .failed:
            return false
        }
    }

    var isPaused: Bool {
        self == .paused
    }
}

enum HeadphoneMotionSessionError: LocalizedError, Sendable {
    case motionUnavailable
    case alreadyRecording
    case notRecording
    case missingStartDate

    var errorDescription: String? {
        switch self {
        case .motionUnavailable:
            return "Compatible headphone motion is not available."
        case .alreadyRecording:
            return "A headphone motion session is already recording."
        case .notRecording:
            return "No headphone motion session is recording."
        case .missingStartDate:
            return "The headphone motion session did not start correctly."
        }
    }
}

struct HeadphoneMotionSessionUpdate: Sendable {
    let stepCount: Int
    let sampleCount: Int
    let acceleration: HeadphoneMotionVector
    let didDetectStep: Bool
    let shouldPublish: Bool
}

@MainActor
@Observable
final class HeadphoneMotionSessionService {
    private var durationTimer: Timer?
    private var targetStepCount: Int?
    private var runner: HeadphoneMotionSessionRunner?
    private var recordingStartedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var lastMotionUpdateAt: Date?
    private var lastMotionRecoveryAttemptAt: Date?

    private(set) var isDeviceMotionAvailable = false
    private(set) var isConnected = false
    private(set) var status: HeadphoneMotionSessionStatus = .idle
    private(set) var stepCount = 0
    private(set) var sampleCount = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentAcceleration: HeadphoneMotionVector = .zero
    private(set) var targetReached = false
    private var onStepSample: ((LiveClimbStepSample) -> Void)?

    init(motionManager: CMHeadphoneMotionManager = CMHeadphoneMotionManager()) {
        self.runner = HeadphoneMotionSessionRunner(
            motionManager: motionManager,
            onConnectionChange: { [weak self] connected in
                Task { @MainActor in
                    self?.handleConnectionChange(connected)
                }
            },
            onUpdate: { [weak self] update in
                Task { @MainActor in
                    self?.handleSessionUpdate(update)
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    self?.handleSessionError(message)
                }
            }
        )
        refreshAvailability()
    }

    func refreshAvailability() {
        isDeviceMotionAvailable = runner?.isDeviceMotionAvailable ?? false
    }

    func setStepSampleHandler(_ handler: ((LiveClimbStepSample) -> Void)?) {
        onStepSample = handler
    }

    func startRecording(targetStepCount: Int? = nil) throws {
        guard !status.isRecording, !status.isPaused else {
            throw HeadphoneMotionSessionError.alreadyRecording
        }

        refreshAvailability()
        guard isDeviceMotionAvailable else {
            status = .failed(HeadphoneMotionSessionError.motionUnavailable.localizedDescription)
            throw HeadphoneMotionSessionError.motionUnavailable
        }

        self.targetStepCount = targetStepCount
        status = .waitingForMotion
        stepCount = 0
        sampleCount = 0
        duration = 0
        currentAcceleration = .zero
        targetReached = false

        let startedAt = Date()
        recordingStartedAt = startedAt
        accumulatedPausedDuration = 0
        pauseStartedAt = nil
        lastMotionUpdateAt = nil
        lastMotionRecoveryAttemptAt = nil
        runner?.startRecording(startedAt: startedAt)

        startDurationTimer()
    }

    func pauseRecording() throws {
        guard status.isRecording else {
            if status.isPaused { return }
            throw HeadphoneMotionSessionError.notRecording
        }

        let pausedAt = Date()
        duration = activeDuration(at: pausedAt)
        pauseStartedAt = pausedAt
        lastMotionUpdateAt = nil
        status = .paused
        durationTimer?.invalidate()
        durationTimer = nil
        runner?.pauseRecording(pausedAt: pausedAt)
    }

    func resumeRecording() throws {
        guard status.isPaused else {
            if status.isRecording { return }
            throw HeadphoneMotionSessionError.notRecording
        }

        let resumedAt = Date()
        if let pauseStartedAt {
            accumulatedPausedDuration += resumedAt.timeIntervalSince(pauseStartedAt)
        }
        pauseStartedAt = nil
        lastMotionUpdateAt = nil
        lastMotionRecoveryAttemptAt = nil
        status = isConnected ? .recording : .waitingForMotion
        runner?.resumeRecording(resumedAt: resumedAt)
        startDurationTimer()
    }

    func stopRecording(
        reason: HeadphoneMotionSessionStopReason = .userStopped
    ) async throws -> HeadphoneMotionSessionResult {
        guard status.isRecording || status.isPaused else {
            throw HeadphoneMotionSessionError.notRecording
        }

        status = .stopping
        durationTimer?.invalidate()
        durationTimer = nil

        do {
            guard let runner else {
                throw HeadphoneMotionSessionError.notRecording
            }

            let result = try await withCheckedThrowingContinuation { continuation in
                runner.stopRecording(reason: reason) { result in
                    switch result {
                    case .success(let sessionResult):
                        continuation.resume(returning: sessionResult)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            stepCount = result.steps
            sampleCount = result.sampleCount
            duration = result.duration
            recordingStartedAt = nil
            accumulatedPausedDuration = 0
            pauseStartedAt = nil
            lastMotionUpdateAt = nil
            lastMotionRecoveryAttemptAt = nil
            status = .finished
            return result
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    private func handleConnectionChange(_ connected: Bool) {
        isConnected = connected
        if connected, status == .waitingForMotion {
            status = .recording
            lastMotionUpdateAt = nil
            lastMotionRecoveryAttemptAt = nil
        } else if !connected, status == .recording {
            status = .waitingForMotion
            lastMotionUpdateAt = nil
        }
    }

    private func handleSessionUpdate(_ update: HeadphoneMotionSessionUpdate) {
        guard !status.isPaused else { return }

        isConnected = true
        if status == .waitingForMotion {
            status = .recording
        }

        lastMotionUpdateAt = Date()
        stepCount = update.stepCount
        sampleCount = update.sampleCount
        currentAcceleration = update.acceleration
        if update.didDetectStep {
            onStepSample?(
                LiveClimbStepSample(
                    elapsedSeconds: Int(activeDuration().rounded(.down)),
                    cumulativeSteps: update.stepCount,
                    source: .headphoneMotion
                )
            )
        }

        if let targetStepCount,
           update.stepCount >= targetStepCount {
            targetReached = true
        }
    }

    private func handleSessionError(_ message: String) {
        status = .failed(message)
        isConnected = false
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.status.isRecording else { return }
                let now = Date()
                self.duration = self.activeDuration(at: now)
                self.restartStalledMotionIfNeeded(at: now)
            }
        }
    }

    private func restartStalledMotionIfNeeded(at now: Date) {
        guard status.isRecording,
              !status.isPaused,
              let recordingStartedAt else {
            return
        }

        let lastUpdateAt = lastMotionUpdateAt ?? recordingStartedAt
        guard now.timeIntervalSince(lastUpdateAt) >= 4 else { return }

        if let lastMotionRecoveryAttemptAt,
           now.timeIntervalSince(lastMotionRecoveryAttemptAt) < 5 {
            return
        }

        lastMotionRecoveryAttemptAt = now
        runner?.restartDeviceMotionUpdatesIfNeeded()
    }

    private func activeDuration(at date: Date = Date()) -> TimeInterval {
        guard let recordingStartedAt else {
            return duration
        }

        let currentPauseDuration = pauseStartedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(0, date.timeIntervalSince(recordingStartedAt) - accumulatedPausedDuration - currentPauseDuration)
    }
}

private final class HeadphoneMotionSessionRunner: @unchecked Sendable {
    private let motionManager: CMHeadphoneMotionManager
    private let motionQueue: OperationQueue
    private let processor = HeadphoneMotionSessionProcessor()
    private var motionDelegate: HeadphoneMotionConnectionDelegate?

    private let onConnectionChange: (Bool) -> Void
    private let onUpdate: (HeadphoneMotionSessionUpdate) -> Void
    private let onError: (String) -> Void
    private var isRecording = false
    private var isPausedByUser = false
    private var restartWorkItem: DispatchWorkItem?
    private var lastRestartAttemptAt: Date?

    var isDeviceMotionAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    init(
        motionManager: CMHeadphoneMotionManager = CMHeadphoneMotionManager(),
        onConnectionChange: @escaping (Bool) -> Void,
        onUpdate: @escaping (HeadphoneMotionSessionUpdate) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.motionManager = motionManager
        self.motionQueue = OperationQueue()
        self.motionQueue.name = "com.ascend.headphone-motion"
        self.motionQueue.maxConcurrentOperationCount = 1
        self.motionQueue.qualityOfService = .userInteractive
        self.onConnectionChange = onConnectionChange
        self.onUpdate = onUpdate
        self.onError = onError

        let delegate = HeadphoneMotionConnectionDelegate { [weak self] connected in
            self?.onConnectionChange(connected)
        }
        self.motionDelegate = delegate
        self.motionManager.delegate = delegate
    }

    deinit {
        restartWorkItem?.cancel()
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopConnectionStatusUpdates()
        motionQueue.cancelAllOperations()
    }

    func startRecording(startedAt: Date) {
        isRecording = true
        isPausedByUser = false
        startConnectionStatusUpdatesIfNeeded()

        motionQueue.addOperation { [processor] in
            processor.start(startedAt: startedAt)
        }

        if !motionManager.isDeviceMotionActive {
            startDeviceMotionUpdates()
        }
    }

    func pauseRecording(pausedAt: Date) {
        isPausedByUser = true
        restartWorkItem?.cancel()
        motionManager.stopDeviceMotionUpdates()

        motionQueue.addOperation { [processor] in
            processor.pause(pausedAt: pausedAt)
        }
    }

    func resumeRecording(resumedAt: Date) {
        isPausedByUser = false

        motionQueue.addOperation { [processor] in
            processor.resume(resumedAt: resumedAt)
        }

        if !motionManager.isDeviceMotionActive {
            startDeviceMotionUpdates()
        }
    }

    func stopRecording(
        reason: HeadphoneMotionSessionStopReason,
        completion: @escaping @Sendable (Result<HeadphoneMotionSessionResult, HeadphoneMotionSessionError>) -> Void
    ) {
        isRecording = false
        isPausedByUser = false
        restartWorkItem?.cancel()
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopConnectionStatusUpdates()

        motionQueue.addOperation { [processor] in
            completion(processor.finish(endedAt: Date(), reason: reason))
        }
    }

    func restartDeviceMotionUpdatesIfNeeded() {
        guard isRecording,
              !isPausedByUser else {
            return
        }

        scheduleDeviceMotionRestart(delay: 0.25)
    }

    private func startConnectionStatusUpdatesIfNeeded() {
        guard !motionManager.isConnectionStatusActive else { return }

        motionManager.startConnectionStatusUpdates()
    }

    private func startDeviceMotionUpdates() {
        guard isRecording,
              !isPausedByUser,
              !motionManager.isDeviceMotionActive else {
            return
        }

        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self, processor] motion, error in
            guard let self else { return }

            if let error {
                self.handleDeviceMotionError(error)
                return
            }

            guard let motion else { return }
            let update = processor.process(motion: motion, receivedAt: Date())
            guard update.shouldPublish else { return }

            self.onUpdate(update)
        }
    }

    private func handleDeviceMotionError(_ error: Error) {
        guard isRecoverableMotionError(error) else {
            onError(error.localizedDescription)
            return
        }

        onConnectionChange(false)
        scheduleDeviceMotionRestart(delay: 0.75)
    }

    private func scheduleDeviceMotionRestart(delay: TimeInterval) {
        let now = Date()
        if let lastRestartAttemptAt,
           now.timeIntervalSince(lastRestartAttemptAt) < 1 {
            return
        }

        lastRestartAttemptAt = now
        restartWorkItem?.cancel()
        motionManager.stopDeviceMotionUpdates()

        let workItem = DispatchWorkItem { [weak self] in
            self?.motionQueue.addOperation { [weak self] in
                self?.startDeviceMotionUpdates()
            }
        }
        restartWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    private func isRecoverableMotionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == CMErrorDomain else { return true }

        switch CMError(rawValue: UInt32(nsError.code)) {
        case CMErrorNotAuthorized,
             CMErrorNotEntitled,
             CMErrorNotAvailable,
             CMErrorMotionActivityNotAuthorized,
             CMErrorMotionActivityNotEntitled,
             CMErrorMotionActivityNotAvailable:
            return false
        default:
            return true
        }
    }
}

/// Mutable detector state is confined to `HeadphoneMotionSessionRunner.motionQueue`.
private final class HeadphoneMotionSessionProcessor: @unchecked Sendable {
    private let detector = HeadphoneMotionStepDetector()
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var sampleCount = 0

    func start(startedAt: Date) {
        detector.reset()
        self.startedAt = startedAt
        pausedAt = nil
        accumulatedPausedDuration = 0
        sampleCount = 0
    }

    func pause(pausedAt: Date) {
        guard startedAt != nil, self.pausedAt == nil else { return }
        self.pausedAt = pausedAt
    }

    func resume(resumedAt: Date) {
        guard let pausedAt else { return }
        accumulatedPausedDuration += resumedAt.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    func process(motion: CMDeviceMotion, receivedAt: Date) -> HeadphoneMotionSessionUpdate {
        guard let startedAt else {
            return HeadphoneMotionSessionUpdate(
                stepCount: 0,
                sampleCount: sampleCount,
                acceleration: .zero,
                didDetectStep: false,
                shouldPublish: false
            )
        }

        guard pausedAt == nil else {
            return HeadphoneMotionSessionUpdate(
                stepCount: detector.stepCount,
                sampleCount: sampleCount,
                acceleration: .zero,
                didDetectStep: false,
                shouldPublish: false
            )
        }

        sampleCount += 1
        let sample = HeadphoneMotionSample(
            timestamp: max(0, receivedAt.timeIntervalSince(startedAt) - accumulatedPausedDuration),
            motion: motion
        )
        let detection = detector.process(sample)

        return HeadphoneMotionSessionUpdate(
            stepCount: detector.stepCount,
            sampleCount: sampleCount,
            acceleration: sample.userAcceleration,
            didDetectStep: detection != nil,
            shouldPublish: detection != nil || sampleCount.isMultiple(of: 5)
        )
    }

    func finish(
        endedAt: Date,
        reason: HeadphoneMotionSessionStopReason
    ) -> Result<HeadphoneMotionSessionResult, HeadphoneMotionSessionError> {
        guard let startedAt else {
            return .failure(.missingStartDate)
        }

        let activePausedDuration = pausedAt.map { endedAt.timeIntervalSince($0) } ?? 0
        let result = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: endedAt,
            duration: max(0, endedAt.timeIntervalSince(startedAt) - accumulatedPausedDuration - activePausedDuration),
            steps: detector.stepCount,
            sampleCount: sampleCount,
            stopReason: reason
        )

        self.startedAt = nil
        pausedAt = nil
        accumulatedPausedDuration = 0
        sampleCount = 0
        detector.reset()

        return .success(result)
    }
}

private final class HeadphoneMotionConnectionDelegate: NSObject, CMHeadphoneMotionManagerDelegate {
    private let onConnectionChange: (Bool) -> Void

    init(onConnectionChange: @escaping (Bool) -> Void) {
        self.onConnectionChange = onConnectionChange
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        onConnectionChange(true)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        onConnectionChange(false)
    }
}

extension HeadphoneMotionSessionService: LiveClimbStepSampleProducing {}
