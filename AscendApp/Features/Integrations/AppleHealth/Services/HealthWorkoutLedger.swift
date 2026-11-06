import Foundation
import SwiftData

/// Every question the import feature asks of its own records, and the writes that keep them true.
///
/// All of it is bounded by a predicate: the ledger grows by one row per Health workout for the
/// life of the account, so nothing here may scan it from a screen's `.task`.
@MainActor
struct HealthWorkoutLedger {
    let modelContext: ModelContext

    // MARK: - Reads

    func record(forUUID uuid: String) throws -> HealthWorkoutRecord? {
        var descriptor = FetchDescriptor<HealthWorkoutRecord>(
            predicate: #Predicate { $0.workoutUUID == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// The row that became this climb, if any.
    func record(forImportedWorkoutID workoutID: UUID) throws -> HealthWorkoutRecord? {
        let target: UUID? = workoutID
        var descriptor = FetchDescriptor<HealthWorkoutRecord>(
            predicate: #Predicate { $0.importedWorkoutID == target }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// A climb already carrying this Health workout's UUID: the dedupe that survives a reinstall.
    ///
    /// The ledger is local, but `healthKitUUID` travels with the climb through the cloud backup,
    /// so a restored climb still stops its own workout from importing a second time.
    func climb(withHealthKitUUID uuid: String) throws -> Workout? {
        let target: String? = uuid
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.healthKitUUID == target }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func climb(withID id: UUID) throws -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Workouts waiting for the climber, newest first.
    func notImported() throws -> [HealthWorkoutRecord] {
        let state = HealthWorkoutImportState.notImported.rawValue
        return try modelContext.fetch(
            FetchDescriptor<HealthWorkoutRecord>(
                predicate: #Predicate { $0.stateRawValue == state },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        )
    }

    /// The rows the Imports screen lists - waiting and imported - newest first.
    func importsScreenRecords() throws -> [HealthWorkoutRecord] {
        let notImported = HealthWorkoutImportState.notImported.rawValue
        let imported = HealthWorkoutImportState.imported.rawValue
        return try modelContext.fetch(
            FetchDescriptor<HealthWorkoutRecord>(
                predicate: #Predicate { $0.stateRawValue == notImported || $0.stateRawValue == imported },
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
        )
    }

    /// The steps and time of these climbs, and nothing else: a `Workout` carries its heart-rate
    /// series inline, so the rest of the row is never loaded.
    func climbMeasurements(forIDs ids: [UUID]) throws -> [UUID: (steps: Int, duration: TimeInterval)] {
        guard !ids.isEmpty else { return [:] }
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { ids.contains($0.id) })
        descriptor.propertiesToFetch = [\.id, \.steps, \.duration]
        let climbs = try modelContext.fetch(descriptor)
        return Dictionary(
            climbs.map { ($0.id, (steps: $0.steps, duration: $0.duration)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func notImportedCount() throws -> Int {
        let state = HealthWorkoutImportState.notImported.rawValue
        return try modelContext.fetchCount(
            FetchDescriptor<HealthWorkoutRecord>(predicate: #Predicate { $0.stateRawValue == state })
        )
    }

    /// The number on the red badge: waiting workouts from the last seven days that Ascend found
    /// after Imports was last opened. Opening Imports empties it even if nothing is imported, which
    /// is why the cut is the last-viewed time and not the row's state.
    ///
    /// The last-viewed cut is on when Ascend found the workout, not when it started: a watch can
    /// hand a workout to the phone long after it ended, and one that started before the climber's
    /// last visit is still news the first time Ascend sees it.
    func badgeCount(now: Date, importsLastViewedAt: Date?) throws -> Int {
        let state = HealthWorkoutImportState.notImported.rawValue
        let weekAgo = now.addingTimeInterval(-AppleHealthImportPolicy.badgeWindow)
        let lastViewed = importsLastViewedAt ?? .distantPast
        return try modelContext.fetchCount(
            FetchDescriptor<HealthWorkoutRecord>(
                predicate: #Predicate {
                    $0.stateRawValue == state && $0.startDate > weekAgo && $0.discoveredAt > lastViewed
                }
            )
        )
    }

    /// The most recent automatic import the Home strip has not yet retired, or nil.
    func pendingNoticeRecord(now: Date) throws -> HealthWorkoutRecord? {
        let imported = HealthWorkoutImportState.imported.rawValue
        let earliest = now.addingTimeInterval(-AppleHealthImportPolicy.noticeLifetime)
        var descriptor = FetchDescriptor<HealthWorkoutRecord>(
            predicate: #Predicate {
                $0.homeNoticePending && $0.stateRawValue == imported && $0.discoveredAt > earliest
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func clearPendingNotices() throws {
        let descriptor = FetchDescriptor<HealthWorkoutRecord>(
            predicate: #Predicate { $0.homeNoticePending }
        )
        let pending = try modelContext.fetch(descriptor)
        guard !pending.isEmpty else { return }
        for record in pending {
            record.homeNoticePending = false
        }
        try modelContext.save()
    }

    /// An Ascend live climb whose window this workout's window overlaps by a minute or more.
    ///
    /// Bounded to the live climbs that could possibly reach the workout: one starting within a
    /// day before it, which is the longest a climb can run.
    func overlappingLiveClimb(start: Date, end: Date) throws -> Workout? {
        let live = WorkoutSource.headphoneMotion.rawValue
        let earliestStart = start.addingTimeInterval(-ClimbPacePolicy.maximumDuration)
        let candidates = try modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate {
                    $0.sourceRawValue == live && $0.date >= earliestStart && $0.date < end
                }
            )
        )
        return candidates.first { candidate in
            AppleHealthImportPolicy.windowsOverlap(
                start,
                end,
                candidate.date,
                candidate.date.addingTimeInterval(candidate.duration)
            )
        }
    }

    /// Whether a headphone session that has not saved its climb yet - still recording, or waiting
    /// to be recovered after the app died - covers this workout's window by a minute or more.
    ///
    /// Such a workout is neither a climb nor an overlap yet: the live climb that will cover it
    /// does not exist until the session saves, so the workout waits and is checked again then.
    func overlapsUnsavedLiveSession(start: Date, end: Date) throws -> Bool {
        let drafts = try modelContext.fetch(
            FetchDescriptor<ActiveHeadphoneWorkoutDraft>(
                predicate: #Predicate { $0.startedAt < end && $0.lastCheckpointAt > start }
            )
        )
        return drafts.contains { draft in
            AppleHealthImportPolicy.windowsOverlap(start, end, draft.startedAt, draft.lastCheckpointAt)
        }
    }

    // MARK: - Writes

    /// Retires the rows of climbs that are being deleted, so a deleted climb's workout never
    /// returns - in either mode. Does not save: the caller's own save carries it with the delete.
    ///
    /// Covers a climb that is not the one the ledger remembers too, by matching the UUID the climb
    /// itself carries.
    func markSkippedForDeletedClimbs(_ climbs: [Workout], resolvedAt: Date = Date()) {
        for climb in climbs {
            let byClimb = try? record(forImportedWorkoutID: climb.id)
            let byUUID = climb.healthKitUUID.flatMap { try? record(forUUID: $0) }
            guard let record = byClimb ?? byUUID else { continue }
            record.state = .skipped
            record.importedWorkoutID = nil
            record.homeNoticePending = false
            record.resolvedAt = resolvedAt
        }
    }
}
