import Foundation
import Observation
import SwiftData
import UIKit

struct ActiveHeadphoneWorkoutDraftStore {
    /// How much wall-clock time after the last checkpoint a recovery sync may still credit as
    /// climbing.
    ///
    /// `applyRecoveryStepSync` credits wall clock on purpose: the draft checkpoints every two
    /// seconds (`LiveClimbSessionViewModel.draftCheckpointInterval`), so it holds no tracked
    /// duration at all for the stretch after the app died, and a climber who kept stepping through
    /// a short dropout would otherwise be under-counted. That intent is sound; the missing part was
    /// a limit. Uncapped, a draft resolved days after it started claimed days of duration - honest
    /// input, an impossible climb, and one `isPhysicallyPossibleClimb` in `firestore.rules` now
    /// refuses above five days with a bare `PERMISSION_DENIED` the client cannot explain.
    ///
    /// One hour is the balance between the two ways this can go wrong. It still stops the runaway
    /// this clamp exists to stop - days of phantom duration walking into the five-day ceiling - and
    /// because checkpoints land every two seconds the measured gap is very close to how long the
    /// app was actually dead rather than an artifact of coarse sampling.
    ///
    /// It is an hour rather than minutes because clamping is not free. The clamp bounds the
    /// duration but never the step count the climber types off the machine, so a session that
    /// dies early and whose climber keeps stepping gets its full steps credited against a short
    /// duration. That is the common crash-early-and-keep-climbing shape, and an hour keeps it
    /// inside the limit, where wall clock is credited and the device's own 220 steps/min gate in
    /// `WorkoutRemoteSyncMapper.snapshot` is never tripped for it.
    ///
    /// An hour narrows that window; it does not close it. A climber who keeps climbing for more
    /// than an hour after a crash still has their typed steps credited against a clamped duration,
    /// and `WorkoutSyncCoordinator` still treats the resulting `implausibleWorkoutTotals` as
    /// terminal. That is a known and accepted bound of this change, not a solved problem.
    static let maximumCreditableTrackingGap: TimeInterval = 60 * 60

    private let userDefaults: UserDefaults
    private let fallbackStore: ActiveHeadphoneWorkoutDraftFallbackStore
    private let diagnostics: AppDiagnosticsRecorder
    private let activeDraftIDKey = "activeHeadphoneWorkoutDraft.id.v1"

    init(
        userDefaults: UserDefaults = .standard,
        fallbackStore: ActiveHeadphoneWorkoutDraftFallbackStore = ActiveHeadphoneWorkoutDraftFallbackStore(),
        diagnostics: AppDiagnosticsRecorder = .shared
    ) {
        self.userDefaults = userDefaults
        self.fallbackStore = fallbackStore
        self.diagnostics = diagnostics
    }

    func activeDraftID() -> UUID? {
        guard let rawValue = userDefaults.string(forKey: activeDraftIDKey) else {
            return nil
        }

        return UUID(uuidString: rawValue)
    }

    func setActiveDraftID(_ id: UUID) {
        userDefaults.set(id.uuidString, forKey: activeDraftIDKey)
        userDefaults.synchronize()
    }

    func clearActiveDraftID(_ id: UUID? = nil) {
        if let id,
           activeDraftID() != id {
            return
        }

        userDefaults.removeObject(forKey: activeDraftIDKey)
        userDefaults.synchronize()
    }

    /// The draft a previous process left behind, after any checkpoint that SwiftData refused has
    /// been folded back in from the fallback file - so the number this returns is the last one
    /// the dead process counted, never the last one its store happened to accept.
    @MainActor
    func activeDraft(in modelContext: ModelContext) throws -> ActiveHeadphoneWorkoutDraft? {
        _ = fallbackStore.reconcile(into: modelContext, diagnostics: diagnostics)

        guard let id = activeDraftID() else {
            return try mostRecentDraft(in: modelContext)
        }

        let descriptor = FetchDescriptor<ActiveHeadphoneWorkoutDraft>(
            predicate: #Predicate { $0.id == id },
            sortBy: [SortDescriptor(\.lastCheckpointAt, order: .reverse)]
        )
        let draft = try modelContext.fetch(descriptor).first

        if draft == nil {
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_draft_pointer_stale",
                level: .warning,
                details: ["draft_id": id.uuidString]
            )
            clearActiveDraftID(id)
        }

        return draft
    }

    @MainActor
    func mostRecentDraft(in modelContext: ModelContext) throws -> ActiveHeadphoneWorkoutDraft? {
        var descriptor = FetchDescriptor<ActiveHeadphoneWorkoutDraft>(
            sortBy: [SortDescriptor(\.lastCheckpointAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let draft = try modelContext.fetch(descriptor).first
        if let draft {
            setActiveDraftID(draft.id)
            AppDiagnosticsRecorder.shared.record(
                "active_headphone_draft_fallback_found",
                level: .warning,
                details: draft.diagnosticDetails
            )
        }
        return draft
    }

    @MainActor
    func draft(sessionID: String, in modelContext: ModelContext) throws -> ActiveHeadphoneWorkoutDraft? {
        let descriptor = FetchDescriptor<ActiveHeadphoneWorkoutDraft>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.lastCheckpointAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }

    @MainActor
    func insert(_ draft: ActiveHeadphoneWorkoutDraft, in modelContext: ModelContext) throws {
        modelContext.insert(draft)
        try modelContext.save()
        setActiveDraftID(draft.id)
        AppDiagnosticsRecorder.shared.record(
            "active_headphone_draft_created",
            details: draft.diagnosticDetails
        )
    }

    @MainActor
    func delete(_ draft: ActiveHeadphoneWorkoutDraft, in modelContext: ModelContext) throws {
        let details = draft.diagnosticDetails
        let draftID = draft.id
        modelContext.delete(draft)
        try modelContext.save()
        clearActiveDraftID(draftID)
        fallbackStore.remove(draftID: draftID)
        AppDiagnosticsRecorder.shared.record(
            "active_headphone_draft_deleted",
            details: details
        )
    }

    /// What crediting the dead time to a draft produced.
    struct TrackingGapCredit: Equatable, Sendable {
        /// Wall clock between the last checkpoint and the resume.
        let gapSeconds: TimeInterval
        /// Whether that time was added to the draft's duration, or only recorded as unavailable.
        let credited: Bool
        /// The draft's duration after the credit.
        let durationSeconds: TimeInterval
    }

    /// Credits the time Ascend was not counting to the draft, as the resume path does for every
    /// mode: the duration grows to the wall clock when the gap is inside
    /// `maximumCreditableTrackingGap`, the gap is recorded in the integrity record as one more
    /// interruption either way, and the checkpoint moves to the resume instant so the next process
    /// death is measured from here.
    ///
    /// No step correction is recorded: the climber has not said a number yet. `applyRecoveryStepSync`
    /// is this plus that correction, for the recovery screen's typed count.
    @MainActor
    @discardableResult
    func creditTrackingGap(
        to draft: ActiveHeadphoneWorkoutDraft,
        in modelContext: ModelContext,
        resumedAt: Date = Date()
    ) throws -> TrackingGapCredit {
        let credit = applyGapCreditUnsaved(to: draft, at: resumedAt)
        try modelContext.save()
        setActiveDraftID(draft.id)

        AppDiagnosticsRecorder.shared.record(
            "active_headphone_recovery_gap_credited",
            level: .warning,
            details: draft.diagnosticDetails.merging([
                "tracking_gap_seconds": String(Int(credit.gapSeconds.rounded(.down))),
                "tracking_gap_credited": String(credit.credited)
            ]) { current, _ in current }
        )
        return credit
    }

    @MainActor
    private func applyGapCreditUnsaved(
        to draft: ActiveHeadphoneWorkoutDraft,
        at resumedAt: Date
    ) -> TrackingGapCredit {
        let trackingGapSeconds = max(resumedAt.timeIntervalSince(draft.lastCheckpointAt), 0)
        // Wall clock is only evidence of climbing while the climber was plausibly still on the
        // machine. Past `maximumCreditableTrackingGap` the session is credited to its last
        // checkpoint - the last moment Ascend has any evidence for - rather than to now. The
        // integrity record below still carries the full gap: how long tracking was unavailable is a
        // fact, and clamping it there would falsify the record instead of bounding a claim.
        let gapIsCreditable = trackingGapSeconds <= Self.maximumCreditableTrackingGap
        let creditedThrough = gapIsCreditable ? resumedAt : draft.lastCheckpointAt
        let elapsedSeconds = max(
            draft.durationSeconds,
            creditedThrough.timeIntervalSince(draft.startedAt)
        )
        let previousIntegrity = draft.trackingIntegrity
        let interruptionCount = trackingGapSeconds > 0
            ? previousIntegrity.interruptionCount + 1
            : previousIntegrity.interruptionCount
        let updatedIntegrity = HeadphoneMotionTrackingIntegrity(
            currentUnavailableDuration: 0,
            totalUnavailableDuration: previousIntegrity.totalUnavailableDuration + trackingGapSeconds,
            longestUnavailableDuration: max(previousIntegrity.longestUnavailableDuration, trackingGapSeconds),
            interruptionCount: interruptionCount
        )

        draft.applyCheckpoint(
            steps: draft.steps,
            durationSeconds: elapsedSeconds,
            sampleCount: draft.sampleCount,
            splitCurve: draft.splitCurve,
            trackingIntegrity: updatedIntegrity,
            stepCorrections: draft.stepCorrections,
            status: draft.status,
            checkpointedAt: creditedThrough
        )

        return TrackingGapCredit(
            gapSeconds: trackingGapSeconds,
            credited: gapIsCreditable,
            durationSeconds: elapsedSeconds
        )
    }

    @MainActor
    func applyRecoveryStepSync(
        correctedSteps: Int,
        to draft: ActiveHeadphoneWorkoutDraft,
        in modelContext: ModelContext,
        syncedAt: Date = Date()
    ) throws {
        let normalizedSteps = max(correctedSteps, 0)
        let detectedSteps = draft.steps
        let credit = applyGapCreditUnsaved(to: draft, at: syncedAt)
        let updatedIntegrity = draft.trackingIntegrity
        let correction = HeadphoneMotionStepCorrection(
            elapsedSeconds: Int(credit.durationSeconds.rounded(.down)),
            detectedSteps: detectedSteps,
            correctedSteps: normalizedSteps,
            deltaSteps: normalizedSteps - detectedSteps,
            trackingGapDurationSeconds: credit.gapSeconds,
            totalUnavailableDurationSeconds: updatedIntegrity.totalUnavailableDuration,
            interruptionCount: updatedIntegrity.interruptionCount
        )
        var recorder = LiveClimbStepTimelineRecorder()
        if let splitCurve = draft.splitCurve {
            recorder.restore(curve: splitCurve)
        }
        let splitCurve = recorder.recordCorrection(correction)
        var corrections = draft.stepCorrections
        corrections.append(correction)

        draft.applyCheckpoint(
            steps: normalizedSteps,
            durationSeconds: credit.durationSeconds,
            sampleCount: draft.sampleCount,
            splitCurve: splitCurve,
            trackingIntegrity: updatedIntegrity,
            stepCorrections: corrections,
            status: draft.status,
            checkpointedAt: draft.lastCheckpointAt
        )
        try modelContext.save()
        setActiveDraftID(draft.id)

        AppDiagnosticsRecorder.shared.record(
            "active_headphone_recovery_steps_synced",
            level: .warning,
            details: draft.diagnosticDetails.merging([
                "detected_steps": String(correction.detectedSteps),
                "corrected_steps": String(correction.correctedSteps),
                "delta_steps": String(correction.deltaSteps),
                "tracking_gap_seconds": String(Int(credit.gapSeconds.rounded(.down))),
                "tracking_gap_credited": String(credit.credited)
            ]) { current, _ in current }
        )
    }
}

/// Which drafts a session in this process is writing right now. Observable, so a surface that
/// sheds weight while a session runs (Home's globe) re-renders the moment one starts or ends.
@MainActor
@Observable
final class ActiveHeadphoneWorkoutRuntimeRegistry {
    static let shared = ActiveHeadphoneWorkoutRuntimeRegistry()

    private var activeDraftIDs: Set<UUID> = []

    /// Production uses `shared`; a test may hold a registry of its own so a session another suite
    /// is running in the same process cannot reach the surface under test.
    init() {}

    var hasActiveSession: Bool {
        !activeDraftIDs.isEmpty
    }

    func isActive(_ draft: ActiveHeadphoneWorkoutDraft) -> Bool {
        activeDraftIDs.contains(draft.id)
    }

    func markActive(_ draft: ActiveHeadphoneWorkoutDraft?) {
        guard let draft else { return }
        activeDraftIDs.insert(draft.id)
    }

    func markInactive(_ draft: ActiveHeadphoneWorkoutDraft?) {
        guard let draft else { return }
        activeDraftIDs.remove(draft.id)
    }
}

@MainActor
enum ActiveHeadphoneWorkoutDraftSaver {
    /// A recovered draft is a session the climber never finished in the app, so it can never
    /// stand as a completion.
    private static let recoveredStopReason: HeadphoneMotionSessionStopReason = .interrupted

    static func save(
        _ draft: ActiveHeadphoneWorkoutDraft,
        modelContext: ModelContext
    ) throws -> Workout {
        if draft.kind == .liveClimb,
           let climb = climb(for: draft) {
            _ = try ClimbService.shared.prepareLiveClimbAttempt(
                for: climb,
                startedAt: draft.startedAt,
                modelContext: modelContext
            )
        }

        let workout = makeRecoveredWorkout(from: draft, deviceModel: UIDevice.current.model)

        modelContext.insert(workout)
        try modelContext.save()

        if draft.kind == .liveClimb {
            try ClimbService.shared.apply(workouts: [workout], modelContext: modelContext)
        } else if draft.kind == .routine {
            try WorkoutParticipationService.addRoutineParticipationIfNeeded(
                for: workout,
                attribution: routineAttribution(for: draft),
                userId: workout.ownerUserId,
                modelContext: modelContext
            )
            try modelContext.save()
        }

        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: .created([LeaderboardWorkoutSnapshot(workout: workout)]),
            newWorkouts: [workout],
            changedWorkouts: [workout]
        )

        AppleHealthEnrichmentService.shared.trackNewlyRecordedWorkout(
            workout,
            modelContext: modelContext
        )

        try ActiveHeadphoneWorkoutDraftStore().delete(draft, in: modelContext)
        return workout
    }

    static func makeRecoveredWorkout(
        from draft: ActiveHeadphoneWorkoutDraft,
        deviceModel: String
    ) -> Workout {
        let splitCurve = draft.splitCurve ?? LiveReplaySplitCurve(
            intervalSeconds: 10,
            steps: [draft.steps]
        )
        let heartRateSamples = draft.heartRateSamples
        let heartRateCoverage = HeartRateTraceCoverage(
            samples: heartRateSamples,
            sessionStartedAt: draft.startedAt,
            sessionDuration: draft.durationSeconds
        )
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: draft.sampleCount,
            trackingMode: trackingMode(for: draft),
            climbId: draft.climbId,
            routineId: draft.routineId?.uuidString,
            routineTemplateId: draft.routineTemplateId,
            routineIntervalCount: draft.routineIntervalCount,
            targetStepCount: draft.targetStepCount,
            climbTargetStepCount: climbTargetStepCount(for: draft),
            targetDurationSeconds: draft.targetDurationSeconds,
            stopReason: recoveredStopReason,
            splitCurve: splitCurve,
            trackingIntegrity: draft.trackingIntegrity,
            stepCorrections: draft.stepCorrections,
            heartRateCoverage: heartRateCoverage
        )
        let heartRates = heartRateSamples.map(\.heartRate)

        return Workout(
            name: draft.workoutName,
            date: draft.startedAt,
            duration: max(draft.durationSeconds, 1),
            steps: draft.steps,
            floors: Workout.stepsToFloors(draft.steps),
            stepsPerFloor: Workout.defaultStepsPerFloor,
            avgHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / heartRates.count,
            maxHeartRate: heartRates.max(),
            heartRateTimeSeries: heartRateSamples.isEmpty ? nil : heartRateSamples,
            source: .headphoneMotion,
            deviceModel: deviceModel,
            sourceMetadata: metadata.jsonString,
            weightConfiguration: draft.routineWeightConfiguration
        )
    }

    private static func trackingMode(for draft: ActiveHeadphoneWorkoutDraft) -> HeadphoneMotionWorkoutTrackingMode {
        switch draft.kind {
        case .liveClimb:
            return .liveClimb
        case .justClimb:
            return .justClimb
        case .routine:
            return .routine
        }
    }

    private static func climbTargetStepCount(for draft: ActiveHeadphoneWorkoutDraft) -> Int? {
        guard draft.kind == .liveClimb else { return nil }
        return draft.targetStepCount
    }

    private static func climb(for draft: ActiveHeadphoneWorkoutDraft) -> Climb? {
        guard let climbId = draft.climbId else { return nil }
        return try? ClimbService.shared.climb(for: climbId)
    }

    static func routineAttribution(for draft: ActiveHeadphoneWorkoutDraft) -> RoutineWorkoutAttribution? {
        guard let routineId = draft.routineId else { return nil }
        let routineSource = draft.routineSourceRawValue.flatMap(RoutineSource.init(rawValue:)) ?? .userCreated
        return RoutineWorkoutAttribution(
            routineId: routineId,
            routineSource: routineSource,
            templateId: draft.routineTemplateId,
            origin: .liveSession(stopReason: recoveredStopReason)
        )
    }
}
