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

    @Test("The gate publishes pressable deletion and sign-out recovery controls")
    func theGateOffersDeletionAndSignOut() async throws {
        try await withAccessibilityAutomation {
            let recorder = DeletionPresentationRecorder()
            let signOutRecorder = SignOutPresentationRecorder()
            let manager = MonetizationManager(
                entitlementService: EntitlementServiceStub(),
                paywallPresenter: PaywallPresenterSpy(),
                telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
            )
            let controller = UIHostingController(
                rootView: AppAccessPaywallPlaceholderView(
                    initialPhase: .failed,
                    onDeleteAccount: { recorder.didRequestDeletion = true; return true },
                    onSignOut: { signOutRecorder.didRequestSignOut = true }
                )
                .environment(manager)
            )

            try await withHostedWindow(controller) { root in
                let elements = try await settledAccessibilityElements(under: root) { elements in
                    elements.contains { $0.accessibilityLabel == "Delete account" }
                }
                let labels = elements.compactMap(\.accessibilityLabel)

                #expect(labels.contains("Delete account"))
                #expect(labels.contains("Sign Out"))

                try activateAccessibilityElement(labelled: "Delete account", in: root)
                #expect(recorder.didRequestDeletion)
                try activateAccessibilityElement(labelled: "Sign Out", in: root)
                #expect(signOutRecorder.didRequestSignOut)
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

                let scrollView = try await settledScrollView(in: sheet)

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

                    // Read again rather than reusing `elements`: those were published against the
                    // preset's 180pt floor, and `settledScrollView` has since laid the dialog out
                    // at its measured height. Frames from the earlier tree describe a sheet that no
                    // longer exists, so comparing them to this viewport fails on nothing.
                    let laidOut = try await settledAccessibilityElements(under: sheet.view) { published in
                        published.contains {
                            $0.accessibilityLabel == "Cancel" && $0.accessibilityFrame.height > 0
                        }
                    }
                    let viewport = scrollView.convert(scrollView.bounds, to: nil)
                    for element in laidOut where element.accessibilityLabel != nil {
                        #expect(
                            viewport.insetBy(dx: -0.5, dy: -0.5).contains(element.accessibilityFrame),
                            """
                            \(element.accessibilityLabel ?? "An element") at \
                            \(element.accessibilityFrame) spills out of the dialog \(viewport)
                            """
                        )
                    }

                    return
                }

                // Every Montserrat helper is declared `relativeTo:`, so this copy roughly triples
                // here and cannot fit any detent. What has to survive is reachability: the dialog
                // takes everything the sheet can take, and Cancel comes into view when a climber
                // scrolls to the bottom. Measured against the visible viewport, never the scroll
                // content - content a climber cannot scroll onto the screen is not reachable.
                #expect(
                    sheet.view.bounds.height >= Self.iPhone16ProSize.height * 0.75,
                    """
                    The dialog took \(sheet.view.bounds.height)pt of \
                    \(Self.iPhone16ProSize.height)pt rather than the largest detent available
                    """
                )
                #expect(
                    scrollView.contentSize.height > scrollView.bounds.height,
                    "This copy cannot fit at an accessibility size, so it has to scroll"
                )

                let cancel = try await scrollingToAccessibilityElement(
                    labelled: "Cancel",
                    in: scrollView,
                    of: sheet
                )
                let viewport = scrollView.convert(scrollView.bounds, to: nil)
                #expect(
                    cancel.map {
                        viewport.insetBy(dx: -0.5, dy: -0.5).contains($0.accessibilityFrame)
                    } == true,
                    """
                    Cancel never came into the dialog's viewport \(viewport) while scrolling to the \
                    bottom of \(scrollView.contentSize.height)pt of copy
                    """
                )
            }
        }
    }

    /// Pages the dialog until the labelled control is on screen, and returns it once its published
    /// frame agrees.
    ///
    /// Two things make the single-scroll-then-read version report a false answer: SwiftUI serves the
    /// frames it built for the offset it last laid out at, so the control still reads at its
    /// pre-scroll position for at least one more pass; and `accessibilityScroll` does not move a
    /// SwiftUI `ScrollView` at all, so a loop built on it spins at offset zero and then blames the
    /// dialog. Hence: move the offset directly, then poll the tree until it catches up.
    private func scrollingToAccessibilityElement(
        labelled label: String,
        in scrollView: UIScrollView,
        of sheet: UIViewController,
        waitingUpTo timeout: Duration = .seconds(5)
    ) async throws -> NSObject? {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            sheet.view.setNeedsLayout()
            sheet.view.layoutIfNeeded()

            let viewport = scrollView.convert(scrollView.bounds, to: nil).insetBy(dx: -0.5, dy: -0.5)
            if let match = accessibilityElements(under: sheet.view)
                .first(where: { $0.accessibilityLabel == label }),
                viewport.contains(match.accessibilityFrame) {
                return match
            }

            let maximumOffset = scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
            if scrollView.contentOffset.y < maximumOffset {
                scrollView.setContentOffset(
                    CGPoint(
                        x: scrollView.contentOffset.x,
                        y: min(scrollView.contentOffset.y + scrollView.bounds.height, maximumOffset)
                    ),
                    animated: false
                )
            }

            try await Task.sleep(for: .milliseconds(20))
        }

        return accessibilityElements(under: sheet.view)
            .first { $0.accessibilityLabel == label }
    }

    /// The dialog once its detent stops growing.
    ///
    /// `.fittedScrolling` starts from a zero measurement, so the first detent is the preset's 180pt
    /// floor - a height ``presentedSheet`` accepts as non-zero. Asserting there compares the full
    /// copy against a viewport the preference -> `presentationDetents` -> `UISheetPresentationController`
    /// chain has not caught up to yet, and the dialog reads as clipped when it is merely mid-grow.
    private func settledScrollView(
        in sheet: UIViewController,
        waitingUpTo timeout: Duration = .seconds(5)
    ) async throws -> UIScrollView {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var previousHeight = CGFloat.nan
        var stableReads = 0

        while ContinuousClock.now < deadline {
            sheet.view.setNeedsLayout()
            sheet.view.layoutIfNeeded()

            if let scrollView = firstScrollView(under: sheet.view) {
                if scrollView.contentSize.height <= scrollView.bounds.height + 1 {
                    return scrollView
                }

                if sheet.view.bounds.height == previousHeight {
                    stableReads += 1
                    if stableReads >= 3 {
                        return scrollView
                    }
                } else {
                    stableReads = 0
                    previousHeight = sheet.view.bounds.height
                }
            }

            try await Task.sleep(for: .milliseconds(20))
        }

        return try #require(
            firstScrollView(under: sheet.view),
            "The dialog must host its copy in a scroll view so no text size can clip it"
        )
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

@MainActor
private final class SignOutPresentationRecorder {
    var didRequestSignOut = false
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
