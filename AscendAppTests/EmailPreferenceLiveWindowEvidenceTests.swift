import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the two surfaces this consent change ships:
/// the Email preference screen in each of its states, and the onboarding
/// notifications step carrying the pre-ticked email checkbox.
///
/// `EmailPreferencesScreenSnapshotTests` reads the content view's copy off the
/// accessibility tree. Hosting the shipping `EmailPreferencesView` in a real
/// `UIWindow` through `RenderedScreen` puts the actual UIKit-backed switch on
/// screen, so which way it is pointing is visible in the photograph rather than
/// only asserted. The whole screen is hosted, navigation chrome included,
/// exactly as a climber arriving from Settings sees it.
///
/// Photographs land in `ASCEND_EVIDENCE_DIR` when it is set and are not taken
/// otherwise. Nothing reads them back - the assertions are on the view models
/// and on the copy the hosted screen publishes.
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
        let saveFailedCopy = try await snapshot(
            EmailPreferencesView(viewModel: saveFailed),
            named: "email-screen-save-failed"
        ) {
            await offlineService.setSaveError(EvidenceError.offline)
            await saveFailed.setLifecycleEmailsEnabled(false)
        }
        #expect(saveFailed.isLifecycleEmailsEnabled)
        #expect(saveFailed.errorMessage == "Couldn't save. Check your connection.")
        #expect(saveFailedCopy.contains("couldn't save"))

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
        // change it, so the screen that gets them there is photographed in place.
        let copy = try await snapshot(
            NotificationSettingsView(),
            named: "notification-settings-email-row"
        )
        #expect(copy.contains("new climb drops"))
    }

    @Test
    func theOnboardingStepIsPhotographedWithItsPreTickedBox() async throws {
        let copy = try await snapshot(
            PostAuthOnboardingFlowView(
                stage: .notifications,
                onBack: {},
                onContinue: {}
            )
            .environment(AuthenticationViewModel()),
            named: "onboarding-notifications-step",
            wrapInNavigationStack: false
        )
        #expect(copy.contains("email me when climbs drop"))
    }

    // MARK: - Hosting

    /// Hosts the shipping view in a real window at iPhone 16 Pro size, so
    /// UIKit-backed controls render for real, runs `whileOnScreen` against the
    /// settled screen, photographs it when `ASCEND_EVIDENCE_DIR` is set, and
    /// hands back the copy the screen publishes.
    @discardableResult
    private func snapshot(
        _ view: some View,
        named name: String,
        wrapInNavigationStack: Bool = true,
        whileOnScreen: (() async -> Void)? = nil
    ) async throws -> String {
        let size = RenderedScreen.iPhone16ProSize
        let hosted = AnyView(
            wrapInNavigationStack ? AnyView(NavigationStack { view }) : AnyView(view)
        )

        return try await RenderedScreen.host(
            hosted
                .frame(width: size.width, height: size.height, alignment: .top)
                .environment(\.colorScheme, .dark),
            size: size
        ) { screen in
            if let whileOnScreen {
                await whileOnScreen()
                try await screen.settle(.turns(6))
            }

            let copy = try await screen.copy()
            try screen.photograph(named: name)
            return copy
        }
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
