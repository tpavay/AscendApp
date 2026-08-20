import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// A crash-recovered headphone draft credits wall clock so a climber who kept stepping while the
/// app was dead is not under-counted. Uncapped, that credited a draft resolved days later a
/// duration of days - and `isPhysicallyPossibleClimb` in `firestore.rules` now refuses anything
/// over five days, so the honest climb would have come back as a bare `PERMISSION_DENIED` forever
/// with nothing the client could say about it.
///
/// These tests pin both halves of `maximumCreditableTrackingGap`: a short dropout still recovers
/// the real time exactly as it did before, and a long absence is credited to the last checkpoint
/// instead - producing a document that fits the envelope rather than one the server can never
/// accept.
@MainActor
struct RecoveredSessionDurationEnvelopeTests {
    /// 2025-06-15. Fixed and in the past, because the envelope also refuses a `startedAt` more than
    /// a day ahead of server time - a fixture dated into the future would fail that check for a
    /// reason that has nothing to do with what these tests are about.
    private static let startedAt = Date(timeIntervalSince1970: 1_750_000_000)

    // MARK: - The bounds `firestore.rules` enforces
    //
    // Mirrored by hand from `isPhysicallyPossibleClimb`. `tests/firebase-rules/
    // workout-physical-envelope.test.mjs` is what proves the rule itself behaves this way; these
    // are here so a Swift-side change that starts producing a refusable document fails here first,
    // where the cause is visible, rather than on a stranger's phone.
    private static let ruleMaximumDurationSeconds: TimeInterval = 432_000
    private static let ruleMaximumSteps = 120_000
    private static let ruleMaximumStepsPerSecond = 4

    // MARK: - A short dropout behaves exactly as it always did

    /// Ninety seconds is the case the `max()` exists for: the app died mid-climb, the climber kept
    /// stepping, and the draft holds no tracked duration for the gap. Wall clock is the only
    /// evidence of that time, and it is still credited in full.
    @Test("A ninety-second tracking gap still recovers the wall-clock time")
    func shortGapStillCreditsWallClock() throws {
        let modelContext = try makeModelContext()
        let trackedSeconds: TimeInterval = 300
        let gapSeconds: TimeInterval = 90
        let draft = makeDraft(
            trackedSeconds: trackedSeconds,
            trackedSteps: 540,
            in: modelContext
        )
        let syncedAt = Self.startedAt.addingTimeInterval(trackedSeconds + gapSeconds)

        try makeStore().applyRecoveryStepSync(
            correctedSteps: 700,
            to: draft,
            in: modelContext,
            syncedAt: syncedAt
        )

        #expect(draft.durationSeconds == trackedSeconds + gapSeconds)
        #expect(draft.steps == 700)
        // The gap is still recorded as a gap: clamping the credit never falsifies the integrity
        // record of how long tracking was actually unavailable.
        #expect(draft.trackingIntegrity.longestUnavailableDuration == gapSeconds)
    }

    /// The boundary itself, from both sides, so the constant means one specific thing.
    @Test("A gap is credited up to the limit and not past it")
    func gapIsCreditedUpToTheLimitOnly() throws {
        let limit = ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap
        let trackedSeconds: TimeInterval = 600

        for (gapSeconds, expectedDuration) in [
            (limit, trackedSeconds + limit),
            (limit + 1, trackedSeconds)
        ] {
            let modelContext = try makeModelContext()
            let draft = makeDraft(
                trackedSeconds: trackedSeconds,
                trackedSteps: 1_000,
                in: modelContext
            )

            try makeStore().applyRecoveryStepSync(
                correctedSteps: 1_200,
                to: draft,
                in: modelContext,
                syncedAt: Self.startedAt.addingTimeInterval(trackedSeconds + gapSeconds)
            )

            #expect(draft.durationSeconds == expectedDuration)
        }
    }

    // MARK: - A long absence is credited to the last checkpoint

    /// Eight days is the case that made the envelope look like a bug in the envelope. The climb is
    /// honest; only the wall clock between the crash and the climber reopening the app is not
    /// climbing. Credited, the document is one no rule can accept; clamped, it is a thirty-minute
    /// climb the server takes.
    @Test("An eight-day tracking gap is not climbing, and the climb still syncs")
    func longGapIsNotCreditedAndTheWorkoutFitsTheEnvelope() throws {
        let modelContext = try makeModelContext()
        let trackedSeconds: TimeInterval = 1_800
        let gapSeconds: TimeInterval = 8 * 24 * 60 * 60
        let draft = makeDraft(
            trackedSeconds: trackedSeconds,
            trackedSteps: 3_000,
            in: modelContext
        )
        let syncedAt = Self.startedAt.addingTimeInterval(trackedSeconds + gapSeconds)

        // What the old formula would have produced, stated so the regression is legible: a
        // duration past the five-day ceiling is a write the server refuses every time it is
        // offered, and a workout that can never back up.
        let uncappedElapsed = syncedAt.timeIntervalSince(draft.startedAt)
        #expect(uncappedElapsed > Self.ruleMaximumDurationSeconds)

        try makeStore().applyRecoveryStepSync(
            correctedSteps: 3_400,
            to: draft,
            in: modelContext,
            syncedAt: syncedAt
        )

        #expect(draft.durationSeconds == trackedSeconds)

        let workout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(
            from: draft,
            deviceModel: "iPhone"
        )
        workout.markPendingRemoteUpsert(ownerUserId: "climber-1")

        // The real mapper, so this is the document `firestore.rules` would actually evaluate -
        // not a restatement of the numbers. `snapshot` throwing is itself a refusal to sync.
        let document = try WorkoutRemoteSyncMapper.snapshot(from: workout).document

        #expect(document.durationSeconds == trackedSeconds)
        #expect(document.steps == 3_400)
        #expect(document.durationSeconds <= Self.ruleMaximumDurationSeconds)
        #expect(document.steps <= Self.ruleMaximumSteps)
        #expect(document.steps <= Int(document.durationSeconds) * Self.ruleMaximumStepsPerSecond)
        #expect(document.startedAt < Date().addingTimeInterval(24 * 60 * 60))
    }

    /// The shape the clamp is most likely to meet: the app dies five minutes in, the climber keeps
    /// stepping for another twenty-five, then types the machine's full count. The clamp bounds
    /// duration and never the typed steps, so crediting this one to its last checkpoint would hand
    /// the mapper 2,000 steps over 300 seconds - 400 steps/min, past the device's own 220 gate, and
    /// `WorkoutSyncCoordinator` treats that refusal as permanent. Inside the limit it is simply the
    /// half-hour climb it was.
    @Test("A climber who keeps stepping for twenty-five minutes after a crash still syncs")
    func gapWithinTheLimitKeepsCadencePlausible() throws {
        let modelContext = try makeModelContext()
        let trackedSeconds: TimeInterval = 300
        let gapSeconds: TimeInterval = 25 * 60
        let machineSteps = 2_000
        let draft = makeDraft(
            trackedSeconds: trackedSeconds,
            trackedSteps: 320,
            in: modelContext
        )

        #expect(gapSeconds <= ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap)

        try makeStore().applyRecoveryStepSync(
            correctedSteps: machineSteps,
            to: draft,
            in: modelContext,
            syncedAt: Self.startedAt.addingTimeInterval(trackedSeconds + gapSeconds)
        )

        #expect(draft.durationSeconds == trackedSeconds + gapSeconds)

        let workout = ActiveHeadphoneWorkoutDraftSaver.makeRecoveredWorkout(
            from: draft,
            deviceModel: "iPhone"
        )
        workout.markPendingRemoteUpsert(ownerUserId: "climber-1")

        let stepsPerMinute = Double(machineSteps) / (draft.durationSeconds / 60)
        #expect(stepsPerMinute < WorkoutPlausibilityPolicy.maximumAverageStepsPerMinute)
        #expect(WorkoutPlausibilityPolicy.hasPlausibleTotals(workout))

        let document = try WorkoutRemoteSyncMapper.snapshot(from: workout).document

        #expect(document.durationSeconds == trackedSeconds + gapSeconds)
        #expect(document.steps == machineSteps)
        #expect(document.steps <= Int(document.durationSeconds) * Self.ruleMaximumStepsPerSecond)
    }

    /// Saving can fail after the sync - `ActiveHeadphoneWorkoutDraftSaver.save` throws from several
    /// places - and the climber is then free to retype the count and tap Save again. The second
    /// sync must measure its gap from the checkpoint the draft has evidence for, not from the
    /// moment of the first sync, or the clamped span is credited after all.
    @Test("Syncing a clamped recovery twice does not re-credit the gap")
    func repeatedRecoverySyncIsIdempotent() throws {
        let modelContext = try makeModelContext()
        let trackedSeconds: TimeInterval = 1_800
        let gapSeconds: TimeInterval = 8 * 24 * 60 * 60
        let draft = makeDraft(
            trackedSeconds: trackedSeconds,
            trackedSteps: 3_000,
            in: modelContext
        )
        let store = makeStore()
        let syncedAt = Self.startedAt.addingTimeInterval(trackedSeconds + gapSeconds)

        try store.applyRecoveryStepSync(
            correctedSteps: 3_400,
            to: draft,
            in: modelContext,
            syncedAt: syncedAt
        )
        try store.applyRecoveryStepSync(
            correctedSteps: 3_500,
            to: draft,
            in: modelContext,
            syncedAt: syncedAt.addingTimeInterval(60)
        )

        #expect(draft.durationSeconds == trackedSeconds)
        #expect(draft.steps == 3_500)
        #expect(draft.durationSeconds <= Self.ruleMaximumDurationSeconds)
    }

    // MARK: - Helpers

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ActiveHeadphoneWorkoutDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A store that cannot touch the shared defaults the app uses to point at the live draft.
    private func makeStore() -> ActiveHeadphoneWorkoutDraftStore {
        ActiveHeadphoneWorkoutDraftStore(
            userDefaults: UserDefaults(suiteName: "RecoveredSessionDurationEnvelopeTests.\(UUID().uuidString)")!
        )
    }

    /// A draft whose tracking kept up until the app died: `lastCheckpointAt` sits exactly
    /// `trackedSeconds` after the start, which is what a two-second checkpoint cadence produces.
    private func makeDraft(
        trackedSeconds: TimeInterval,
        trackedSteps: Int,
        in modelContext: ModelContext
    ) -> ActiveHeadphoneWorkoutDraft {
        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "session-recovered",
            kind: .justClimb,
            startedAt: Self.startedAt,
            title: "Just Climb",
            subtitle: "Recovered",
            workoutName: "Just Climb",
            targetStepCount: nil,
            targetDurationSeconds: nil
        )
        modelContext.insert(draft)
        draft.applyCheckpoint(
            steps: trackedSteps,
            durationSeconds: trackedSeconds,
            sampleCount: 100,
            splitCurve: nil,
            trackingIntegrity: .verified,
            stepCorrections: [],
            checkpointedAt: Self.startedAt.addingTimeInterval(trackedSeconds)
        )
        return draft
    }
}
