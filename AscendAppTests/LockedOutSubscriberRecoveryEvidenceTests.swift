import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the locked-out climber's recovery routes.
///
/// The contract suite holds the shape of the source and the hosting suite proves the routes
/// work; this hosts what the climber actually sees. The gate is hosted in a real window
/// (`RenderedScreen`) wired exactly the way `RootView` wires it, the hosted paywall's
/// `DELETE ACCOUNT` control is answered through the real gate, and the dialog that opens has its
/// copy read back off the accessibility tree - so the Apple-billing sentence is asserted from the
/// screen rather than from a string in a Swift file. Photographs are written only under
/// `ASCEND_EVIDENCE_DIR`.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LockedOutSubscriberRecoveryEvidenceTests {
    @Test
    func theHostedDeletionControlOpensTheRealDialogOverTheSpinner() async throws {
        let presenter = GateTestPresenter()
        let manager = MonetizationManager(
            configuration: makeGateTestConfiguration(),
            entitlementService: GateTestEntitlementService(
                identity: MonetizationIdentityTransition(revision: 1, userID: "user-a")
            ),
            paywallPresenter: presenter,
            appAccessReconciler: GateTestReconciler(),
            freeWeek: FreeWeekTestHarness(isEnabled: false).store,
            telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        )
        let controller = UIHostingController(
            rootView: LockedOutGateJourneyHarness(monetizationManager: manager)
                .modelContainer(for: AscendLocalStore.models, inMemory: true)
        )
        controller.overrideUserInterfaceStyle = .dark

        try await RenderedScreen.host(controller) { screen in
            #expect(await gateWaitUntil { presenter.placements == [.appAccessGate] })
            presenter.send(.presented, registration: 0)
            // Behind the hosted paywall the gate is a spinner: no plan, no link, no line of copy.
            try await expectOnlyTheGateSpinner(on: screen, "the locked-out gate")
            try screen.photograph(named: "locked-out-gate-spinner")

            // The hosted paywall's DELETE ACCOUNT, which Ascend has dismissed the paywall to answer.
            presenter.send(.deleteAccountRequested, registration: 0)

            let sheet = try await presentedSheet(of: controller)
            _ = try await settledAccessibilityElements(under: sheet.view) { elements in
                elements.contains { $0.accessibilityLabel?.contains("billed by Apple") == true }
            }
            try await screen.settle()

            let dialogText = try await screen.copy { $0.contains("billed by apple") }
            try screen.photograph(named: "locked-out-gate-deletion-dialog")
            #expect(dialogText.contains("delete account"))
            #expect(dialogText.contains("billed by apple"))
            #expect(dialogText.contains("keeps renewing after deletion"))
            #expect(dialogText.contains("cancel it in your apple subscription settings"))
            #expect(dialogText.contains("cannot be undone"))
            #expect(dialogText.contains("sign in again"))
        }
    }

    @Test
    func settingsShowsManageSubscriptionAboveRestorePurchases() async throws {
        let size = CGSize(width: 390, height: 1500)
        let controller = UIHostingController(
            rootView: NavigationStack {
                AccountView()
                    .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        try await RenderedScreen.host(controller, size: size) { screen in
            let text = try await screen.copy { $0.contains("restore purchases") }
            try screen.photograph(named: "settings-manage-subscription")

            let manage = try #require(
                text.range(of: "manage subscription"),
                "Settings never drew a Manage Subscription row. Read: \(text)"
            )
            let restore = try #require(text.range(of: "restore purchases"))
            #expect(
                manage.lowerBound < restore.lowerBound,
                "Managing the plan must lead the Subscription section"
            )
        }
    }

    // MARK: - Hosting

    /// The dialog once it exists and has taken a real height - a merely-present sheet still measures
    /// zero by zero, and a read there sees an empty screen.
    private func presentedSheet(
        of controller: UIViewController,
        waitingUpTo timeout: Duration = .seconds(5)
    ) async throws -> UIViewController {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let presented = controller.presentedViewController {
                presented.view.setNeedsLayout()
                presented.view.layoutIfNeeded()
                if presented.view.bounds.height > 0 {
                    return presented
                }
            }

            try await Task.sleep(for: .milliseconds(20))
        }

        let sheet = try #require(controller.presentedViewController, "The dialog never presented")
        #expect(sheet.view.bounds.height > 0, "The dialog never took its detent")
        return sheet
    }
}

/// The gate wired the way `RootView` wires it: the hosted control presents the real deletion dialog.
private struct LockedOutGateJourneyHarness: View {
    let monetizationManager: MonetizationManager
    @State private var isShowingDeletion = false

    var body: some View {
        AppAccessPaywallPlaceholderView(
            onDeleteAccount: { isShowingDeletion = true },
            onSignOut: {}
        )
        .environment(monetizationManager)
        .sheet(isPresented: $isShowingDeletion) {
            DeleteAccountConfirmationView(onAccountDeleted: {})
        }
    }
}
