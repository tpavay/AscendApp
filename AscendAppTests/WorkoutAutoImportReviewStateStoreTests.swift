import Foundation
import Testing
@testable import AscendApp

struct WorkoutAutoImportReviewStateStoreTests {
    @Test
    func recordsOnlyTheNewestWorkoutForReview() {
        let defaults = makeDefaults()
        let store = WorkoutAutoImportReviewStateStore(defaults: defaults, key: "review")
        let olderWorkoutID = UUID()
        let newerWorkoutID = UUID()

        store.recordLatestWorkout(
            id: newerWorkoutID,
            referenceDate: Date(timeIntervalSince1970: 2_000)
        )
        store.recordLatestWorkout(
            id: olderWorkoutID,
            referenceDate: Date(timeIntervalSince1970: 1_000)
        )

        #expect(store.latestUnseenWorkoutID() == newerWorkoutID)
    }

    @Test
    func markingLatestWorkoutHandledClearsItsReviewState() {
        let defaults = makeDefaults()
        let store = WorkoutAutoImportReviewStateStore(defaults: defaults, key: "review")
        let workoutID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 2_000)

        store.recordLatestWorkout(id: workoutID, referenceDate: referenceDate)
        store.markHandled(referenceDate: referenceDate)

        #expect(store.latestUnseenWorkoutID() == nil)
    }

    @Test
    func pruningRemovesMissingLatestWorkout() {
        let defaults = makeDefaults()
        let store = WorkoutAutoImportReviewStateStore(defaults: defaults, key: "review")
        let workoutID = UUID()

        store.recordLatestWorkout(
            id: workoutID,
            referenceDate: Date(timeIntervalSince1970: 2_000)
        )
        store.prune(validIDs: [])

        #expect(store.latestUnseenWorkoutID() == nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WorkoutAutoImportReviewStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
