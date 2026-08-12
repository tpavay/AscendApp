import Foundation
import Observation
import SwiftData

/// Attaches wearable heart rate and calories to climbs Ascend recorded itself, and keeps
/// looking until they arrive.
///
/// ## Device-agnostic by construction
///
/// This reads `heartRate` and `activeEnergyBurned` quantity samples over the climb's own time
/// window. It does not look for an Apple Health *workout* and does not care which device wrote
/// the samples: HealthKit normalises Garmin, Whoop, Polar, a chest-strap app and Apple Watch
/// into the same quantity types, so they all arrive through this one path. What differs
/// between them is how many samples they wrote and how late - which is what the schedule is
/// for - never the shape of the data.
///
/// Matching an Apple Health workout is a separate concern that belongs to import, and it is
/// deliberately not a precondition here: a climber whose wearable publishes heart rate but no
/// stair-stepper workout still gets their heart rate.
///
/// ## Why it retries
///
/// Enrichment used to run exactly once, in the moment the climb was saved - before the wearable
/// had published anything - and then never again unless the climber happened to open that
/// climb's detail screen. It found nothing, said nothing, and stopped (#438).
///
/// One timer serves every tracked climb: it sleeps until the earliest due attempt across all of
/// them, runs one pass, and re-arms. Nothing is tracked, no timer exists. Eligibility lives in
/// `AppleHealthEnrichmentAttemptStore` as an absolute date, so the budget survives relaunch and
/// cannot be spent three times in one millisecond by three callers asking at once, and the
/// series ends on its own after `AppleHealthEnrichmentSchedule`'s budget.
@MainActor
@Observable
final class AppleHealthEnrichmentService: AuthenticatedSessionWorker {
    static let shared = AppleHealthEnrichmentService()

    /// What one read of Apple Health actually did, before it is phrased for anyone.
    private enum ReadOutcome: Equatable {
        case addedHeartRate
        case nothingToAdd
        case failed
    }

    private let authorizationController: any HealthKitAuthorizationControlling
    private let metricsReader: any HealthKitMetricsReading
    private let attemptStore: AppleHealthEnrichmentAttemptStore
    private let sessionWorkGate: AuthenticatedBootstrapCoordinator
    private let featureFlags: RemoteFeatureFlagStore
    private let diagnostics: any AppDiagnosticsRecording
    private let recordLifecycleState: @MainActor (AppleHealthConnectionState) -> Void
    private let now: @MainActor () -> Date

    /// Climbs the timer is currently watching. Identity only - a `Workout` is a SwiftData
    /// object whose context this service does not own.
    private var trackedWorkoutIDs: Set<UUID> = []
    private var modelContext: ModelContext?
    private var timerTask: Task<Void, Never>?
    private var passTask: Task<Bool, Never>?

    /// The read each tracked climb is waiting on, so a second caller joins it.
    ///
    /// A scheduled pass suspends at the HealthKit read, which frees the main actor for the
    /// Integrations card's `Check now` on the same climb. Two reads would spend two of the nine
    /// attempts on one answer.
    private var readTasks: [UUID: Task<ReadOutcome, Never>] = [:]

    /// The connection state the backend was last told about, so it is only told again when it
    /// is genuinely news.
    ///
    /// Account-scoped even though it looks like a cache: the event it gates is written under the
    /// signed-in uid, so `cancelInFlightWork` clears it along with everything else belonging to
    /// the climber who just left. Kept, it would silence the next climber on the same device -
    /// Health authorization is device-wide, so their state matches and nothing would report it.
    private var lastReportedConnectionState: AppleHealthConnectionState?

    init(
        authorizationController: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        metricsReader: any HealthKitMetricsReading = HealthKitMetricsReader.shared,
        attemptStore: AppleHealthEnrichmentAttemptStore = AppleHealthEnrichmentAttemptStore(),
        sessionWorkGate: AuthenticatedBootstrapCoordinator = .shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        diagnostics: any AppDiagnosticsRecording = AppDiagnosticsRecorder.shared,
        recordLifecycleState: @escaping @MainActor (AppleHealthConnectionState) -> Void = { state in
            LifecycleEventRecorder.shared.recordAppleHealthIntegration(state: state)
        },
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.authorizationController = authorizationController
        self.metricsReader = metricsReader
        self.attemptStore = attemptStore
        self.sessionWorkGate = sessionWorkGate
        self.featureFlags = featureFlags
        self.diagnostics = diagnostics
        self.recordLifecycleState = recordLifecycleState
        self.now = now
    }

    /// The retry curve, read back off the ledger that enforces it.
    ///
    /// One source of truth on purpose: the ledger computes eligibility, the window and the
    /// budget from its own schedule, so a service holding a second copy could hand out a
    /// verdict the ledger disagrees with for the same climb.
    private var schedule: AppleHealthEnrichmentSchedule { attemptStore.schedule }


    var connectionState: AppleHealthConnectionState {
        authorizationController.connectionState
    }

    /// The Integrations card reads this name; kept so one connection state has one spelling.
    var appleHealthConnectionState: AppleHealthConnectionState { connectionState }

    /// Why the connect or check the climber just asked for could not proceed, for the
    /// Integrations card to show.
    ///
    /// Only ever written by a climber-initiated action - connecting, or a `Check now` that
    /// passes `isUserInitiated`. The automatic series stays silent whatever happens to it: a
    /// scheduled pass that fails while nobody is watching would leave a message waiting on a
    /// screen the climber opens later with nothing to attach it to.
    private(set) var lastErrorMessage: String?

    /// Hands the service the store to work in.
    ///
    /// Every entry point also assigns it, so this exists for the surfaces that adopt the service
    /// before asking it for anything - Home, the workout list, the Integrations card and the root
    /// view all call it from their `.task`.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Connects Apple Health without a climb in hand.
    ///
    /// Settings -> Integrations is the only surface that offers the connection, and it connects
    /// as a standing setup step rather than for one climb - which is why nothing here takes a
    /// `Workout`. Refusals are reported through `lastErrorMessage` rather than swallowed,
    /// because this is a button a climber pressed.
    @discardableResult
    func requestAppleHealthAuthorizationIfNeeded() async -> Bool {
        // Every exit reports the state it resolved to, including the refusals: the backend's
        // view of a climber's Health connection is only as current as the last time the app
        // said something.
        defer { recordAppleHealthLifecycleState(force: true) }

        await authorizationController.refreshAuthorizationRequestStatus()

        guard authorizationController.isHealthDataAvailable else {
            lastErrorMessage = "Apple Health is not available on this device."
            return false
        }

        switch authorizationController.connectionState {
        case .connected:
            lastErrorMessage = nil
            return true
        case .revoked:
            lastErrorMessage = "Apple Health access is off. Turn Ascend back on under Heart Rate in the Health app."
            return false
        case .unavailable:
            lastErrorMessage = "Apple Health is not available on this device."
            return false
        case .neverConnected:
            break
        }

        guard await authorizationController.requestAuthorization() else {
            lastErrorMessage = authorizationController.lastPermissionErrorMessage
                ?? "Apple Health could not be connected."
            return false
        }

        lastErrorMessage = nil
        return true
    }

    /// Runs a pass now for every climb still inside the retry window.
    ///
    /// The awaitable form of `resumeTracking`, for surfaces that want the work to have happened
    /// before they render - Home on entry, and the Integrations card after connecting.
    /// Defaults to the store handed over by `configure`, so a surface that already adopted the
    /// service does not have to pass it again.
    ///
    /// A climber-initiated check reports its own outcome through `lastErrorMessage`, clearing it
    /// first: the card presenting it has to be told about the check that was just asked for,
    /// never about a refusal or a failure from an earlier one. Home's automatic entries pass
    /// nothing and leave that property alone - nobody is waiting on those.
    func refreshPendingEnrichment(
        modelContext: ModelContext? = nil,
        isUserInitiated: Bool = false
    ) async {
        if isUserInitiated {
            lastErrorMessage = nil
        }

        // Nothing at all while account work is suspended, not even a status read.
        guard sessionWorkGate.isSuspended == false else { return }

        // Refreshed here rather than only inside a pass, because a pass is skipped entirely when
        // no climb is currently due - and this is the entry point the Integrations card uses to
        // show the connection state, which must be current whether or not there was work to do.
        await authorizationController.refreshAuthorizationRequestStatus()

        let refusal = checkRefusalMessage

        guard let context = modelContext ?? self.modelContext else {
            if isUserInitiated {
                lastErrorMessage = refusal
            }
            return
        }

        // The pass this call runs is what answers it. A global failure count would also catch a
        // read some other surface started for another climb, and report that as this tap's.
        let pass = resumeTracking(modelContext: context)
        let didFailAnyRead = await pass?.value ?? false
        await drainInFlightWork()

        if isUserInitiated {
            lastErrorMessage = refusal ?? (didFailAnyRead ? Self.checkFailedMessage : nil)
        }

        recordAppleHealthLifecycleState()
    }

    /// Why a check asked for by hand could not read anything, or `nil` when it could.
    ///
    /// The kill switch is named as its own refusal rather than folded into the connection
    /// states: a climber whose Health is connected and whose checks are switched off has done
    /// nothing wrong, and telling them to reconnect would send them after a problem they do
    /// not have.
    private var checkRefusalMessage: String? {
        switch authorizationController.connectionState {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .revoked:
            return "Apple Health access is off. Turn Ascend back on under Heart Rate in the Health app."
        case .neverConnected:
            return "Apple Health isn't connected yet. Connect it to put heart rate on your climbs."
        case .connected:
            guard isEnrichmentSwitchedOn else {
                return "Ascend isn't reading Apple Health right now. Your climbs keep their place - heart rate lands when checks resume."
            }
            return nil
        }
    }

    /// What Ascend says when its own check broke. Deliberately says nothing about the climber's
    /// equipment: the failure was here, and the underlying error goes to diagnostics instead.
    static let checkFailedMessage = "Ascend couldn't finish that check. Try again in a moment."

    /// Tells the backend the connection state, but only when it is news.
    ///
    /// The event is named for a change, and it costs a callable and a Firestore transaction
    /// each time. A pass runs on every Home entry, every tab return and every foreground, so
    /// reporting an unchanged state from there would count Home entries rather than changes.
    /// `force` is for the climber-initiated authorization path, where the tap itself is the
    /// event worth timestamping.
    private func recordAppleHealthLifecycleState(force: Bool = false) {
        let state = authorizationController.connectionState
        guard force || state != lastReportedConnectionState else { return }

        lastReportedConnectionState = state
        recordLifecycleState(state)
    }

    /// Whether a wake-up is currently scheduled.
    ///
    /// Exposed so the bound can be asserted rather than assumed: a climb that can never match -
    /// disconnected, killed, out of budget, out of window - must leave nothing behind waking the
    /// app up to find that out again.
    var hasScheduledWakeUp: Bool { timerTask != nil }

    /// Whether the backend still permits enrichment, read the cheap way.
    ///
    /// A plain in-memory flag lookup rather than `RemoteFeatureGate.allows`, because this
    /// answers the Integrations card's refusal copy rather than gating work: the gate records a
    /// diagnostic every time it blocks, and one per card render would fill an incident with
    /// noise. The gate stays on the work path, where a blocked pass is worth recording once.
    private var isEnrichmentSwitchedOn: Bool {
        featureFlags.isEnabled(.appleHealthEnrichment)
    }

    // MARK: - Entry points

    /// Starts the retry series for a climb that has just been saved.
    ///
    /// Runs the save-time attempt immediately - an Apple Watch has often already published by
    /// the time the summary renders - and arms the timer for the rest of the curve.
    func trackNewlyRecordedWorkout(_ workout: Workout, modelContext: ModelContext) {
        self.modelContext = modelContext
        track(workout)
        runPass(modelContext: modelContext)
    }

    /// Re-arms the timer for every climb still inside the retry window.
    ///
    /// Called on authenticated bootstrap and on app foreground. A suspended app's `Task.sleep`
    /// is not a reliable alarm clock, and a relaunched app has no in-memory tracking set at
    /// all - the ledger is what survives, and this is what reads it back.
    ///
    /// Returns the pass it started or joined, so a caller with a climber waiting can report what
    /// that pass did rather than what happened to be running alongside it. `nil` means there was
    /// nothing to do.
    @discardableResult
    func resumeTracking(modelContext: ModelContext) -> Task<Bool, Never>? {
        self.modelContext = modelContext
        attemptStore.prune(at: now())

        let windowStart = now().addingTimeInterval(-schedule.eligibilityWindow)
        let candidates = (try? InAppSensorWorkoutQuery.inAppSensorWorkouts(
            startingOnOrAfter: windowStart,
            in: modelContext
        )) ?? []

        trackedWorkoutIDs = []
        for workout in candidates where isTrackable(workout) {
            trackedWorkoutIDs.insert(workout.id)
        }

        guard !trackedWorkoutIDs.isEmpty else {
            timerTask?.cancel()
            timerTask = nil
            return nil
        }

        return runPass(modelContext: modelContext)
    }

    // MARK: - AuthenticatedSessionWorker

    /// Stops every read and forgets what it was watching.
    ///
    /// Account deletion and sign-out drain this: a timer holding workout IDs would otherwise
    /// keep waking up to write the previous account's rows into a store that has been emptied
    /// underneath it.
    func cancelInFlightWork() {
        timerTask?.cancel()
        timerTask = nil
        passTask?.cancel()
        for task in readTasks.values {
            task.cancel()
        }
        trackedWorkoutIDs = []
        lastReportedConnectionState = nil

        // The store handed over by `configure` is deliberately kept. Nothing can run on it while
        // it is cancelled - the tracking set is empty, so no climb is due and no wake-up is
        // armed, and `sessionWorkGate.isSuspended` refuses a pass outright. Dropping it instead
        // made the service unable to resume for any owner that adopted it once and does not
        // re-configure, which is how a deletion that resolved left enrichment permanently dead.
    }

    /// Waits for the reads, not for the wait between them.
    ///
    /// Deliberately does not await `timerTask`: a timer that is asleep holds no account state
    /// and its sleep can be hours long, so awaiting it would park account deletion's bounded
    /// drain until it timed out. `cancelInFlightWork` runs first under this protocol and stops
    /// the timer, so nothing it would have started can still run.
    ///
    /// The reads are awaited on their own after the pass rather than assumed to have ended with
    /// it: a read outlives the pass that started it if that pass is cancelled mid-flight, and a
    /// drain that returned while one was still writing would hand the store back mid-write.
    func drainInFlightWork() async {
        _ = await passTask?.value

        for task in readTasks.values {
            _ = await task.value
        }
    }

    // MARK: - Scheduling

    private func track(_ workout: Workout) {
        guard isTrackable(workout) else { return }
        trackedWorkoutIDs.insert(workout.id)
    }

    private func isTrackable(_ workout: Workout) -> Bool {
        workout.isInAppSensorWorkout &&
            needsEnrichment(workout) &&
            schedule.isWithinEligibilityWindow(workout, at: now()) &&
            !attemptStore.hasExhaustedAutomaticAttempts(for: workout, at: now())
    }

    /// Whether a pass could accomplish anything at all right now.
    ///
    /// The single choke point every reason a pass could not run is read through - a suspended
    /// account session, a missing Health connection, the kill switch - and it is checked
    /// *before* a pass rather than inside one. A pass that cannot read still leaves every
    /// tracked climb due, so re-arming off the back of one would schedule the next wake-up one
    /// second out and keep doing it - a spin, dressed as a schedule. Every condition that can
    /// stop a pass belongs here for exactly that reason: one checked somewhere else is a door
    /// back into the spin. Blocked work is deferred to the next lifecycle event instead:
    /// `resumeTracking` runs on foreground and on authenticated bootstrap, and connecting
    /// Health fetches directly.
    ///
    /// Nothing about the retry ledger is touched either way, so a climb resumes its own series
    /// exactly where it left off.
    private var canRunEnrichment: Bool {
        guard sessionWorkGate.isSuspended == false else { return false }
        guard authorizationController.connectionState == .connected else { return false }

        return RemoteFeatureGate.allows(
            .appleHealthEnrichment,
            path: "AppleHealthEnrichmentService.runPass",
            store: featureFlags
        )
    }

    /// Runs the climbs that are due now, then sleeps until the next one is.
    ///
    /// One task for all tracked climbs rather than one per climb: the wake-ups a climber pays
    /// for should be a function of the schedule, not of how many times they climbed today.
    ///
    /// A pass already in flight is left to finish rather than cancelled and restarted. Several
    /// callers reach it in quick succession - a foreground, a Home entry and a workout detail can
    /// all land together - and restarting would throw away a read that had already completed,
    /// having already spent the attempt that paid for it. The in-flight pass re-arms from the
    /// current tracking set when it ends, so nothing added meanwhile is missed.
    ///
    /// Its value is whether any read *this pass* made failed, which is what a caller with a
    /// climber waiting reports.
    @discardableResult
    private func runPass(modelContext: ModelContext) -> Task<Bool, Never> {
        if let passTask { return passTask }

        let pass = Task { @MainActor [weak self] in
            guard let self else { return false }
            defer { self.passTask = nil }

            let didFailAnyRead = await self.enrichDueWorkouts(modelContext: modelContext)
            self.armTimer()
            return didFailAnyRead
        }

        passTask = pass
        return pass
    }

    /// Schedules the next wake-up, or deliberately none.
    ///
    /// Both halves of "none" are explicit rather than incidental: a pass that could not run
    /// arms nothing, and a service with no tracked climb still due has nothing to arm *for*.
    /// That second half is what makes cancellation stick - `cancelInFlightWork` keeps the store
    /// on purpose and empties the tracking set instead, so an arm that races it finds nothing
    /// pending and schedules nothing.
    private func armTimer() {
        timerTask?.cancel()
        timerTask = nil

        guard canRunEnrichment,
              let modelContext,
              let wakeAt = earliestPendingAttemptDate(in: modelContext) else { return }

        let delay = max(wakeAt.timeIntervalSince(now()), 1)
        timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let modelContext = self.modelContext else { return }
            self.runPass(modelContext: modelContext)
        }
    }

    private func earliestPendingAttemptDate(in modelContext: ModelContext) -> Date? {
        trackedWorkouts(in: modelContext)
            .compactMap { attemptStore.nextEligibleDate(for: $0, at: now()) }
            .min()
    }

    /// Suspension mid-pass is covered by cancellation rather than by a second guard here:
    /// `suspendAndDrain` cancels this task before it drains, and the loop checks for that.
    private func enrichDueWorkouts(modelContext: ModelContext) async -> Bool {
        // Nothing at all while account work is suspended - not even a status read, which would
        // touch the account being deleted.
        guard sessionWorkGate.isSuspended == false else { return false }

        // Authorization can change while Ascend is not running: a climber grants or revokes
        // Health in Settings, and nothing tells the app. Re-reading it at the top of a pass is
        // what lets a grant made overnight take effect on the next foreground instead of leaving
        // the series refusing to look at data it now has access to.
        await authorizationController.refreshAuthorizationRequestStatus()

        guard canRunEnrichment else { return false }

        var didFailAnyRead = false
        for workout in trackedWorkouts(in: modelContext) {
            if Task.isCancelled { return didFailAnyRead }
            guard attemptStore.isAutomaticAttemptDue(for: workout, at: now()) else { continue }

            if await enrich(workout, modelContext: modelContext) == .failed {
                didFailAnyRead = true
            }
        }

        return didFailAnyRead
    }

    /// Resolves tracked IDs back to live objects and drops the ones that no longer qualify.
    ///
    /// A tracked climb stops qualifying for ordinary reasons - its heart rate arrived, it
    /// aged out of the window, it was deleted - and each one has to remove it from the set,
    /// or the timer keeps waking for a climb that will never match.
    private func trackedWorkouts(in modelContext: ModelContext) -> [Workout] {
        guard !trackedWorkoutIDs.isEmpty else { return [] }

        let windowStart = now().addingTimeInterval(-schedule.eligibilityWindow)
        let candidates = (try? InAppSensorWorkoutQuery.inAppSensorWorkouts(
            startingOnOrAfter: windowStart,
            in: modelContext
        )) ?? []

        let stillTracked = candidates.filter { workout in
            trackedWorkoutIDs.contains(workout.id) && isTrackable(workout)
        }

        trackedWorkoutIDs = Set(stillTracked.map(\.id))
        return stillTracked
    }

    // MARK: - Reading

    /// One read per climb at a time, whoever asked for it.
    ///
    /// A caller arriving while a read is already in flight joins that read instead of starting
    /// a second one, and is answered by its outcome. Joining rather than refusing is what keeps
    /// the answer honest: the climber who tapped `Check now` while a scheduled pass was mid-read
    /// is told what that read found, not that Ascend could not look.
    private func enrich(_ workout: Workout, modelContext: ModelContext) async -> ReadOutcome {
        let workoutID = workout.id

        if let inFlight = readTasks[workoutID] {
            return await inFlight.value
        }

        attemptStore.recordAttempt(for: workout, at: now())

        let read = Task { @MainActor [weak self] in
            guard let self else { return ReadOutcome.nothingToAdd }
            defer { self.readTasks[workoutID] = nil }

            return await self.performRead(of: workout, modelContext: modelContext)
        }

        readTasks[workoutID] = read
        return await read.value
    }

    private func performRead(of workout: Workout, modelContext: ModelContext) async -> ReadOutcome {
        let workoutID = workout.id
        let window = AppleHealthEnrichmentSchedule.endDate(of: workout)

        let metrics: WorkoutMetrics
        do {
            metrics = try await metricsReader.fetchMetrics(during: workout.date...window)
        } catch {
            // A query that failed is not a wearable that published nothing, and the two must not
            // arrive at the same copy: one sends the climber to their own equipment for a problem
            // that is ours.
            record(readFailure: error, code: "apple_health_enrichment_read_failed")
            return .failed
        }

        guard !Task.isCancelled else { return .nothingToAdd }

        let wantedHeartRate = needsHeartRate(workout)
        let before = LeaderboardWorkoutSnapshot(workout: workout)
        guard apply(metrics, to: workout) else { return .nothingToAdd }

        do {
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: WorkoutMutation(updated: [
                    .init(before: before, after: LeaderboardWorkoutSnapshot(workout: workout))
                ]),
                changedWorkouts: [workout]
            )
        } catch {
            // Health had something for this climb and Ascend could not keep it. That is a
            // failure of ours, and saying so is what stops the surfaces above reporting it as
            // an empty read.
            record(readFailure: error, code: "apple_health_enrichment_write_failed")
            return .failed
        }

        let didAddHeartRate = wantedHeartRate && !needsHeartRate(workout)

        // Calories can land in a pass that brought no heart rate. Retiring the climb on that
        // partial answer is how the series would stop one attempt short of the thing the
        // climber was actually waiting for.
        if !needsEnrichment(workout) {
            attemptStore.clear(workoutID: workoutID)
            trackedWorkoutIDs.remove(workoutID)
        }

        return didAddHeartRate ? .addedHeartRate : .nothingToAdd
    }

    /// Sends the underlying error where an engineer can read it, since the climber never sees it.
    private func record(readFailure error: any Error, code: String) {
        diagnostics.record(
            code,
            level: .warning,
            details: ["error": String(describing: error)],
            mirrorToCrashlytics: true
        )
    }

    /// Writes whatever Health had, and only what it had.
    ///
    /// A sparse series is a real answer, not a failed read: a wearable that wrote four samples
    /// across a twenty-minute climb has told the truth about that climb. Ascend takes those
    /// four and stops asking. Only a genuinely empty read leaves the climb pending.
    ///
    /// A live-captured series wins over anything Health holds - a chest strap paired to Ascend
    /// during the session is first-party and denser than a wrist-derived summary - so heart
    /// rate is only ever filled in, never overwritten.
    private func apply(_ metrics: WorkoutMetrics, to workout: Workout) -> Bool {
        var didChange = false

        if workout.heartRateTimeSeries.isEmpty {
            if let avgHeartRate = metrics.avgHeartRate, workout.avgHeartRate != avgHeartRate {
                workout.avgHeartRate = avgHeartRate
                didChange = true
            }
            if let maxHeartRate = metrics.maxHeartRate, workout.maxHeartRate != maxHeartRate {
                workout.maxHeartRate = maxHeartRate
                didChange = true
            }
            if !metrics.heartRateTimeSeries.isEmpty {
                let encoded = metrics.heartRateTimeSeries.encoded
                if workout.heartRateData != encoded {
                    workout.heartRateData = encoded
                    didChange = true
                }
            }
        }

        if let caloriesBurned = metrics.caloriesBurned, workout.caloriesBurned != caloriesBurned {
            workout.caloriesBurned = caloriesBurned
            didChange = true
        }

        return didChange
    }

    /// A climb still wants heart rate when it has no series *and* no summary.
    ///
    /// Both halves matter: a wearable that published only an average with no samples has still
    /// answered, and re-reading it forever would be Ascend refusing an answer it already has.
    private func needsHeartRate(_ workout: Workout) -> Bool {
        workout.heartRateTimeSeries.isEmpty &&
            workout.avgHeartRate == nil &&
            workout.maxHeartRate == nil
    }

    /// What keeps a climb on the timer. Wider than `needsHeartRate` because the same read
    /// answers for calories, and narrower than the import path's notion of completeness
    /// because average METs only ever come off an Apple Health workout object - waiting on a
    /// number this read cannot produce is how a series burns its whole budget for nothing.
    private func needsEnrichment(_ workout: Workout) -> Bool {
        needsHeartRate(workout) || workout.caloriesBurned == nil
    }
}
