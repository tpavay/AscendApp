import Foundation
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Reviewer-facing pixels for the locked-out climber's recovery routes.
///
/// The contract suite holds the shape of the source and the hosting suite proves the controls are
/// operable; this photographs what the climber actually sees. The gate is hosted in a real window
/// wired exactly the way `RootView` wires it, the `Delete account` link is activated through the
/// same accessibility action VoiceOver uses, and the dialog that opens is captured with the pixels
/// read back - so the Apple-billing sentence is asserted from the screen rather than from a string
/// in a Swift file.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LockedOutSubscriberRecoveryEvidenceTests {
    private static let iPhone16ProSize = CGSize(width: 402, height: 874)

    @Test
    func theGateShowsItsDeletionLinkAndOpensTheRealDialog() async throws {
        try await withAccessibilityAutomation {
            let manager = MonetizationManager(
                entitlementService: EntitlementServiceStub(),
                paywallPresenter: PaywallPresenterSpy(),
                telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
            )
            let controller = UIHostingController(
                rootView: LockedOutGateJourneyHarness(monetizationManager: manager)
                    .modelContainer(for: AscendLocalStore.models, inMemory: true)
            )
            controller.overrideUserInterfaceStyle = .dark

            try await withHostedWindow(controller) { window in
                _ = try await settledAccessibilityElements(under: controller.view) { elements in
                    elements.contains { $0.accessibilityLabel == "Delete account" }
                }
                try await settle(window)

                let gate = try await capture(window, named: "locked-out-gate-deletion-link")
                let gateText = try await recognizedText(in: gate).lowercased()
                #expect(gateText.contains("choose your ascend plan"))
                #expect(gateText.contains("delete account"))
                #expect(gateText.contains("sign out"))

                try activateAccessibilityElement(labelled: "Delete account", in: controller.view)

                let sheet = try await presentedSheet(of: controller)
                _ = try await settledAccessibilityElements(under: sheet.view) { elements in
                    elements.contains { $0.accessibilityLabel?.contains("billed by Apple") == true }
                }
                try await settle(window)

                let dialog = try await capture(window, named: "locked-out-gate-deletion-dialog")
                let dialogText = try await recognizedText(in: dialog).lowercased()
                #expect(dialogText.contains("delete account"))
                #expect(dialogText.contains("billed by apple"))
                #expect(dialogText.contains("keeps renewing after deletion"))
                #expect(dialogText.contains("cancel it in your apple subscription settings"))
                #expect(dialogText.contains("cannot be undone"))
                #expect(dialogText.contains("sign in again"))
            }
        }
    }

    @Test
    func settingsShowsManageSubscriptionAboveRestorePurchases() async throws {
        let controller = UIHostingController(
            rootView: NavigationStack {
                AccountView()
                    .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            }
            .frame(width: 390, height: 1500, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: CGSize(width: 390, height: 1500))

        try await withHostedWindow(controller, size: CGSize(width: 390, height: 1500)) { window in
            try await settle(window)

            let image = try await capture(window, named: "settings-manage-subscription")
            let text = try await recognizedText(in: image).lowercased()

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

    private func withHostedWindow(
        _ controller: UIViewController,
        size: CGSize = LockedOutSubscriberRecoveryEvidenceTests.iPhone16ProSize,
        perform body: (UIWindow) async throws -> Void
    ) async throws {
        let windowScene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = .black
        window.rootViewController = controller

        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        try await body(window)
    }

    /// The dialog once it exists and has taken a real height - a merely-present sheet still measures
    /// zero by zero, and a capture there photographs an empty screen.
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

    private func settle(_ window: UIWindow, turns: Int = 12) async throws {
        for _ in 0..<turns {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @discardableResult
    private func capture(_ window: UIWindow, named name: String) async throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("ASCEND_EVIDENCE_FILE: \(url.path())")
        return image
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }
}

/// The gate wired the way `RootView` wires it: the link presents the real deletion dialog.
private struct LockedOutGateJourneyHarness: View {
    let monetizationManager: MonetizationManager
    @State private var isShowingDeletion = false

    var body: some View {
        AppAccessPaywallPlaceholderView(
            initialPhase: .failed,
            onDeleteAccount: { isShowingDeletion = true; return true },
            onSignOut: {}
        )
        .environment(monetizationManager)
        .sheet(isPresented: $isShowingDeletion) {
            DeleteAccountConfirmationView(onAccountDeleted: {})
        }
    }
}
