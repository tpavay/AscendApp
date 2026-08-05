import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing photographs of the two surfaces this consent change ships:
/// the Email preference screen in each of its states, and the onboarding
/// notifications step carrying the pre-ticked email checkbox.
///
/// `EmailPreferencesScreenSnapshotTests` reads its renders back with Vision and
/// therefore uses `ImageRenderer`, which cannot rasterize the UIKit control
/// behind `Toggle` - the switch is a placeholder glyph there. Hosting the
/// shipping `EmailPreferencesView` in a real `UIWindow` photographs the actual
/// switch, so which way it is pointing is visible rather than only asserted.
/// The whole screen is captured, navigation chrome included, exactly as a
/// climber arriving from Settings sees it.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's
/// temporary directory otherwise; the path is logged either way. Nothing reads
/// them back - these are evidence, not golden-image assertions.
@Suite(.serialized, .hostsAWindow)
@MainActor
struct EmailPreferenceLiveWindowEvidenceTests {
    @Test
    func theEmailScreenIsPhotographedInEveryStateItShips() async throws {
        let granted = EmailPreferencesViewModel(
            service: EvidenceEmailPreferencesService(storedConsent: .granted)
        )
        await granted.load()
        try await snapshot(
            EmailPreferencesView(viewModel: granted),
            named: "email-screen-on"
        )
        #expect(granted.isLifecycleEmailsEnabled)

        let declined = EmailPreferencesViewModel(
            service: EvidenceEmailPreferencesService(storedConsent: .declined)
        )
        await declined.load()
        try await snapshot(
            EmailPreferencesView(viewModel: declined),
            named: "email-screen-off"
        )
        #expect(!declined.isLifecycleEmailsEnabled)

        // The state a climber lands in when the write does not reach the
        // server: the switch goes back to what the server last accepted and
        // the screen says so. The switch is thrown while the screen is up,
        // because that is the only order it happens in - the screen re-reads
        // the server whenever it appears, so a failure staged before that read
        // would be one no climber can ever be looking at.
        let offlineService = EvidenceEmailPreferencesService(storedConsent: .granted)
        let saveFailed = EmailPreferencesViewModel(service: offlineService)
        try await snapshot(
            EmailPreferencesView(viewModel: saveFailed),
            named: "email-screen-save-failed"
        ) {
            await offlineService.setSaveError(EvidenceError.offline)
            await saveFailed.setLifecycleEmailsEnabled(false)
        }
        #expect(saveFailed.isLifecycleEmailsEnabled)
        #expect(saveFailed.errorMessage == "Couldn't save. Check your connection.")

        // Nobody has ever answered: the switch reads off rather than claiming a
        // consent that was never given.
        let undecided = EmailPreferencesViewModel(
            service: EvidenceEmailPreferencesService(storedConsent: .undecided)
        )
        await undecided.load()
        try await snapshot(
            EmailPreferencesView(viewModel: undecided),
            named: "email-screen-never-answered"
        )
        #expect(undecided.consent == .undecided)
        #expect(!undecided.isLifecycleEmailsEnabled)
    }

    @Test
    func theEmailScreenIsReachableFromNotificationSettings() async throws {
        // The definition of done is that a climber can find this preference and
        // change it, so the row that gets them there is photographed in place.
        try await snapshot(
            NotificationSettingsView(),
            named: "notification-settings-email-row"
        )
    }

    @Test
    func theOnboardingStepIsPhotographedWithItsPreTickedBox() async throws {
        try await snapshot(
            PostAuthOnboardingFlowView(
                stage: .notifications,
                onBack: {},
                onContinue: {}
            )
            .environment(AuthenticationViewModel()),
            named: "onboarding-notifications-step",
            wrapInNavigationStack: false
        )
    }

    // MARK: - Rendering

    /// Hosts the shipping view in a real window at iPhone 16 Pro size and
    /// captures what is on screen, so UIKit-backed controls render for real.
    private func snapshot(
        _ view: some View,
        named name: String,
        wrapInNavigationStack: Bool = true,
        whileOnScreen: (() async -> Void)? = nil
    ) async throws {
        let size = CGSize(width: 402, height: 874)
        let hosted = AnyView(
            wrapInNavigationStack ? AnyView(NavigationStack { view }) : AnyView(view)
        )
        let controller = UIHostingController(
            rootView: hosted
                .frame(width: size.width, height: size.height, alignment: .top)
                .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for _ in 0..<12 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        if let whileOnScreen {
            await whileOnScreen()

            for _ in 0..<6 {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("Rendered email consent evidence: \(url.path())")
    }
}

private enum EvidenceError: Error {
    case offline
}

private actor EvidenceEmailPreferencesService: EmailPreferencesProviding {
    private var storedConsent: LifecycleEmailConsent
    private var saveError: Error?

    init(storedConsent: LifecycleEmailConsent) {
        self.storedConsent = storedConsent
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        storedConsent
    }

    func recordConsent(
        isGranted: Bool,
        source: LifecycleEmailConsentSource
    ) async throws {
        if let saveError {
            throw saveError
        }

        storedConsent = LifecycleEmailConsent(isGranted: isGranted)
    }
}
