import Foundation
import Testing
@testable import AscendApp

struct PostAuthOnboardingCoordinatorTests {
    @Test
    func postAuthStagesStartWithDisplayName() {
        #expect(PostAuthOnboardingStage.allCases == [
            .displayName,
            .stairStepperBaseline,
            .exerciseLevel,
            .goal,
            .motivation,
            .plan,
            .gender,
            .age,
            .weight,
            .location,
            .notifications,
            .planLoading,
            .firstClimb
        ])
        #expect(PostAuthOnboardingStage.first == .displayName)
        #expect(PostAuthOnboardingStage.flowID == "post_auth_onboarding")
        #expect(PostAuthOnboardingStage.plannedStepCount == 13)
    }

    @MainActor
    @Test
    func completingDisplayNameAdvancesToStairStepperBaseline() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-1"

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        coordinator.completeCurrentStage()

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
    }

    @MainActor
    @Test
    func completingAllStagesCompletesPostAuthOnboarding() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-complete"

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        for _ in PostAuthOnboardingStage.allCases {
            coordinator.completeCurrentStage()
        }

        #expect(coordinator.phase == .complete)
        #expect(store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == Set(PostAuthOnboardingStage.allCases))
    }

    @MainActor
    @Test
    func legacyRemovedStageSnapshotStartsAtDisplayName() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-2"

        defaults.set(
            Data(
                """
                {
                  "currentStage": "ratingSentiment",
                  "completedStages": ["valueScreens"],
                  "isComplete": false,
                  "startedAt": 1000
                }
                """.utf8
            ),
            forKey: "postAuthOnboarding.v1.\(userId)"
        )

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.displayName))
    }

    @MainActor
    @Test
    func legacyRemovedStageSnapshotWithDisplayNameCompletedResumesAtFirstSurveyQuestion() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-3"

        defaults.set(
            Data(
                """
                {
                  "currentStage": "paywall",
                  "completedStages": ["displayName", "ratingSentiment", "userSurvey", "paywallPriming"],
                  "isComplete": false,
                  "startedAt": 1000
                }
                """.utf8
            ),
            forKey: "postAuthOnboarding.v1.\(userId)"
        )

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
    }

    @MainActor
    @Test
    func snapshotWithCurrentStageAfterNewRequiredQuestionsReopensAtFirstMissingQuestion() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-4"

        let snapshot = PostAuthOnboardingSnapshot(
            currentStage: .gender,
            completedStages: [.displayName],
            isComplete: false,
            startedAt: Date(timeIntervalSince1970: 1000)
        )
        store.save(snapshot, for: userId)

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!store.snapshot(for: userId).isComplete)
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PostAuthOnboardingCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
