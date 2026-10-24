import FirebaseAuth
import Foundation
import Observation
import SwiftData

/// What a session hands the checkpointer on every pass: the counts, the curve, the integrity
/// record and the live status, read off whichever view model owns the session.
struct HeadphoneSessionCheckpointSnapshot: Sendable {
    var steps: Int
    var durationSeconds: TimeInterval
    var sampleCount: Int
    var splitCurve: LiveReplaySplitCurve?
    var trackingIntegrity: HeadphoneMotionTrackingIntegrity
    var stepCorrections: [HeadphoneMotionStepCorrection]
    /// The heart-rate series as it stands. The checkpointer decides whether this pass writes it;
    /// the payload is the largest thing a checkpoint carries, so it rides a slower cadence.
    var heartRateBuffer: HeartRateSessionSampleBuffer?
    var motionStatus: String
    var skippedIntervalCount: Int?

    init(
        steps: Int,
        durationSeconds: TimeInterval,
        sampleCount: Int,
        splitCurve: LiveReplaySplitCurve?,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity,
        stepCorrections: [HeadphoneMotionStepCorrection],
        heartRateBuffer: HeartRateSessionSampleBuffer? = nil,
        motionStatus: String,
        skippedIntervalCount: Int? = nil
    ) {
        self.steps = steps
        self.durationSeconds = durationSeconds
        self.sampleCount = sampleCount
        self.splitCurve = splitCurve
        self.trackingIntegrity = trackingIntegrity
        self.stepCorrections = stepCorrections
        self.heartRateBuffer = heartRateBuffer
        self.motionStatus = motionStatus
        self.skippedIntervalCount = skippedIntervalCount
    }
}

/// How a checkpoint landed, so a caller (and a test) can tell a save from a fallback.
enum HeadphoneSessionCheckpointOutcome: Equatable, Sendable {
    /// Rate-limited: the last checkpoint was too recent and nothing forced this one.
    case skipped
    case saved
    /// SwiftData refused the save; the draft went to the JSON fallback file instead.
    case fellBackToFile
    /// Both the store and the file refused. The diagnostic carries why.
    case failed
}

/// The one place a headphone session's draft is written, for every mode.
///
/// `LiveClimbSessionViewModel` and `ActiveRoutineViewModel` each used to carry their own copy of
/// this: a two-second rate limit, a fifteen-second heart-rate cadence, a `modelContext.save()`
/// whose failure was swallowed with a Debug-only log, and a checkpoint that only ever ran because
/// the *view* ticked. The duplicates drifted (the routine copy never wrote heart rate) and the
/// view dependency meant a process relaunched in the background checkpointed nothing. This owns
/// all of it:
///
/// - the draft row and its registry entry, created once and cleared once;
/// - a timer of its own, so checkpoints continue with no view mounted;
/// - the device diagnostics written onto every checkpoint
///   (`HeadphoneSessionCheckpointDiagnostics`), so the launch that finds the draft can say what
///   happened;
/// - a loud failure path: a refused save records a diagnostic with the error and the free disk,
///   then writes the draft to `ActiveHeadphoneWorkoutDraftFallbackStore` so the on-disk record can
///   never silently freeze;
/// - the server heartbeat (`AttemptHeartbeat`) every sixty seconds, behind its kill switch.
///
/// A future step source that is not headphone motion - the Watch's own counter - plugs in here by
/// producing the same `HeadphoneSessionCheckpointSnapshot`; nothing below this line knows where
/// the steps came from.
@MainActor
@Observable
final class HeadphoneSessionCheckpointer {
    static let draftCheckpointInterval: TimeInterval = 2
    static let heartRateCheckpointInterval: TimeInterval = 15
    static let automaticCheckpointInterval: TimeInterval = 1

    private(set) var activeDraft: ActiveHeadphoneWorkoutDraft?
    private(set) var lastOutcome: HeadphoneSessionCheckpointOutcome?
    /// How many checkpoints fell back to the file this session. A climber whose store is refusing
    /// writes deserves to hear about it once, not on every tick.
    private(set) var fallbackCount = 0

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var lastDraftCheckpointAt: Date?
    @ObservationIgnored private var lastHeartRateCheckpointAt: Date?
    @ObservationIgnored private var lastHeartbeatPublishedAt: Date?
    @ObservationIgnored private var memoryWarningCountAtStart = 0
    @ObservationIgnored private var automaticTimer: Timer?
    @ObservationIgnored private var snapshotProvider: (@MainActor () -> HeadphoneSessionCheckpointSnapshot?)?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

    private let draftStore: ActiveHeadphoneWorkoutDraftStore
    private let fallbackStore: ActiveHeadphoneWorkoutDraftFallbackStore
    private let deviceDiagnostics: any HeadphoneSessionDeviceDiagnosticsProviding
    private let memoryMonitor: AppMemoryPressureMonitor
    private let backgroundSession: any LiveClimbBackgroundSessionControlling
    private let heartbeatPublisher: any AttemptHeartbeatPublishing
    private let currentUserId: @MainActor () -> String?
    private let featureFlags: RemoteFeatureFlagStore
    private let diagnostics: AppDiagnosticsRecorder
    private let save: @MainActor (ModelContext) throws -> Void
    private let now: () -> Date

    init(
        draftStore: ActiveHeadphoneWorkoutDraftStore = ActiveHeadphoneWorkoutDraftStore(),
        fallbackStore: ActiveHeadphoneWorkoutDraftFallbackStore = ActiveHeadphoneWorkoutDraftFallbackStore(),
        deviceDiagnostics: (any HeadphoneSessionDeviceDiagnosticsProviding)? = nil,
        memoryMonitor: AppMemoryPressureMonitor = .shared,
        backgroundSession: any LiveClimbBackgroundSessionControlling = LiveClimbBackgroundSessionService.shared,
        heartbeatPublisher: any AttemptHeartbeatPublishing = FirestoreAttemptHeartbeatRepository.shared,
        currentUserId: @escaping @MainActor () -> String? = { Auth.auth().currentUser?.uid },
        featureFlags: RemoteFeatureFlagStore = .shared,
        diagnostics: AppDiagnosticsRecorder = .shared,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        now: @escaping () -> Date = Date.init
    ) {
        self.draftStore = draftStore
        self.fallbackStore = fallbackStore
        self.deviceDiagnostics = deviceDiagnostics ?? LiveHeadphoneSessionDeviceDiagnostics()
        self.memoryMonitor = memoryMonitor
        self.backgroundSession = backgroundSession
        self.heartbeatPublisher = heartbeatPublisher
        self.currentUserId = currentUserId
        self.featureFlags = featureFlags
        self.diagnostics = diagnostics
        self.save = save
        self.now = now
    }

    var hasActiveDraft: Bool {
        activeDraft != nil
    }

    /// Waits for the heartbeat write in flight, if any. For tests; production never waits on it.
    func settlePendingHeartbeat() async {
        await heartbeatTask?.value
    }

    /// Hands the checkpointer a draft a previous process wrote, ahead of `prepareDraftIfNeeded`.
    func adopt(_ draft: ActiveHeadphoneWorkoutDraft?) {
        activeDraft = draft
    }

    /// The draft this session writes: the adopted one, or a new row built by `make` and inserted.
    /// Either way it is pointed at in `UserDefaults` and marked live in the runtime registry.
    @discardableResult
    func prepareDraftIfNeeded(
        modelContext: ModelContext,
        make: () -> ActiveHeadphoneWorkoutDraft
    ) throws -> ActiveHeadphoneWorkoutDraft {
        self.modelContext = modelContext
        memoryWarningCountAtStart = memoryMonitor.warningCount

        if let activeDraft {
            draftStore.setActiveDraftID(activeDraft.id)
            ActiveHeadphoneWorkoutRuntimeRegistry.shared.markActive(activeDraft)
            return activeDraft
        }

        let draft = make()
        try draftStore.insert(draft, in: modelContext)
        activeDraft = draft
        ActiveHeadphoneWorkoutRuntimeRegistry.shared.markActive(draft)
        return draft
    }

    /// Starts the checkpointer's own clock. Every second it asks `snapshot` for the session's
    /// state and checkpoints it on the normal cadence; a view may still force checkpoints on top.
    func beginAutomaticCheckpoints(
        snapshot: @escaping @MainActor () -> HeadphoneSessionCheckpointSnapshot?
    ) {
        snapshotProvider = snapshot
        automaticTimer?.invalidate()
        automaticTimer = Timer.scheduledTimer(
            withTimeInterval: Self.automaticCheckpointInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.runAutomaticCheckpoint()
            }
        }
    }

    func stopAutomaticCheckpoints() {
        automaticTimer?.invalidate()
        automaticTimer = nil
        snapshotProvider = nil
    }

    /// One pass of the automatic clock, callable directly so a test can tick without a timer.
    func runAutomaticCheckpoint() {
        guard let snapshot = snapshotProvider?() else { return }
        checkpoint(snapshot)
    }

    /// Writes the draft when the cadence allows it (or `force` is set), with the device
    /// diagnostics of this instant attached, and publishes the server heartbeat when it is due.
    @discardableResult
    func checkpoint(
        _ snapshot: HeadphoneSessionCheckpointSnapshot,
        status: ActiveHeadphoneWorkoutDraftStatus = .recording,
        force: Bool = false
    ) -> HeadphoneSessionCheckpointOutcome {
        guard let activeDraft, let modelContext else { return .skipped }

        let now = now()
        if !force,
           let lastDraftCheckpointAt,
           now.timeIntervalSince(lastDraftCheckpointAt) < Self.draftCheckpointInterval {
            return .skipped
        }

        let heartRateBuffer = shouldCheckpointHeartRate(
            draft: activeDraft,
            sampleCount: snapshot.heartRateBuffer?.samples.count ?? 0,
            now: now,
            force: force
        ) ? snapshot.heartRateBuffer : nil

        activeDraft.applyCheckpoint(
            steps: snapshot.steps,
            durationSeconds: snapshot.durationSeconds,
            sampleCount: snapshot.sampleCount,
            splitCurve: snapshot.splitCurve,
            trackingIntegrity: snapshot.trackingIntegrity,
            stepCorrections: snapshot.stepCorrections,
            heartRateBuffer: heartRateBuffer,
            status: status,
            skippedIntervalCount: snapshot.skippedIntervalCount,
            diagnostics: makeDiagnostics(motionStatus: snapshot.motionStatus, at: now),
            checkpointedAt: now
        )

        let outcome: HeadphoneSessionCheckpointOutcome
        do {
            try save(modelContext)
            outcome = .saved
        } catch {
            outcome = fallBackToFile(draft: activeDraft, error: error)
        }

        if outcome != .failed {
            lastDraftCheckpointAt = now
            if heartRateBuffer != nil {
                lastHeartRateCheckpointAt = now
            }
        }
        lastOutcome = outcome
        publishHeartbeatIfDue(draft: activeDraft, state: .open, outcome: nil, now: now, force: false)
        return outcome
    }

    /// The forced checkpoint the scene-phase hooks and the finish path call.
    func checkpointForLifecycleChange(_ snapshot: HeadphoneSessionCheckpointSnapshot, kind: String) {
        let outcome = checkpoint(snapshot, force: true)
        diagnostics.record(
            "headphone_session_lifecycle_checkpoint",
            details: [
                "kind": kind,
                "session_id": activeDraft?.sessionID ?? "",
                "steps": String(snapshot.steps),
                "duration_seconds": String(Int(snapshot.durationSeconds.rounded(.down))),
                "outcome": String(describing: outcome)
            ]
        )
    }

    /// Tells the server the session is over. Runs even when the heartbeat cadence is not due.
    func publishSessionEnd(outcome: AttemptHeartbeat.Outcome) {
        guard let activeDraft else { return }
        publishHeartbeatIfDue(draft: activeDraft, state: .ended, outcome: outcome, now: now(), force: true)
    }

    /// Deletes the draft, its fallback file and its registry entry. Called on save and discard.
    func clearDraft() {
        stopAutomaticCheckpoints()
        guard let activeDraft else {
            draftStore.clearActiveDraftID()
            return
        }

        ActiveHeadphoneWorkoutRuntimeRegistry.shared.markInactive(activeDraft)
        fallbackStore.remove(draftID: activeDraft.id)
        if let modelContext {
            do {
                try draftStore.delete(activeDraft, in: modelContext)
            } catch {
                diagnostics.record(
                    "active_headphone_draft_cleanup_failed",
                    level: .error,
                    details: ["draft_id": activeDraft.id.uuidString, "error": error.localizedDescription]
                )
                draftStore.clearActiveDraftID(activeDraft.id)
            }
        } else {
            draftStore.clearActiveDraftID(activeDraft.id)
        }
        self.activeDraft = nil
        lastDraftCheckpointAt = nil
        lastHeartRateCheckpointAt = nil
        lastHeartbeatPublishedAt = nil
    }

    /// Removes a draft this session created a moment ago and never wrote a step into, when the
    /// sensor refused to start. A recovered draft is never discarded here: it is somebody's work.
    func discardUnstartedDraft(wasRecovered: Bool) {
        guard !wasRecovered,
              let activeDraft,
              activeDraft.status == .recording,
              activeDraft.steps == 0 else { return }
        clearDraft()
    }

    // MARK: - Private

    private func shouldCheckpointHeartRate(
        draft: ActiveHeadphoneWorkoutDraft,
        sampleCount: Int,
        now: Date,
        force: Bool
    ) -> Bool {
        guard sampleCount != (draft.heartRateSampleCount ?? 0) else { return false }
        if force { return true }
        guard let lastHeartRateCheckpointAt else { return true }
        return now.timeIntervalSince(lastHeartRateCheckpointAt) >= Self.heartRateCheckpointInterval
    }

    private func makeDiagnostics(motionStatus: String, at now: Date) -> HeadphoneSessionCheckpointDiagnostics {
        HeadphoneSessionCheckpointDiagnostics(
            availableMemoryBytes: deviceDiagnostics.availableMemoryBytes(),
            freeDiskBytes: deviceDiagnostics.freeDiskBytes(),
            memoryWarningCount: max(memoryMonitor.warningCount - memoryWarningCountAtStart, 0),
            batteryLevel: deviceDiagnostics.batteryLevel(),
            batteryState: deviceDiagnostics.batteryState(),
            workoutSessionState: backgroundSession.diagnosticState,
            motionStatus: motionStatus,
            systemUptimeSeconds: deviceDiagnostics.systemUptime(),
            processUptimeSeconds: deviceDiagnostics.processUptime(),
            recordedAt: now
        )
    }

    private func fallBackToFile(draft: ActiveHeadphoneWorkoutDraft, error: Error) -> HeadphoneSessionCheckpointOutcome {
        var details = draft.diagnosticDetails
        details["error"] = error.localizedDescription
        details["error_type"] = String(describing: type(of: error))
        if let freeDisk = deviceDiagnostics.freeDiskBytes() {
            details["free_disk_mb"] = String(freeDisk / 1_048_576)
        }
        diagnostics.record("active_headphone_draft_checkpoint_failed", level: .error, details: details)

        do {
            try fallbackStore.write(ActiveHeadphoneWorkoutDraftSnapshot(draft))
            fallbackCount += 1
            diagnostics.record(
                "active_headphone_draft_fallback_written",
                level: .warning,
                details: ["draft_id": draft.id.uuidString, "fallback_count": String(fallbackCount)]
            )
            return .fellBackToFile
        } catch {
            diagnostics.record(
                "active_headphone_draft_fallback_write_failed",
                level: .error,
                details: ["draft_id": draft.id.uuidString, "error": error.localizedDescription]
            )
            return .failed
        }
    }

    private func publishHeartbeatIfDue(
        draft: ActiveHeadphoneWorkoutDraft,
        state: AttemptHeartbeat.State,
        outcome: AttemptHeartbeat.Outcome?,
        now: Date,
        force: Bool
    ) {
        guard force || AttemptHeartbeatPolicy.isDue(lastPublishedAt: lastHeartbeatPublishedAt, now: now) else {
            return
        }
        guard let userId = currentUserId() else { return }
        guard RemoteFeatureGate.allows(
            .attemptHeartbeats,
            path: "HeadphoneSessionCheckpointer.publishHeartbeatIfDue",
            store: featureFlags,
            diagnostics: diagnostics
        ) else { return }

        lastHeartbeatPublishedAt = now
        let heartbeat = AttemptHeartbeat(
            sessionID: draft.sessionID,
            mode: draft.kind,
            steps: draft.steps,
            durationSeconds: draft.durationSeconds,
            startedAt: draft.startedAt,
            climbId: draft.climbId,
            state: state,
            outcome: outcome
        )
        let publisher = heartbeatPublisher
        let diagnostics = diagnostics
        heartbeatTask = Task {
            do {
                try await publisher.publish(heartbeat, userId: userId)
            } catch {
                diagnostics.record(
                    "attempt_heartbeat_publish_failed",
                    level: .warning,
                    details: ["session_id": heartbeat.sessionID, "error": error.localizedDescription]
                )
            }
        }
    }
}
