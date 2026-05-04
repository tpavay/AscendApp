import Foundation
import SwiftData

@MainActor
final class ClimbService {
    static let shared = ClimbService()

    private let catalogRepository: any ClimbCatalogRepository
    private var cachedClimbs: [Climb]?
    private var cachedClimbsByID: [String: Climb] = [:]
    private(set) var featuredClimbId: String?
    private(set) var catalogSource: ClimbCatalogSource = .bootstrap
    private(set) var catalogVersion: Int = 0

    init(catalogRepository: any ClimbCatalogRepository = HostedClimbCatalogRepository()) {
        self.catalogRepository = catalogRepository
    }

    func loadClimbs() throws -> [Climb] {
        if let cachedClimbs {
            return cachedClimbs
        }

        let snapshot = try catalogRepository.loadInitialCatalog()
        cache(snapshot: snapshot)
        return snapshot.publishedClimbs
    }

    @discardableResult
    func refreshCatalogIfNeeded() async throws -> Bool {
        let existingVersion = catalogVersion
        let existingFeaturedClimbId = featuredClimbId
        let existingClimbs = cachedClimbs ?? []

        let snapshot = try await catalogRepository.refreshCatalog()
        cache(snapshot: snapshot)

        let didChange = existingVersion != snapshot.catalogVersion ||
            existingFeaturedClimbId != snapshot.featuredClimbId ||
            existingClimbs != snapshot.publishedClimbs

        if didChange {
            postCatalogChangeNotification()
        }

        return didChange
    }

    func climb(for id: String) throws -> Climb? {
        if cachedClimbs == nil {
            _ = try loadClimbs()
        }
        return cachedClimbsByID[id]
    }

    func homeCardState(modelContext: ModelContext) throws -> ClimbHomeCardState {
        let climbs = try loadClimbs()

        if let activeSummary = try activeSummary(modelContext: modelContext) {
            return .active(activeSummary)
        }

        if let lastCompletedSummary = try lastCompletedSummary(modelContext: modelContext) {
            return .inactive(lastCompletedSummary)
        }

        return .neverClimbed(totalClimbs: climbs.count)
    }

    func completedClimbIds(modelContext: ModelContext) -> Set<String> {
        let attempts = fetchAttempts(modelContext: modelContext)
        return Set(
            attempts
                .filter { $0.status == .completed }
                .map(\.climbId)
        )
    }

    func collectionCount(modelContext: ModelContext) -> Int {
        completedClimbIds(modelContext: modelContext).count
    }

    func activeSummary(modelContext: ModelContext) throws -> ActiveClimbSummary? {
        guard let attempt = try activeAttempt(modelContext: modelContext),
              let climb = try climb(for: attempt.climbId) else {
            return nil
        }

        guard shouldSurfaceActiveAttempt(attempt, climb: climb) else {
            return nil
        }

        return ActiveClimbSummary(
            attemptId: attempt.id,
            climb: climb,
            accumulatedSteps: attempt.accumulatedSteps,
            requiredSteps: climb.referenceStepCount,
            accumulatedDurationSeconds: attempt.accumulatedDurationSeconds,
            sessionsCount: attempt.sessionsCount,
            startedAt: attempt.startedAt,
            projectedCollectionOrder: projectedCollectionOrder(for: climb, modelContext: modelContext)
        )
    }

    func previewSummary(for climb: Climb, modelContext: ModelContext) -> ClimbPreviewSummary {
        let completedClimbIds = completedClimbIds(modelContext: modelContext)
        let activeClimbId: String?
        if let activeAttempt = try? activeAttempt(modelContext: modelContext) {
            activeClimbId = activeAttempt.climbId
        } else {
            activeClimbId = nil
        }

        return ClimbPreviewSummary(
            climb: climb,
            isCompleted: completedClimbIds.contains(climb.id),
            isActive: activeClimbId == climb.id
        )
    }

    func lastCompletedSummary(modelContext: ModelContext) throws -> CompletedClimbSummary? {
        let climbs = try loadClimbs()
        let totalClimbs = climbs.count
        let completedAttempts = fetchAttempts(modelContext: modelContext)
            .filter { $0.status == .completed }
            .sorted { lhs, rhs in
                Self.attemptSortDate(for: lhs) > Self.attemptSortDate(for: rhs)
            }

        guard let lastAttempt = completedAttempts.first,
              let climb = try climb(for: lastAttempt.climbId) else {
            return nil
        }

        let attemptsForClimb = completedAttempts.filter { $0.climbId == climb.id }
        let bestDuration = attemptsForClimb
            .compactMap { $0.bestCompletionDurationSeconds ?? $0.accumulatedDurationSeconds }
            .min()

        return CompletedClimbSummary(
            climb: climb,
            completedAt: Self.attemptSortDate(for: lastAttempt),
            completionsCount: attemptsForClimb.count,
            bestCompletionDurationSeconds: bestDuration,
            collectionCount: Set(completedAttempts.map(\.climbId)).count,
            totalClimbs: totalClimbs,
            collectionOrder: collectionOrder(for: climb, modelContext: modelContext)
        )
    }

    func historySummary(for climb: Climb, modelContext: ModelContext) -> ClimbHistorySummary {
        let relevantAttempts = fetchAttempts(modelContext: modelContext)
            .filter { $0.climbId == climb.id && ($0.status == .completed || $0.status == .failed) }
            .sorted { lhs, rhs in
                Self.attemptSortDate(for: lhs) > Self.attemptSortDate(for: rhs)
            }

        let completedAttempts = fetchAttempts(modelContext: modelContext)
            .filter { $0.climbId == climb.id && $0.status == .completed }
            .sorted { lhs, rhs in
                Self.attemptSortDate(for: lhs) > Self.attemptSortDate(for: rhs)
            }

        let bestDuration = completedAttempts
            .compactMap { $0.bestCompletionDurationSeconds ?? $0.accumulatedDurationSeconds }
            .min()

        let recentEntries = relevantAttempts.prefix(8).map { attempt in
            let duration = attempt.bestCompletionDurationSeconds ?? attempt.accumulatedDurationSeconds
            return ClimbHistoryEntry(
                attemptId: attempt.id,
                status: attempt.status,
                date: Self.attemptSortDate(for: attempt),
                durationSeconds: duration,
                recordedSteps: attempt.accumulatedSteps,
                totalSteps: climb.referenceStepCount,
                isPersonalBest: attempt.status == .completed && duration == bestDuration
            )
        }

        return ClimbHistorySummary(
            climb: climb,
            attemptsCount: relevantAttempts.count,
            completionsCount: completedAttempts.count,
            failedAttemptsCount: relevantAttempts.filter { $0.status == .failed }.count,
            bestCompletionDurationSeconds: bestDuration,
            recentEntries: recentEntries
        )
    }

    func startClimb(_ climb: Climb, modelContext: ModelContext) throws -> ClimbAttempt {
        if let activeAttempt = try activeAttempt(modelContext: modelContext) {
            guard activeAttempt.climbId == climb.id else {
                throw StartError.activeClimbConflict
            }
            return activeAttempt
        }

        let attempt = ClimbAttempt(climbId: climb.id)
        modelContext.insert(attempt)
        try modelContext.save()
        postStateChangeNotification()
        return attempt
    }

    func replaceActiveClimb(with climb: Climb, modelContext: ModelContext) throws -> ClimbAttempt {
        if let activeAttempt = storedActiveAttempt(modelContext: modelContext) {
            if activeAttempt.climbId == climb.id {
                return activeAttempt
            }

            activeAttempt.status = .abandoned
            activeAttempt.endedAt = Date()
        }

        let attempt = ClimbAttempt(climbId: climb.id)
        modelContext.insert(attempt)
        try modelContext.save()
        postStateChangeNotification()
        return attempt
    }

    @discardableResult
    func abandonActiveClimb(modelContext: ModelContext) throws -> Bool {
        guard let activeAttempt = try activeAttempt(modelContext: modelContext) else {
            return false
        }

        activeAttempt.status = .abandoned
        activeAttempt.endedAt = Date()
        try modelContext.save()
        postStateChangeNotification()
        return true
    }

    func prepareLiveClimbAttempt(
        for climb: Climb,
        startedAt: Date,
        replacingActiveClimb: Bool,
        modelContext: ModelContext
    ) throws -> ClimbAttempt {
        let attempts = fetchAttempts(modelContext: modelContext)

        if let activeAttempt = attempts.first(where: { $0.status == .active }) {
            if activeAttempt.climbId == climb.id {
                return activeAttempt
            }

            if let activeClimb = try self.climb(for: activeAttempt.climbId),
               isUnrecordedSingleSessionAttempt(activeAttempt, climb: activeClimb) {
                activeAttempt.status = .abandoned
                activeAttempt.endedAt = startedAt
            } else {
                guard replacingActiveClimb else {
                    throw StartError.activeClimbConflict
                }

                activeAttempt.status = .abandoned
                activeAttempt.endedAt = startedAt
            }
        }

        let attempt = ClimbAttempt(climbId: climb.id, startedAt: startedAt)
        modelContext.insert(attempt)
        try modelContext.save()
        postStateChangeNotification()
        return attempt
    }

    func apply(workouts: [Workout], modelContext: ModelContext) throws {
        guard !workouts.isEmpty,
              let activeAttempt = storedActiveAttempt(modelContext: modelContext),
              let climb = try climb(for: activeAttempt.climbId) else {
            return
        }

        let sortedWorkouts = workouts.sorted {
            Self.sessionStartDate(for: $0) < Self.sessionStartDate(for: $1)
        }
        var appliedWorkoutIds = activeAttempt.appliedWorkoutIds
        var didChange = false

        for workout in sortedWorkouts {
            guard Self.isEligibleForActiveClimb(workout, startedAt: activeAttempt.startedAt) else { continue }

            let workoutIdentifier = workout.id.uuidString
            guard !appliedWorkoutIds.contains(workoutIdentifier) else { continue }

            appliedWorkoutIds.append(workoutIdentifier)
            activeAttempt.appliedWorkoutIds = appliedWorkoutIds
            activeAttempt.accumulatedSteps = min(
                climb.referenceStepCount,
                activeAttempt.accumulatedSteps + workout.steps
            )
            activeAttempt.accumulatedDurationSeconds += Int(workout.duration.rounded())
            activeAttempt.sessionsCount += 1
            didChange = true

            try WorkoutParticipationService.addClimbAttemptParticipationIfNeeded(
                for: workout,
                attempt: activeAttempt,
                userId: workout.ownerUserId,
                leaderboardEligible: false,
                modelContext: modelContext
            )

            if activeAttempt.accumulatedSteps >= climb.referenceStepCount {
                activeAttempt.status = .completed
                activeAttempt.endedAt = Self.sessionEndDate(for: workout)
                activeAttempt.completedAt = Self.sessionEndDate(for: workout)
                activeAttempt.bestCompletionDurationSeconds = activeAttempt.accumulatedDurationSeconds
                activeAttempt.completedInSingleSessionMulti = climb.multiSession && activeAttempt.sessionsCount == 1
                try WorkoutParticipationService.setLeaderboardEligibility(
                    true,
                    forClimbAttemptId: activeAttempt.id,
                    modelContext: modelContext
                )
                break
            }

            if climb.isSingleSession {
                activeAttempt.status = .failed
                activeAttempt.endedAt = Self.sessionEndDate(for: workout)
                activeAttempt.completedAt = nil
                activeAttempt.bestCompletionDurationSeconds = nil
                activeAttempt.completedInSingleSessionMulti = false
                break
            }
        }

        guard didChange else { return }

        try modelContext.save()
        postStateChangeNotification()
    }

    static func isEligibleForActiveClimb(_ workout: Workout, startedAt: Date) -> Bool {
        workout.source == .headphoneMotion &&
            sessionStartDate(for: workout) >= startedAt
    }

    static func sessionStartDate(for workout: Workout) -> Date {
        workout.date
    }

    static func sessionEndDate(for workout: Workout) -> Date {
        workout.date.addingTimeInterval(workout.duration)
    }

    static func attemptSortDate(for attempt: ClimbAttempt) -> Date {
        attempt.endedAt ?? attempt.completedAt ?? attempt.startedAt
    }

    enum LoadError: LocalizedError {
        case missingBundledData

        var errorDescription: String? {
            switch self {
            case .missingBundledData:
                return "The bundled climbs catalog could not be found."
            }
        }
    }

    enum StartError: LocalizedError {
        case activeClimbConflict

        var errorDescription: String? {
            switch self {
            case .activeClimbConflict:
                return "Another climb is already active."
            }
        }
    }

    func activeAttempt(modelContext: ModelContext) throws -> ClimbAttempt? {
        let activeAttempts = fetchAttempts(modelContext: modelContext).filter { $0.status == .active }

        for attempt in activeAttempts {
            guard let climb = try climb(for: attempt.climbId) else {
                return attempt
            }

            if isUnrecordedSingleSessionAttempt(attempt, climb: climb) {
                continue
            }

            return attempt
        }

        return nil
    }

    private func storedActiveAttempt(modelContext: ModelContext) -> ClimbAttempt? {
        fetchAttempts(modelContext: modelContext).first { $0.status == .active }
    }

    func collectionOrder(for climb: Climb, modelContext: ModelContext) -> Int? {
        let orderedUniqueClimbIDs = fetchAttempts(modelContext: modelContext)
            .filter { $0.status == .completed }
            .sorted { lhs, rhs in
                Self.attemptSortDate(for: lhs) < Self.attemptSortDate(for: rhs)
            }
            .reduce(into: [String]()) { orderedIDs, attempt in
                guard !orderedIDs.contains(attempt.climbId) else { return }
                orderedIDs.append(attempt.climbId)
            }

        guard let index = orderedUniqueClimbIDs.firstIndex(of: climb.id) else {
            return nil
        }

        return index + 1
    }

    func projectedCollectionOrder(for climb: Climb, modelContext: ModelContext) -> Int {
        if let existingOrder = collectionOrder(for: climb, modelContext: modelContext) {
            return existingOrder
        }

        return completedClimbIds(modelContext: modelContext).count + 1
    }

    private func fetchAttempts(modelContext: ModelContext) -> [ClimbAttempt] {
        let descriptor = FetchDescriptor<ClimbAttempt>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func cache(snapshot: ClimbCatalogSnapshot) {
        let publishedClimbs = snapshot.publishedClimbs
        cachedClimbs = publishedClimbs
        cachedClimbsByID = Dictionary(uniqueKeysWithValues: publishedClimbs.map { ($0.id, $0) })
        featuredClimbId = snapshot.featuredClimbId
        catalogSource = snapshot.source
        catalogVersion = snapshot.catalogVersion
    }

    private func postStateChangeNotification() {
        NotificationCenter.default.post(name: .climbStateDidChange, object: nil)
    }

    private func postCatalogChangeNotification() {
        NotificationCenter.default.post(name: .climbCatalogDidChange, object: nil)
    }

    private func shouldSurfaceActiveAttempt(_ attempt: ClimbAttempt, climb: Climb) -> Bool {
        !isUnrecordedSingleSessionAttempt(attempt, climb: climb)
    }

    private func isUnrecordedSingleSessionAttempt(_ attempt: ClimbAttempt, climb: Climb) -> Bool {
        climb.isSingleSession &&
            attempt.status == .active &&
            attempt.sessionsCount == 0 &&
            attempt.accumulatedSteps == 0
    }
}
