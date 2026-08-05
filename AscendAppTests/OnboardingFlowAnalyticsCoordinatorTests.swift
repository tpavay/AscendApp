import Foundation
import Testing
@testable import AscendApp

@MainActor
struct OnboardingFlowAnalyticsCoordinatorTests {
    @Test
    func cleanPassEmitsOneStartAndOneCompletionAfterAccessIsConfirmed() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)

        let started = fixture.records(named: "onboarding_flow_started")
        #expect(started.count == 1)
        #expect(started.first?.parameters["step_id"] == .string("welcome"))
        #expect(started.first?.parameters["resume"] == .bool(false))
        #expect(fixture.records(named: "onboarding_flow_completed").isEmpty)

        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .restore)

        let completed = fixture.records(named: "onboarding_flow_completed")
        #expect(completed.count == 1)
        #expect(completed.first?.parameters["completion_reason"] == .string("purchase"))
        #expect(completed.first?.parameters["step_id"] == .string("paywall"))
        #expect(completed.first?.parameters["step_index"] == .int(20))
    }

    @Test
    func relaunchMidFlowDoesNotEmitASecondStartForThePersistedPass() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        let relaunchedCoordinator = fixture.makeRelaunchedCoordinator()
        relaunchedCoordinator.recordFlowStartedIfNeeded(
            context: PostAuthOnboardingStage.stairStepperBaseline.analyticsContext
        )
        fixture.telemetry.track(
            OnboardingAnalyticsEvent.screenViewed(
                context: PostAuthOnboardingStage.stairStepperBaseline.analyticsContext,
                resume: relaunchedCoordinator.consumeScreenResumeFlag()
            )
        )
        relaunchedCoordinator.recordFlowCompletedIfNeeded(reason: .existingEntitlement)

        #expect(fixture.records(named: "onboarding_flow_started").count == 1)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
        #expect(
            fixture.records(named: "onboarding_screen_viewed").first?.parameters["resume"]
                == .bool(true)
        )
    }

    /// Firebase Auth survives a reinstall in the Keychain while `UserDefaults` does not, so a
    /// climber who signed in but never finished resumes mid-flow and never sees welcome. That pass
    /// still has to be counted, and its first screen still has to say it is a resume.
    @Test
    func passThatBeginsAfterAuthStartsAtTheStepItResumesAt() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        let resumedContext = PostAuthOnboardingStage.displayName.analyticsContext
        fixture.coordinator.recordFlowStartedIfNeeded(context: resumedContext)
        fixture.telemetry.track(
            OnboardingAnalyticsEvent.screenViewed(
                context: resumedContext,
                resume: fixture.coordinator.consumeScreenResumeFlag()
            )
        )
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)

        let started = fixture.records(named: "onboarding_flow_started")
        #expect(started.count == 1)
        #expect(started.first?.parameters["step_id"] == .string("displayName"))
        #expect(started.first?.parameters["resume"] == .bool(true))
        #expect(
            fixture.records(named: "onboarding_screen_viewed").first?.parameters["resume"]
                == .bool(true)
        )
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
    }

    @Test
    func backNavigationDoesNotCreateAnotherFlowLifecycle() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.telemetry.track(
            OnboardingAnalyticsEvent.backTapped(
                context: PostAuthOnboardingStage.gender.analyticsContext,
                inputType: "button"
            )
        )
        fixture.coordinator.recordFlowStartedIfNeeded(
            context: PostAuthOnboardingStage.motivation.analyticsContext
        )
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .restore)

        #expect(fixture.records(named: "onboarding_back_tapped").count == 1)
        #expect(fixture.records(named: "onboarding_flow_started").count == 1)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
    }

    @Test
    func completionWithoutAStartedPassIsIgnored() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .existingEntitlement)

        #expect(fixture.records(named: "onboarding_flow_completed").isEmpty)
    }

    /// One climber abandons a pass and a second signs up on the same device. The second climber's
    /// completion may not close the first climber's start, or starts and completions stop being
    /// one-to-one per pass.
    @Test
    func aDifferentAccountGetsItsOwnPassRatherThanInheritingTheAbandonedOne() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.adoptPassOwner("climber-a")

        fixture.coordinator.resetPass()
        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.adoptPassOwner("climber-b")
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)

        #expect(fixture.records(named: "onboarding_flow_started").count == 2)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
    }

    @Test
    func adoptingASecondAccountRetiresTheStartTheFirstAccountOpened() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.adoptPassOwner("climber-a")
        fixture.coordinator.adoptPassOwner("climber-b")

        // The retired pass left no start for climber B to close.
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)
        #expect(fixture.records(named: "onboarding_flow_completed").isEmpty)

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)

        #expect(fixture.records(named: "onboarding_flow_started").count == 2)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
    }

    @Test
    func adoptingTheSameAccountKeepsThePassItOpenedAcrossRelaunch() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.adoptPassOwner("climber-a")

        let relaunchedCoordinator = fixture.makeRelaunchedCoordinator()
        relaunchedCoordinator.adoptPassOwner("climber-a")
        relaunchedCoordinator.recordFlowStartedIfNeeded(
            context: PostAuthOnboardingStage.gender.analyticsContext
        )
        relaunchedCoordinator.recordFlowCompletedIfNeeded(reason: .restore)

        #expect(fixture.records(named: "onboarding_flow_started").count == 1)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
    }

    /// A QA replay after a real completion has to produce a whole pass, not silence.
    @Test
    func aRetiredPassLetsTheNextOneStartAndCompleteAgain() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.adoptPassOwner("climber-a")
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)

        fixture.coordinator.resetPass()
        fixture.coordinator.recordFlowStartedIfNeeded(
            context: PostAuthOnboardingStage.displayName.analyticsContext
        )
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .existingEntitlement)

        #expect(fixture.records(named: "onboarding_flow_started").count == 2)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 2)
    }

    /// A completed pass gives way to the next one without a manual reset, so a climber who finishes
    /// onboarding and later walks the flow again is counted as a second pass rather than silence.
    @Test
    func aCompletedPassGivesWayToTheNextWelcome() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)
        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)

        #expect(fixture.records(named: "onboarding_flow_started").count == 2)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
    }

    @Test
    func completionReasonRequiresConfirmedAccessWhileRoutingToHome() {
        #expect(
            OnboardingFlowCompletionResolver.completionReason(
                rootRoute: .paywall,
                postAuthPhase: .complete,
                confirmedAccessReason: .purchase
            ) == nil
        )
        #expect(
            OnboardingFlowCompletionResolver.completionReason(
                rootRoute: .mainApp,
                postAuthPhase: .onboarding(.firstClimb),
                confirmedAccessReason: .purchase
            ) == nil
        )
        #expect(
            OnboardingFlowCompletionResolver.completionReason(
                rootRoute: .mainApp,
                postAuthPhase: .complete,
                confirmedAccessReason: nil
            ) == nil
        )
        #expect(
            OnboardingFlowCompletionResolver.completionReason(
                rootRoute: .mainApp,
                postAuthPhase: .complete,
                confirmedAccessReason: .restore
            ) == .restore
        )
    }

    private func makeFixture() -> Fixture {
        let suiteName = "OnboardingFlowAnalyticsCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        return Fixture(
            suiteName: suiteName,
            defaults: defaults,
            sink: sink,
            telemetry: telemetry,
            coordinator: OnboardingFlowAnalyticsCoordinator(
                userDefaults: defaults,
                telemetry: telemetry
            )
        )
    }

    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let sink: InMemoryTelemetrySink
        let telemetry: TelemetryManager
        let coordinator: OnboardingFlowAnalyticsCoordinator

        func records(named name: String) -> [TelemetryRecord] {
            sink.records.filter { $0.name == name }
        }

        /// A fresh instance over the same persisted state - what a relaunch actually builds.
        @MainActor
        func makeRelaunchedCoordinator() -> OnboardingFlowAnalyticsCoordinator {
            OnboardingFlowAnalyticsCoordinator(
                userDefaults: defaults,
                telemetry: telemetry
            )
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
