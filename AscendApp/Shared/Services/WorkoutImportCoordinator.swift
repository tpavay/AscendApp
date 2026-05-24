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

protocol WorkoutDataProviding {
    func refreshCandidates(existingIndex: WorkoutImportCoordinator.ExistingWorkoutIndex) async throws -> [ImportedWorkoutCandidate]
}

private struct LiveClimbAppleHealthCandidatePair {
    let workout: Workout
    let sample: HealthKitWorkoutSample
    let score: Double
}

private struct LiveClimbAppleHealthMatch {
    let workout: Workout
    let sample: HealthKitWorkoutSample
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

    struct ExistingWorkoutIndex {
        let allWorkouts: [Workout]
        let appleHealthWorkoutsByID: [String: Workout]

        func workout(forAppleHealthID externalRecordID: String) -> Workout? {
            appleHealthWorkoutsByID[externalRecordID]
        }
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

    private var modelContext: ModelContext?
    private var lastAutomaticCheckAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshTrigger: ImportRefreshTrigger?
    var currentAutoImportedReviewWorkoutID: UUID?

    init(
        authorizationController: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        workoutReader: any HealthKitWorkoutReading = HealthKitWorkoutReader.shared,
        metricsReader: any HealthKitMetricsReading = HealthKitMetricsReader.shared,
        telemetry: TelemetryManager = .shared,
        settingsManager: SettingsManager = .shared,
        reviewStateStore: WorkoutAutoImportReviewStateStore = WorkoutAutoImportReviewStateStore(),
        ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore = IgnoredAppleHealthWorkoutStore()
    ) {
        self.authorizationController = authorizationController
        self.workoutReader = workoutReader
        self.metricsReader = metricsReader
        self.telemetry = telemetry
        self.settingsManager = settingsManager
        self.reviewStateStore = reviewStateStore
        self.ignoredAppleHealthWorkoutStore = ignoredAppleHealthWorkoutStore
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

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        leaderboardService.configure(modelContext: modelContext)

        do {
            try WorkoutSourceMigrationService.runIfNeeded(modelContext: modelContext)
            try pruneAutoImportedReviewState(modelContext: modelContext)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        Task {
            await syncAppleHealthAutomationServices()
        }
    }

    func requestAppleHealthAuthorizationIfNeeded() async -> Bool {
        await authorizationController.refreshAuthorizationRequestStatus()

        guard authorizationController.isHealthDataAvailable else {
            lastErrorMessage = "Apple Health is not available on this device."
            return false
        }

        if authorizationController.connectionState == .revoked {
            lastErrorMessage = "Apple Health permissions were previously revoked. Re-enable them in the Health app."
            return false
        }

        if authorizationController.hasRequestedAuthorization, authorizationController.hasCompletedInitialBackfill {
            lastErrorMessage = nil
            return true
        }

        let granted = await authorizationController.requestAuthorization()
        if !granted {
            lastErrorMessage = authorizationController.lastPermissionErrorMessage
            return false
        }

        await refreshPendingImports(trigger: .manualSync)
        await syncAppleHealthAutomationServices()
        return lastErrorMessage == nil
    }

    func refreshPendingImports(trigger: ImportRefreshTrigger) async {
        if let refreshTask {
            let activeRefreshTrigger = activeRefreshTrigger
            await refreshTask.value

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

        await refreshTask.value
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
            try WorkoutSourceMigrationService.runIfNeeded(modelContext: modelContext)
            await authorizationController.refreshAuthorizationRequestStatus()
            let previousSuccessfulCheckAt = HealthKitSyncState.lastSuccessfulCheckAt ?? lastCheckAt
            _ = await performAppleHealthRefreshIfNeeded(trigger: trigger)

            var existingIndex = try buildExistingWorkoutIndex(modelContext: modelContext)
            let enrichedWorkouts = try await enrichLiveClimbWorkoutsWithAppleHealthIfPossible(
                existingIndex: existingIndex,
                modelContext: modelContext
            )
            if !enrichedWorkouts.isEmpty {
                existingIndex = try buildExistingWorkoutIndex(modelContext: modelContext)
            }
            pendingCandidates = try await buildPendingCandidates(existingIndex: existingIndex)
            try pruneAutoImportedReviewState(modelContext: modelContext)
            await autoImportEligibleAppleHealthCandidatesIfNeeded(
                modelContext: modelContext,
                missingActivationFallback: previousSuccessfulCheckAt
            )
            lastCheckAt = Date()
            lastErrorMessage = nil
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
        guard let modelContext else { return false }

        do {
            let existingIndex = try buildExistingWorkoutIndex(modelContext: modelContext)
            return isCandidateImported(candidate, existingIndex: existingIndex)
        } catch {
            return false
        }
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

    func enrichLiveClimbWorkoutWithAppleHealthIfPossible(
        _ workout: Workout,
        modelContext: ModelContext
    ) async {
        await authorizationController.refreshAuthorizationRequestStatus()
        _ = await performAppleHealthRefreshIfNeeded(trigger: .backgroundObserver)

        do {
            let existingIndex = try buildExistingWorkoutIndex(modelContext: modelContext)
            _ = try await enrichLiveClimbWorkoutsWithAppleHealthIfPossible(
                existingIndex: existingIndex,
                modelContext: modelContext,
                eligibleWorkoutIDs: [workout.id]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
    }

    private func buildPendingCandidates(existingIndex: ExistingWorkoutIndex) async throws -> [ImportedWorkoutCandidate] {
        let ignoredAppleHealthWorkoutIDs = ignoredAppleHealthWorkoutStore.load()
        let appleSamples = HealthKitSyncState.cachedWorkoutSamples
            .filter { !ignoredAppleHealthWorkoutIDs.contains($0.externalRecordID) }
            .sorted { $0.startDate > $1.startDate }

        var candidates: [ImportedWorkoutCandidate] = []

        for sample in appleSamples {
            guard !isAppleHealthImported(sample.externalRecordID, existingIndex: existingIndex) else { continue }
            candidates.append(.appleHealth(sample: sample))
        }

        return candidates.sorted { lhs, rhs in
            lhs.startDate > rhs.startDate
        }
    }

    @discardableResult
    private func enrichLiveClimbWorkoutsWithAppleHealthIfPossible(
        existingIndex: ExistingWorkoutIndex,
        modelContext: ModelContext,
        eligibleWorkoutIDs: Set<UUID>? = nil
    ) async throws -> [Workout] {
        guard authorizationController.connectionState == .connected else { return [] }

        let ignoredAppleHealthWorkoutIDs = ignoredAppleHealthWorkoutStore.load()
        let appleSamples = HealthKitSyncState.cachedWorkoutSamples
            .filter { !ignoredAppleHealthWorkoutIDs.contains($0.externalRecordID) }
            .filter { !isAppleHealthImported($0.externalRecordID, existingIndex: existingIndex) }

        guard !appleSamples.isEmpty else { return [] }

        let liveClimbWorkouts = existingIndex.allWorkouts.filter { workout in
            if let eligibleWorkoutIDs, !eligibleWorkoutIDs.contains(workout.id) {
                return false
            }

            return isEligibleForLiveClimbAppleHealthEnrichment(workout)
        }

        let matches = resolveLiveClimbAppleHealthMatches(
            liveClimbWorkouts: liveClimbWorkouts,
            appleSamples: appleSamples
        )
        guard !matches.isEmpty else { return [] }

        var updatedWorkouts: [Workout] = []
        var updates: [WorkoutMutation.Update] = []
        var linkedAppleHealthIDs = Set<String>()

        for match in matches {
            guard let hkWorkout = try await workoutReader.fetchWorkout(withExternalRecordID: match.sample.externalRecordID),
                  let metricWindow = liveClimbMetricWindow(for: match.workout, sample: match.sample) else {
                continue
            }

            let metrics = await metricsReader.fetchMetrics(for: hkWorkout, during: metricWindow)
            let before = LeaderboardWorkoutSnapshot(workout: match.workout)
            applyAppleHealthEnrichmentMetrics(metrics, from: match.sample, to: match.workout)
            ensureAppleHealthLinkExists(sample: match.sample, for: match.workout, modelContext: modelContext)

            updatedWorkouts.append(match.workout)
            updates.append(.init(before: before, after: LeaderboardWorkoutSnapshot(workout: match.workout)))
            linkedAppleHealthIDs.insert(match.sample.externalRecordID)
        }

        guard !updatedWorkouts.isEmpty else { return [] }

        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: WorkoutMutation(updated: updates),
            changedWorkouts: updatedWorkouts
        )

        pendingCandidates.removeAll { candidate in
            guard let externalRecordID = candidate.appleHealthSample?.externalRecordID else { return false }
            return linkedAppleHealthIDs.contains(externalRecordID)
        }

        return updatedWorkouts
    }

    private func isEligibleForLiveClimbAppleHealthEnrichment(_ workout: Workout) -> Bool {
        workout.isLiveClimbAttemptWorkout && !hasAppleHealthLink(workout)
    }

    private func resolveLiveClimbAppleHealthMatches(
        liveClimbWorkouts: [Workout],
        appleSamples: [HealthKitWorkoutSample]
    ) -> [LiveClimbAppleHealthMatch] {
        let pairs = liveClimbWorkouts.flatMap { workout in
            appleSamples.compactMap { sample -> LiveClimbAppleHealthCandidatePair? in
                guard let score = liveClimbAppleHealthMatchScore(workout: workout, sample: sample) else {
                    return nil
                }

                return LiveClimbAppleHealthCandidatePair(workout: workout, sample: sample, score: score)
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
            .map { LiveClimbAppleHealthMatch(workout: $0.workout, sample: $0.sample) }
    }

    private func liveClimbAppleHealthMatchScore(
        workout: Workout,
        sample: HealthKitWorkoutSample
    ) -> Double? {
        let liveDuration = max(workout.duration, 1)
        let liveStart = workout.date
        let liveEnd = liveStart.addingTimeInterval(liveDuration)
        let overlapStart = max(liveStart, sample.startDate)
        let overlapEnd = min(liveEnd, sample.endDate)
        let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
        guard overlapDuration > 0 else { return nil }

        let overlapRatio = overlapDuration / liveDuration
        guard overlapRatio >= 0.70 else { return nil }

        let startDelta = abs(sample.startDate.timeIntervalSince(liveStart))
        guard startDelta <= 15 * 60 else { return nil }

        return (overlapRatio * 100) - min(startDelta / 60, 15)
    }

    private func liveClimbMetricWindow(
        for workout: Workout,
        sample: HealthKitWorkoutSample
    ) -> ClosedRange<Date>? {
        let liveStart = workout.date
        let liveEnd = workout.date.addingTimeInterval(max(workout.duration, 1))
        let start = max(liveStart, sample.startDate)
        let end = min(liveEnd, sample.endDate)

        guard end > start else { return nil }
        return start...end
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
        defer {
            isImporting = false
            currentImportingCandidateID = nil
        }

        var importedWorkouts: [Workout] = []
        var updatedWorkouts: [Workout] = []
        var failedCandidateIDs: [String] = []

        for candidate in candidates.sorted(by: { $0.startDate < $1.startDate }) {
            currentImportingCandidateID = candidate.id

            let outcome = await importCandidateInternal(candidate, modelContext: modelContext)
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
            let existingIndex = try buildExistingWorkoutIndex(modelContext: modelContext)

            switch candidate.kind {
            case .appleHealth:
                guard let appleHealthSample = candidate.appleHealthSample else {
                    return .failed(candidateID: candidate.id)
                }
                if let existingWorkout = existingIndex.workout(forAppleHealthID: appleHealthSample.externalRecordID) {
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

        let refreshedIndex = try buildExistingWorkoutIndex(modelContext: modelContext)
        if let existingWorkout = refreshedIndex.workout(forAppleHealthID: sample.externalRecordID) {
            return .updatedExisting(existingWorkout)
        }

        let enrichedWorkouts = try await enrichLiveClimbWorkoutsWithAppleHealthIfPossible(
            existingIndex: refreshedIndex,
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

    private func buildExistingWorkoutIndex(modelContext: ModelContext) throws -> ExistingWorkoutIndex {
        let workouts = try fetchAllWorkouts(from: modelContext)

        var appleHealthWorkoutsByID: [String: Workout] = [:]

        for workout in workouts {
            if let healthKitUUID = workout.healthKitUUID {
                appleHealthWorkoutsByID[healthKitUUID] = workout
            }

            for sourceLink in workout.sourceLinks {
                switch sourceLink.provider {
                case .appleHealth:
                    appleHealthWorkoutsByID[sourceLink.externalRecordID] = workout
                case .garmin, .fitbit, .hevy:
                    break
                }
            }
        }

        return ExistingWorkoutIndex(
            allWorkouts: workouts,
            appleHealthWorkoutsByID: appleHealthWorkoutsByID
        )
    }

    private func isCandidateImported(_ candidate: ImportedWorkoutCandidate, existingIndex: ExistingWorkoutIndex) -> Bool {
        switch candidate.kind {
        case .appleHealth:
            guard let appleHealthSample = candidate.appleHealthSample else { return false }
            return isAppleHealthImported(appleHealthSample.externalRecordID, existingIndex: existingIndex)
        }
    }

    private func isAppleHealthImported(_ externalRecordID: String, existingIndex: ExistingWorkoutIndex) -> Bool {
        existingIndex.workout(forAppleHealthID: externalRecordID) != nil
    }

    private func hasAppleHealthLink(_ workout: Workout) -> Bool {
        workout.hasSourceLink(provider: .appleHealth) || workout.healthKitUUID != nil
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

    private func applyAppleHealthEnrichmentMetrics(
        _ metrics: WorkoutMetrics,
        from sample: HealthKitWorkoutSample,
        to workout: Workout
    ) {
        if let avgHeartRate = metrics.avgHeartRate {
            workout.avgHeartRate = avgHeartRate
        }
        if let maxHeartRate = metrics.maxHeartRate {
            workout.maxHeartRate = maxHeartRate
        }
        if !metrics.heartRateTimeSeries.isEmpty {
            workout.heartRateData = metrics.heartRateTimeSeries.encoded
        }
        if let caloriesBurned = metrics.caloriesBurned {
            workout.caloriesBurned = caloriesBurned
        }
        if let averageMETs = metrics.averageMETs {
            workout.averageMETs = averageMETs
        }

        workout.deviceModel = sample.deviceModel ?? sample.displaySourceName
        workout.healthKitUUID = sample.externalRecordID
    }

    private func ensureAppleHealthLinkExists(
        sample: HealthKitWorkoutSample,
        for workout: Workout,
        modelContext: ModelContext
    ) {
        guard workout.sourceLink(for: .appleHealth) == nil else { return }

        let link = makeAppleHealthSourceLink(from: sample, workout: workout)
        modelContext.insert(link)
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

    private func pruneAutoImportedReviewState(modelContext: ModelContext) throws {
        let validWorkoutIDs = try Set(fetchAllWorkouts(from: modelContext).map(\.id))
        reviewStateStore.prune(validIDs: validWorkoutIDs)

        if let currentAutoImportedReviewWorkoutID,
           !validWorkoutIDs.contains(currentAutoImportedReviewWorkoutID) {
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
        let allWorkouts = try fetchAllWorkouts(from: modelContext)

        for workout in allWorkouts {
            workout.percentileScores = PercentileScoreService.calculateAllPercentiles(
                for: workout,
                existingWorkouts: allWorkouts
            )
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
        print("DEBUG auto-import queued review workout: \(workout.id.uuidString)")
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

        print("DEBUG auto-import cleared simulated workouts: \(workouts.count)")
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
