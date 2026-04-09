//
//  WorkoutImportCoordinator.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import FirebaseAuth
import Foundation
import HealthKit
import SwiftData
import Observation

enum ImportRefreshTrigger {
    case automatic
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

@MainActor
@Observable
final class WorkoutImportCoordinator {
    static let shared = WorkoutImportCoordinator()

    enum ImportOutcome {
        case imported(Workout)
        case updatedExisting(Workout)
        case failed(candidateID: String)
    }

    struct ExistingWorkoutIndex {
        let allWorkouts: [Workout]
        let appleHealthWorkoutsByID: [String: Workout]
        let hevyWorkoutsByID: [String: Workout]

        func workout(forAppleHealthID externalRecordID: String) -> Workout? {
            appleHealthWorkoutsByID[externalRecordID]
        }

        func workout(forHevyID externalRecordID: String) -> Workout? {
            hevyWorkoutsByID[externalRecordID]
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
    private let hevyManager: HevyManager
    private let telemetry: TelemetryManager
    private let leaderboardService = LeaderboardService.shared

    private var modelContext: ModelContext?
    private var lastAutomaticCheckAt: Date?

    init(
        authorizationController: any HealthKitAuthorizationControlling = HealthKitAuthorizationClient.shared,
        workoutReader: any HealthKitWorkoutReading = HealthKitWorkoutReader.shared,
        metricsReader: any HealthKitMetricsReading = HealthKitMetricsReader.shared,
        hevyManager: HevyManager = .shared,
        telemetry: TelemetryManager = .shared
    ) {
        self.authorizationController = authorizationController
        self.workoutReader = workoutReader
        self.metricsReader = metricsReader
        self.hevyManager = hevyManager
        self.telemetry = telemetry
        self.lastCheckAt = HealthKitSyncState.lastSuccessfulCheckAt
    }

    var pendingCount: Int {
        pendingCandidates.count
    }

    var appleHealthPendingCount: Int {
        pendingCandidates.filter { $0.sourceProviders.contains(.appleHealth) }.count
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
        } catch {
            lastErrorMessage = error.localizedDescription
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

        let didRefresh = await performAppleHealthRefreshIfNeeded(trigger: .manualSync)
        if didRefresh {
            lastErrorMessage = nil
        }
        return didRefresh
    }

    func refreshPendingImports(trigger: ImportRefreshTrigger) async {
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
            _ = await performAppleHealthRefreshIfNeeded(trigger: trigger)

            let existingIndex = try buildExistingWorkoutIndex(modelContext: modelContext)
            pendingCandidates = try await buildPendingCandidates(existingIndex: existingIndex)
            lastCheckAt = Date()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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

    private func performAppleHealthRefreshIfNeeded(trigger: ImportRefreshTrigger) async -> Bool {
        guard authorizationController.isHealthDataAvailable else { return false }

        let isExplicitRefresh = trigger == .manualReview || trigger == .manualSync

        if authorizationController.connectionState == .revoked {
            return false
        }

        if !authorizationController.hasRequestedAuthorization {
            guard isExplicitRefresh else { return false }
            let granted = await authorizationController.requestAuthorization()
            if !granted {
                lastErrorMessage = authorizationController.lastPermissionErrorMessage
                return false
            }
        }

        if !authorizationController.hasCompletedInitialBackfill {
            guard isExplicitRefresh else { return false }
        }

        do {
            let result = try await workoutReader.fetchAnchoredStairStepperWorkouts(
                anchorData: HealthKitSyncState.workoutAnchorData
            )
            HealthKitSyncState.updateCachedWorkoutSamples(
                added: result.addedSamples,
                deletedExternalRecordIDs: result.deletedExternalRecordIDs
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

    private func buildPendingCandidates(existingIndex: ExistingWorkoutIndex) async throws -> [ImportedWorkoutCandidate] {
        let appleSamples = HealthKitSyncState.cachedWorkoutSamples.sorted { $0.startDate > $1.startDate }
        let hevyMetricType = HevySyncState.templateType == "floors" ? WorkoutMetric.floors : WorkoutMetric.steps

        var matchedAppleIDs = Set<String>()
        var candidates: [ImportedWorkoutCandidate] = []

        for workout in existingIndex.hevyWorkoutsByID.values.sorted(by: { $0.date > $1.date }) {
            guard !hasAppleHealthLink(workout) else { continue }

            let hevyWorkoutID = hevyExternalID(for: workout)
            guard let hevyWorkoutID else { continue }

            guard let sample = matchAppleHealthSample(
                toWorkoutWindowStart: hevyWindowStart(for: workout),
                workoutWindowEnd: hevyWindowEnd(for: workout),
                expectedDuration: workout.duration,
                candidates: appleSamples,
                matchedAppleIDs: matchedAppleIDs,
                allowImportedAppleWorkout: false,
                existingIndex: existingIndex
            ) else {
                continue
            }

            matchedAppleIDs.insert(sample.externalRecordID)
            candidates.append(
                ImportedWorkoutCandidate.hevy(
                    workoutID: hevyWorkoutID,
                    workoutTitle: workout.name,
                    startDate: hevyWindowStart(for: workout),
                    endDate: hevyWindowEnd(for: workout),
                    duration: workout.duration,
                    metricValue: hevyMetricType == .floors ? workout.floors : workout.steps,
                    metricType: hevyMetricType,
                    matchingAppleHealthSample: sample,
                    existingWorkoutID: workout.id
                )
            )
        }

        if hevyManager.isConnected {
            let exercises = try await hevyManager.fetchExerciseHistory()

            for exercise in exercises {
                guard !isHevyImported(exercise.workout_id, existingIndex: existingIndex) else { continue }
                guard let startDate = exercise.startDate else { continue }

                let endDate = resolvedHevyWindowEnd(for: exercise)
                let matchingSample: HealthKitWorkoutSample?
                if hevyManager.autoLinkAppleHealth && appleHealthConnectionState == .connected {
                    matchingSample = matchAppleHealthSample(
                        toWorkoutWindowStart: startDate,
                        workoutWindowEnd: endDate,
                        expectedDuration: exercise.duration,
                        candidates: appleSamples,
                        matchedAppleIDs: matchedAppleIDs,
                        allowImportedAppleWorkout: true,
                        existingIndex: existingIndex
                    )
                } else {
                    matchingSample = nil
                }

                if let matchingSample {
                    matchedAppleIDs.insert(matchingSample.externalRecordID)
                }

                candidates.append(
                    ImportedWorkoutCandidate.hevy(
                        workoutID: exercise.workout_id,
                        workoutTitle: exercise.workout_title,
                        startDate: startDate,
                        endDate: endDate,
                        duration: exercise.duration,
                        metricValue: exercise.metricValue,
                        metricType: hevyMetricType,
                        matchingAppleHealthSample: matchingSample
                    )
                )
            }
        }

        for sample in appleSamples where !matchedAppleIDs.contains(sample.externalRecordID) {
            guard !isAppleHealthImported(sample.externalRecordID, existingIndex: existingIndex) else { continue }
            candidates.append(.appleHealth(sample: sample))
        }

        return candidates.sorted { lhs, rhs in
            lhs.startDate > rhs.startDate
        }
    }

    private func matchAppleHealthSample(
        toWorkoutWindowStart workoutWindowStart: Date,
        workoutWindowEnd: Date?,
        expectedDuration: TimeInterval,
        candidates: [HealthKitWorkoutSample],
        matchedAppleIDs: Set<String>,
        allowImportedAppleWorkout: Bool,
        existingIndex: ExistingWorkoutIndex
    ) -> HealthKitWorkoutSample? {
        let workoutWindowEnd = workoutWindowEnd ?? workoutWindowStart.addingTimeInterval(expectedDuration)
        guard workoutWindowEnd > workoutWindowStart else { return nil }

        let tolerance: TimeInterval = 5 * 60
        let durationTolerance = max(10 * 60, expectedDuration * 0.25)

        let matches = candidates.filter { candidate in
            guard !matchedAppleIDs.contains(candidate.externalRecordID) else { return false }
            guard !isAppleHealthLinkedToHevy(candidate.externalRecordID, existingIndex: existingIndex) else { return false }

            if !allowImportedAppleWorkout && isAppleHealthImported(candidate.externalRecordID, existingIndex: existingIndex) {
                return false
            }

            let startsWithinWindow = candidate.startDate >= workoutWindowStart.addingTimeInterval(-tolerance) &&
                candidate.startDate <= workoutWindowEnd.addingTimeInterval(tolerance)
            guard startsWithinWindow else { return false }

            guard expectedDuration > 0 else { return true }
            let durationDifference = abs(candidate.duration - expectedDuration)
            return durationDifference <= durationTolerance
        }

        guard matches.count == 1 else { return nil }
        return matches.first
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
                return try await importAppleHealthCandidate(candidate, modelContext: modelContext)
            case .hevy, .linkedHevyAppleHealth:
                return try await importHevyCandidate(
                    candidate,
                    modelContext: modelContext,
                    existingIndex: existingIndex
                )
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
        let settings = SettingsManager.shared
        let workout = hkWorkout.toAscendWorkout(with: metrics, stepsPerFloor: settings.stepsPerFloor)
        let appleHealthLink = makeAppleHealthSourceLink(from: sample, workout: workout)

        modelContext.insert(workout)
        modelContext.insert(appleHealthLink)
        try modelContext.save()

        return .imported(workout)
    }

    private func importHevyCandidate(
        _ candidate: ImportedWorkoutCandidate,
        modelContext: ModelContext,
        existingIndex: ExistingWorkoutIndex
    ) async throws -> ImportOutcome {
        guard let hevyWorkoutID = candidate.hevyWorkoutID,
              let hevyWindowStart = candidate.hevyWorkoutWindowStart else {
            return .failed(candidateID: candidate.id)
        }

        let stepsPerFloor = SettingsManager.shared.stepsPerFloor
        let metricType = candidate.hevyMetricType ?? .steps
        let metricValue = candidate.hevyMetricValue ?? 0
        let steps: Int
        let floors: Int

        if metricType == .floors {
            floors = metricValue
            steps = Workout.floorsToSteps(metricValue, stepsPerFloor: stepsPerFloor)
        } else {
            steps = metricValue
            floors = Workout.stepsToFloors(metricValue, stepsPerFloor: stepsPerFloor)
        }

        if let existingWorkoutID = candidate.existingWorkoutID,
           let existingWorkout = existingIndex.allWorkouts.first(where: { $0.id == existingWorkoutID }) {
            applyHevyOwnership(
                to: existingWorkout,
                title: candidate.hevyWorkoutTitle,
                duration: candidate.duration,
                steps: steps,
                floors: floors,
                hevyWorkoutID: hevyWorkoutID
            )

            if let appleHealthSample = candidate.appleHealthSample,
               let hkWorkout = try await workoutReader.fetchWorkout(withExternalRecordID: appleHealthSample.externalRecordID) {
                let metrics = await metricsReader.fetchMetrics(for: hkWorkout)
                applyAppleHealthMetrics(metrics, from: appleHealthSample, to: existingWorkout)
                ensureAppleHealthLinkExists(
                    sample: appleHealthSample,
                    for: existingWorkout,
                    modelContext: modelContext
                )
            }

            ensureHevyLinkExists(
                workoutID: hevyWorkoutID,
                windowStart: hevyWindowStart,
                windowEnd: candidate.hevyWorkoutWindowEnd ?? hevyWindowStart.addingTimeInterval(candidate.duration),
                title: candidate.displayName,
                metricType: metricType,
                metricValue: metricValue,
                for: existingWorkout,
                modelContext: modelContext
            )

            try modelContext.save()
            return .updatedExisting(existingWorkout)
        }

        if let existingWorkout = existingIndex.workout(forHevyID: hevyWorkoutID) {
            applyHevyOwnership(
                to: existingWorkout,
                title: candidate.hevyWorkoutTitle,
                duration: candidate.duration,
                steps: steps,
                floors: floors,
                hevyWorkoutID: hevyWorkoutID
            )
            try modelContext.save()
            return .updatedExisting(existingWorkout)
        }

        if let appleHealthSample = candidate.appleHealthSample,
           let existingAppleWorkout = existingIndex.workout(forAppleHealthID: appleHealthSample.externalRecordID) {
            applyHevyOwnership(
                to: existingAppleWorkout,
                title: candidate.hevyWorkoutTitle,
                duration: candidate.duration,
                steps: steps,
                floors: floors,
                hevyWorkoutID: hevyWorkoutID
            )
            ensureHevyLinkExists(
                workoutID: hevyWorkoutID,
                windowStart: hevyWindowStart,
                windowEnd: candidate.hevyWorkoutWindowEnd ?? hevyWindowStart.addingTimeInterval(candidate.duration),
                title: candidate.displayName,
                metricType: metricType,
                metricValue: metricValue,
                for: existingAppleWorkout,
                modelContext: modelContext
            )
            try modelContext.save()
            return .updatedExisting(existingAppleWorkout)
        }

        let workout = Workout(
            name: (candidate.hevyWorkoutTitle?.isEmpty == false) ? candidate.hevyWorkoutTitle! : Workout.generateDefaultName(for: candidate.startDate),
            date: candidate.appleHealthSample?.startDate ?? hevyWindowStart,
            duration: candidate.duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: stepsPerFloor,
            source: .hevy,
            hevyWorkoutId: hevyWorkoutID
        )

        modelContext.insert(workout)

        if let appleHealthSample = candidate.appleHealthSample,
           let hkWorkout = try await workoutReader.fetchWorkout(withExternalRecordID: appleHealthSample.externalRecordID) {
            let metrics = await metricsReader.fetchMetrics(for: hkWorkout)
            applyAppleHealthMetrics(metrics, from: appleHealthSample, to: workout)
            ensureAppleHealthLinkExists(sample: appleHealthSample, for: workout, modelContext: modelContext)
        }

        ensureHevyLinkExists(
            workoutID: hevyWorkoutID,
            windowStart: hevyWindowStart,
            windowEnd: candidate.hevyWorkoutWindowEnd ?? hevyWindowStart.addingTimeInterval(candidate.duration),
            title: candidate.displayName,
            metricType: metricType,
            metricValue: metricValue,
            for: workout,
            modelContext: modelContext
        )

        try modelContext.save()

        return .imported(workout)
    }

    private func buildExistingWorkoutIndex(modelContext: ModelContext) throws -> ExistingWorkoutIndex {
        let workouts = try fetchAllWorkouts(from: modelContext)

        var appleHealthWorkoutsByID: [String: Workout] = [:]
        var hevyWorkoutsByID: [String: Workout] = [:]

        for workout in workouts {
            if let healthKitUUID = workout.healthKitUUID {
                appleHealthWorkoutsByID[healthKitUUID] = workout
            }
            if let hevyWorkoutId = workout.hevyWorkoutId {
                hevyWorkoutsByID[hevyWorkoutId] = workout
            }

            for sourceLink in workout.sourceLinks {
                switch sourceLink.provider {
                case .appleHealth:
                    appleHealthWorkoutsByID[sourceLink.externalRecordID] = workout
                case .hevy:
                    hevyWorkoutsByID[sourceLink.externalRecordID] = workout
                case .garmin, .strava, .fitbit:
                    break
                }
            }
        }

        return ExistingWorkoutIndex(
            allWorkouts: workouts,
            appleHealthWorkoutsByID: appleHealthWorkoutsByID,
            hevyWorkoutsByID: hevyWorkoutsByID
        )
    }

    private func isCandidateImported(_ candidate: ImportedWorkoutCandidate, existingIndex: ExistingWorkoutIndex) -> Bool {
        switch candidate.kind {
        case .appleHealth:
            guard let appleHealthSample = candidate.appleHealthSample else { return false }
            return isAppleHealthImported(appleHealthSample.externalRecordID, existingIndex: existingIndex)
        case .hevy:
            guard let hevyWorkoutID = candidate.hevyWorkoutID else { return false }
            return isHevyImported(hevyWorkoutID, existingIndex: existingIndex)
        case .linkedHevyAppleHealth:
            if let existingWorkoutID = candidate.existingWorkoutID,
               let workout = existingIndex.allWorkouts.first(where: { $0.id == existingWorkoutID }),
               let appleHealthSample = candidate.appleHealthSample {
                return workout.hasSourceLink(provider: .appleHealth) &&
                    workout.hasSourceLink(provider: .hevy) &&
                    workout.sourceLink(for: .appleHealth)?.externalRecordID == appleHealthSample.externalRecordID
            }

            guard let hevyWorkoutID = candidate.hevyWorkoutID else { return false }
            let hasHevyWorkout = isHevyImported(hevyWorkoutID, existingIndex: existingIndex)
            let appleLinkedToHevy = candidate.appleHealthSample.map {
                isAppleHealthLinkedToHevy($0.externalRecordID, existingIndex: existingIndex)
            } ?? false
            return hasHevyWorkout && appleLinkedToHevy
        }
    }

    private func isAppleHealthImported(_ externalRecordID: String, existingIndex: ExistingWorkoutIndex) -> Bool {
        existingIndex.workout(forAppleHealthID: externalRecordID) != nil
    }

    private func isHevyImported(_ externalRecordID: String, existingIndex: ExistingWorkoutIndex) -> Bool {
        existingIndex.workout(forHevyID: externalRecordID) != nil
    }

    private func isAppleHealthLinkedToHevy(_ externalRecordID: String, existingIndex: ExistingWorkoutIndex) -> Bool {
        guard let workout = existingIndex.workout(forAppleHealthID: externalRecordID) else { return false }
        return hasHevyLink(workout)
    }

    private func hasAppleHealthLink(_ workout: Workout) -> Bool {
        workout.hasSourceLink(provider: .appleHealth) || workout.healthKitUUID != nil
    }

    private func hasHevyLink(_ workout: Workout) -> Bool {
        workout.hasSourceLink(provider: .hevy) || workout.hevyWorkoutId != nil
    }

    private func hevyExternalID(for workout: Workout) -> String? {
        workout.sourceLink(for: .hevy)?.externalRecordID ?? workout.hevyWorkoutId
    }

    private func hevyWindowStart(for workout: Workout) -> Date {
        workout.sourceLink(for: .hevy)?.providerWindowStart ?? workout.date
    }

    private func hevyWindowEnd(for workout: Workout) -> Date? {
        workout.sourceLink(for: .hevy)?.providerWindowEnd ?? workout.date.addingTimeInterval(workout.duration)
    }

    private func resolvedHevyWindowEnd(for exercise: HevyExerciseHistory) -> Date? {
        if let endDate = exercise.endDate {
            return endDate
        }

        guard let startDate = exercise.startDate, exercise.duration > 0 else {
            return nil
        }

        return startDate.addingTimeInterval(exercise.duration)
    }

    private func applyHevyOwnership(
        to workout: Workout,
        title: String?,
        duration: TimeInterval,
        steps: Int,
        floors: Int,
        hevyWorkoutID: String
    ) {
        workout.name = (title?.isEmpty == false) ? title! : workout.name
        if duration > 0 {
            workout.duration = duration
        }
        workout.steps = steps
        workout.floors = floors
        workout.source = .hevy
        workout.hevyWorkoutId = hevyWorkoutID
        workout.integrityLevel = .verified
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

    private func ensureHevyLinkExists(
        workoutID: String,
        windowStart: Date,
        windowEnd: Date,
        title: String,
        metricType: WorkoutMetric,
        metricValue: Int,
        for workout: Workout,
        modelContext: ModelContext
    ) {
        guard workout.sourceLink(for: .hevy) == nil else { return }

        let link = WorkoutSourceLink(
            provider: .hevy,
            externalRecordID: workoutID,
            providerWindowStart: windowStart,
            providerWindowEnd: windowEnd,
            timingPrecision: .containerWindow,
            sourceName: "Hevy",
            sourceBundleIdentifier: nil,
            deviceModel: nil,
            metadataJSON: hevyMetadataJSON(title: title, metricType: metricType, metricValue: metricValue),
            workout: workout
        )
        modelContext.insert(link)
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

    private func hevyMetadataJSON(title: String, metricType: WorkoutMetric, metricValue: Int) -> String? {
        let payload: [String: Any] = [
            "title": title,
            "metricType": metricType.rawValue,
            "metricValue": metricValue
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

    private func recalculateDerivedData(modelContext: ModelContext, newWorkouts: [Workout] = []) throws {
        let allWorkouts = try fetchAllWorkouts(from: modelContext)
        let settings = SettingsManager.shared

        for workout in allWorkouts {
            workout.percentileScores = PercentileScoreService.calculateAllPercentiles(
                for: workout,
                existingWorkouts: allWorkouts,
                preferredMetric: settings.preferredWorkoutMetric
            )
        }

        // Recalculate PRs and leaderboard stats
        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            newWorkouts: newWorkouts
        )

        try modelContext.save()
    }
}
