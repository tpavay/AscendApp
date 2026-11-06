import Foundation
import Testing
@testable import AscendApp

/// The v3 onboarding ends at sign-in, and a climber without access is handed to the app-access
/// gate: the Superwall paywall for the `app_access_gate` placement, whose decline offer is
/// configured in the dashboard. These hold what the app reports at that hand-off, because the
/// paywall itself is no longer one of the flow's steps.
@MainActor
struct OnboardingGateHandOffTests {
    private struct Fixture {
        let sink: InMemoryTelemetrySink
        let lifecycle: OnboardingFlowAnalyticsCoordinator
        let presenter: PaywallPresenterSpy
        let manager: MonetizationManager
    }

    private func fixture(passFlowVersion: String?, completed: Bool = false) -> Fixture {
        let suiteName = "OnboardingGateHandOffTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        telemetry.setUserId("test-user")
        let lifecycle = OnboardingFlowAnalyticsCoordinator(userDefaults: defaults, telemetry: telemetry)

        if let passFlowVersion {
            lifecycle.recordFlowStartedIfNeeded(
                context: OnboardingAnalyticsContext(
                    segmentID: "onboarding_v3",
                    flowVersion: passFlowVersion,
                    stepID: "welcome"
                )
            )
        }
        if completed { lifecycle.recordFlowCompletedIfNeeded(reason: .purchase) }

        let presenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: presenter,
            telemetry: telemetry,
            onboardingLifecycle: lifecycle
        )
        return Fixture(sink: sink, lifecycle: lifecycle, presenter: presenter, manager: manager)
    }

    @Test
    func aV3ClimberReachesTheGateUnderTheV3PassOnePastTheLastStep() {
        let f = fixture(passFlowVersion: "v3")

        f.manager.presentPaywall(.appAccessGate, params: ["source": "app_access_gate"])

        let reached = f.sink.records.filter { $0.name == "onboarding_paywall_reached" }
        #expect(reached.count == 1)
        #expect(reached.first?.parameters["placement"] == .string("app_access_gate"))
        #expect(reached.first?.parameters["flow_version"] == .string("v3"))
        #expect(reached.first?.parameters["step_id"] == .string("paywall"))
        #expect(reached.first?.parameters["step_index"] == .int(15))
        #expect(reached.first?.parameters["step_count"] == .int(15))

        let views = f.sink.records.filter {
            $0.name == "onboarding_screen_viewed" && $0.parameters["screen_id"] == .string("paywall")
        }
        #expect(views.count == 1)
        #expect(views.first?.parameters["flow_version"] == .string("v3"))
    }

    @Test
    func completingAV3PassReportsAContextTheV3FunnelCanPlace() {
        let f = fixture(passFlowVersion: "v3")

        f.lifecycle.recordFlowCompletedIfNeeded(reason: .purchase)

        let completed = f.sink.records.first { $0.name == "onboarding_flow_completed" }
        #expect(completed?.parameters["flow_version"] == .string("v3"))
        #expect(completed?.parameters["step_id"] == .string("paywall"))
        #expect(completed?.parameters["step_index"] == .int(15))
        #expect(completed?.parameters["step_count"] == .int(15))
        #expect(completed?.parameters["completion_reason"] == .string("purchase"))
    }

    @Test
    func aV1ClimberStillReportsTheGateWhereItAlwaysDid() {
        let f = fixture(passFlowVersion: "v1")

        f.manager.presentPaywall(.appAccessGate, params: ["source": "app_access_gate"])

        let reached = f.sink.records.first { $0.name == "onboarding_paywall_reached" }
        #expect(reached?.parameters["flow_version"] == .string("v1"))
        #expect(reached?.parameters["step_index"] == .int(20))
        #expect(reached?.parameters["step_count"] == .int(21))
    }

    @Test
    func aSubscriberWhoLapsedMonthsAfterTheirOnboardingIsNotCreditedToIt() {
        let f = fixture(passFlowVersion: "v3", completed: true)

        f.manager.presentPaywall(.appAccessGate, params: ["source": "app_access_gate"])

        let reached = f.sink.records.first { $0.name == "onboarding_paywall_reached" }
        #expect(reached?.parameters["flow_version"] == .string("v1"))
        #expect(f.presenter.userAttributeWrites.last == [MonetizationManager.onboardingFlowVersionAttribute: nil])
    }

    @Test
    func theGateTellsSuperwallWhichOnboardingLedThereAndNothingElse() {
        let f = fixture(passFlowVersion: "v3")

        f.manager.presentPaywall(.appAccessGate, params: ["source": "app_access_gate"])

        #expect(MonetizationManager.onboardingFlowVersionAttribute == "onboarding_flow_version")
        #expect(f.presenter.userAttributeWrites == [["onboarding_flow_version": "v3"]])
        #expect(f.presenter.registeredPlacement == .appAccessGate)
        #expect(f.presenter.registrations == [.appAccessGate], "the app asks for one placement only")
    }

    @Test
    func aPlacementThatIsNotTheGateSetsNoAttribute() {
        let f = fixture(passFlowVersion: "v3")

        f.manager.presentPaywall(.appLaunchHardGate)

        #expect(f.presenter.userAttributeWrites.isEmpty)
    }
}
