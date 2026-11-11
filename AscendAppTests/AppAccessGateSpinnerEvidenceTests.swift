import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The app-access gate, hosted through `RenderedScreen` and read back off the screen: in every
/// state it can be in, the only thing Ascend draws is the system spinner at the centre of a black
/// screen. No headline, no status line, no plan, no button.
///
/// "Nothing else" is read two ways, because either alone can be fooled. The accessibility tree
/// says the gate publishes no label or value beyond the spinner's own element. The pixels say that
/// everything drawn fits a small box at the centre of the screen, which a single line of copy
/// anywhere would break. Photographs are written only under `ASCEND_EVIDENCE_DIR`.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppAccessGateSpinnerEvidenceTests {
    @Test(arguments: SpinnerSurface.all)
    func theSpinnerIsCentredOnBlackWithNothingElseOnTheScreen(surface: SpinnerSurface) async throws {
        let content = AppAccessSpinnerView()
            .environment(\.dynamicTypeSize, surface.dynamicTypeSize)

        try await RenderedScreen.host(
            content,
            size: surface.size,
            interfaceStyle: surface.style
        ) { screen in
            try await expectOnlyTheGateSpinner(on: screen, surface.id)

            // The app's background, edge to edge, whatever the system appearance is.
            let corners = [
                CGPoint(x: 2, y: 2),
                CGPoint(x: surface.size.width - 3, y: 2),
                CGPoint(x: 2, y: surface.size.height - 3),
                CGPoint(x: surface.size.width - 3, y: surface.size.height - 3)
            ]
            for corner in corners {
                let colour = try screen.color(at: corner)
                #expect(colour.luminance < 8, "\(surface.id): \(corner) is not the black background")
            }
            try screen.photograph(named: "app-access-gate-spinner-\(surface.id)")
        }
    }

    /// One session at the gate, from the paywall opening to the app opening, with a free week on
    /// offer: every wait in it is the same spinner.
    @Test
    func everyStateFromThePaywallToTheFreeWeekIsTheSameSpinner() async throws {
        let harness = await GateEvidenceHarness(freeWeekEnabled: true)
        harness.freeWeek.granter.responses = [.failure(FreeWeekTestError())]

        try await RenderedScreen.host(harness.view) { screen in
            #expect(await gateWaitUntil { harness.presenter.placements == [.appAccessGate] })
            try await expectOnlyTheGateSpinner(on: screen, "opening the paywall")
            try screen.photograph(named: "app-access-gate-01-opening-paywall")

            harness.presenter.send(.presented, registration: 0)
            try await expectOnlyTheGateSpinner(on: screen, "behind the paywall")

            harness.presenter.send(.followOnPaywallOpening, registration: 0)
            try await expectOnlyTheGateSpinner(on: screen, "opening the decline offer")
            harness.presenter.send(.presented, registration: 0)

            // "No thanks" on the decline offer: the founder letter is asked for.
            harness.presenter.send(.dismissedWithoutPurchase, registration: 0)
            #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
            try await expectOnlyTheGateSpinner(on: screen, "opening the founder letter")
            try screen.photograph(named: "app-access-gate-02-after-no-thanks")

            harness.presenter.send(.presented, registration: 1)
            try await expectOnlyTheGateSpinner(on: screen, "behind the founder letter")

            // The letter closes and the server cannot start the week yet.
            harness.presenter.send(.dismissedWithoutPurchase, registration: 1)
            #expect(await gateWaitUntil { harness.freeWeek.granter.callCount >= 2 })
            try await expectOnlyTheGateSpinner(on: screen, "the week could not be started yet")
            try screen.photograph(named: "app-access-gate-03-starting-free-week")

            // The gate asks again by itself, and this time the week lands.
            harness.freeWeek.granter.responses = [.success(.granted(harness.freeWeek.week()))]
            #expect(await gateWaitUntil { harness.freeWeek.store.routingAccess == .live })
            try await expectOnlyTheGateSpinner(on: screen, "access confirmed, route not yet resolved")
            try screen.photograph(named: "app-access-gate-04-access-confirmed")

            // Nothing native was ever asked for: two hosted screens, and that is all.
            #expect(harness.presenter.placements == [.appAccessGate, .founderLetter])
        }
    }

    /// The failure paths, which used to be where the plan picker and its messages lived.
    @Test
    func aPaywallThatCannotOpenAndAChargeThatCannotBeConfirmedAreTheSameSpinner() async throws {
        let harness = await GateEvidenceHarness(freeWeekEnabled: false)

        try await RenderedScreen.host(harness.view) { screen in
            #expect(await gateWaitUntil { harness.presenter.placements.count == 1 })

            // Superwall refuses the paywall, and the climber leaves and comes back.
            harness.presenter.send(.skipped(reason: "no_rule_match"), registration: 0)
            NotificationCenter.default.post(
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            #expect(
                await gateWaitUntil { harness.presenter.placements.count == 2 },
                "Coming back to the app never asked for the paywall again"
            )
            #expect(harness.presenter.sources.last == "foreground_retry")
            try await expectOnlyTheGateSpinner(on: screen, "the paywall could not open")
            try screen.photograph(named: "app-access-gate-05-paywall-could-not-open")

            // Apple charged, and RevenueCat has not confirmed it.
            harness.presenter.send(.presented, registration: 1)
            harness.manager.holdPendingPurchase(.unconfirmedCharge)
            harness.presenter.send(.verificationUnavailable, registration: 1)
            #expect(await gateWaitUntil { harness.entitlements.refreshCount >= 1 })
            try await expectOnlyTheGateSpinner(on: screen, "a charge is not confirmed yet")
            try screen.photograph(named: "app-access-gate-06-confirming-access")

            // The next check on the schedule finds the purchase.
            harness.entitlements.entitlementState = .active(["app_access"])
            #expect(await gateWaitUntil { harness.entitlements.refreshCount >= 2 })
            try await expectOnlyTheGateSpinner(on: screen, "the charge confirmed")
            #expect(harness.presenter.placements == [.appAccessGate, .appAccessGate])
        }
    }

    /// The gate draws no control, so the two routes Apple requires leave from the hosted paywall
    /// and are answered here.
    @Test(arguments: [HostedExit.deleteAccount, .signOut])
    func theHostedPaywallsDeleteAccountAndSignOutStillReachTheApp(exit: HostedExit) async throws {
        let harness = await GateEvidenceHarness(freeWeekEnabled: false)

        try await RenderedScreen.host(harness.view) { screen in
            #expect(await gateWaitUntil { harness.presenter.placements.count == 1 })
            harness.presenter.send(.presented, registration: 0)

            harness.presenter.send(exit.outcome, registration: 0)

            #expect(harness.deletionRequests == (exit == .deleteAccount ? 1 : 0))
            #expect(harness.signOutRequests == (exit == .signOut ? 1 : 0))
            // Neither asks Superwall for another screen, and neither draws one of the gate's own.
            #expect(harness.presenter.placements == [.appAccessGate])
            try await expectOnlyTheGateSpinner(on: screen, "after \(exit)")
        }
    }

    /// The deletion dialog closing without a deletion puts the paywall back, because the spinner
    /// has nothing behind it.
    @Test
    func backingOutOfAccountDeletionReopensTheHostedPaywall() async throws {
        let harness = await GateEvidenceHarness(freeWeekEnabled: false)

        try await RenderedScreen.host(harness.view) { screen in
            #expect(await gateWaitUntil { harness.presenter.placements.count == 1 })
            harness.presenter.send(.presented, registration: 0)
            harness.presenter.send(.deleteAccountRequested, registration: 0)
            #expect(harness.deletionRequests == 1)

            harness.dismissAccountDeletion()

            #expect(await gateWaitUntil { harness.presenter.placements.count == 2 })
            #expect(harness.presenter.sources.last == "account_deletion_dismissed")
            try await expectOnlyTheGateSpinner(on: screen, "the paywall is reopening")
        }
    }
}

enum HostedExit: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case deleteAccount
    case signOut

    var outcome: PaywallPresentationOutcome {
        switch self {
        case .deleteAccount: .deleteAccountRequested
        case .signOut: .signOutRequested
        }
    }

    var testDescription: String { rawValue }
}

struct SpinnerSurface: CustomTestStringConvertible, Sendable {
    let id: String
    let size: CGSize
    let dynamicTypeSize: DynamicTypeSize
    let style: UIUserInterfaceStyle

    var testDescription: String { id }

    static let all: [SpinnerSurface] = [
        .init(id: "compact-dark", size: CGSize(width: 375, height: 667), dynamicTypeSize: .large, style: .dark),
        .init(id: "large-system-light", size: CGSize(width: 430, height: 932), dynamicTypeSize: .large, style: .light),
        .init(id: "accessibility-dark", size: CGSize(width: 430, height: 932), dynamicTypeSize: .accessibility3, style: .dark)
    ]
}

/// The real gate view over a manager whose Superwall, RevenueCat and free week are scripted.
@MainActor
private final class GateEvidenceHarness {
    let presenter = GateTestPresenter()
    let entitlements = GateTestEntitlementService(
        identity: MonetizationIdentityTransition(revision: 1, userID: "user-a")
    )
    let freeWeek: FreeWeekTestHarness
    let manager: MonetizationManager
    private let state = GateEvidenceState()

    var deletionRequests: Int { state.deletionRequests }
    var signOutRequests: Int { state.signOutRequests }

    init(freeWeekEnabled: Bool) async {
        freeWeek = FreeWeekTestHarness(isEnabled: freeWeekEnabled)
        freeWeek.store.setUser("user-a")
        if freeWeekEnabled {
            _ = await gateWaitUntil { [freeWeek] in freeWeek.store.record != .unknown }
        }
        let telemetry = makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        telemetry.setUserId("user-a")
        manager = MonetizationManager(
            configuration: makeGateTestConfiguration(),
            entitlementService: entitlements,
            paywallPresenter: presenter,
            appAccessReconciler: GateTestReconciler(),
            freeWeek: freeWeek.store,
            telemetry: telemetry,
            onboardingLifecycle: makeScratchOnboardingLifecycle(telemetry: telemetry),
            userDefaults: UserDefaults(suiteName: "AppAccessGateSpinnerEvidence-\(UUID().uuidString)")!
        )
    }

    var view: some View {
        GateEvidenceView(state: state)
            .environment(manager)
    }

    /// What `RootView` does when its deletion sheet closes.
    func dismissAccountDeletion() {
        state.accountDeletionDismissalRevision &+= 1
    }
}

@MainActor
@Observable
private final class GateEvidenceState {
    var deletionRequests = 0
    var signOutRequests = 0
    var accountDeletionDismissalRevision: UInt = 0
}

/// The gate wired the way `RootView` wires it.
private struct GateEvidenceView: View {
    let state: GateEvidenceState

    var body: some View {
        AppAccessPaywallPlaceholderView(
            accountDeletionDismissalRevision: state.accountDeletionDismissalRevision,
            onDeleteAccount: { state.deletionRequests += 1 },
            onSignOut: { state.signOutRequests += 1 }
        )
    }
}
