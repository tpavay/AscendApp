//
//  AppleHealthEnrichmentCoordinator.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import SwiftData
import Observation

/// Remembers when each climb was last asked about, so a pass that finds nothing does not ask
/// again a second later, and a climb old enough that Health will never write for it stops being
/// asked at all.
final class AppleHealthEnrichmentRetryStore {
    private let defaults: UserDefaults
    private let key: String
    private let minimumRetryInterval: TimeInterval
    private let retryWindow: TimeInterval
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        key: String = "appleHealth.enrichmentRetry.lastAttemptByWorkoutID",
        minimumRetryInterval: TimeInterval = 60,
        retryWindow: TimeInterval = 72 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.minimumRetryInterval = minimumRetryInterval
        self.retryWindow = retryWindow
        self.now = now
    }

    func isRetryDue(for workout: Workout) -> Bool {
        let currentDate = now()
        guard isWithinRetryWindow(for: workout, now: currentDate) else {
            clear(workoutID: workout.id)
            return false
        }

        let attempts = lastAttemptTimestamps()
        guard let lastAttempt = attempts[workout.id.uuidString] else {
            return true
        }

        return currentDate.timeIntervalSince1970 - lastAttempt >= minimumRetryInterval
    }

    func recordAttempt(for workouts: [Workout]) {
        let currentDate = now()
        var attempts = prunedLastAttemptTimestamps(now: currentDate)

        for workout in workouts where isWithinRetryWindow(for: workout, now: currentDate) {
            attempts[workout.id.uuidString] = currentDate.timeIntervalSince1970
        }

        defaults.set(attempts, forKey: key)
    }

    func clear(workoutID: UUID) {
        var attempts = lastAttemptTimestamps()
        attempts.removeValue(forKey: workoutID.uuidString)
        defaults.set(attempts, forKey: key)
    }

    func isWithinRetryWindow(for workout: Workout) -> Bool {
        isWithinRetryWindow(for: workout, now: now())
    }

    private func isWithinRetryWindow(for workout: Workout, now currentDate: Date) -> Bool {
        let endedAt = workout.date.addingTimeInterval(max(workout.duration, 1))
        let secondsSinceEnd = currentDate.timeIntervalSince(endedAt)
        return secondsSinceEnd >= -60 && secondsSinceEnd <= retryWindow
    }

    private func lastAttemptTimestamps() -> [String: TimeInterval] {
        (defaults.dictionary(forKey: key) ?? [:]).compactMapValues { value in
            value as? TimeInterval
        }
    }

    private func prunedLastAttemptTimestamps(now currentDate: Date) -> [String: TimeInterval] {
        lastAttemptTimestamps().filter { _, timestamp in
            currentDate.timeIntervalSince1970 - timestamp <= retryWindow * 2
        }
    }
}

/// Attaches Apple Health's heart rate and active energy to climbs Ascend recorded itself.
///
/// Enrichment reads quantity samples over a climb's own time window and never looks at anyone
/// else's `HKWorkout`: Ascend does not import workouts, so a foreign workout record is not a thing
/// this app has an opinion about. That also keeps the integration device-agnostic - Garmin, Whoop,
/// Polar and Apple Watch all write `heartRate` samples, and HealthKit normalises them.
@MainActor
@Observable
final class AppleHealthEnrichmentCoordinator: AuthenticatedSessionWorker {
    static let shared = AppleHealthEnrichmentCoordinator()

    enum AppleHealthEnrichmentStatus: Equatable {
        case notPending
        case metricsPending
        case metricsStalled
        case complete
    }

    /// Why a pass ran, which is the only thing that decides whether it may be skipped outright.
    ///
    /// `.automatic` is a surface re-entering on its own - Home mounting, a tab return, a
    /// foreground. `.userInitiated` is a climber who just did something about Apple Health and is
    /// waiting to see the result, and is never throttled.
    enum EnrichmentTrigger {
        case userInitiated
        case automatic
    }

    /// Automatic sweeps inside this window cannot find anything the last one did not: the retry
    /// store already refuses a second read of the same climb within a minute, so the fetch and its
    /// per-climb heart-rate decode would be pure cost.
    private static let automaticPassMinimumInterval: TimeInterval = 30

    var lastErrorMessage: String?

    private let authorizationController: any HealthKitAuthorizationControlling
    private let metricsReader: any HealthKitMetricsReading
    private let leaderboardService = LeaderboardService.shared
    private let enrichmentRetryStore: AppleHealthEnrichmentRetryStore
    private let sessionWorkGate: AuthenticatedBootstrapCoordinator

    private var modelContext: ModelContext?
    private var lastAutomaticPassAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var refreshJoinContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var joinsInFlight: Set<UUID> = []
    private var joinsEndedBeforeParking: Set<UUID> = []

    init(
        authorizationController: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        metricsReader: any HealthKitMetricsReading = HealthKitMetricsReader.shared,
        enrichmentRetryStore: AppleHealthEnrichmentRetryStore = AppleHealthEnrichmentRetryStore(),
        sessionWorkGate: AuthenticatedBootstrapCoordinator = .shared
    ) {
        self.authorizationController = authorizationController
        self.metricsReader = metricsReader
        self.enrichmentRetryStore = enrichmentRetryStore
        self.sessionWorkGate = sessionWorkGate
    }

    var appleHealthConnectionState: AppleHealthConnectionState {
        authorizationController.connectionState
    }

    /// Attaches the store. Called from `HomeView.task`, so everything it does synchronously runs
    /// before Home can render - it must stay bounded no matter how much history the climber has
    /// (ASCEND-IOS-1K).
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        leaderboardService.configure(modelContext: modelContext)
    }

    func requestAppleHealthAuthorizationIfNeeded() async -> Bool {
        await authorizationController.refreshAuthorizationRequestStatus()

        guard authorizationController.isHealthDataAvailable else {
            lastErrorMessage = "Apple Health is not available on this device."
            recordAppleHealthLifecycleState()
            return false
        }

        if authorizationController.connectionState == .revoked {
            lastErrorMessage = "Apple Health permissions were previously revoked. Re-enable them in the Health app."
            recordAppleHealthLifecycleState()
            return false
        }

        if authorizationController.hasRequestedAuthorization {
            lastErrorMessage = nil
            recordAppleHealthLifecycleState()
            return true
        }

        let granted = await authorizationController.requestAuthorization()
        guard granted else {
            lastErrorMessage = authorizationController.lastPermissionErrorMessage
            recordAppleHealthLifecycleState()
            return false
        }

        await refreshPendingEnrichment()
        recordAppleHealthLifecycleState()
        return lastErrorMessage == nil
    }

    /// Coalesces concurrent passes onto one task, and cancels that task when the caller that
    /// *started* it is cancelled.
    ///
    /// The pass is unstructured so that several surfaces can share one run, which also means it
    /// does not inherit cancellation for free. Only the owner may cancel: a caller that merely
    /// joins someone else's in-flight pass stops waiting when it is cancelled, without stopping
    /// the pass the other surface is still watching.
    ///
    /// Refuses to start while account-scoped work is suspended, so a pass started a millisecond
    /// after account deletion began cannot write into the store deletion is emptying.
    ///
    /// The throttle is decided here rather than inside the pass, so a refused automatic sweep
    /// leaves no task behind. Otherwise a climber who taps "Check for heart rate now" a moment
    /// after a foreground could coalesce onto a pass that was already refused, and get silence.
    func refreshPendingEnrichment(trigger: EnrichmentTrigger = .userInitiated) async {
        guard sessionWorkGate.isSuspended == false else { return }

        if refreshTask != nil {
            await joinInFlightRefresh()
            return
        }

        guard claimPass(for: trigger) else { return }

        let refreshTask = Task { @MainActor [weak self] in
            await self?.performRefreshPendingEnrichment()
            self?.refreshTask = nil
            self?.resumeAllJoiners()
        }
        self.refreshTask = refreshTask

        await awaitOwnedRefresh(refreshTask)
    }

    /// Stops any in-flight enrichment. The store is left consistent - each pass saves once - and
    /// the next pass picks up whatever is still outstanding.
    func cancelInFlightWork() {
        refreshTask?.cancel()
    }

    func drainInFlightWork() async {
        await refreshTask?.value
    }

    @discardableResult
    func enrichInAppWorkoutWithAppleHealthIfPossible(
        _ workout: Workout,
        modelContext: ModelContext,
        force: Bool = false
    ) async -> Bool {
        guard workout.isInAppSensorWorkout,
              needsAppleHealthEnrichment(workout) else {
            return false
        }

        await authorizationController.refreshAuthorizationRequestStatus()

        do {
            let enrichedWorkouts = try await enrich(
                [workout],
                modelContext: modelContext,
                force: force
            )
            return enrichedWorkouts.contains { $0.id == workout.id }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func appleHealthEnrichmentStatus(for workout: Workout) -> AppleHealthEnrichmentStatus {
        guard workout.isInAppSensorWorkout else { return .notPending }
        guard needsAppleHealthEnrichment(workout) else { return .complete }

        return enrichmentRetryStore.isWithinRetryWindow(for: workout) ? .metricsPending : .metricsStalled
    }

    func appleHealthHeartRateEnrichmentStatus(for workout: Workout) -> AppleHealthEnrichmentStatus {
        guard needsAppleHealthHeartRateEnrichment(workout) else { return .complete }

        return appleHealthEnrichmentStatus(for: workout)
    }

    private func performRefreshPendingEnrichment() async {
        guard let modelContext else { return }

        do {
            await authorizationController.refreshAuthorizationRequestStatus()

            // This comes before the fetch on purpose. The fetch reads every in-app climb and
            // decodes each one's heart-rate series to decide what is still outstanding, so a
            // climber who never connected Apple Health must not pay for it.
            if authorizationController.connectionState == .connected {
                try Task.checkCancellation()
                let pending = try InAppSensorWorkoutQuery
                    .allInAppSensorWorkouts(in: modelContext)
                    .filter(needsAppleHealthEnrichment)

                try Task.checkCancellation()
                _ = try await enrich(pending, modelContext: modelContext, force: false)
            }

            lastErrorMessage = nil
        } catch is CancellationError {
            // The surface that asked for this pass went away. Whatever was written is saved; the
            // next entry resumes from there.
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        recordAppleHealthLifecycleState()
    }

    /// Reads Apple Health over each climb's own window and writes back whatever is still missing.
    @discardableResult
    private func enrich(
        _ workouts: [Workout],
        modelContext: ModelContext,
        force: Bool
    ) async throws -> [Workout] {
        guard authorizationController.connectionState == .connected else { return [] }

        let candidates = workouts.filter { workout in
            guard workout.isInAppSensorWorkout, needsAppleHealthEnrichment(workout) else {
                return false
            }

            return force || enrichmentRetryStore.isRetryDue(for: workout)
        }
        guard !candidates.isEmpty else { return [] }

        enrichmentRetryStore.recordAttempt(for: candidates)

        var updatedWorkouts: [Workout] = []
        var updates: [WorkoutMutation.Update] = []

        for workout in candidates {
            try Task.checkCancellation()

            let metricWindow = workout.date...workout.date.addingTimeInterval(max(workout.duration, 1))
            let metrics = await metricsReader.fetchMetrics(during: metricWindow)
            let before = LeaderboardWorkoutSnapshot(workout: workout)

            guard applyAppleHealthEnrichmentMetrics(metrics, to: workout) else { continue }

            updatedWorkouts.append(workout)
            updates.append(.init(before: before, after: LeaderboardWorkoutSnapshot(workout: workout)))
            enrichmentRetryStore.clear(workoutID: workout.id)
        }

        guard !updatedWorkouts.isEmpty else { return [] }

        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: WorkoutMutation(updated: updates),
            changedWorkouts: updatedWorkouts
        )

        return updatedWorkouts
    }

    private func claimPass(for trigger: EnrichmentTrigger) -> Bool {
        guard trigger == .automatic else { return true }

        let now = Date()
        if let lastAutomaticPassAt,
           now.timeIntervalSince(lastAutomaticPassAt) < Self.automaticPassMinimumInterval {
            return false
        }

        lastAutomaticPassAt = now
        return true
    }

    private func needsAppleHealthEnrichment(_ workout: Workout) -> Bool {
        needsAppleHealthHeartRateEnrichment(workout) || workout.caloriesBurned == nil
    }

    private func needsAppleHealthHeartRateEnrichment(_ workout: Workout) -> Bool {
        workout.avgHeartRate == nil ||
            workout.maxHeartRate == nil ||
            workout.heartRateTimeSeries.isEmpty
    }

    @discardableResult
    private func applyAppleHealthEnrichmentMetrics(
        _ metrics: WorkoutMetrics,
        to workout: Workout
    ) -> Bool {
        var didChange = false

        // A workout that already carries a live-captured heart-rate series (Bluetooth chest strap
        // during the session) keeps it: strap data is first-party and more accurate than
        // wrist-derived Apple Health HR. Enrichment still fills calories below.
        let hasLiveCapturedHeartRate = !workout.heartRateTimeSeries.isEmpty

        if !hasLiveCapturedHeartRate {
            if let avgHeartRate = metrics.avgHeartRate, workout.avgHeartRate != avgHeartRate {
                workout.avgHeartRate = avgHeartRate
                didChange = true
            }
            if let maxHeartRate = metrics.maxHeartRate, workout.maxHeartRate != maxHeartRate {
                workout.maxHeartRate = maxHeartRate
                didChange = true
            }
            if !metrics.heartRateTimeSeries.isEmpty {
                let encodedHeartRateData = metrics.heartRateTimeSeries.encoded
                if workout.heartRateData != encodedHeartRateData {
                    workout.heartRateData = encodedHeartRateData
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

    private func recordAppleHealthLifecycleState() {
        LifecycleEventRecorder.shared.recordAppleHealthIntegration(
            state: authorizationController.connectionState
        )
    }

    private func awaitOwnedRefresh(_ task: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Waits for the in-flight pass without owning it.
    ///
    /// Deliberately not `await task.value`: a `Task<Void, Never>` is not interruptible by the
    /// awaiting task's own cancellation, so a joiner that awaited it directly would stay suspended
    /// for the rest of someone else's pass. Parking on a continuation instead lets the joiner be
    /// resumed by whichever comes first - the pass finishing, or its own cancellation - while
    /// leaving the shared task untouched either way.
    private func joinInFlightRefresh() async {
        let joinID = UUID()
        joinsInFlight.insert(joinID)
        defer {
            joinsInFlight.remove(joinID)
            joinsEndedBeforeParking.remove(joinID)
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // `joinsEndedBeforeParking` closes the window where cancellation arrives after
                // the handler is installed but before the continuation exists. Without it that
                // ordering parks a joiner nothing will ever resume.
                guard refreshTask != nil,
                      joinsEndedBeforeParking.remove(joinID) == nil else {
                    continuation.resume()
                    return
                }

                refreshJoinContinuations[joinID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.endJoin(joinID)
            }
        }
    }

    private func endJoin(_ joinID: UUID) {
        if let continuation = refreshJoinContinuations.removeValue(forKey: joinID) {
            continuation.resume()
        } else if joinsInFlight.contains(joinID) {
            joinsEndedBeforeParking.insert(joinID)
        }
    }

    private func resumeAllJoiners() {
        let continuations = refreshJoinContinuations.values
        refreshJoinContinuations.removeAll()

        for continuation in continuations {
            continuation.resume()
        }
    }
}
