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

    private(set) var isDeviceMotionAvailable = false
    private(set) var isConnected = false
    private(set) var status: HeadphoneMotionSessionStatus = .idle
    private(set) var stepCount = 0
    private(set) var sampleCount = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentAcceleration: HeadphoneMotionVector = .zero
    private(set) var targetReached = false

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
        }
    }

    private func handleSessionUpdate(_ update: HeadphoneMotionSessionUpdate) {
        guard !status.isPaused else { return }

        isConnected = true
        if status == .waitingForMotion {
            status = .recording
        }

        stepCount = update.stepCount
        sampleCount = update.sampleCount
        currentAcceleration = update.acceleration

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
                self.duration = self.activeDuration()
            }
        }
    }

    private func activeDuration(at date: Date = Date()) -> TimeInterval {
        guard let recordingStartedAt else {
            return duration
        }

        let currentPauseDuration = pauseStartedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(0, date.timeIntervalSince(recordingStartedAt) - accumulatedPausedDuration - currentPauseDuration)
    }
}

private final class HeadphoneMotionSessionRunner {
    private let motionManager: CMHeadphoneMotionManager
    private let motionQueue: OperationQueue
    private let processor = HeadphoneMotionSessionProcessor()
    private var motionDelegate: HeadphoneMotionConnectionDelegate?

    private let onConnectionChange: (Bool) -> Void
    private let onUpdate: (HeadphoneMotionSessionUpdate) -> Void
    private let onError: (String) -> Void

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
        motionManager.stopDeviceMotionUpdates()
        motionQueue.cancelAllOperations()
    }

    func startRecording(startedAt: Date) {
        motionQueue.addOperation { [processor] in
            processor.start(startedAt: startedAt)
        }

        if !motionManager.isDeviceMotionActive {
            startDeviceMotionUpdates()
        }
    }

    func pauseRecording(pausedAt: Date) {
        motionManager.stopDeviceMotionUpdates()

        motionQueue.addOperation { [processor] in
            processor.pause(pausedAt: pausedAt)
        }
    }

    func resumeRecording(resumedAt: Date) {
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
        motionManager.stopDeviceMotionUpdates()

        motionQueue.addOperation { [processor] in
            completion(processor.finish(endedAt: Date(), reason: reason))
        }
    }

    private func startDeviceMotionUpdates() {
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self, processor] motion, error in
            guard let self else { return }

            if let error {
                self.onError(error.localizedDescription)
                return
            }

            guard let motion else { return }
            let update = processor.process(motion: motion, receivedAt: Date())
            guard update.shouldPublish else { return }

            self.onUpdate(update)
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
