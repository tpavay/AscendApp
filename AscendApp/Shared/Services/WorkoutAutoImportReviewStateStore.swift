import Foundation

struct WorkoutAutoImportReviewStateStore {
    private struct Snapshot: Codable {
        var latestWorkoutID: UUID?
        var latestReferenceDate: Date?
        var lastHandledReferenceDate: Date?
    }

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "workoutImport.autoImportedReviewState"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func latestUnseenWorkoutID() -> UUID? {
        let snapshot = loadSnapshot()
        guard let latestWorkoutID = snapshot.latestWorkoutID,
              let latestReferenceDate = snapshot.latestReferenceDate else {
            return nil
        }

        if let lastHandledReferenceDate = snapshot.lastHandledReferenceDate,
           latestReferenceDate <= lastHandledReferenceDate {
            return nil
        }

        return latestWorkoutID
    }

    func hasUnseenWorkout() -> Bool {
        latestUnseenWorkoutID() != nil
    }

    func latestReferenceDate(for workoutID: UUID) -> Date? {
        let snapshot = loadSnapshot()
        guard snapshot.latestWorkoutID == workoutID else { return nil }
        return snapshot.latestReferenceDate
    }

    func recordLatestWorkout(id: UUID, referenceDate: Date) {
        var snapshot = loadSnapshot()

        if let existingLatestReferenceDate = snapshot.latestReferenceDate,
           let existingLatestWorkoutID = snapshot.latestWorkoutID,
           existingLatestReferenceDate > referenceDate,
           existingLatestWorkoutID != id {
            return
        }

        snapshot.latestWorkoutID = id
        snapshot.latestReferenceDate = referenceDate
        saveSnapshot(snapshot)
    }

    func markHandled(referenceDate: Date) {
        var snapshot = loadSnapshot()
        let resolvedHandledDate = max(snapshot.lastHandledReferenceDate ?? .distantPast, referenceDate)
        snapshot.lastHandledReferenceDate = resolvedHandledDate

        if let latestReferenceDate = snapshot.latestReferenceDate,
           latestReferenceDate <= resolvedHandledDate {
            snapshot.latestWorkoutID = nil
            snapshot.latestReferenceDate = nil
        }

        saveSnapshot(snapshot)
    }

    func clearLatestWorkout(ifMatches workoutID: UUID? = nil) {
        var snapshot = loadSnapshot()

        if let workoutID, snapshot.latestWorkoutID != workoutID {
            return
        }

        snapshot.latestWorkoutID = nil
        snapshot.latestReferenceDate = nil
        saveSnapshot(snapshot)
    }

    func prune(validIDs: Set<UUID>) {
        var snapshot = loadSnapshot()

        if let latestWorkoutID = snapshot.latestWorkoutID,
           !validIDs.contains(latestWorkoutID) {
            snapshot.latestWorkoutID = nil
            snapshot.latestReferenceDate = nil
        }

        saveSnapshot(snapshot)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func loadSnapshot() -> Snapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot()
        }

        return snapshot
    }

    private func saveSnapshot(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
