import Foundation
import Testing
@testable import AscendApp

/// The screen-view dedupe used to live in `@State` on six different views, so it could not survive
/// the route change that back-from-the-paywall causes. These pin the behaviour that replaced it.
@MainActor
struct OnboardingScreenViewPassDedupeTests {
    /// The case the old mechanism could not express: a climber walks to the paywall, taps back, and
    /// re-passes screens whose recorder was destroyed by the route change.
    @Test
    func walkingBackThroughOnboardingReEmitsNothing() {
        let harness = Harness()
        let steps = [
            OnboardingAnalyticsEvent.welcomeContext,
            Self.context(for: .gender),
            Self.context(for: .firstClimb),
            OnboardingAnalyticsEvent.paywallContext
        ]

        for step in steps {
            harness.record(step)
        }
        // Back to `first_climb`, forward again to the paywall. Every recorder here is a fresh
        // instance, exactly as a rebuilt view would be.
        for step in [steps[2], steps[3]] {
            harness.record(step)
        }

        #expect(harness.viewedScreenIDs == ["welcome", "gender", "first_climb", "paywall"])
    }

    @Test
    func aRelaunchMidPassReEmitsNothingButReportsTheResumeOnce() {
        let defaults = Self.makeDefaults()
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)

        let firstLaunch = OnboardingFlowAnalyticsCoordinator(userDefaults: defaults, telemetry: telemetry)
        for step in [OnboardingAnalyticsEvent.welcomeContext, Self.context(for: .gender)] {
            firstLaunch.recordFlowStartedIfNeeded(context: step)
            firstLaunch.reportResumeIfNeeded(context: step)
            OnboardingScreenViewRecorder(lifecycle: firstLaunch).recordIfNeeded(step, telemetry: telemetry)
        }
        #expect(sink.records.filter { $0.name == "onboarding_flow_resumed" }.isEmpty)

        // The process dies. A relaunch rebuilds the coordinator over the persisted pass.
        let relaunch = OnboardingFlowAnalyticsCoordinator(userDefaults: defaults, telemetry: telemetry)
        for step in [Self.context(for: .gender), Self.context(for: .age)] {
            relaunch.recordFlowStartedIfNeeded(context: step)
            relaunch.reportResumeIfNeeded(context: step)
            OnboardingScreenViewRecorder(lifecycle: relaunch).recordIfNeeded(step, telemetry: telemetry)
        }

        let viewed = sink.records
            .filter { $0.name == "onboarding_screen_viewed" }
            .compactMap { record -> String? in
                guard case .string(let id)? = record.parameters["screen_id"] else { return nil }
                return id
            }
        // `gender` was already banked by the first launch, so only `age` is new.
        #expect(viewed == ["welcome", "gender", "age"])
        #expect(sink.records.filter { $0.name == "onboarding_flow_started" }.count == 1)

        let resumed = sink.records.filter { $0.name == "onboarding_flow_resumed" }
        #expect(resumed.count == 1)
        #expect(resumed.first?.parameters["screen_id"] == .string("gender"))
    }

    /// Retiring the pass is the only thing that makes a step reportable again, so a second climber
    /// on the same device is a fresh funnel entry rather than a silent one.
    @Test
    func retiringThePassMakesEveryStepReportableAgain() {
        let harness = Harness()
        harness.record(OnboardingAnalyticsEvent.welcomeContext)
        harness.record(OnboardingAnalyticsEvent.welcomeContext)
        #expect(harness.viewedScreenIDs == ["welcome"])

        harness.lifecycle.adoptPassOwner("user-1")
        harness.lifecycle.retireAdoptedPass()

        harness.record(OnboardingAnalyticsEvent.welcomeContext)
        #expect(harness.viewedScreenIDs == ["welcome", "welcome"])
    }

    @Test
    func screenViewsNoLongerCarryAResumeFlag() {
        let harness = Harness()
        harness.record(OnboardingAnalyticsEvent.welcomeContext)

        let viewed = harness.sink.records.first { $0.name == "onboarding_screen_viewed" }
        #expect(viewed?.parameters["viewed"] == .bool(true))
        #expect(viewed?.parameters["resume"] == nil)
    }

    // MARK: - Harness

    @MainActor
    private final class Harness {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry: TelemetryManager
        let lifecycle: OnboardingFlowAnalyticsCoordinator

        init() {
            telemetry = makeTestTelemetry(sink: sink)
            lifecycle = OnboardingFlowAnalyticsCoordinator(
                userDefaults: OnboardingScreenViewPassDedupeTests.makeDefaults(),
                telemetry: telemetry
            )
        }

        /// Mirrors the shipped modifier: a fresh recorder every time, because the view holding it
        /// may have been torn down between screens.
        func record(_ context: OnboardingAnalyticsContext) {
            lifecycle.recordFlowStartedIfNeeded(context: context)
            lifecycle.reportResumeIfNeeded(context: context)
            OnboardingScreenViewRecorder(lifecycle: lifecycle)
                .recordIfNeeded(context, telemetry: telemetry)
        }

        var viewedScreenIDs: [String] {
            sink.records
                .filter { $0.name == "onboarding_screen_viewed" }
                .compactMap { record -> String? in
                    guard case .string(let id)? = record.parameters["screen_id"] else { return nil }
                    return id
                }
        }
    }

    private static func context(for stage: PostAuthOnboardingStage) -> OnboardingAnalyticsContext {
        stage.analyticsContext
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "OnboardingScreenViewPassDedupeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
