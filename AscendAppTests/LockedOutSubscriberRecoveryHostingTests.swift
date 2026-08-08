import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The two surfaces a locked-out climber has to be able to *operate*, hosted in a real window and
/// driven through the same accessibility activation VoiceOver uses.
///
/// The source-level contract next door proves the controls are wired; this proves a climber can
/// actually reach them - the gate publishes a pressable deletion control, and the dialog it opens
/// shows every line of its grown copy inside the detent it declares.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LockedOutSubscriberRecoveryHostingTests {
    private static let iPhone16ProSize = CGSize(width: 402, height: 874)

    @Test("The gate publishes a pressable deletion control and no sign-out escape")
    func theGateOffersDeletionAndNothingElseNew() async throws {
        try await withAccessibilityAutomation {
            let recorder = DeletionPresentationRecorder()
            let manager = MonetizationManager(
                entitlementService: EntitlementServiceStub(),
                paywallPresenter: PaywallPresenterSpy(),
                telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
            )
            let controller = UIHostingController(
                rootView: AppAccessPaywallPlaceholderView(
                    initialPresentationState: .readyToRetry,
                    onDeleteAccount: { recorder.didRequestDeletion = true }
                )
                .environment(manager)
            )

            try await withHostedWindow(controller) { root in
                let elements = try await settledAccessibilityElements(under: root) { elements in
                    elements.contains { $0.accessibilityLabel == "Delete account" }
                }
                let labels = elements.compactMap(\.accessibilityLabel)

                #expect(labels.contains("Delete account"))
                #expect(
                    !labels.contains { $0.localizedCaseInsensitiveContains("sign out") },
                    "Signing back in returns to this same screen, so the gate offers no sign-out"
                )

                try activateAccessibilityElement(labelled: "Delete account", in: root)
                #expect(recorder.didRequestDeletion)
            }
        }
    }

    @Test("The deletion dialog shows all of its copy inside the detent it declares")
    func theDeletionDialogFitsItsGrownCopy() async throws {
        try await withAccessibilityAutomation {
            let controller = UIHostingController(
                rootView: DeleteAccountDialogHarness()
                    .modelContainer(for: AscendLocalStore.models, inMemory: true)
            )

            try await withHostedWindow(controller) { _ in
                let sheet = try await presentedSheet(of: controller)
                let elements = try await settledAccessibilityElements(under: sheet.view) { elements in
                    elements.contains { $0.accessibilityLabel == "Cancel" }
                }

                let billingLine = try #require(
                    elements.first { $0.accessibilityLabel?.contains("billed by Apple") == true },
                    """
                    The dialog never published the Apple-billing sentence. \
                    Found: \(elements.compactMap(\.accessibilityLabel))
                    """
                )
                #expect(
                    billingLine.accessibilityLabel?.localizedCaseInsensitiveContains("keeps renewing")
                        == true
                )

                // A hand-tuned detent is only correct while the copy still fits it, and the copy just
                // grew. The dialog centres its stack, so a detent that is short by one line pushes
                // the title off the top and Cancel off the bottom at once - hence every element.
                let bounds = sheet.view.convert(sheet.view.bounds, to: nil)
                for element in elements {
                    #expect(
                        bounds.contains(element.accessibilityFrame),
                        """
                        \(element.accessibilityLabel ?? "An element") at \(element.accessibilityFrame) \
                        spills out of the sheet \(bounds)
                        """
                    )
                }
            }
        }
    }

    // MARK: - Hosting

    private func withHostedWindow(
        _ controller: UIViewController,
        perform body: (UIView) async throws -> Void
    ) async throws {
        let windowScene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(origin: .zero, size: Self.iPhone16ProSize)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        try await body(controller.view)
    }

    private func presentedSheet(
        of controller: UIViewController,
        waitingUpTo timeout: Duration = .seconds(5)
    ) async throws -> UIViewController {
        // The detent is applied by the presentation controller a run loop turn or more after the
        // sheet exists, so a view that is merely present still measures zero by zero - and every
        // containment check against it passes vacuously.
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

@MainActor
private final class DeletionPresentationRecorder {
    var didRequestDeletion = false
}

/// Presents the real dialog the way `RootView` and Settings both do - as a sheet, so the detent it
/// declares is the one under test.
private struct DeleteAccountDialogHarness: View {
    @State private var isPresented = true

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                DeleteAccountConfirmationView(onAccountDeleted: {})
            }
    }
}
