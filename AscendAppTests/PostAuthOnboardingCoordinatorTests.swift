import Foundation
import Testing
@testable import AscendApp

struct PostAuthOnboardingCoordinatorTests {
    @Test
    func postAuthStagesStartWithDisplayName() {
        #expect(PostAuthOnboardingStage.allCases == [
            .displayName
        ])
        #expect(PostAuthOnboardingStage.first == .displayName)
    }

    @MainActor
    @Test
    func completingDisplayNameCompletesPostAuthOnboarding() {
        let defaults = makeDefaults()
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-1"

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        coordinator.completeCurrentStage()

        #expect(coordinator.phase == .complete)
        #expect(store.snapshot(for: userId).isComplete)
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
    func legacyRemovedStageSnapshotWithDisplayNameCompletedIsComplete() {
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

        #expect(coordinator.phase == .complete)
        #expect(store.snapshot(for: userId).completedStages == [.displayName])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PostAuthOnboardingCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
