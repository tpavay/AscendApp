import Foundation
import Testing
@testable import AscendApp

@MainActor
struct OnboardingFlowAnalyticsCoordinatorTests {
    @Test
    func cleanPassEmitsOneStartAndOneCompletionAfterAccessIsConfirmed() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded()
        fixture.coordinator.recordFlowStartedIfNeeded()

        #expect(fixture.records(named: "onboarding_flow_started").count == 1)
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

        fixture.coordinator.recordFlowStartedIfNeeded()
        let relaunchedCoordinator = OnboardingFlowAnalyticsCoordinator(
            userDefaults: fixture.defaults,
            telemetry: fixture.telemetry
        )
        relaunchedCoordinator.recordFlowStartedIfNeeded()
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

    @Test
    func backNavigationDoesNotCreateAnotherFlowLifecycle() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.recordFlowStartedIfNeeded()
        fixture.telemetry.track(
            OnboardingAnalyticsEvent.backTapped(
                context: PostAuthOnboardingStage.gender.analyticsContext,
                inputType: "button"
            )
        )
        fixture.coordinator.recordFlowStartedIfNeeded()
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

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
