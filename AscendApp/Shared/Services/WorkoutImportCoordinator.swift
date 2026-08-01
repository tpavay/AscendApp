//
//  WorkoutImportCoordinator.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import HealthKit
import SwiftData
import Observation

enum ImportRefreshTrigger {
    case automatic
    case backgroundObserver
    case homeEntry
    case manualReview
    case manualSync
}

struct ImportBatchResult {
    let importedWorkouts: [Workout]
    let updatedWorkouts: [Workout]
    let failedCandidateIDs: [String]

    var successCount: Int { importedWorkouts.count }
    var updatedCount: Int { updatedWorkouts.count }
    var failedCount: Int { failedCandidateIDs.count }
}

private struct AppleHealthWorkoutEnrichmentCandidatePair {
    let policy: AppleHealthWorkoutEnrichmentPolicy
    let workout: Workout
    let sample: HealthKitWorkoutSample
    let score: Double
}

private struct AppleHealthWorkoutEnrichmentMatch {
    let policy: AppleHealthWorkoutEnrichmentPolicy
    let workout: Workout
    let sample: HealthKitWorkoutSample
}

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

@MainActor
@Observable
final class WorkoutImportCoordinator {
    static let shared = WorkoutImportCoordinator()

    enum ImportInboxResolution {
        case showImportSheet
    }

    enum ImportOutcome {
        case imported(Workout)
        case updatedExisting(Workout)
        case skipped(candidateID: String)
        case failed(candidateID: String)
    }

    enum AppleHealthEnrichmentStatus: Equatable {
        case notPending
        case linkPending
        case metricsPending
        case metricsStalled
        case complete
    }

    var pendingCandidates: [ImportedWorkoutCandidate] = []
    var isChecking = false
    var isImporting = false
    var currentImportingCandidateID: String?
    var lastCheckAt: Date?
    var lastErrorMessage: String?

    private let authorizationController: any HealthKitAuthorizationControlling
    private let workoutReader: any HealthKitWorkoutReading
    private let metricsReader: any HealthKitMetricsReading
    private let telemetry: TelemetryManager
    private let leaderboardService = LeaderboardService.shared
    private let settingsManager: SettingsManager
    private let reviewStateStore: WorkoutAutoImportReviewStateStore
    private let ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore
    private let enrichmentRetryStore: AppleHealthEnrichmentRetryStore

    private var modelContext: ModelContext?
    private var lastAutomaticCheckAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshTrigger: ImportRefreshTrigger?
    private var legacySourceLinkBackfillTask: Task<Void, Never>?
    var currentAutoImportedReviewWorkoutID: UUID?

    /// How many Apple Health workouts the current import pass has left to bring in.
    ///
    /// Drives Home's "still importing" affordance: the screen is usable throughout, and this is
    /// what tells the user history is still arriving rather than missing.
    private(set) var remainingImportCount = 0
    private(set) var totalImportCount = 0

    init(
        authorizationController: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        workoutReader: any HealthKitWorkoutReading = HealthKitWorkoutReader.shared,
        metricsReader: any HealthKitMetricsReading = HealthKitMetricsReader.shared,
        telemetry: TelemetryManager = .shared,
        settingsManager: SettingsManager = .shared,
        reviewStateStore: WorkoutAutoImportReviewStateStore = WorkoutAutoImportReviewStateStore(),
        ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore = IgnoredAppleHealthWorkoutStore(),
        enrichmentRetryStore: AppleHealthEnrichmentRetryStore = AppleHealthEnrichmentRetryStore()
    ) {
        self.authorizationController = authorizationController
        self.workoutReader = workoutReader
        self.metricsReader = metricsReader
        self.telemetry = telemetry
        self.settingsManager = settingsManager
        self.reviewStateStore = reviewStateStore
        self.ignoredAppleHealthWorkoutStore = ignoredAppleHealthWorkoutStore
        self.enrichmentRetryStore = enrichmentRetryStore
        self.lastCheckAt = HealthKitSyncState.lastSuccessfulCheckAt
    }

    var pendingCount: Int {
        pendingCandidates.count
    }

    var pendingAutoImportedReviewCount: Int {
        reviewStateStore.hasUnseenWorkout() ? 1 : 0
    }

    var attentionCount: Int {
        pendingCount + pendingAutoImportedReviewCount
    }

    var appleHealthPendingCount: Int {
        pendingCandidates.filter { $0.sourceProviders.contains(.appleHealth) }.count
    }

    var appleHealthAttentionCount: Int {
        appleHealthPendingCount + pendingAutoImportedReviewCount
    }

    var appleHealthConnectionState: AppleHealthConnectionState {
        authorizationController.connectionState
    }

    var isAppleHealthAvailable: Bool {
        authorizationController.isHealthDataAvailable
    }

    var hasCompletedInitialBackfill: Bool {
        authorizationController.hasCompletedInitialBackfill
    }

    var hasRequestedAppleHealthAuthorization: Bool {
        authorizationController.hasRequestedAuthorization
    }

    var appleHealthAuthorizationRequestStatus: HKAuthorizationRequestStatus {
        authorizationController.authorizationRequestStatus
    }

    /// Attaches the store. Called from `HomeView.task`, so everything it does synchronously runs
    /// before Home can render - it must stay bounded no matter how much history the user has.
    ///
    /// The legacy source-link backfill is unbounded by nature, so it is handed to a cancellable
    /// batched task rather than run inline; the review-state prune is bounded to the one or two
    /// IDs it inspects. Running both inline is what produced ASCEND-IOS-1K.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        leaderboardService.configure(modelContext: modelContext)

        do {
            try pruneAutoImportedReviewState(modelContext: modelContext)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        startLegacySourceLinkBackfillIfNeeded(modelContext: modelContext)

        Task {
            await syncAppleHealthAutomationServices()
        }
    }

    /// Runs the legacy source-link backfill once, in the background, at most one task at a time.
    private func startLegacySourceLinkBackfillIfNeeded(modelContext: ModelContext) {
        guard legacySourceLinkBackfillTask == nil,
              !WorkoutSourceMigrationService.hasCompletedBackfill else {
            return
        }

        legacySourceLinkBackfillTask = Task { @MainActor [weak self] in
            defer { self?.legacySourceLinkBackfillTask = nil }

            do {
                try await WorkoutSourceMigrationService.runIfNeeded(modelContext: modelContext)
            } catch is CancellationError {
                // The owner went away mid-sweep; the next `configure` resumes it.
            } catch {
                self?.lastErrorMessage = error.localizedDescription
            }
        }
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

        if authorizationController.hasRequestedAuthorization, authorizationController.hasCompletedInitialBackfill {
            lastErrorMessage = nil
            recordAppleHealthLifecycleState()
            return true
        }

        let granted = await authorizationController.requestAuthorization()
        if !granted {
            lastErrorMessage = authorizationController.lastPermissionErrorMessage
            recordAppleHealthLifecycleState()
            return false
        }

        await refreshPendingImports(trigger: .manualSync)
        await syncAppleHealthAutomationServices()
        return lastErrorMessage == nil
    }

    /// Coalesces concurrent refreshes onto one task, and cancels that task when the caller that
    /// *started* it is cancelled.
    ///
    /// The refresh is unstructured so that several surfaces can share one pass, which also means
    /// it does not inherit cancellation for free. Without the handler below, walking away from
    /// Home mid-backfill left the import running against a screen nobody was looking at.
    ///
    /// Only the owner may cancel. A caller that merely joins someone else's in-flight pass stops
    /// caring about the result when it is cancelled, but the surface that asked for the pass is
    /// still watching it: dismissing the import sheet must not stop the backfill Home started.
    func refreshPendingImports(trigger: ImportRefreshTrigger) async {
        if let refreshTask {
            let activeRefreshTrigger = activeRefreshTrigger
            await refreshTask.value

            if Task.isCancelled { return }

            if activeRefreshTrigger?.covers(trigger) == false {
                await refreshPendingImports(trigger: trigger)
            }

            return
        }

        let refreshTask = Task { @MainActor [weak self] in
            await self?.performRefreshPendingImports(trigger: trigger)
            self?.refreshTask = nil
            self?.activeRefreshTrigger = nil
        }
        self.refreshTask = refreshTask
        activeRefreshTrigger = trigger

        await awaitOwnedRefresh(refreshTask)
    }

    private func awaitOwnedRefresh(_ task: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Stops any in-flight import work. The store is left consistent - each imported workout is
    /// saved on its own - and the next refresh picks up whatever is still outstanding.
    func cancelInFlightWork() {
        refreshTask?.cancel()
        legacySourceLinkBackfillTask?.cancel()
    }

    private func performRefreshPendingImports(trigger: ImportRefreshTrigger) async {
        guard let modelContext else { return }

        if trigger == .automatic,
           let lastAutomaticCheckAt,
           Date().timeIntervalSince(lastAutomaticCheckAt) < 30 {
            return
        }

        if trigger == .automatic {
            lastAutomaticCheckAt = Date()
        }

        isChecking = true
        defer { isChecking = false }

        do {
            startLegacySourceLinkBackfillIfNeeded(modelContext: modelContext)
            await authorizationController.refreshAuthorizationRequestStatus()
            let previousSuccessfulCheckAt = HealthKitSyncState.lastSuccessfulCheckAt ?? lastCheckAt
            _ = await performAppleHealthRefreshIfNeeded(trigger: trigger)

            try Task.checkCancellation()
            _ = try await enrichInAppWorkoutsWithAppleHealthIfPossible(modelContext: modelContext)

            try Task.checkCancellation()
            pendingCandidates = try buildPendingCandidates(modelContext: modelContext)
            try pruneAutoImportedReviewState(modelContext: modelContext)

            try Task.checkCancellation()
            await autoImportEligibleAppleHealthCandidatesIfNeeded(
                modelContext: modelContext,
                missingActivationFallback: previousSuccessfulCheckAt
            )
            lastCheckAt = Date()
            lastErrorMessage = nil
        } catch is CancellationError {
            // The surface that asked for this refresh went away. Whatever imported already is
            // saved; the next entry resumes from there.
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        await syncAppleHealthAutomationServices()
    }

    func prepareImportInbox() async -> ImportInboxResolution {
        await refreshPendingImports(trigger: .manualReview)
        return .showImportSheet
    }

    func importCandidate(_ candidate: ImportedWorkoutCandidate) async -> ImportOutcome {
        guard let modelContext else {
            return .failed(candidateID: candidate.id)
        }

        telemetry.track(
            WorkoutImportAnalyticsEvent.started(
                mode: .single,
                candidates: [candidate]
            )
        )

        isImporting = true
        currentImportingCandidateID = candidate.id
        defer {
            isImporting = false
            currentImportingCandidateID = nil
        }

        let outcome = await importCandidateInternal(candidate, modelContext: modelContext)

        switch outcome {
        case .imported(let workout):
            pendingCandidates.removeAll { $0.id == candidate.id }
            do {
                try recalculateDerivedData(modelContext: modelContext, newWorkouts: [workout])
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        case .updatedExisting:
            pendingCandidates.removeAll { $0.id == candidate.id }
            do {
                try recalculateDerivedData(modelContext: modelContext)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        case .skipped(let candidateID):
            pendingCandidates.removeAll { $0.id == candidateID }
        case .failed:
            break
        }

        telemetry.track(
            WorkoutImportAnalyticsEvent.finished(
                mode: .single,
                candidate: candidate,
                outcome: outcome
            )
        )

        return outcome
    }

    func importCandidates(ids: Set<String>) async -> ImportBatchResult {
        let candidates = pendingCandidates.filter { ids.contains($0.id) }
        return await importCandidatesInternal(
            candidates: candidates,
            mode: .selected
        )
    }

    func importAllCandidates() async -> ImportBatchResult {
        await importCandidatesInternal(
            candidates: pendingCandidates,
            mode: .all
        )
    }

    func isImported(_ candidate: ImportedWorkoutCandidate) -> Bool {
        guard let modelContext,
              let appleHealthSample = candidate.appleHealthSample else {
            return false
        }

        let existingWorkout = try? AppleHealthLinkQuery.workout(
            forExternalRecordID: appleHealthSample.externalRecordID,
            in: modelContext
        )
        return existingWorkout != nil
    }

    func resetAutomaticCheckThrottle() {
        lastAutomaticCheckAt = nil
    }

    @discardableResult
    func presentPendingAutoImportedReviewOnHomeIfNeeded() -> Bool {
        guard let nextWorkoutID = reviewStateStore.latestUnseenWorkoutID() else {
            currentAutoImportedReviewWorkoutID = nil
            return false
        }

        if currentAutoImportedReviewWorkoutID != nextWorkoutID {
            currentAutoImportedReviewWorkoutID = nextWorkoutID
        }

        return true
    }

    func dismissCurrentAutoImportedReview() {
        currentAutoImportedReviewWorkoutID = nil
    }

    func completeAutoImportedReview(for workoutID: UUID) {
        markAutoImportedReviewHandled(for: workoutID)
        reviewStateStore.clearLatestWorkout(ifMatches: workoutID)
        if currentAutoImportedReviewWorkoutID == workoutID {
            currentAutoImportedReviewWorkoutID = nil
        }
    }

    func handleAppleHealthAutoImportPreferenceChanged() async {
        await syncAppleHealthAutomationServices()
    }

    @discardableResult
    func enrichInAppWorkoutWithAppleHealthIfPossible(
        _ workout: Workout,
        modelContext: ModelContext,
        forceRangeDiscovery: Bool = false
    ) async -> Bool {
        guard workout.isInAppSensorWorkout,
              needsAppleHealthEnrichment(workout) else {
            return false
        }

        await authorizationController.refreshAuthorizationRequestStatus()

        do {
            if let externalRecordID = appleHealthExternalRecordID(for: workout) {
                return try await enrichLinkedInAppWorkoutWithAppleHealthIfPossible(
                    workout,
                    externalRecordID: externalRecordID,
                    modelContext: modelContext
                )
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }

        let shouldUseRangeDiscovery = forceRangeDiscovery || enrichmentRetryStore.isRetryDue(for: workout)
        guard shouldUseRangeDiscovery || hasCachedAppleHealthEnrichmentSample(for: workout) else {
            return false
        }

        do {
            let enrichedWorkouts = try await enrichInAppWorkoutsWithAppleHealthIfPossible(
                modelContext: modelContext,
                eligibleWorkoutIDs: [workout.id],
                forceRangeDiscovery: forceRangeDiscovery
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

        if appleHealthExternalRecordID(for: workout) != nil {
            return enrichmentRetryStore.isWithinRetryWindow(for: workout) ? .metricsPending : .metricsStalled
        }

        if enrichmentRetryStore.isWithinRetryWindow(for: workout) ||
            hasCachedAppleHealthEnrichmentSample(for: workout) {
            return .linkPending
        }

        return .notPending
    }

    func appleHealthHeartRateEnrichmentStatus(for workout: Workout) -> AppleHealthEnrichmentStatus {
        guard needsAppleHealthHeartRateEnrichment(workout) else { return .complete }

        return appleHealthEnrichmentStatus(for: workout)
    }

    private func performAppleHealthRefreshIfNeeded(trigger: ImportRefreshTrigger) async -> Bool {
        guard authorizationController.isHealthDataAvailable else { return false }

        let shouldRequestAuthorization = trigger == .manualSync
        let shouldAllowInitialBackfill = trigger == .homeEntry || trigger == .manualReview || trigger == .manualSync

        if authorizationController.connectionState == .revoked {
            return false
        }

        if !authorizationController.hasRequestedAuthorization {
            guard shouldRequestAuthorization else { return false }
            let granted = await authorizationController.requestAuthorization()
            if !granted {
                lastErrorMessage = authorizationController.lastPermissionErrorMessage
                return false
            }
        }

        if !authorizationController.hasCompletedInitialBackfill {
            guard shouldAllowInitialBackfill else { return false }
        }

        do {
            let result = try await workoutReader.fetchAnchoredStairStepperWorkouts(
                anchorData: HealthKitSyncState.workoutAnchorData
            )
            HealthKitSyncState.updateCachedWorkoutSamples(
                added: result.addedSamples,
                deletedExternalRecordIDs: result.deletedExternalRecordIDs
            )
            ignoredAppleHealthWorkoutStore.prune(
                validExternalRecordIDs: Set(HealthKitSyncState.cachedWorkoutSamples.map(\.externalRecordID))
            )
            HealthKitSyncState.workoutAnchorData = result.anchorData
            HealthKitSyncState.lastSuccessfulCheckAt = Date()
            lastCheckAt = HealthKitSyncState.lastSuccessfulCheckAt

            if !authorizationController.hasCompletedInitialBackfill {
                HealthKitSyncState.hasCompletedInitialBackfill = true
            }

            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func autoImportEligibleAppleHealthCandidatesIfNeeded(
        modelContext: ModelContext,
        missingActivationFallback: Date?
    ) async {
        guard settingsManager.appleHealthAutoImportEnabled else { return }

        let policy = AppleHealthAutoImportPolicy(
            activatedAt: settingsManager.appleHealthAutoImportActivatedAt,
            missingActivationFallback: missingActivationFallback
        )
        let autoImportCandidates = pendingCandidates.filter(policy.shouldAutoImport(_:))
        guard !autoImportCandidates.isEmpty else { return }

        let result = await importCandidatesInternal(
            candidates: autoImportCandidates,
            mode: .automatic
        )

        for workout in result.importedWorkouts {
            recordAutoImportedWorkoutForReview(workout)
        }

        do {
            try pruneAutoImportedReviewState(modelContext: modelContext)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func syncAppleHealthAutomationServices() async {
        let shouldObserveForAutoImport =
            settingsManager.appleHealthAutoImportEnabled &&
            authorizationController.connectionState == .connected &&
            authorizationController.hasCompletedInitialBackfill

        await HealthKitBackgroundSyncManager.shared.updateObservation(enabled: shouldObserveForAutoImport)
        recordAppleHealthLifecycleState()
    }

    private func recordAppleHealthLifecycleState() {
        LifecycleEventRecorder.shared.recordAppleHealthIntegration(
            state: authorizationController.connectionState,
            autoImportEnabled: settingsManager.appleHealthAutoImportEnabled
        )
    }

    private func buildPendingCandidates(modelContext: ModelContext) throws -> [ImportedWorkoutCandidate] {
        let ignoredAppleHealthWorkoutIDs = ignoredAppleHealthWorkoutStore.load()
        let appleSamples = HealthKitSyncState.cachedWorkoutSamples
            .filter { !ignoredAppleHealthWorkoutIDs.contains($0.externalRecordID) }

        let importedRecordIDs = try AppleHealthLinkQuery.importedRecordIDs(
            among: Set(appleSamples.map(\.externalRecordID)),
            in: modelContext
        )

        return appleSamples
            .filter { !importedRecordIDs.contains($0.externalRecordID) }
            .map { ImportedWorkoutCandidate.appleHealth(sample: $0) }
            .sorted { lhs, rhs in
                lhs.startDate > rhs.startDate
            }
    }

    @discardableResult
    private func enrichInAppWorkoutsWithAppleHealthIfPossible(
        modelContext: ModelContext,
        eligibleWorkoutIDs: Set<UUID>? = nil,
        forceRangeDiscovery: Bool = false
    ) async throws -> [Workout] {
        guard authorizationController.connectionState == .connected else { return [] }

        let inScopeWorkouts = try InAppSensorWorkoutQuery
            .allInAppSensorWorkouts(in: modelContext)
            .filter { workout in
                if let eligibleWorkoutIDs, !eligibleWorkoutIDs.contains(workout.id) {
                    return false
                }

                return needsAppleHealthEnrichment(workout)
            }

        let linkedMetricWorkouts = inScopeWorkouts.filter { workout in
            appleHealthExternalRecordID(for: workout) != nil &&
                enrichmentRetryStore.isRetryDue(for: workout)
        }
        enrichmentRetryStore.recordAttempt(for: linkedMetricWorkouts)

        var linkedMetricUpdates: [Workout] = []
        for workout in linkedMetricWorkouts {
            guard let externalRecordID = appleHealthExternalRecordID(for: workout) else { continue }
            do {
                if try await enrichLinkedInAppWorkoutWithAppleHealthIfPossible(
                    workout,
                    externalRecordID: externalRecordID,
                    modelContext: modelContext
                ) {
                    linkedMetricUpdates.append(workout)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        let eligibleWorkouts = inScopeWorkouts.filter(canAttemptAppleHealthEnrichment)
        guard !eligibleWorkouts.isEmpty else { return linkedMetricUpdates }

        let heartRateFallbackWorkouts = forceRangeDiscovery
            ? eligibleWorkouts
            : eligibleWorkouts.filter { enrichmentRetryStore.isRetryDue(for: $0) }
        let appleSamples = try await appleHealthSamplesForEnrichment(
            eligibleWorkouts: eligibleWorkouts,
            modelContext: modelContext,
            forceRangeDiscovery: forceRangeDiscovery
        )
        guard !appleSamples.isEmpty else {
            let heartRateUpdates = try await enrichInAppWorkoutsWithAppleHealthHeartRateByTimeWindowIfPossible(
                heartRateFallbackWorkouts,
                modelContext: modelContext
            )
            return linkedMetricUpdates + heartRateUpdates
        }

        let matches = resolveAppleHealthEnrichmentMatches(
            eligibleWorkouts: eligibleWorkouts,
            appleSamples: appleSamples
        )
        guard !matches.isEmpty else {
            let heartRateUpdates = try await enrichInAppWorkoutsWithAppleHealthHeartRateByTimeWindowIfPossible(
                heartRateFallbackWorkouts,
                modelContext: modelContext
            )
            return linkedMetricUpdates + heartRateUpdates
        }

        var updatedWorkouts: [Workout] = []
        var updates: [WorkoutMutation.Update] = []
        var linkedAppleHealthIDs = Set<String>()

        for match in matches {
            guard let hkWorkout = try await workoutReader.fetchWorkout(withExternalRecordID: match.sample.externalRecordID),
                  let metricWindow = match.policy.metricWindow(for: match.workout, sample: match.sample) else {
                continue
            }

            let metrics = await metricsReader.fetchMetrics(for: hkWorkout, during: metricWindow)
            let before = LeaderboardWorkoutSnapshot(workout: match.workout)
            applyAppleHealthEnrichmentMetrics(metrics, to: match.workout)
            acquireAppleHealthLink(sample: match.sample, for: match.workout, modelContext: modelContext)

            updatedWorkouts.append(match.workout)
            updates.append(.init(before: before, after: LeaderboardWorkoutSnapshot(workout: match.workout)))
            linkedAppleHealthIDs.insert(match.sample.externalRecordID)
            enrichmentRetryStore.clear(workoutID: match.workout.id)
        }

        guard !updatedWorkouts.isEmpty else {
            let heartRateUpdates = try await enrichInAppWorkoutsWithAppleHealthHeartRateByTimeWindowIfPossible(
                heartRateFallbackWorkouts,
                modelContext: modelContext
            )
            return linkedMetricUpdates + heartRateUpdates
        }

        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: WorkoutMutation(updated: updates),
            changedWorkouts: updatedWorkouts
        )

        pendingCandidates.removeAll { candidate in
            guard let externalRecordID = candidate.appleHealthSample?.externalRecordID else { return false }
            return linkedAppleHealthIDs.contains(externalRecordID)
        }

        let heartRateFallbackUpdates = try await enrichInAppWorkoutsWithAppleHealthHeartRateByTimeWindowIfPossible(
            heartRateFallbackWorkouts.filter { needsAppleHealthHeartRateEnrichment($0) },
            modelContext: modelContext
        )

        return linkedMetricUpdates + updatedWorkouts + heartRateFallbackUpdates
    }

    private func appleHealthSamplesForEnrichment(
        eligibleWorkouts: [Workout],
        modelContext: ModelContext,
        forceRangeDiscovery: Bool = false
    ) async throws -> [HealthKitWorkoutSample] {
        let ignoredAppleHealthWorkoutIDs = ignoredAppleHealthWorkoutStore.load()
        var samplesByID: [String: HealthKitWorkoutSample] = [:]
        let retryableWorkouts = forceRangeDiscovery
            ? eligibleWorkouts
            : eligibleWorkouts.filter { workout in
                enrichmentRetryStore.isRetryDue(for: workout)
            }

        // Imported-ness is resolved a batch at a time rather than per sample: one bounded query
        // over the IDs in hand, instead of an index built by scanning the whole store.
        func addAllEligible(_ samples: [HealthKitWorkoutSample]) throws {
            let unignoredSamples = samples.filter {
                !ignoredAppleHealthWorkoutIDs.contains($0.externalRecordID)
            }
            guard !unignoredSamples.isEmpty else { return }

            let importedRecordIDs = try AppleHealthLinkQuery.importedRecordIDs(
                among: Set(unignoredSamples.map(\.externalRecordID)),
                in: modelContext
            )

            for sample in unignoredSamples
            where !importedRecordIDs.contains(sample.externalRecordID) {
                samplesByID[sample.externalRecordID] = sample
            }
        }

        func sortedSamples() -> [HealthKitWorkoutSample] {
            samplesByID.values.sorted { lhs, rhs in
                lhs.startDate > rhs.startDate
            }
        }

        try addAllEligible(HealthKitSyncState.cachedWorkoutSamples)

        if let dateRange = appleHealthEnrichmentDiscoveryRange(for: retryableWorkouts) {
            enrichmentRetryStore.recordAttempt(for: retryableWorkouts)
            guard let discoveredSamples = try? await workoutReader.fetchStairStepperWorkouts(in: dateRange) else {
                return sortedSamples()
            }
            HealthKitSyncState.updateCachedWorkoutSamples(
                added: discoveredSamples,
                deletedExternalRecordIDs: []
            )
            try addAllEligible(discoveredSamples)
        }

        return sortedSamples()
    }

    @discardableResult
    private func enrichLinkedInAppWorkoutWithAppleHealthIfPossible(
        _ workout: Workout,
        externalRecordID: String,
        modelContext: ModelContext
    ) async throws -> Bool {
        guard authorizationController.connectionState == .connected,
              let hkWorkout = try await workoutReader.fetchWorkout(withExternalRecordID: externalRecordID) else {
            return false
        }

        let sample = healthKitWorkoutSample(from: hkWorkout)
        let metricWindow = AppleHealthWorkoutEnrichmentPolicy.inAppSensorWorkout.metricWindow(
            for: workout,
            sample: sample
        ) ?? (sample.startDate...sample.endDate)
        let metrics = await metricsReader.fetchMetrics(for: hkWorkout, during: metricWindow)
        let before = LeaderboardWorkoutSnapshot(workout: workout)
        let didChangeMetrics = applyAppleHealthEnrichmentMetrics(metrics, to: workout)
        let didChangeLink = acquireAppleHealthLink(
            sample: sample,
            for: workout,
            modelContext: modelContext
        )

        guard didChangeMetrics || didChangeLink else { return false }

        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: WorkoutMutation(updated: [
                .init(before: before, after: LeaderboardWorkoutSnapshot(workout: workout))
            ]),
            changedWorkouts: [workout]
        )
        return true
    }

    private func appleHealthEnrichmentDiscoveryRange(
        for workouts: [Workout]
    ) -> ClosedRange<Date>? {
        let starts = workouts.map(\.date)
        let ends = workouts.map { workout in
            workout.date.addingTimeInterval(max(workout.duration, 1))
        }
        guard let earliestStart = starts.min(),
              let latestEnd = ends.max() else {
            return nil
        }

        let tolerance: TimeInterval = 30 * 60
        let lowerBound = earliestStart.addingTimeInterval(-tolerance)
        let upperBound = latestEnd.addingTimeInterval(tolerance)
        return lowerBound...upperBound
    }

    private func resolveAppleHealthEnrichmentMatches(
        eligibleWorkouts: [Workout],
        appleSamples: [HealthKitWorkoutSample]
    ) -> [AppleHealthWorkoutEnrichmentMatch] {
        let pairs = eligibleWorkouts.flatMap { workout in
            appleSamples.compactMap { sample -> AppleHealthWorkoutEnrichmentCandidatePair? in
                for policy in AppleHealthWorkoutEnrichmentPolicy.inAppSessionPolicies {
                    guard policy.isEligible(workout, hasAppleHealthLink: hasAppleHealthLink(workout)),
                          let score = policy.matchScore(workout: workout, sample: sample) else {
                        continue
                    }

                    return AppleHealthWorkoutEnrichmentCandidatePair(
                        policy: policy,
                        workout: workout,
                        sample: sample,
                        score: score
                    )
                }

                return nil
            }
        }

        let pairsByWorkoutID = Dictionary(grouping: pairs, by: { $0.workout.id })
        let pairsByAppleHealthID = Dictionary(grouping: pairs, by: { $0.sample.externalRecordID })

        return pairs
            .filter { pair in
                pairsByWorkoutID[pair.workout.id]?.count == 1 &&
                    pairsByAppleHealthID[pair.sample.externalRecordID]?.count == 1
            }
            .sorted { lhs, rhs in
                if lhs.workout.date != rhs.workout.date {
                    return lhs.workout.date < rhs.workout.date
                }

                return lhs.score > rhs.score
            }
            .map {
                AppleHealthWorkoutEnrichmentMatch(
                    policy: $0.policy,
                    workout: $0.workout,
                    sample: $0.sample
                )
            }
    }

    private func importCandidatesInternal(
        candidates: [ImportedWorkoutCandidate],
        mode: WorkoutImportAnalyticsEvent.ImportMode
    ) async -> ImportBatchResult {
        guard let modelContext else {
            return ImportBatchResult(importedWorkouts: [], updatedWorkouts: [], failedCandidateIDs: [])
        }

        guard !candidates.isEmpty else {
            return ImportBatchResult(importedWorkouts: [], updatedWorkouts: [], failedCandidateIDs: [])
        }

        telemetry.track(
            WorkoutImportAnalyticsEvent.started(
                mode: mode,
                candidates: candidates
            )
        )

        isImporting = true
        totalImportCount = candidates.count
        remainingImportCount = candidates.count
        defer {
            isImporting = false
            currentImportingCandidateID = nil
            totalImportCount = 0
            remainingImportCount = 0
        }

        var importedWorkouts: [Workout] = []
        var updatedWorkouts: [Workout] = []
        var failedCandidateIDs: [String] = []

        for candidate in candidates.sorted(by: { $0.startDate < $1.startDate }) {
            // A backfill can be hundreds of workouts long. Yielding between them keeps Home
            // interactive while it runs, and gives cancellation somewhere to land.
            await Task.yield()
            if Task.isCancelled { break }

            currentImportingCandidateID = candidate.id

            let outcome = await importCandidateInternal(candidate, modelContext: modelContext)
            remainingImportCount = max(0, remainingImportCount - 1)

            switch outcome {
            case .imported(let workout):
                importedWorkouts.append(workout)
                pendingCandidates.removeAll { $0.id == candidate.id }
            case .updatedExisting(let workout):
                updatedWorkouts.append(workout)
                pendingCandidates.removeAll { $0.id == candidate.id }
            case .skipped(let candidateID):
                pendingCandidates.removeAll { $0.id == candidateID }
            case .failed(let candidateID):
                failedCandidateIDs.append(candidateID)
            }
        }

        if !importedWorkouts.isEmpty || !updatedWorkouts.isEmpty {
            do {
                try recalculateDerivedData(
                    modelContext: modelContext,
                    newWorkouts: importedWorkouts
                )
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        let result = ImportBatchResult(
            importedWorkouts: importedWorkouts,
            updatedWorkouts: updatedWorkouts,
            failedCandidateIDs: failedCandidateIDs
        )

        telemetry.track(
            WorkoutImportAnalyticsEvent.finished(
                mode: mode,
                candidates: candidates,
                result: result
            )
        )

        return result
    }

    private func importCandidateInternal(
        _ candidate: ImportedWorkoutCandidate,
        modelContext: ModelContext
    ) async -> ImportOutcome {
        do {
            switch candidate.kind {
            case .appleHealth:
                guard let appleHealthSample = candidate.appleHealthSample else {
                    return .failed(candidateID: candidate.id)
                }
                if let existingWorkout = try AppleHealthLinkQuery.workout(
                    forExternalRecordID: appleHealthSample.externalRecordID,
                    in: modelContext
                ) {
                    return .updatedExisting(existingWorkout)
                }
                return try await importAppleHealthCandidate(candidate, modelContext: modelContext)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return .failed(candidateID: candidate.id)
        }
    }

    private func importAppleHealthCandidate(
        _ candidate: ImportedWorkoutCandidate,
        modelContext: ModelContext
    ) async throws -> ImportOutcome {
        guard let sample = candidate.appleHealthSample,
              let hkWorkout = try await workoutReader.fetchWorkout(withExternalRecordID: sample.externalRecordID) else {
            return .failed(candidateID: candidate.id)
        }

        let metrics = await metricsReader.fetchMetrics(for: hkWorkout)
        let workout = hkWorkout.toAscendWorkout(with: metrics)
        guard WorkoutPlausibilityPolicy.hasPlausibleTotals(workout) else {
            ignoredAppleHealthWorkoutStore.insert(sample.externalRecordID)
            return .skipped(candidateID: candidate.id)
        }
        let appleHealthLink = makeAppleHealthSourceLink(from: sample, workout: workout)

        if let existingWorkout = try AppleHealthLinkQuery.workout(
            forExternalRecordID: sample.externalRecordID,
            in: modelContext
        ) {
            return .updatedExisting(existingWorkout)
        }

        // Re-run per candidate, deliberately: this sample may be the Apple Health side of an
        // in-app session recorded moments ago, and only enriching now can tell. The cost is real
        // and is stated in full on `InAppSensorWorkoutQuery.allInAppSensorWorkouts` - a backfill
        // of n candidates refetches the in-app sensor history n times.
        let enrichedWorkouts = try await enrichInAppWorkoutsWithAppleHealthIfPossible(
            modelContext: modelContext
        )
        if let enrichedWorkout = enrichedWorkouts.first(where: { $0.healthKitUUID == sample.externalRecordID }) {
            return .updatedExisting(enrichedWorkout)
        }

        modelContext.insert(workout)
        modelContext.insert(appleHealthLink)
        try modelContext.save()

        return .imported(workout)
    }

    private func hasAppleHealthLink(_ workout: Workout) -> Bool {
        workout.hasSourceLink(provider: .appleHealth) || workout.healthKitUUID != nil
    }

    private func appleHealthExternalRecordID(for workout: Workout) -> String? {
        workout.sourceLink(for: .appleHealth)?.externalRecordID ?? workout.healthKitUUID
    }

    private func canAttemptAppleHealthEnrichment(_ workout: Workout) -> Bool {
        AppleHealthWorkoutEnrichmentPolicy.inAppSessionPolicies.contains { policy in
            policy.isEligible(workout, hasAppleHealthLink: hasAppleHealthLink(workout))
        } && needsAppleHealthEnrichment(workout)
    }

    private func needsAppleHealthEnrichment(_ workout: Workout) -> Bool {
        workout.avgHeartRate == nil ||
            workout.maxHeartRate == nil ||
            workout.heartRateTimeSeries.isEmpty ||
            workout.caloriesBurned == nil ||
            workout.averageMETs == nil
    }

    private func needsAppleHealthHeartRateEnrichment(_ workout: Workout) -> Bool {
        workout.avgHeartRate == nil ||
            workout.maxHeartRate == nil ||
            workout.heartRateTimeSeries.isEmpty
    }

    @discardableResult
    private func enrichInAppWorkoutsWithAppleHealthHeartRateByTimeWindowIfPossible(
        _ workouts: [Workout],
        modelContext: ModelContext
    ) async throws -> [Workout] {
        guard authorizationController.connectionState == .connected else { return [] }

        let candidates = workouts.filter { workout in
            workout.isInAppSensorWorkout && needsAppleHealthHeartRateEnrichment(workout)
        }
        guard !candidates.isEmpty else { return [] }

        var updatedWorkouts: [Workout] = []
        var updates: [WorkoutMutation.Update] = []

        for workout in candidates {
            let metricWindow = workout.date...workout.date.addingTimeInterval(max(workout.duration, 1))
            let metrics = await metricsReader.fetchMetrics(during: metricWindow)
            let before = LeaderboardWorkoutSnapshot(workout: workout)
            let didChangeMetrics = applyAppleHealthHeartRateMetrics(metrics, to: workout)

            guard didChangeMetrics else { continue }

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

    private func hasCachedAppleHealthEnrichmentSample(for workout: Workout) -> Bool {
        let ignoredAppleHealthWorkoutIDs = ignoredAppleHealthWorkoutStore.load()
        return HealthKitSyncState.cachedWorkoutSamples.contains { sample in
            guard !ignoredAppleHealthWorkoutIDs.contains(sample.externalRecordID) else {
                return false
            }

            return AppleHealthWorkoutEnrichmentPolicy.inAppSessionPolicies.contains { policy in
                policy.isEligible(workout, hasAppleHealthLink: hasAppleHealthLink(workout)) &&
                    policy.matchScore(workout: workout, sample: sample) != nil
            }
        }
    }

    private func applyAppleHealthMetrics(
        _ metrics: WorkoutMetrics,
        from sample: HealthKitWorkoutSample,
        to workout: Workout
    ) {
        workout.date = sample.startDate
        workout.avgHeartRate = metrics.avgHeartRate
        workout.maxHeartRate = metrics.maxHeartRate
        workout.heartRateData = metrics.heartRateTimeSeries.encoded
        workout.caloriesBurned = metrics.caloriesBurned
        workout.averageMETs = metrics.averageMETs
        workout.deviceModel = sample.deviceModel ?? sample.displaySourceName
        workout.healthKitUUID = sample.externalRecordID
    }

    @discardableResult
    private func applyAppleHealthEnrichmentMetrics(
        _ metrics: WorkoutMetrics,
        to workout: Workout
    ) -> Bool {
        var didChange = false

        // A workout that already carries a live-captured heart-rate series
        // (Bluetooth chest strap during the session) keeps it: strap data is
        // first-party and more accurate than wrist-derived Apple Health HR.
        // Enrichment still fills calories/METs below.
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
        if let averageMETs = metrics.averageMETs, workout.averageMETs != averageMETs {
            workout.averageMETs = averageMETs
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private func applyAppleHealthHeartRateMetrics(
        _ metrics: WorkoutMetrics,
        to workout: Workout
    ) -> Bool {
        var didChange = false

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

        return didChange
    }

    private func healthKitWorkoutSample(from workout: HKWorkout) -> HealthKitWorkoutSample {
        HealthKitWorkoutSample(
            externalRecordID: workout.uuid.uuidString,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            sourceName: workout.sourceRevision.source.name,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            deviceModel: workout.device?.name
        )
    }

    @discardableResult
    private func acquireAppleHealthLink(
        sample: HealthKitWorkoutSample,
        for workout: Workout,
        modelContext: ModelContext
    ) -> Bool {
        var didChange = false

        let deviceModel = sample.deviceModel ?? sample.displaySourceName
        if workout.deviceModel != deviceModel {
            workout.deviceModel = deviceModel
            didChange = true
        }
        if workout.healthKitUUID != sample.externalRecordID {
            workout.healthKitUUID = sample.externalRecordID
            didChange = true
        }

        guard workout.sourceLink(for: .appleHealth) == nil else { return didChange }

        let link = makeAppleHealthSourceLink(from: sample, workout: workout)
        modelContext.insert(link)
        return true
    }

    private func makeAppleHealthSourceLink(
        from sample: HealthKitWorkoutSample,
        workout: Workout
    ) -> WorkoutSourceLink {
        WorkoutSourceLink(
            provider: .appleHealth,
            externalRecordID: sample.externalRecordID,
            providerWindowStart: sample.startDate,
            providerWindowEnd: sample.endDate,
            timingPrecision: .exact,
            sourceName: sample.displaySourceName,
            sourceBundleIdentifier: sample.sourceBundleIdentifier,
            deviceModel: sample.deviceModel,
            metadataJSON: appleHealthMetadataJSON(for: sample),
            workout: workout
        )
    }

    private func appleHealthMetadataJSON(for sample: HealthKitWorkoutSample) -> String? {
        let payload: [String: String] = [
            "sourceName": sample.displaySourceName,
            "sourceBundleIdentifier": sample.sourceBundleIdentifier,
            "deviceModel": sample.deviceModel ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func fetchAllWorkouts(from modelContext: ModelContext) throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Drops review state that points at a workout the user has since deleted.
    ///
    /// This runs on every Home entry, so it queries only the one or two IDs it actually cares
    /// about. Deriving them from a full `fetchAllWorkouts` is what blocked the main thread for
    /// 182 seconds on a large history (ASCEND-IOS-1K).
    private func pruneAutoImportedReviewState(modelContext: ModelContext) throws {
        var reviewedWorkoutIDs: Set<UUID> = []
        if let recordedWorkoutID = reviewStateStore.recordedWorkoutID() {
            reviewedWorkoutIDs.insert(recordedWorkoutID)
        }
        if let currentAutoImportedReviewWorkoutID {
            reviewedWorkoutIDs.insert(currentAutoImportedReviewWorkoutID)
        }
        guard !reviewedWorkoutIDs.isEmpty else { return }

        let survivingWorkoutIDs = try WorkoutExistenceQuery.existingIDs(
            among: reviewedWorkoutIDs,
            in: modelContext
        )
        reviewStateStore.prune(validIDs: survivingWorkoutIDs)

        if let currentAutoImportedReviewWorkoutID,
           !survivingWorkoutIDs.contains(currentAutoImportedReviewWorkoutID) {
            self.currentAutoImportedReviewWorkoutID = nil
        }
    }

    private func recordAutoImportedWorkoutForReview(_ workout: Workout) {
        let referenceDate = autoImportedReviewReferenceDate(for: workout)
        reviewStateStore.recordLatestWorkout(
            id: workout.id,
            referenceDate: referenceDate
        )

        if let currentAutoImportedReviewWorkoutID,
           currentAutoImportedReviewWorkoutID != workout.id,
           let currentReferenceDate = autoImportedReferenceDate(forWorkoutID: currentAutoImportedReviewWorkoutID),
           currentReferenceDate >= referenceDate {
            return
        }

        currentAutoImportedReviewWorkoutID = workout.id
    }

    private func markAutoImportedReviewHandled(for workoutID: UUID) {
        if let referenceDate = autoImportedReferenceDate(forWorkoutID: workoutID) {
            reviewStateStore.markHandled(referenceDate: referenceDate)
            return
        }

        if let latestReferenceDate = reviewStateStore.latestReferenceDate(for: workoutID) {
            reviewStateStore.markHandled(referenceDate: latestReferenceDate)
        }
    }

    private func autoImportedReferenceDate(forWorkoutID workoutID: UUID) -> Date? {
        guard let modelContext else { return nil }

        let workoutID = workoutID
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.id == workoutID
            }
        )

        guard let workout = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        return autoImportedReviewReferenceDate(for: workout)
    }

    private func autoImportedReviewReferenceDate(for workout: Workout) -> Date {
        workout.date.addingTimeInterval(workout.duration)
    }

    func ignoreAppleHealthWorkout(externalRecordID: String) {
        ignoredAppleHealthWorkoutStore.insert(externalRecordID)
    }

    private func recalculateDerivedData(modelContext: ModelContext, newWorkouts: [Workout] = []) throws {
        // `fetchAllWorkouts` is unavoidable here: a percentile is defined against the user's whole
        // history. What is avoidable is deriving that history once per workout - see
        // `allPercentiles(forDateAscendingWorkouts:)`.
        let allWorkouts = try fetchAllWorkouts(from: modelContext)
        let percentiles = PercentileScoreService.allPercentiles(
            forDateAscendingWorkouts: allWorkouts
        )

        for (workout, scores) in zip(allWorkouts, percentiles) {
            workout.percentileScores = scores
        }

        // Refresh derived workout data and leaderboard stats.
        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: .imported(newWorkouts.map(LeaderboardWorkoutSnapshot.init(workout:))),
            newWorkouts: newWorkouts,
            changedWorkouts: newWorkouts
        )
    }

#if DEBUG
    func debugQueueSimulatedAutoImportedReview(modelContext: ModelContext) async throws -> Workout {
        let workout = try await debugCreateSimulatedAppleHealthWorkout(modelContext: modelContext)
        currentAutoImportedReviewWorkoutID = nil
        debugLog("DEBUG auto-import queued review workout: \(workout.id.uuidString)")
        return workout
    }

    func debugClearSimulatedAutoImports(modelContext: ModelContext) throws -> Int {
        let workouts = try fetchAllWorkouts(from: modelContext).filter { workout in
            workout.healthKitUUID?.hasPrefix("debug-auto-import-") == true
        }

        for workout in workouts {
            modelContext.delete(workout)
        }

        try modelContext.save()
        try recalculateDerivedData(modelContext: modelContext)
        try pruneAutoImportedReviewState(modelContext: modelContext)

        debugLog("DEBUG auto-import cleared simulated workouts: \(workouts.count)")
        return workouts.count
    }

    private func debugCreateSimulatedAppleHealthWorkout(
        modelContext: ModelContext
    ) async throws -> Workout {
        let duration: TimeInterval = 26 * 60
        let completedAt = Date().addingTimeInterval(-60)
        let startedAt = completedAt.addingTimeInterval(-duration)
        let externalRecordID = "debug-auto-import-\(UUID().uuidString.lowercased())"
        let sample = HealthKitWorkoutSample(
            externalRecordID: externalRecordID,
            startDate: startedAt,
            endDate: completedAt,
            duration: duration,
            sourceName: "Apple Watch Simulator",
            sourceBundleIdentifier: "com.apple.Health",
            deviceModel: "Apple Watch Simulator"
        )

        let floors = 132
        let steps = Workout.floorsToSteps(floors)
        let workout = Workout(
            name: "Simulated Apple Health Import",
            date: sample.startDate,
            duration: sample.duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: Workout.defaultStepsPerFloor,
            notes: "Debug-only Apple Health auto-import simulation.",
            avgHeartRate: 146,
            maxHeartRate: 168,
            caloriesBurned: 318,
            averageMETs: 9.1,
            source: .appleHealth,
            deviceModel: sample.deviceModel,
            sourceMetadata: appleHealthMetadataJSON(for: sample),
            healthKitUUID: sample.externalRecordID
        )
        let sourceLink = makeAppleHealthSourceLink(from: sample, workout: workout)

        modelContext.insert(workout)
        modelContext.insert(sourceLink)
        try modelContext.save()
        try recalculateDerivedData(modelContext: modelContext, newWorkouts: [workout])

        recordAutoImportedWorkoutForReview(workout)

        lastErrorMessage = nil
        return workout
    }
#endif
}

private extension ImportRefreshTrigger {
    var capabilityLevel: Int {
        switch self {
        case .automatic, .backgroundObserver:
            return 0
        case .homeEntry, .manualReview:
            return 1
        case .manualSync:
            return 2
        }
    }

    func covers(_ trigger: ImportRefreshTrigger) -> Bool {
        capabilityLevel >= trigger.capabilityLevel
    }
}
