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
        #expect(completed.first?.parameters["step_index"] == .int(19))
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
        relaunchedCoordinator.reportResumeIfNeeded(
            context: PostAuthOnboardingStage.stairStepperBaseline.analyticsContext
        )
        relaunchedCoordinator.recordFlowCompletedIfNeeded(reason: .existingEntitlement)

        #expect(fixture.records(named: "onboarding_flow_started").count == 1)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
        // The return is one event of its own now, not a re-emitted screen view.
        let resumed = fixture.records(named: "onboarding_flow_resumed")
        #expect(resumed.count == 1)
        #expect(resumed.first?.parameters["step_id"] == .string("stair_stepper_baseline"))
    }

    /// Firebase Auth survives a reinstall in the Keychain while `UserDefaults` does not, so a
    /// climber who signed in but never finished resumes mid-flow and never sees welcome. That pass
    /// still has to be counted, and its first screen still has to say it is a resume.
    @Test
    func passThatBeginsAfterAuthStartsAtTheStepItResumesAt() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        let resumedContext = PostAuthOnboardingStage.stairStepperBaseline.analyticsContext
        fixture.coordinator.recordFlowStartedIfNeeded(context: resumedContext)
        fixture.coordinator.reportResumeIfNeeded(context: resumedContext)
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)

        let started = fixture.records(named: "onboarding_flow_started")
        #expect(started.count == 1)
        #expect(started.first?.parameters["step_id"] == .string("stair_stepper_baseline"))
        #expect(started.first?.parameters["resume"] == .bool(true))
        #expect(fixture.records(named: "onboarding_flow_resumed").count == 1)
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

    /// Firebase reports "no user" on every signed-out cold launch, not only on a deliberate sign
    /// out, and that report reaches the monetization identity reset before any screen renders. A
    /// climber who killed the app mid-carousel must come back to the pass they left.
    @Test
    func aSignedOutColdLaunchKeepsThePreAuthPassItFinds() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)

        let relaunchedCoordinator = fixture.makeRelaunchedCoordinator()
        let relaunchedMonetization = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: fixture.telemetry,
            onboardingLifecycle: relaunchedCoordinator
        )
        relaunchedMonetization.prepareIdentityReset()

        relaunchedCoordinator.recordFlowStartedIfNeeded(
            context: OnboardingAnalyticsEvent.welcomeContext
        )
        relaunchedCoordinator.reportResumeIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)

        #expect(fixture.records(named: "onboarding_flow_started").count == 1)
        #expect(fixture.records(named: "onboarding_flow_resumed").count == 1)
    }

    /// Signing out of an account that claimed a pass does abandon it.
    @Test
    func signingOutOfAnAdoptedPassRetiresIt() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        let monetization = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: fixture.telemetry,
            onboardingLifecycle: fixture.coordinator
        )

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        monetization.prepareIdentity(.climber("climber-a"))
        monetization.prepareIdentityReset()

        // Climber A's start is gone, so their pass cannot be closed by whoever comes next.
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .purchase)
        #expect(fixture.records(named: "onboarding_flow_completed").isEmpty)

        fixture.coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
        #expect(fixture.records(named: "onboarding_flow_started").count == 2)
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
            context: PostAuthOnboardingStage.stairStepperBaseline.analyticsContext
        )
        fixture.coordinator.recordFlowCompletedIfNeeded(reason: .existingEntitlement)

        #expect(fixture.records(named: "onboarding_flow_started").count == 2)
        #expect(fixture.records(named: "onboarding_flow_completed").count == 2)
    }

    /// The StoreKit sheet is exactly where a climber backgrounds or kills the app, so the purchase
    /// has to outlive the process that recorded it. Every runtime dependency is rebuilt here; only
    /// the persisted pass carries the answer across.
    @Test
    func aPurchaseRecordedBeforeProcessDeathStillCompletesAsAPurchase() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.startPassAndRecordPaywallOutcome(.purchased)

        #expect(fixture.completionReasonAfterProcessRestart() == .string("purchase"))
    }

    @Test
    func aRestoreRecordedBeforeProcessDeathStillCompletesAsARestore() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.startPassAndRecordPaywallOutcome(.restored)

        #expect(fixture.completionReasonAfterProcessRestart() == .string("restore"))
    }

    /// A request the process died holding can never report, so the next process closes it rather
    /// than deferring a completion nothing is left to release - and the access it finds is still
    /// the grant this pass asked for, never an entitlement the climber arrived with.
    @Test
    func aRequestLeftInFlightByADeadProcessStillCompletesAsAGrant() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.startPassAndRecordPaywallOutcome(nil)

        #expect(fixture.completionReasonAfterProcessRestart() == .string("purchase"))
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

        func records(named name: String) -> [EnvelopedTelemetryRecord] {
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

        /// Opens a pass, reaches the paywall, and lets it report `outcome` - or nothing at all,
        /// which is what a process that dies on the purchase sheet leaves behind.
        @MainActor
        func startPassAndRecordPaywallOutcome(_ outcome: PaywallPresentationOutcome?) {
            coordinator.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)

            let paywallPresenter = PaywallPresenterSpy()
            let monetization = MonetizationManager(
                entitlementService: EntitlementServiceStub(),
                paywallPresenter: paywallPresenter,
                telemetry: telemetry,
                onboardingLifecycle: coordinator
            )
            monetization.presentPaywall(.appAccessGate, params: ["source": "onboarding"])

            if let outcome {
                paywallPresenter.send(outcome)
            }
        }

        /// Rebuilds every runtime dependency over the persisted pass - the coordinator and the
        /// monetization manager both - and completes from whatever the new process can work out.
        @MainActor
        func completionReasonAfterProcessRestart() -> TelemetryValue? {
            let relaunchedCoordinator = makeRelaunchedCoordinator()
            let relaunchedMonetization = MonetizationManager(
                entitlementService: EntitlementServiceStub(
                    entitlementState: .active(["app_access"])
                ),
                paywallPresenter: PaywallPresenterSpy(),
                telemetry: telemetry,
                onboardingLifecycle: relaunchedCoordinator
            )

            guard let reason = relaunchedMonetization.onboardingCompletionReasonForActiveAccess else {
                return nil
            }

            relaunchedCoordinator.recordFlowCompletedIfNeeded(reason: reason)

            let completed = records(named: "onboarding_flow_completed")
            #expect(completed.count == 1)
            return completed.first?.parameters["completion_reason"]
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
