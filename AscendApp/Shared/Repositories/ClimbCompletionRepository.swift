import Foundation
import SwiftData

/// The ONE read surface for the completed-climb domain (CANONICAL §3). The UI
/// asks the repository; it never queries Firestore or a raw `ClimbAttempt`
/// `@Query` directly.
///
///     UI ──▶ ClimbCompletionRepository ──▶ Cache (ClimbAttempt) ↕ Firestore
///
/// The repository OWNS the cache: `read` serves the local `ClimbAttempt` cache
/// distinct-per-landmark; `refresh` pulls the server-derived `landmarkResults`
/// projection and reconciles it INTO the cache losslessly. Because the cache is
/// only ever filled by a lossless sync from the authoritative projection,
/// `cache < authoritative` cannot arise - the "never show less than earned"
/// invariant is enforced here, not as a per-screen `max(local, server)`. This is
/// what makes the completed count survive an in-place UPDATE (not just a
/// reinstall): the count is a server read, independent of whether the legacy
/// hydration path ever ran on this install.
@MainActor
final class ClimbCompletionRepository {
    static let shared = ClimbCompletionRepository()

    private let remoteRepository: any ClimbCompletionRemoteRepositoryProtocol

    init(
        remoteRepository: any ClimbCompletionRemoteRepositoryProtocol =
            FirestoreClimbCompletionRemoteRepository.shared
    ) {
        self.remoteRepository = remoteRepository
    }

    /// Cache-first read: the distinct completed-landmark set from the local
    /// `ClimbAttempt` cache. Pure over the store, so it is assertable without a
    /// SwiftUI tree or a configured Firebase.
    func read(modelContext: ModelContext) -> CompletedClimbSet {
        Self.completedClimbSet(modelContext: modelContext)
    }

    /// Pulls `users/{uid}/landmarkResults` into the local cache and returns the
    /// reconciled set. Idempotent and lossless: it only ever ADDS completed
    /// landmarks the cache is missing, never removes or downgrades one, so a
    /// short local cache (the in-place-update gap) is healed to the
    /// server-authoritative set. A transient/offline failure keeps serving the
    /// existing cache rather than dropping earned completions.
    @discardableResult
    func refresh(userId: String, modelContext: ModelContext) async -> CompletedClimbSet {
        do {
            let results = try await remoteRepository.fetchLandmarkResults(userId: userId)
            let didChange = Self.reconcile(
                results,
                userId: userId,
                modelContext: modelContext
            )
            if didChange {
                NotificationCenter.default.post(name: .climbStateDidChange, object: nil)
            }
        } catch {
            // Offline or a transient read error: serve the cache unchanged.
        }
        return read(modelContext: modelContext)
    }

    /// Builds the distinct completed-climb set from the local `ClimbAttempt`
    /// cache. Static + pure - this is the single completed-set definition every
    /// surface reads.
    static func completedClimbSet(modelContext: ModelContext) -> CompletedClimbSet {
        let completedStatus = ClimbAttemptStatus.completed.rawValue
        let descriptor = FetchDescriptor<ClimbAttempt>(
            predicate: #Predicate<ClimbAttempt> { attempt in
                attempt.statusRawValue == completedStatus
            }
        )
        return completedClimbSet(from: (try? modelContext.fetch(descriptor)) ?? [])
    }

    /// Builds the distinct completed-climb set from an in-memory attempt list,
    /// filtering to completed attempts. The single completed-set definition,
    /// shared by the cache read and the profile snapshot builder.
    static func completedClimbSet(from attempts: [ClimbAttempt]) -> CompletedClimbSet {
        let completed = attempts.filter { $0.status == .completed }

        let climbs = Dictionary(grouping: completed, by: \.climbId).map {
            climbId, group -> CompletedClimb in
            let completionDates = group.map(completionDate(for:))
            let bestElapsed = group
                .compactMap { attempt -> Int? in
                    if let best = attempt.bestCompletionDurationSeconds {
                        return best
                    }
                    return attempt.accumulatedDurationSeconds > 0
                        ? attempt.accumulatedDurationSeconds
                        : nil
                }
                .min()
            return CompletedClimb(
                climbId: climbId,
                firstCompletedAt: completionDates.min() ?? Date(),
                latestCompletedAt: completionDates.max() ?? Date(),
                attemptCount: group.count,
                bestElapsedSeconds: bestElapsed
            )
        }

        return CompletedClimbSet(climbs: climbs)
    }

    /// Materializes a completed `ClimbAttempt` for every completed landmark the
    /// cache is missing. Lossless (never deletes or downgrades) and idempotent:
    /// a landmark that already has a completed attempt is left untouched, and a
    /// synthetic attempt is keyed by a deterministic id so a re-run upserts
    /// rather than duplicates (serves I2). Returns whether the cache changed.
    static func reconcile(
        _ results: [RemoteLandmarkResult],
        userId: String,
        modelContext: ModelContext
    ) -> Bool {
        let completedResults = results.filter(\.completed)
        guard !completedResults.isEmpty else { return false }

        let existing = (try? modelContext.fetch(FetchDescriptor<ClimbAttempt>())) ?? []
        var completedClimbIds = Set(
            existing.filter { $0.status == .completed }.map(\.climbId)
        )
        let existingIds = Set(existing.map(\.id))
        var didChange = false

        for result in completedResults where !completedClimbIds.contains(result.climbId) {
            let attemptId = deterministicAttemptId(for: result, userId: userId)
            guard !existingIds.contains(attemptId) else {
                // An attempt with this id already exists but was not counted as
                // completed above; leave it (lossless) and treat the landmark as
                // present so we never insert a duplicate.
                completedClimbIds.insert(result.climbId)
                continue
            }

            let attempt = ClimbAttempt(
                climbId: result.climbId,
                status: .completed,
                startedAt: result.firstCompletedAt,
                endedAt: result.latestCompletedAt,
                completedAt: result.latestCompletedAt,
                accumulatedSteps: 0,
                accumulatedDurationSeconds: result.bestElapsedSeconds ?? 0,
                sessionsCount: max(result.attemptCount, 1),
                appliedWorkoutIds: result.bestWorkoutId.map { [$0] } ?? [],
                bestCompletionDurationSeconds: result.bestElapsedSeconds
            )
            attempt.id = attemptId
            modelContext.insert(attempt)
            completedClimbIds.insert(result.climbId)
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
        return didChange
    }

    private static func completionDate(for attempt: ClimbAttempt) -> Date {
        attempt.completedAt ?? attempt.endedAt ?? attempt.startedAt
    }

    /// The stable id for a synthetic cache row. Keyed off the best workout id
    /// when the projection carries one - which matches the id the legacy
    /// hydration path derives for that same workout, so the two converge on one
    /// attempt instead of two - and off a stable per-landmark seed otherwise.
    private static func deterministicAttemptId(
        for result: RemoteLandmarkResult,
        userId: String
    ) -> UUID {
        let seedWorkoutId = result.bestWorkoutId
            .flatMap { UUID(uuidString: $0) }
            ?? Self.zeroWorkoutSeed
        return LegacyClimbCompletionPredicate.deterministicAttemptId(
            userId: userId,
            legacyWorkoutId: seedWorkoutId,
            climbId: result.climbId
        )
    }

    private static let zeroWorkoutSeed = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    ) ?? UUID()
}
