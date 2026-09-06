import Foundation
import enum SuperwallKit.PurchaseResult
import Testing
@testable import AscendApp

/// The whole back-out-of-the-paywall journey, driven through the shipped pieces in the order the
/// running app wires them: the SuperwallKit dismissal a back tap produces, the presenter's custom
/// action latch, `MonetizationManager`, the gate coordinator, the onboarding coordinator, and the
/// root route a climber actually sees.
///
/// Renders the journey as a transcript so the funnel a real session emits is readable rather than
/// inferred, and writes it to `ASCEND_EVIDENCE_DIR` alongside the gate's rendered screenshots.
@MainActor
struct PaywallBackToOnboardingJourneyEvidenceTests {
    @Test
    func aClimberWalksBackFromThePaywallIntoOnboardingAndForwardAgainWithoutDoubleCounting() throws {
        let journey = Journey()

        // 1. The climber is on the last onboarding screen, which reports its view.
        journey.viewOnboardingScreen(.firstClimb)
        journey.note("first_climb is on screen; route = \(journey.route)")
        #expect(journey.route == .onboarding(.firstClimb))

        // 2. They finish it. With no entitlement the paywall is the next and last step.
        journey.finishOnboarding()
        journey.note("onboarding finished, no entitlement; route = \(journey.route)")
        #expect(journey.route == .paywall)

        // 3. The gate opens the hosted Superwall paywall, which reports the paywall screen view.
        let firstArrival = journey.arriveAtPaywall()
        journey.note("hosted paywall presented; route = \(journey.route)")
        #expect(journey.route == .paywall)

        // 4. The climber taps the paywall's back arrow. SuperwallKit fires the custom action and
        //    then closes with the same `declined`/`manualClose` every other close reports.
        journey.tapPaywallBackArrow()
        journey.note("back tapped; route = \(journey.route)")

        // The captain's rule: back never falls through to the native plan list.
        #expect(firstArrival.nativeProvider.loadCount == 0)
        #expect(firstArrival.gate.phase != .nativeReady)
        #expect(journey.route == .onboarding(.firstClimb))
        #expect(journey.postAuth.isReopenedByClimber)

        // 5. `RootView` re-checks the remote profile, which is already complete for anyone who
        //    reached the paywall. The back tap must survive it.
        journey.simulateRemoteProfileRecheck()
        journey.note("remote profile re-check ran; route = \(journey.route)")
        #expect(journey.route == .onboarding(.firstClimb))

        // 6. The re-passed screen renders again from a freshly built view. It must report nothing.
        journey.viewOnboardingScreen(.firstClimb)

        // 7. Forward again: second arrival at the paywall is identical to the first and
        //    re-presents Superwall.
        journey.finishOnboarding()
        #expect(journey.route == .paywall)
        #expect(!journey.postAuth.isReopenedByClimber)
        let secondArrival = journey.arriveAtPaywall()
        journey.note("second arrival at the paywall; route = \(journey.route)")

        let transcript = journey.renderTranscript()
        print(transcript)
        Journey.writeEvidence(transcript, named: "paywall-back-to-onboarding-journey")

        // No screen reports itself twice across the whole journey.
        #expect(
            journey.viewedScreenIDs == ["first_climb", "paywall"],
            "Screen views double-counted: \(journey.viewedScreenIDs)"
        )

        // The back tap reports itself once, from the paywall.
        let backTaps = journey.records(named: "onboarding_back_tapped")
        #expect(backTaps.count == 1)
        #expect(backTaps.first?.parameters["from_step"] == .string("paywall"))

        // The second arrival re-presents Superwall and looks exactly like the first: no variant,
        // no arrival counter.
        let arrivals = journey.records(named: "paywall_reached")
        #expect(arrivals.count == 2)
        #expect(arrivals.first?.parameters == arrivals.last?.parameters)
        #expect(arrivals.allSatisfy { $0.parameters["arrival_count"] == nil })
        // The second arrival is a genuinely new Superwall presentation, not a reuse of the first.
        #expect(secondArrival.presentationRevision > firstArrival.presentationRevision)

        // The resume signal is its own event now. This pass opened at `first_climb` rather than at
        // the flow's start, so it reports exactly one resume - and walking back does not re-report
        // it, which is what a re-emitted screen view used to do.
        #expect(journey.records(named: "onboarding_flow_resumed").count == 1)
        #expect(
            journey.records(named: "onboarding_screen_viewed")
                .allSatisfy { $0.parameters["resume"] == nil }
        )
    }

    // MARK: - Journey

    @MainActor
    private final class Journey {
        struct Arrival {
            let gate: AppAccessPaywallCoordinator
            let nativeProvider: JourneyNativeProviderSpy
            /// The Superwall presentation attempt this arrival opened.
            let presentationRevision: UInt
        }

        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry: TelemetryManager
        let lifecycle: OnboardingFlowAnalyticsCoordinator
        let postAuth: PostAuthOnboardingCoordinator
        let manager: MonetizationManager
        let presenter: SuperwallPaywallPresenter

        private let placements: PlacementRecorder
        private let registry = SuperwallPresentationAttemptRegistry()
        private let userID = "test-user"
        private var notes: [(index: Int, text: String)] = []

        init() {
            telemetry = makeTestTelemetry(sink: sink)
            telemetry.setUserId(userID)
            lifecycle = makeScratchOnboardingLifecycle(telemetry: telemetry)
            lifecycle.adoptPassOwner(userID)

            let placementRecorder = PlacementRecorder()
            placements = placementRecorder
            presenter = SuperwallPaywallPresenter(
                telemetry: telemetry,
                attemptRegistry: registry,
                startsConfigured: true,
                registerPlacement: { placement, _, _ in placementRecorder.record(placement) },
                dismissPresentation: {}
            )

            manager = MonetizationManager(
                configuration: MonetizationConfiguration(infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]),
                entitlementService: EntitlementServiceStub(entitlementState: .inactive),
                paywallPresenter: presenter,
                telemetry: telemetry,
                onboardingLifecycle: lifecycle,
                userDefaults: Self.scratchDefaults("Journey.monetization")
            )

            postAuth = PostAuthOnboardingCoordinator(
                store: PostAuthOnboardingStore(
                    userDefaults: Self.scratchDefaults("Journey.onboarding")
                ),
                telemetry: telemetry
            )
            postAuth.resolve(userId: userID)
            // Walk to the last onboarding stage the way the climber does.
            while case .onboarding(let stage) = postAuth.phase, stage != .firstClimb {
                postAuth.completeCurrentStage()
            }
        }

        /// The route `RootView` renders, resolved from the same state the app resolves it from.
        var route: AppRootRoute {
            AppRootRouteResolver.resolve(
                updatePresentation: nil,
                authenticationState: .authenticated,
                userId: userID,
                postAuthOnboardingPhase: postAuth.phase,
                entitlementState: .inactive,
                requiredEntitlementID: manager.configuration.revenueCatEntitlementID
            )
        }

        /// Mirrors `.trackOnboardingScreenView`: a fresh recorder every time, because the view that
        /// used to hold the dedupe is rebuilt - or destroyed by the route change - between screens.
        func viewOnboardingScreen(_ stage: PostAuthOnboardingStage) {
            let context = stage.analyticsContext
            lifecycle.recordFlowStartedIfNeeded(context: context)
            lifecycle.reportResumeIfNeeded(context: context)
            OnboardingScreenViewRecorder(lifecycle: lifecycle)
                .recordIfNeeded(context, telemetry: telemetry)
        }

        func finishOnboarding() {
            postAuth.completeCurrentStage()
        }

        /// Mounts a fresh gate coordinator, exactly as routing to `.paywall` does, and opens the
        /// hosted paywall through the real presenter.
        @discardableResult
        func arriveAtPaywall() -> Arrival {
            let nativeProvider = JourneyNativeProviderSpy()
            let gate = AppAccessPaywallCoordinator(
                monetizationManager: manager,
                nativeProvider: nativeProvider,
                telemetry: telemetry,
                onRequestOnboardingBack: { [postAuth] in postAuth.reopenLastStage() },
                sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
            )
            gate.start()
            presenter.handlePresentationBegan(
                revision: registry.currentRevision,
                presentationID: "presentation-\(registry.currentRevision)"
            )
            return Arrival(
                gate: gate,
                nativeProvider: nativeProvider,
                presentationRevision: registry.currentRevision
            )
        }

        /// The back control fires a `Custom action` and SuperwallKit then closes the paywall with
        /// the same `declined` every other user-driven close reports.
        func tapPaywallBackArrow() {
            presenter.handleCustomPaywallAction(withName: SuperwallCustomAction.back.rawValue)
            presenter.handleDismissForTesting(
                revision: registry.currentRevision,
                result: .declined
            )
        }

        /// `RootView.completePostAuthOnboardingIfRemoteProfileExists` re-completes onboarding from a
        /// loaded remote profile. Its guard is `isReopenedByClimber`.
        func simulateRemoteProfileRecheck() {
            guard !postAuth.isReopenedByClimber else { return }
            postAuth.markCurrentUserComplete()
        }

        func note(_ text: String) {
            notes.append((index: sink.records.count, text: text))
        }

        func records(named name: String) -> [EnvelopedTelemetryRecord] {
            sink.records.filter { $0.name == name }
        }

        var viewedScreenIDs: [String] {
            records(named: "onboarding_screen_viewed").compactMap { record in
                guard case .string(let id)? = record.parameters["screen_id"] else { return nil }
                return id
            }
        }

        func renderTranscript() -> String {
            var lines = [
                "PAYWALL BACK-TO-ONBOARDING JOURNEY",
                String(repeating: "=", count: 78),
                ""
            ]
            var noteIndex = 0
            for (index, record) in sink.records.enumerated() {
                while noteIndex < notes.count, notes[noteIndex].index <= index {
                    lines.append("  -- \(notes[noteIndex].text)")
                    noteIndex += 1
                }
                let parameters = record.parameters
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(Self.describe($0.value))" }
                    .joined(separator: " ")
                lines.append("  \(record.name.padding(toLength: 34, withPad: " ", startingAt: 0)) \(parameters)")
            }
            while noteIndex < notes.count {
                lines.append("  -- \(notes[noteIndex].text)")
                noteIndex += 1
            }
            lines.append("")
            lines.append("onboarding_screen_viewed order: \(viewedScreenIDs)")
            return lines.joined(separator: "\n")
        }

        private static func describe(_ value: TelemetryValue) -> String {
            switch value {
            case .string(let string): return string
            case .bool(let flag): return String(flag)
            case .int(let number): return String(number)
            case .double(let number): return String(number)
            }
        }

        private static func scratchDefaults(_ prefix: String) -> UserDefaults {
            let suiteName = "\(prefix).\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            return defaults
        }

        static func writeEvidence(_ text: String, named name: String) {
            let sourceRoot = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"].map {
                URL(filePath: $0, directoryHint: .isDirectory)
            } ?? sourceRoot.appending(path: ".build/issue554-evidence", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appending(path: "\(name).txt")
            try? Data(text.utf8).write(to: url)
            print("evidence: \(url.path())")
        }
    }
}

@MainActor
private final class PlacementRecorder {
    private(set) var placements: [String] = []

    var count: Int { placements.count }

    func record(_ placement: String) {
        placements.append(placement)
    }
}

@MainActor
private final class JourneyNativeProviderSpy: NativeSubscriptionProviding {
    private(set) var loadCount = 0

    func loadPlans() async throws -> [NativeSubscriptionPlan] {
        loadCount += 1
        return []
    }

    func purchase(planID: String) async -> PurchaseResult { .cancelled }
}
