import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the climber the lockout used to miss: unentitled, on a stale build.
///
/// The resolver suite holds the ordering and the hosting suite proves the lockout's controls are
/// operable. This hosts the screen the climber actually lands on, reads its copy off the
/// accessibility tree (`RenderedScreen`), photographs it when `ASCEND_EVIDENCE_DIR` is set, and drives it from the real
/// chain rather than from a hand-set verdict: a `RemoteFeatureFlagService` over a fake backend
/// resolves ``AppVersionGateState``, the same ``AppRootRouteResolver`` `RootView` calls picks the
/// route, and the harness renders whatever that route names - the paywall gate or the lockout - with
/// the nudge sheet wired at the same modifier level `RootView` wires it at.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppUpdateLockoutRootRouteEvidenceTests {
    /// The defect end to end. The same unentitled climber, the same session: with no floor the gate
    /// hands off to Superwall, and the moment an operator arms the floor the refusal takes the whole
    /// screen instead. Under the old sheet this climber kept the paywall and never saw the lockout.
    @Test("An operator arming the floor replaces the paywall gate with the lockout", .bug(id: 429))
    func armingTheFloorTakesTheScreenFromTheUnentitledPaywallGate() async throws {
        let source = FakeVersionFloorSource()
        let gateState = AppVersionGateState()
        let service = RemoteFeatureFlagService(
            source: source,
            store: RemoteFeatureFlagStore(),
            appVersionGateState: gateState,
            appMarketingVersionProvider: .init { "1.0" }
        )
        defer { service.teardown() }

        service.configure()
        await service.refreshAndWait()
        #expect(gateState.presentation == nil)

        let controller = UIHostingController(
            rootView: RootRouteEvidenceHarness(
                gateState: gateState,
                entitlementState: .inactive,
                monetizationManager: makeMonetizationManager()
            )
        )
        controller.overrideUserInterfaceStyle = .dark

        try await RenderedScreen.host(controller) { screen in
            let paywallText = try await screen.copy { $0.contains("choose your ascend plan") }
            try screen.photograph(named: "root-route-unentitled-01-paywall-gate")
            #expect(paywallText.contains("choose your ascend plan"))
            #expect(!paywallText.contains("update required"))

            // The operator retires this build. No relaunch, no foreground - the listener lands it.
            source.setAppVersionValues([
                RemoteAppVersionParameter.minimumSupported.key: "1.1.0",
                RemoteAppVersionParameter.recommended.key: "1.2.0"
            ])
            source.emitUpdate([:])

            #expect(
                await settles { gateState.isUpdateRequired },
                "The armed floor never reached the gate state"
            )
            try await screen.settle()

            let lockoutText = try await screen.copy { $0.contains("update required") }
            try screen.photograph(named: "root-route-unentitled-02-lockout")
            #expect(lockoutText.contains("update required"))
            #expect(lockoutText.contains("update on the app store"))
            // The paywall gate is gone from the screen, not merely covered by something over it.
            #expect(!lockoutText.contains("choose your ascend plan"))
            #expect(!lockoutText.contains("restore purchases"))
            #expect(
                controller.presentedViewController == nil,
                "Something was presented over the refusal"
            )
        }
    }

    /// The offline cold start the policy is written for: nothing on this launch reaches the network,
    /// and the floor a previous launch persisted still refuses the build - before any view renders.
    @Test("An offline cold start still lands on the lockout", .bug(id: 429))
    func anOfflineColdStartStillLandsOnTheLockout() async throws {
        let source = FakeVersionFloorSource(
            fetchResult: .failure(RemoteFeatureFlagSourceError.fetchFailed),
            appVersionValues: [
                RemoteAppVersionParameter.minimumSupported.key: "1.1.0",
                RemoteAppVersionParameter.recommended.key: "1.2.0"
            ]
        )
        let gateState = AppVersionGateState()
        let service = RemoteFeatureFlagService(
            source: source,
            store: RemoteFeatureFlagStore(),
            appVersionGateState: gateState,
            appMarketingVersionProvider: .init { "1.0" }
        )
        defer { service.teardown() }

        service.configure()
        #expect(gateState.isUpdateRequired)

        let controller = UIHostingController(
            rootView: RootRouteEvidenceHarness(
                gateState: gateState,
                entitlementState: .active(["app_access"]),
                monetizationManager: makeMonetizationManager()
            )
        )
        controller.overrideUserInterfaceStyle = .dark

        try await RenderedScreen.host(controller) { screen in
            await service.waitForCurrentRefresh()
            try await screen.settle()

            let text = try await screen.copy { $0.contains("update required") }
            try screen.photograph(named: "root-route-offline-cold-start-lockout")
            #expect(text.contains("update required"))
            #expect(text.contains("this version is no longer supported"))
            #expect(text.contains("update on the app store"))
            #expect(text.contains("delete account"))
            // A paying climber is refused too: the lockout outranks the entitlement, not the reverse.
            #expect(service.hasCompletedInitialFetch == false)
            #expect(controller.presentedViewController == nil)
        }
    }

    /// The nudge is the half that stayed a sheet. Same harness, same modifier - it still opens over
    /// whatever the climber is on, and it still carries the Later that dismisses it.
    @Test("The soft nudge still arrives as a dismissible sheet over the app", .bug(id: 429))
    func theSoftNudgeStillArrivesAsADismissibleSheet() async throws {
        try await exerciseTheSoftNudge()
    }

    private func exerciseTheSoftNudge() async throws {
        let source = FakeVersionFloorSource()
        let gateState = AppVersionGateState()
        let service = RemoteFeatureFlagService(
            source: source,
            store: RemoteFeatureFlagStore(),
            appVersionGateState: gateState,
            appMarketingVersionProvider: .init { "1.0" }
        )
        defer { service.teardown() }

        service.configure()
        await service.refreshAndWait()

        let controller = UIHostingController(
            rootView: RootRouteEvidenceHarness(
                gateState: gateState,
                entitlementState: .inactive,
                monetizationManager: makeMonetizationManager()
            )
        )
        controller.overrideUserInterfaceStyle = .dark

        try await RenderedScreen.host(controller) { screen in
            source.setAppVersionValues([
                RemoteAppVersionParameter.minimumSupported.key: "0.9.0",
                RemoteAppVersionParameter.recommended.key: "1.2.0"
            ])
            source.emitUpdate([:])

            #expect(await settles { gateState.presentation == .recommended })
            #expect(gateState.isUpdateRequired == false)
            #expect(
                await settles { controller.presentedViewController?.view.bounds.height ?? 0 > 0 },
                "The recommendation never opened its sheet"
            )
            try await screen.settle()

            let text = try await screen.copy { $0.contains("a newer version is ready") }
            try screen.photograph(named: "root-route-soft-nudge-sheet")
            #expect(text.contains("a newer version is ready"))
            #expect(text.contains("later"))
            // Still a sheet: the gate it opened over is visible behind it.
            #expect(text.contains("choose your ascend plan"))

            let sheet = try #require(controller.presentedViewController)
            #expect(sheet.isModalInPresentation == false)
            try activateAccessibilityElement(labelled: "Later", in: sheet.view)
            #expect(
                await settles { controller.presentedViewController == nil },
                "Later did not dismiss the nudge"
            )
        }
    }

    // MARK: - Support

    private func makeMonetizationManager() -> MonetizationManager {
        MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        )
    }

    private func settles(
        waitingUpTo timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if condition() { return true }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// `RootView`'s root decision, reduced to the routes this bug is about.
///
/// The resolver call and the nudge sheet are the ones `RootView` makes, so the screen this renders
/// is the screen the app renders for the same state.
private struct RootRouteEvidenceHarness: View {
    let gateState: AppVersionGateState
    let entitlementState: MonetizationEntitlementState
    let monetizationManager: MonetizationManager

    var body: some View {
        Group {
            switch route {
            case .updateRequired:
                AppUpdateRequiredView(onOpenAppStore: {}, onDeleteAccount: {})
            case .paywall:
                AppAccessPaywallPlaceholderView(
                    initialPhase: .failed,
                    onDeleteAccount: {}
                )
            default:
                Color.black
            }
        }
        .environment(monetizationManager)
        .animation(.easeInOut(duration: 0.25), value: route)
        .sheet(item: Bindable(gateState).nudgePresentation) { presentation in
            AppUpdateSheet(
                presentation: presentation,
                onOpenAppStore: {},
                onLater: gateState.dismissRecommended
            )
        }
    }

    private var route: AppRootRoute {
        AppRootRouteResolver.resolve(
            updatePresentation: gateState.presentation,
            authenticationState: .authenticated,
            userId: "climber-on-a-stale-build",
            postAuthOnboardingPhase: .complete,
            entitlementState: entitlementState,
            requiredEntitlementID: "app_access"
        )
    }
}

/// A backend whose version floor the test moves, standing in for Remote Config.
private final class FakeVersionFloorSource: RemoteFeatureFlagSource, @unchecked Sendable {
    private let lock = NSLock()
    private let fetchResult: Result<[String: Bool], any Error>
    private var storedAppVersionValues: [String: String]
    private var onUpdate: (@Sendable ([String: Bool]) -> Void)?

    init(
        fetchResult: Result<[String: Bool], any Error> = .success([:]),
        appVersionValues: [String: String] = [:]
    ) {
        self.fetchResult = fetchResult
        storedAppVersionValues = appVersionValues
    }

    func setAppVersionValues(_ values: [String: String]) {
        lock.withLock { storedAppVersionValues = values }
    }

    func emitUpdate(_ values: [String: Bool]) {
        lock.withLock { onUpdate }?(values)
    }

    func fetchAndActivate() async throws -> [String: Bool] {
        try fetchResult.get()
    }

    func activatedValues() -> [String: Bool] { [:] }

    func appVersionValues() -> [String: String] {
        lock.withLock { storedAppVersionValues }
    }

    func startListening(onUpdate: @escaping @Sendable ([String: Bool]) -> Void) {
        lock.withLock { self.onUpdate = onUpdate }
    }

    func stopListening() {
        lock.withLock { onUpdate = nil }
    }
}
