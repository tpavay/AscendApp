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
/// keeps every line of its grown copy reachable at the default text size and at an accessibility
/// one, where this copy roughly triples.
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

    @Test(
        "The deletion dialog keeps every line of its copy reachable at any text size",
        arguments: [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge]
    )
    func theDeletionDialogFitsItsGrownCopy(
        contentSizeCategory: UIContentSizeCategory
    ) async throws {
        try await withAccessibilityAutomation {
            let controller = UIHostingController(
                rootView: DeleteAccountDialogHarness()
                    .modelContainer(for: AscendLocalStore.models, inMemory: true)
            )
            controller.overrideUserInterfaceStyle = .dark
            controller.traitOverrides.preferredContentSizeCategory = contentSizeCategory

            try await withHostedWindow(controller) { _ in
                let sheet = try await presentedSheet(of: controller)
                // A sheet is presented into the window rather than into the presenter's view, so the
                // presenter's override does not reach it on its own.
                sheet.traitOverrides.preferredContentSizeCategory = contentSizeCategory
                sheet.view.setNeedsLayout()
                sheet.view.layoutIfNeeded()

                let elements = try await settledAccessibilityElements(under: sheet.view) { elements in
                    elements.contains { $0.accessibilityLabel?.contains("billed by Apple") == true }
                }
                #expect(elements.contains { $0.accessibilityLabel == "Cancel" })

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
                #expect(
                    billingLine.accessibilityLabel?
                        .contains("If you have an Ascend subscription") == true,
                    "The billing warning is conditional, not an assertion that the climber subscribed"
                )

                // Every Montserrat helper is declared `relativeTo:`, so this copy triples at an
                // accessibility size. The dialog centres its stack, so a size it cannot take pushes
                // the title off the top and Cancel off the bottom at once - hence every element,
                // measured against the area a climber can actually scroll to.
                let scrollView = try #require(
                    firstScrollView(under: sheet.view),
                    "The dialog must host its copy in a scroll view so no text size can clip it"
                )
                // The sheet's own container element is taller than the scrollable content by the
                // bottom safe area, so reachable is the union rather than either one alone.
                let reachable = scrollView
                    .convert(CGRect(origin: .zero, size: scrollView.contentSize), to: nil)
                    .union(sheet.view.convert(sheet.view.bounds, to: nil))
                for element in elements {
                    #expect(
                        reachable.insetBy(dx: -0.5, dy: -0.5).contains(element.accessibilityFrame),
                        """
                        \(element.accessibilityLabel ?? "An element") at \(element.accessibilityFrame) \
                        is unreachable inside the dialog \(reachable)
                        """
                    )
                }

                if contentSizeCategory == .large {
                    // At the default text size the dialog still hugs its copy: scrolling here would
                    // mean the sheet came up short, which is the bug the fixed detent had.
                    #expect(
                        scrollView.contentSize.height <= scrollView.bounds.height + 1,
                        """
                        The dialog needs scrolling at the default text size: content \
                        \(scrollView.contentSize.height) in \(scrollView.bounds.height)
                        """
                    )
                }
            }
        }
    }

    private func firstScrollView(under view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let found = firstScrollView(under: subview) {
                return found
            }
        }

        return nil
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
