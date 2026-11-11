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
        let telemetry: TelemetryManager
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
            // No free week here, so closing the paywall is the hard paywall reopening.
            freeWeek: FreeWeekTestHarness(isEnabled: false).store,
            telemetry: telemetry,
            onboardingLifecycle: lifecycle,
            userDefaults: defaults
        )
        return Fixture(
            sink: sink,
            telemetry: telemetry,
            lifecycle: lifecycle,
            presenter: presenter,
            manager: manager
        )
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
    }

    @Test
    func theGateAsksSuperwallForOnePlacementOnly() {
        let f = fixture(passFlowVersion: "v3")

        f.manager.presentPaywall(.appAccessGate, params: ["source": "app_access_gate"])

        #expect(f.presenter.registrations == [.appAccessGate])
    }

    @Test
    func backDuringAV3PassIsAPlainCloseThatNeverReopensALegacyStage() {
        let f = fixture(passFlowVersion: "v3")
        var reopenCount = 0
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: f.manager,
            telemetry: f.telemetry,
            onRequestOnboardingBack: {
                reopenCount += 1
                return true
            },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )

        coordinator.start()
        coordinator.handleHostedOutcomeForTesting(.presented)
        coordinator.handleHostedOutcomeForTesting(.backRequested)

        // A plain close: no legacy stage reopens, and with no free week on offer the paywall the
        // climber closed is the one that comes back.
        #expect(reopenCount == 0)
        #expect(f.presenter.registrations == [.appAccessGate, .appAccessGate])
        #expect(f.presenter.registeredSource == "paid_offers_declined")
        #expect(coordinator.phase == .openingHosted)

        let back = f.sink.records.filter { $0.name == "onboarding_back_tapped" }
        #expect(back.count == 1)
        #expect(back.first?.parameters["flow_version"] == .string("v3"))
        #expect(back.first?.parameters["step_index"] == .int(15))
        #expect(back.first?.parameters["step_count"] == .int(15))
    }

    @Test
    func backInALegacyPassStillReopensTheStageBehindTheGate() {
        let f = fixture(passFlowVersion: "v1")
        var reopenCount = 0
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: f.manager,
            telemetry: f.telemetry,
            onRequestOnboardingBack: {
                reopenCount += 1
                return true
            },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )

        coordinator.start()
        coordinator.handleHostedOutcomeForTesting(.presented)
        coordinator.handleHostedOutcomeForTesting(.backRequested)

        #expect(reopenCount == 1)
        let back = f.sink.records.first { $0.name == "onboarding_back_tapped" }
        #expect(back?.parameters["flow_version"] == .string("v1"))
        #expect(back?.parameters["step_index"] == .int(20))
    }

    @Test
    func aDeclineOfferOpeningDuringAV3PassCountsNoBackAndReopensNothing() {
        let f = fixture(passFlowVersion: "v3")
        var reopenCount = 0
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: f.manager,
            telemetry: f.telemetry,
            onRequestOnboardingBack: {
                reopenCount += 1
                return true
            },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )

        coordinator.start()
        coordinator.handleHostedOutcomeForTesting(.presented)
        coordinator.handleHostedOutcomeForTesting(.followOnPaywallOpening)

        #expect(reopenCount == 0)
        #expect(coordinator.phase == .openingHosted)
        #expect(f.sink.records.contains { $0.name == "onboarding_back_tapped" } == false)
    }
}
