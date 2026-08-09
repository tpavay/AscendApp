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
/// cannot be spent three times in one millisecond by three surfaces asking at once, and the
/// series ends on its own after `AppleHealthEnrichmentSchedule`'s budget.
@MainActor
@Observable
final class AppleHealthEnrichmentService: AuthenticatedSessionWorker {
    static let shared = AppleHealthEnrichmentService()

    /// What Ascend can honestly tell a climber about their heart rate for one climb.
    ///
    /// Every case is something the UI says out loud. There is no case that renders as a blank
    /// - a silent absence was the original bug.
    enum Phase: Equatable {
        /// Not a climb Ascend recorded, or its heart rate is already attached.
        case notApplicable
        /// Health has never been connected. The climber is offered the connection here.
        case connectionOffered
        /// This device cannot read Apple Health at all.
        case unavailable
        /// Access was granted once and has since been turned off in the Health app.
        case accessRevoked
        /// A read is in flight right now.
        case checking
        /// Connected, nothing published yet, and another automatic attempt is coming.
        ///
        /// Deliberately carries no date. A rendered countdown would be a promise the schedule
        /// cannot keep: `Task.sleep` does not advance while the app is suspended, so the number
        /// would be wrong in exactly the case a climber checks it - after backgrounding.
        case waiting
        /// The automatic series is spent. Manual fetch is still offered.
        case stoppedLooking
        /// Enrichment is switched off at the backend. Nothing is being read, and nothing was
        /// spent - distinct from `stoppedLooking`, which says Ascend looked and found nothing.
        case checksPaused
    }

    /// What a hand-requested read actually did, so the surface asking can say something true.
    ///
    /// "Ascend looked and Health had nothing" and "Ascend never got to look" are different
    /// facts, and reporting the second as the first is the dishonest blank this service exists
    /// to remove.
    enum FetchResult: Equatable {
        /// Heart rate landed on the climb from this read.
        case added
        /// Ascend read Apple Health and nothing covered this climb.
        case foundNothing
        /// Ascend never read: the connection is missing, or enrichment is switched off.
        case couldNotLook
    }

    private let authorizationController: any HealthKitAuthorizationControlling
    private let metricsReader: any HealthKitMetricsReading
    private let attemptStore: AppleHealthEnrichmentAttemptStore
    private let sessionWorkGate: AuthenticatedBootstrapCoordinator
    private let featureFlags: RemoteFeatureFlagStore
    private let now: @MainActor () -> Date

    /// Climbs the timer is currently watching. Identity only - a `Workout` is a SwiftData
    /// object whose context this service does not own.
    private var trackedWorkoutIDs: Set<UUID> = []
    private var modelContext: ModelContext?
    private var timerTask: Task<Void, Never>?
    private var passTask: Task<Void, Never>?

    /// Climbs with a read in flight, so the UI can say "checking" rather than guess.
    private(set) var checkingWorkoutIDs: Set<UUID> = []

    /// The read each of those climbs is waiting on, so a second caller joins it.
    ///
    /// A scheduled pass suspends at the HealthKit read, which frees the main actor for a
    /// climber's "Check now" on the same climb. Two reads would spend two of the nine attempts
    /// on one answer, and whichever finished first would drop the climb out of `.checking`
    /// while the other was still running.
    private var readTasks: [UUID: Task<Bool, Never>] = [:]

    init(
        authorizationController: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        metricsReader: any HealthKitMetricsReading = HealthKitMetricsReader.shared,
        attemptStore: AppleHealthEnrichmentAttemptStore = AppleHealthEnrichmentAttemptStore(),
        sessionWorkGate: AuthenticatedBootstrapCoordinator = .shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.authorizationController = authorizationController
        self.metricsReader = metricsReader
        self.attemptStore = attemptStore
        self.sessionWorkGate = sessionWorkGate
        self.featureFlags = featureFlags
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

    /// Why the last connect or read could not proceed, for the Integrations card to show.
    ///
    /// Only ever set from a climber-initiated action. The automatic series stays silent: a
    /// background pass that found nothing is not an error worth putting on a screen.
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
    /// The Integrations card connects as a standing setup step rather than for one climb, so it
    /// cannot go through `connectAndFetch`. Refusals are reported through `lastErrorMessage`
    /// rather than swallowed, because this is a button a climber pressed.
    @discardableResult
    func requestAppleHealthAuthorizationIfNeeded() async -> Bool {
        // Every exit reports the state it resolved to, including the refusals: the backend's
        // view of a climber's Health connection is only as current as the last time the app
        // said something.
        defer { recordAppleHealthLifecycleState() }

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
    /// It reports its own outcome through `lastErrorMessage`, clearing it first: the card that
    /// presents that message has to be told about the check the climber just asked for, never
    /// about a refusal from an earlier one.
    func refreshPendingEnrichment(modelContext: ModelContext? = nil) async {
        lastErrorMessage = nil

        // Nothing at all while account work is suspended, not even a status read.
        guard sessionWorkGate.isSuspended == false else { return }

        // Refreshed here rather than only inside a pass, because a pass is skipped entirely when
        // no climb is currently due - and this is the entry point the Integrations card uses to
        // show the connection state, which must be current whether or not there was work to do.
        await authorizationController.refreshAuthorizationRequestStatus()

        lastErrorMessage = checkRefusalMessage

        guard let context = modelContext ?? self.modelContext else { return }

        resumeTracking(modelContext: context)
        await drainInFlightWork()

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

    private func recordAppleHealthLifecycleState() {
        LifecycleEventRecorder.shared.recordAppleHealthIntegration(
            state: authorizationController.connectionState
        )
    }

    /// Whether a wake-up is currently scheduled.
    ///
    /// Exposed so the bound can be asserted rather than assumed: a climb that can never match -
    /// disconnected, killed, out of budget, out of window - must leave nothing behind waking the
    /// app up to find that out again.
    var hasScheduledWakeUp: Bool { timerTask != nil }

    // MARK: - Phase

    /// Whether the backend still permits enrichment, read the cheap way.
    ///
    /// A plain in-memory flag lookup rather than `RemoteFeatureGate.allows`, because this is
    /// reachable from a view body: the gate records a diagnostic every time it blocks, so
    /// routing rendering through it would emit one per render for a whole incident. The gate
    /// stays on the work path, where a blocked pass is worth recording exactly once.
    private var isEnrichmentSwitchedOn: Bool {
        featureFlags.isEnabled(.appleHealthEnrichment)
    }

    /// What to tell the climber about this climb's heart rate right now.
    func phase(for workout: Workout) -> Phase {
        guard workout.isInAppSensorWorkout, needsHeartRate(workout) else { return .notApplicable }

        if checkingWorkoutIDs.contains(workout.id) { return .checking }

        // Said ahead of connection state, because with checks switched off neither connecting
        // nor re-granting access would produce a read - only a device that cannot reach Health
        // at all outranks it.
        if authorizationController.connectionState != .unavailable, !isEnrichmentSwitchedOn {
            return .checksPaused
        }

        switch authorizationController.connectionState {
        case .unavailable:
            return .unavailable
        case .neverConnected:
            return .connectionOffered
        case .revoked:
            return .accessRevoked
        case .connected:
            break
        }

        guard attemptStore.nextEligibleDate(for: workout, at: now()) != nil else {
            return .stoppedLooking
        }

        return .waiting
    }

    /// Whether this climb is one a Health connection would still pay off for.
    ///
    /// What the post-climb connect prompt asks. It is deliberately not conditioned on the
    /// retry ledger: a climber who has never connected has never had an attempt run, and the
    /// offer is the point.
    ///
    /// It is conditioned on the kill switch, though. Asking for Health access while enrichment
    /// is switched off spends a permission prompt - the one thing a climber can only be asked
    /// once - on a benefit the app has been told not to deliver.
    func offersConnectionPrompt(for workout: Workout) -> Bool {
        guard workout.isInAppSensorWorkout, needsHeartRate(workout) else { return false }
        guard isEnrichmentSwitchedOn else { return false }
        guard authorizationController.connectionState == .neverConnected else { return false }
        return schedule.isWithinEligibilityWindow(workout, at: now())
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
    func resumeTracking(modelContext: ModelContext) {
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
            return
        }

        runPass(modelContext: modelContext)
    }

    /// The climber asked for this one by hand.
    ///
    /// Ignores the retry ledger - a manual fetch is a person telling Ascend to look now, and
    /// refusing them because a timer has not elapsed would be the app arguing with its user.
    /// It still spends a ledger attempt so a series of manual fetches cannot outrun the budget
    /// and then leave the automatic curve claiming attempts it no longer has - unless a read for
    /// this climb is already in flight, in which case it joins that one and spends nothing.
    @discardableResult
    func fetchNow(_ workout: Workout, modelContext: ModelContext) async -> FetchResult {
        self.modelContext = modelContext

        guard workout.isInAppSensorWorkout, needsEnrichment(workout) else { return .couldNotLook }
        guard canRunEnrichment else { return .couldNotLook }

        let didEnrich = await enrich(workout, modelContext: modelContext)
        if !didEnrich {
            track(workout)
        }
        armTimer()

        return didEnrich ? .added : .foundNothing
    }

    /// Requests Health access and, if granted, looks immediately.
    ///
    /// The contextual prompt's action: a climber who connects right after a climb should see
    /// their heart rate arrive from that tap, not from a timer minutes later.
    @discardableResult
    func connectAndFetch(_ workout: Workout, modelContext: ModelContext) async -> FetchResult {
        self.modelContext = modelContext

        await authorizationController.refreshAuthorizationRequestStatus()

        if authorizationController.connectionState == .neverConnected {
            guard await authorizationController.requestAuthorization() else { return .couldNotLook }
        }

        guard authorizationController.connectionState == .connected else { return .couldNotLook }

        return await fetchNow(workout, modelContext: modelContext)
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
        checkingWorkoutIDs = []

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
    /// A hand-requested read belongs to no pass, so the reads are awaited on their own after
    /// the pass rather than assumed to have ended with it.
    func drainInFlightWork() async {
        await passTask?.value

        for task in readTasks.values {
            await task.value
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
    /// surfaces call this in quick succession - a foreground, a summary and a workout detail can
    /// all land together - and restarting would throw away a read that had already completed,
    /// having already spent the attempt that paid for it. The in-flight pass re-arms from the
    /// current tracking set when it ends, so nothing added meanwhile is missed.
    private func runPass(modelContext: ModelContext) {
        guard passTask == nil else { return }

        passTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.passTask = nil }

            await self.enrichDueWorkouts(modelContext: modelContext)
            self.armTimer()
        }
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
    private func enrichDueWorkouts(modelContext: ModelContext) async {
        // Nothing at all while account work is suspended - not even a status read, which would
        // touch the account being deleted.
        guard sessionWorkGate.isSuspended == false else { return }

        // Authorization can change while Ascend is not running: a climber grants or revokes
        // Health in Settings, and nothing tells the app. Re-reading it at the top of a pass is
        // what lets a grant made overnight take effect on the next foreground instead of leaving
        // the series refusing to look at data it now has access to.
        await authorizationController.refreshAuthorizationRequestStatus()

        guard canRunEnrichment else { return }

        for workout in trackedWorkouts(in: modelContext) {
            if Task.isCancelled { return }
            guard attemptStore.isAutomaticAttemptDue(for: workout, at: now()) else { continue }

            await enrich(workout, modelContext: modelContext)
        }
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
    /// the answer honest: the climber who tapped "Check now" while a scheduled pass was mid-read
    /// is told what that read found, not that Ascend could not look.
    @discardableResult
    private func enrich(_ workout: Workout, modelContext: ModelContext) async -> Bool {
        let workoutID = workout.id

        if let inFlight = readTasks[workoutID] {
            return await inFlight.value
        }

        checkingWorkoutIDs.insert(workoutID)
        attemptStore.recordAttempt(for: workout, at: now())

        let read = Task { @MainActor [weak self] in
            guard let self else { return false }
            defer {
                self.readTasks[workoutID] = nil
                self.checkingWorkoutIDs.remove(workoutID)
            }

            return await self.performRead(of: workout, modelContext: modelContext)
        }

        readTasks[workoutID] = read
        return await read.value
    }

    private func performRead(of workout: Workout, modelContext: ModelContext) async -> Bool {
        let workoutID = workout.id
        let window = AppleHealthEnrichmentSchedule.endDate(of: workout)
        let metrics = await metricsReader.fetchMetrics(during: workout.date...window)

        guard !Task.isCancelled else { return false }

        let wantedHeartRate = needsHeartRate(workout)
        let before = LeaderboardWorkoutSnapshot(workout: workout)
        guard apply(metrics, to: workout) else { return false }

        do {
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: WorkoutMutation(updated: [
                    .init(before: before, after: LeaderboardWorkoutSnapshot(workout: workout))
                ]),
                changedWorkouts: [workout]
            )
        } catch {
            return false
        }

        let didAddHeartRate = wantedHeartRate && !needsHeartRate(workout)

        // Calories can land in a pass that brought no heart rate. Retiring the climb on that
        // partial answer is how the series would stop one attempt short of the thing the
        // climber was actually waiting for.
        if !needsEnrichment(workout) {
            attemptStore.clear(workoutID: workoutID)
            trackedWorkoutIDs.remove(workoutID)
        }

        return didAddHeartRate
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
