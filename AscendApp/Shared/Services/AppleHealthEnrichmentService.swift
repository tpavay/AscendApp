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
        case waiting(nextCheckAt: Date?)
        /// The automatic series is spent. Manual fetch is still offered.
        case stoppedLooking
    }

    private let authorizationController: any HealthKitAuthorizationControlling
    private let metricsReader: any HealthKitMetricsReading
    private let attemptStore: AppleHealthEnrichmentAttemptStore
    private let schedule: AppleHealthEnrichmentSchedule
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

    /// The climb whose heart rate landed most recently, so a surface showing it can confirm
    /// the arrival instead of silently swapping a card for a chart.
    private(set) var lastEnrichedWorkoutID: UUID?

    init(
        authorizationController: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        metricsReader: any HealthKitMetricsReading = HealthKitMetricsReader.shared,
        attemptStore: AppleHealthEnrichmentAttemptStore = AppleHealthEnrichmentAttemptStore(),
        schedule: AppleHealthEnrichmentSchedule = .standard,
        sessionWorkGate: AuthenticatedBootstrapCoordinator = .shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.authorizationController = authorizationController
        self.metricsReader = metricsReader
        self.attemptStore = attemptStore
        self.schedule = schedule
        self.sessionWorkGate = sessionWorkGate
        self.featureFlags = featureFlags
        self.now = now
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var connectionState: AppleHealthConnectionState {
        authorizationController.connectionState
    }

    /// Whether a wake-up is currently scheduled.
    ///
    /// Exposed so the bound can be asserted rather than assumed: a climb that can never match -
    /// disconnected, killed, out of budget, out of window - must leave nothing behind waking the
    /// app up to find that out again.
    var hasScheduledWakeUp: Bool { timerTask != nil }

    // MARK: - Phase

    /// What to tell the climber about this climb's heart rate right now.
    func phase(for workout: Workout) -> Phase {
        guard workout.isInAppSensorWorkout, needsHeartRate(workout) else { return .notApplicable }

        if checkingWorkoutIDs.contains(workout.id) { return .checking }

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

        guard let nextCheckAt = attemptStore.nextEligibleDate(for: workout, at: now()) else {
            return .stoppedLooking
        }

        return .waiting(nextCheckAt: nextCheckAt)
    }

    /// Whether this climb is one a Health connection would still pay off for.
    ///
    /// What the post-climb connect prompt asks. It is deliberately not conditioned on the
    /// retry ledger: a climber who has never connected has never had an attempt run, and the
    /// offer is the point.
    func offersConnectionPrompt(for workout: Workout) -> Bool {
        guard workout.isInAppSensorWorkout, needsHeartRate(workout) else { return false }
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
    /// and then leave the automatic curve claiming attempts it no longer has.
    @discardableResult
    func fetchNow(_ workout: Workout, modelContext: ModelContext) async -> Bool {
        self.modelContext = modelContext

        guard workout.isInAppSensorWorkout, needsEnrichment(workout) else { return false }
        guard authorizationController.connectionState == .connected else { return false }

        guard canRunEnrichment else { return false }

        let didEnrich = await enrich(workout, modelContext: modelContext)
        if !didEnrich {
            track(workout)
        }
        armTimer(modelContext: modelContext)

        return didEnrich
    }

    /// Requests Health access and, if granted, looks immediately.
    ///
    /// The contextual prompt's action: a climber who connects right after a climb should see
    /// their heart rate arrive from that tap, not from a timer minutes later.
    @discardableResult
    func connectAndFetch(_ workout: Workout, modelContext: ModelContext) async -> Bool {
        self.modelContext = modelContext

        await authorizationController.refreshAuthorizationRequestStatus()

        if authorizationController.connectionState == .neverConnected {
            guard await authorizationController.requestAuthorization() else { return false }
        }

        guard authorizationController.connectionState == .connected else { return false }

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
        trackedWorkoutIDs = []
        checkingWorkoutIDs = []
        modelContext = nil
    }

    /// Waits for the reads, not for the wait between them.
    ///
    /// Deliberately does not await `timerTask`: a timer that is asleep holds no account state
    /// and its sleep can be hours long, so awaiting it would park account deletion's bounded
    /// drain until it timed out. `cancelInFlightWork` runs first under this protocol and stops
    /// the timer, so nothing it would have started can still run.
    func drainInFlightWork() async {
        await passTask?.value
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
    /// The single choke point the kill switch and the Health connection are both read through,
    /// and it is checked *before* a pass rather than inside one. A pass that cannot read still
    /// leaves every tracked climb due, so re-arming off the back of one would schedule the next
    /// wake-up one second out and keep doing it - a spin, dressed as a schedule. Blocked work is
    /// deferred to the next lifecycle event instead: `resumeTracking` runs on foreground and on
    /// authenticated bootstrap, and connecting Health fetches directly.
    ///
    /// Nothing about the retry ledger is touched either way, so a climb resumes its own series
    /// exactly where it left off.
    private var canRunEnrichment: Bool {
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
            self.armTimer(modelContext: modelContext)
        }
    }

    private func armTimer(modelContext: ModelContext) {
        timerTask?.cancel()
        timerTask = nil

        guard canRunEnrichment, let wakeAt = earliestPendingAttemptDate() else { return }

        let delay = max(wakeAt.timeIntervalSince(now()), 1)
        timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.runPass(modelContext: modelContext)
        }
    }

    private func earliestPendingAttemptDate() -> Date? {
        guard let modelContext else { return nil }

        return trackedWorkouts(in: modelContext)
            .compactMap { attemptStore.nextEligibleDate(for: $0, at: now()) }
            .min()
    }

    private func enrichDueWorkouts(modelContext: ModelContext) async {
        guard canRunEnrichment else { return }

        for workout in trackedWorkouts(in: modelContext) {
            if Task.isCancelled { return }
            guard sessionWorkGate.isSuspended == false else { return }
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

    @discardableResult
    private func enrich(_ workout: Workout, modelContext: ModelContext) async -> Bool {
        let workoutID = workout.id
        checkingWorkoutIDs.insert(workoutID)
        attemptStore.recordAttempt(for: workout, at: now())
        defer { checkingWorkoutIDs.remove(workoutID) }

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
        if didAddHeartRate {
            lastEnrichedWorkoutID = workoutID
        }

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
