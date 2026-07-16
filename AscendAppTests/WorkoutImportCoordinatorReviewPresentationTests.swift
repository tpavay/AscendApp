import Foundation
import Testing
@testable import AscendApp

@MainActor
struct WorkoutImportCoordinatorReviewPresentationTests {
    @Test
    func presentingPendingReviewPrefersLatestUnseenWorkout() {
        let suiteName = "WorkoutImportCoordinatorReviewPresentationTests.latest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let reviewStateStore = WorkoutAutoImportReviewStateStore(
            defaults: defaults,
            key: "latest-unseen-review"
        )
        let coordinator = WorkoutImportCoordinator(reviewStateStore: reviewStateStore)

        let olderWorkoutID = UUID()
        let newerWorkoutID = UUID()
        reviewStateStore.recordLatestWorkout(
            id: olderWorkoutID,
            referenceDate: Date(timeIntervalSince1970: 1_776_350_400)
        )
        coordinator.currentAutoImportedReviewWorkoutID = olderWorkoutID

        reviewStateStore.recordLatestWorkout(
            id: newerWorkoutID,
            referenceDate: Date(timeIntervalSince1970: 1_776_436_800)
        )

        #expect(coordinator.presentPendingAutoImportedReviewOnHomeIfNeeded())
        #expect(coordinator.currentAutoImportedReviewWorkoutID == newerWorkoutID)
    }

    @Test
    func presentingPendingReviewClearsCurrentWhenAllUnseenWorkoutsAreHandled() {
        let suiteName = "WorkoutImportCoordinatorReviewPresentationTests.handled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let reviewStateStore = WorkoutAutoImportReviewStateStore(
            defaults: defaults,
            key: "handled-review"
        )
        let coordinator = WorkoutImportCoordinator(reviewStateStore: reviewStateStore)

        let workoutID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 1_776_436_800)
        reviewStateStore.recordLatestWorkout(id: workoutID, referenceDate: referenceDate)
        reviewStateStore.markHandled(referenceDate: referenceDate)
        coordinator.currentAutoImportedReviewWorkoutID = workoutID

        #expect(coordinator.presentPendingAutoImportedReviewOnHomeIfNeeded() == false)
        #expect(coordinator.currentAutoImportedReviewWorkoutID == nil)
    }
}
