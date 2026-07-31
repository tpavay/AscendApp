import Foundation

/// Durable local copy of the server's `completionSnapshots/{workoutId}` document.
///
/// A completed climb's rank is permanent competitive history: once the server has ranked a workout,
/// the position *and* the denominator are settled for that workout forever. Nothing about a later
/// climber changes what the user placed on the day they finished. So the completed-climb detail and
/// summary surfaces read the value once, keep it, and never ask the network again.
///
/// This deliberately stores only server-authored snapshots. A rank recomputed against today's rows
/// is a *current* standing, not the workout's frozen result, and must never be written here - see
/// `LiveClimbSummaryRankHero`, which keeps the two apart on screen.
///
/// Backed by `UserDefaults`, which account deletion already wipes wholesale
/// (`AppAccountDeletionLocalCleanup.clearUserDefaults`). `@unchecked Sendable` because
/// `UserDefaults` is thread-safe but not yet annotated as such.
struct FrozenCompletionRankStore: @unchecked Sendable {
    /// Bound on retained records. Each is well under 200 bytes, and a climber accumulates one per
    /// finished session, so this is a runaway guard rather than a working limit.
    static let maxRecordCount = 500

    private struct Record: Codable, Equatable {
        var contextKey: String
        var workoutId: String
        var rank: Int
        var completedCount: Int
        var completionDurationSeconds: TimeInterval
        var rankedAt: Date?
        var rankingMetric: String
        var tiePolicy: String
        /// When this device froze the record. Only used to decide what to evict.
        var frozenAt: Date

        var snapshot: LiveReplayCompletionRankSnapshot {
            LiveReplayCompletionRankSnapshot(
                workoutId: workoutId,
                rank: rank,
                completedCount: completedCount,
                completionDurationSeconds: completionDurationSeconds,
                rankedAt: rankedAt,
                rankingMetric: rankingMetric,
                tiePolicy: tiePolicy
            )
        }
    }

    private let defaults: UserDefaults
    private let key: String
    private let now: @Sendable () -> Date

    init(
        defaults: UserDefaults = .standard,
        key: String = "liveReplay.frozenCompletionRanks",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    func snapshot(
        contextKey: String,
        workoutId: String
    ) -> LiveReplayCompletionRankSnapshot? {
        guard let storageKey = storageKey(contextKey: contextKey, workoutId: workoutId) else {
            return nil
        }

        return loadRecords()[storageKey]?.snapshot
    }

    /// Writes the server snapshot once. A frozen record is immutable: a second server read that
    /// disagrees is a later recomputation, not a correction, and must not overwrite what the user
    /// has already been shown as permanent.
    @discardableResult
    func freeze(
        _ snapshot: LiveReplayCompletionRankSnapshot,
        contextKey: String
    ) -> LiveReplayCompletionRankSnapshot {
        guard let storageKey = storageKey(
            contextKey: contextKey,
            workoutId: snapshot.workoutId
        ) else {
            return snapshot
        }

        var records = loadRecords()
        if let existing = records[storageKey] {
            return existing.snapshot
        }

        records[storageKey] = Record(
            contextKey: contextKey,
            workoutId: snapshot.workoutId,
            rank: snapshot.rank,
            completedCount: snapshot.completedCount,
            completionDurationSeconds: snapshot.completionDurationSeconds,
            rankedAt: snapshot.rankedAt,
            rankingMetric: snapshot.rankingMetric,
            tiePolicy: snapshot.tiePolicy,
            frozenAt: now()
        )

        saveRecords(trimmed(records))
        return snapshot
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }

    private func storageKey(contextKey: String, workoutId: String) -> String? {
        let trimmedContextKey = contextKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkoutId = workoutId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContextKey.isEmpty, !trimmedWorkoutId.isEmpty else { return nil }

        return "\(trimmedContextKey)|\(trimmedWorkoutId)"
    }

    private func trimmed(_ records: [String: Record]) -> [String: Record] {
        guard records.count > Self.maxRecordCount else { return records }

        let retainedKeys = Set(
            records
                .sorted { $0.value.frozenAt > $1.value.frozenAt }
                .prefix(Self.maxRecordCount)
                .map(\.key)
        )

        return records.filter { retainedKeys.contains($0.key) }
    }

    private func loadRecords() -> [String: Record] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return [:]
        }

        return records
    }

    private func saveRecords(_ records: [String: Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
