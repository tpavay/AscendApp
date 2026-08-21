import Foundation
import Testing
@testable import AscendApp

/// What happens to a climber who already had onboarding state when a stage was
/// removed from the flow.
///
/// The name stage was removed to settle the Guideline 4 rejection, and removing
/// a `Codable` enum case is not a local change: every snapshot on every device
/// names stages that existed when it was written. `markComplete` stores
/// `Set(PostAuthOnboardingStage.allCases)`, so *every finished climber's*
/// snapshot names the removed stage. Without a tolerant decode the synthesised
/// `Codable` throws, `PostAuthOnboardingStore` falls back to its one-time legacy
/// migration - which resets `isComplete` and discards completed stages - and the
/// entire installed base is dropped back into onboarding on the update. An iOS
/// binary cannot be rolled back, so that has no undo.
struct PostAuthOnboardingSnapshotDecodingTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "PostAuthOnboardingSnapshotDecodingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func store(_ json: String, for userId: String, in defaults: UserDefaults) {
        defaults.set(Data(json.utf8), forKey: "postAuthOnboarding.v1.\(userId)")
    }

    /// The whole installed base. A climber who finished onboarding on the
    /// rejected build stays finished.
    @Test
    func aFinishedClimberStaysFinishedWhenAStageIsRemoved() {
        let defaults = makeDefaults()
        let userId = "finished"
        store(
            """
            {
              "currentStage": "displayName",
              "completedStages": [
                "displayName", "stair_stepper_baseline", "exercise_level", "goal",
                "motivation", "plan", "features", "gender", "age", "weight",
                "location", "notifications", "loading", "first_climb"
              ],
              "isComplete": true,
              "startedAt": 1000,
              "completedAt": 2000
            }
            """,
            for: userId,
            in: defaults
        )

        let snapshot = PostAuthOnboardingStore(userDefaults: defaults).snapshot(for: userId)

        #expect(snapshot.isComplete, "a finished climber must not be dropped back into onboarding")
        #expect(snapshot.completedAt == Date(timeIntervalSinceReferenceDate: 2000))
        #expect(snapshot.completedStages == Set(PostAuthOnboardingStage.allCases))
        #expect(snapshot.currentStage == .first, "a stage that no longer exists falls back to the first")
    }

    /// A climber part-way through keeps the answers they already gave, rather
    /// than being sent back to the beginning to repeat them.
    @Test
    func aMidFlowClimberKeepsTheStagesTheyAlreadyCompleted() {
        let defaults = makeDefaults()
        let userId = "mid-flow"
        store(
            """
            {
              "currentStage": "gender",
              "completedStages": [
                "displayName", "stair_stepper_baseline", "exercise_level",
                "goal", "motivation", "plan", "features"
              ],
              "isComplete": false,
              "startedAt": 1000
            }
            """,
            for: userId,
            in: defaults
        )

        let snapshot = PostAuthOnboardingStore(userDefaults: defaults).snapshot(for: userId)

        #expect(!snapshot.isComplete)
        #expect(snapshot.currentStage == .gender, "they resume where they actually were")
        #expect(
            snapshot.completedStages == [
                .stairStepperBaseline, .exerciseLevel, .goal, .motivation, .plan, .features
            ],
            "the removed stage is dropped; everything else survives"
        )
        #expect(snapshot.startedAt == Date(timeIntervalSinceReferenceDate: 1000))
    }

    /// A climber who had only reached the removed stage has nothing to resume, so
    /// they open on the new first question rather than on nothing.
    @MainActor
    @Test
    func aClimberParkedOnTheRemovedStageOpensOnTheFirstRemainingQuestion() {
        let defaults = makeDefaults()
        let userId = "parked"
        store(
            """
            {
              "currentStage": "displayName",
              "completedStages": [],
              "isComplete": false,
              "startedAt": 1000
            }
            """,
            for: userId,
            in: defaults
        )

        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
    }

    /// The tolerance is general, not a one-off for this rename: a snapshot naming
    /// a stage no build ever had decodes the same way rather than resetting the
    /// climber.
    @Test
    func anUnrecognisedStageIsDroppedRatherThanThrowing() {
        let defaults = makeDefaults()
        let userId = "unknown-stage"
        store(
            """
            {
              "currentStage": "someStageFromTheFuture",
              "completedStages": ["stair_stepper_baseline", "someStageFromTheFuture"],
              "isComplete": false,
              "startedAt": 1000
            }
            """,
            for: userId,
            in: defaults
        )

        let snapshot = PostAuthOnboardingStore(userDefaults: defaults).snapshot(for: userId)

        #expect(snapshot.currentStage == .first)
        #expect(snapshot.completedStages == [.stairStepperBaseline])
        #expect(snapshot.startedAt == Date(timeIntervalSinceReferenceDate: 1000))
    }

    /// A snapshot this build wrote still round-trips unchanged.
    @Test
    func aCurrentSnapshotRoundTrips() throws {
        let original = PostAuthOnboardingSnapshot(
            currentStage: .weight,
            completedStages: [.stairStepperBaseline, .exerciseLevel],
            isComplete: false,
            startedAt: Date(timeIntervalSinceReferenceDate: 1000),
            completedAt: nil
        )

        let decoded = try JSONDecoder().decode(
            PostAuthOnboardingSnapshot.self,
            from: try JSONEncoder().encode(original)
        )

        #expect(decoded == original)
    }
}
