import Foundation
import Testing
@testable import AscendApp

/// The paywall's back control is the only way out of the gate, so the two things that make it work
/// are pinned here: a hosted dismissal can be told apart from an ordinary close, and taking it walks
/// the climber back into onboarding instead of into a second paywall.
struct PaywallBackToOnboardingTests {
    @Test
    func onlyTheBackActionNameResolvesToABackIntent() {
        #expect(PaywallDismissIntent.resolve(latchedActionName: "back") == .back)
        #expect(PaywallDismissIntent.resolve(latchedActionName: nil) == .undifferentiated)
        #expect(PaywallDismissIntent.resolve(latchedActionName: "") == .undifferentiated)
        // A control the dashboard adds that the app does not model yet must degrade to an ordinary
        // dismissal rather than be mistaken for back.
        #expect(PaywallDismissIntent.resolve(latchedActionName: "delete_account") == .undifferentiated)

        #expect(PaywallDismissIntent.back.outcome == .backRequested)
        #expect(PaywallDismissIntent.undifferentiated.outcome == .dismissedWithoutPurchase)
        #expect(PaywallPresentationOutcome.backRequested.isTerminal)
    }

    /// Superwall reports every user close as the same `declined`, so without the latch these two
    /// cases are the same event.
    @MainActor
    @Test
    func aLatchedBackActionSeparatesTheDismissalFromAnOrdinaryClose() {
        for (latched, expected) in [
            ("back", PaywallPresentationOutcome.backRequested),
            (nil, PaywallPresentationOutcome.dismissedWithoutPurchase)
        ] as [(String?, PaywallPresentationOutcome)] {
            let presenter = SuperwallPaywallPresenter(startsConfigured: true)
            var outcomes: [PaywallPresentationOutcome] = []
            let identity = MonetizationIdentityTransition(revision: 1, userID: "user-1")
            let revision = presenter.beginPresentationAttemptForTesting(identity: identity) {
                outcomes.append($0)
            }
            presenter.handlePresentationBegan(revision: revision, presentationID: "presentation-1")

            if let latched {
                presenter.handleCustomPaywallAction(withName: latched)
                #expect(presenter.latchedActionNameForTesting() == latched)
            }

            presenter.handleDismissForTesting(revision: revision, result: .declined)
            #expect(outcomes == [expected])
        }
    }

    /// A custom action must not dismiss anything by itself - SuperwallKit keeps the paywall up, and
    /// acting on arrival would race the close that follows it.
    @MainActor
    @Test
    func aCustomActionAloneReportsNoOutcome() {
        let presenter = SuperwallPaywallPresenter(startsConfigured: true)
        var outcomes: [PaywallPresentationOutcome] = []
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-1")
        let revision = presenter.beginPresentationAttemptForTesting(identity: identity) {
            outcomes.append($0)
        }
        presenter.handlePresentationBegan(revision: revision, presentationID: "presentation-1")

        presenter.handleCustomPaywallAction(withName: "back")

        #expect(outcomes.isEmpty)
    }

    /// Back must never fall through to `beginNativeFallback`. The captain's rule is that the native
    /// plan list is a failure fallback and nothing else.
    @MainActor
    @Test
    func reopeningTheLastStageWalksAFinishedClimberBackAndSurvivesAProfileRecheck() {
        let suiteName = "PaywallBackToOnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = PostAuthOnboardingStore(userDefaults: defaults)
        let userId = "user-1"
        store.markComplete(for: userId)

        let coordinator = PostAuthOnboardingCoordinator(store: store)
        coordinator.resolve(userId: userId)
        #expect(coordinator.phase == .complete)
        #expect(!coordinator.isReopenedByClimber)

        coordinator.reopenLastStage()

        #expect(coordinator.phase == .onboarding(.firstClimb))
        #expect(coordinator.isReopenedByClimber)

        // Routing reads the persisted snapshot, so a forced re-resolve must not snap back to
        // `.complete`.
        coordinator.resolve(userId: userId, force: true)
        #expect(coordinator.phase == .onboarding(.firstClimb))
        #expect(coordinator.isReopenedByClimber)

        // Finishing again clears the marker, so the profile check is free to run once more.
        coordinator.completeCurrentStage()
        #expect(coordinator.phase == .complete)
        #expect(!coordinator.isReopenedByClimber)
    }

    @MainActor
    @Test
    func reopeningDoesNothingForAClimberWhoIsStillMidFlow() {
        let suiteName = "PaywallBackToOnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let coordinator = PostAuthOnboardingCoordinator(
            store: PostAuthOnboardingStore(userDefaults: defaults)
        )
        coordinator.resolve(userId: "user-1")
        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))

        coordinator.reopenLastStage()

        #expect(coordinator.phase == .onboarding(.stairStepperBaseline))
        #expect(!coordinator.isReopenedByClimber)
    }
}
