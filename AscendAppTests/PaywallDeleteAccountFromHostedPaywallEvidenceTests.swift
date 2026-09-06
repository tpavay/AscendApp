import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the control that did nothing: a locked-out climber taps
/// `DELETE ACCOUNT` on the hosted paywall and lands on Ascend's own deletion dialog.
///
/// The contract suites next door prove the wiring in source. This drives the real chain through
/// `RenderedScreen`, photographs what the climber sees when `ASCEND_EVIDENCE_DIR` is set, and
/// reads the screen back: the production ``SuperwallPaywallPresenter`` takes the
/// `delete_account` custom action, owns the dismissal itself, and the outcome reaches the real
/// ``AppAccessPaywallPlaceholderView`` coordinator, which opens the real
/// ``DeleteAccountConfirmationView``.
///
/// The paywall itself is remote content this branch does not change, so it is drawn here as a
/// clearly labelled stand-in whose control does exactly what the dashboard control does - fire the
/// custom action and chain nothing after it. Everything below that call is production code.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct PaywallDeleteAccountFromHostedPaywallEvidenceTests {
    /// The defect, end to end. Under the old code this tap resolved to `.undifferentiated`, nothing
    /// was chained after it, and the paywall did not even close.
    ///
    /// Read by OCR rather than off the accessibility tree: this test's contract is that every
    /// line of the deletion dialog Apple requires - the title, the billed-by-Apple warning, the
    /// typed confirmation step - is legibly on the screen the climber lands on, not merely
    /// published by it.
    @Test("DELETE ACCOUNT on the hosted paywall opens Ascend's deletion dialog", .bug(id: 558))
    func theHostedControlOpensTheDeletionDialog() async throws {
        let harness = GateHarness()
        let controller = UIHostingController(
            rootView: harness.view
                .modelContainer(for: AscendLocalStore.models, inMemory: true)
        )
        controller.overrideUserInterfaceStyle = .dark

        try await withAnimationsDisabled {
            try await RenderedScreen.host(controller, settle: .turns(1)) { screen in
                #expect(
                    await settles { harness.isHostedPaywallPresented },
                    "The gate never registered the hosted paywall"
                )
                harness.markHostedPaywallShown()
                try await screen.settle()

                let paywallText = try await screen.recognizedText(scale: 3)
                try screen.photograph(named: "delete-account-01-hosted-paywall")

                // The tap, through the same activation VoiceOver uses.
                try activateAccessibilityElement(labelled: "DELETE ACCOUNT", in: controller.view)

                // Ascend owns this dismissal: the paywall goes away because the app took it away.
                #expect(
                    await settles { harness.dismissalCount == 1 },
                    "The paywall was never dismissed, so nothing could be raised over it"
                )
                #expect(
                    await settles { controller.presentedViewController != nil },
                    "The deletion dialog never opened"
                )
                try await screen.settle()

                let dialogText = try await screen.recognizedText(scale: 3)
                try screen.photograph(named: "delete-account-02-deletion-dialog")

                #expect(paywallText.contains("delete account"))
                #expect(dialogText.contains("delete account"))
                #expect(dialogText.contains("permanently delete your account"))
                // Apple's own requirement, still on the screen this route reaches.
                #expect(dialogText.contains("billed by apple"))
                #expect(
                    dialogText.contains("type delete"),
                    "The confirmation step must not be weakened by the new route: \(dialogText)"
                )

                // The gate's own telemetry is asserted in
                // `PaywallDeleteAccountFromHostedPaywallTests`: the coordinator this view builds
                // takes `TelemetryManager.shared`, so a terminal it records never reaches a
                // harness-owned sink.

                // Backing out means nothing happened, so the paywall the climber was reading comes
                // back rather than an opening spinner with no controls on it.
                let sheet = try #require(controller.presentedViewController)
                try activateAccessibilityElement(labelled: "Cancel", in: sheet.view)
                #expect(
                    await settles { harness.registrationCount == 2 },
                    "Cancelling the deletion never reopened the hosted paywall"
                )
                harness.markHostedPaywallShown()
                try await screen.settle()

                let reopenedText = try await screen.recognizedText(scale: 3)
                try screen.photograph(named: "delete-account-03-paywall-reopened-after-cancel")
                #expect(reopenedText.contains("delete account"))
                #expect(harness.hostedPresentationSources.last == "account_deletion_dismissed")
            }
        }
    }

    /// The one sheet that could have deferred the deletion dialog is the soft update nudge, which
    /// shares the root's modifier level (#429). It yields: a climber asking to delete their account
    /// outranks a recommended update, and the gate has already given up its paywall to ask.
    ///
    /// Which sheet is on the screen is a fact the accessibility tree answers, so this reads
    /// `screen.copy()`.
    @Test("A live update nudge yields so the deletion dialog still opens", .bug(id: 558))
    func theSoftNudgeYieldsToTheDeletionDialog() async throws {
        let harness = GateHarness(updatePresentation: .recommended)
        let controller = UIHostingController(
            rootView: harness.view
                .modelContainer(for: AscendLocalStore.models, inMemory: true)
        )
        controller.overrideUserInterfaceStyle = .dark

        try await withAnimationsDisabled {
            try await RenderedScreen.host(controller, settle: .turns(1)) { screen in
                #expect(await settles { harness.isHostedPaywallPresented })
                harness.markHostedPaywallShown()
                #expect(
                    await settles { controller.presentedViewController != nil },
                    "The recommendation never opened its nudge sheet"
                )
                try await screen.settle()

                let nudgeText = try await screen.copy { $0.contains("newer version is ready") }
                try screen.photograph(named: "delete-account-04-nudge-over-gate")
                #expect(nudgeText.contains("newer version is ready"))

                try activateAccessibilityElement(labelled: "DELETE ACCOUNT", in: controller.view)

                #expect(
                    await settles { harness.gateState.nudgePresentation == nil },
                    "The nudge never yielded"
                )
                #expect(
                    await settles { harness.isDeletionDialogPresented },
                    "The deletion dialog never replaced the nudge"
                )
                try await screen.settle()

                let text = try await screen.copy { $0.contains("permanently delete your account") }
                try screen.photograph(named: "delete-account-05-deletion-dialog-after-nudge-yield")
                #expect(text.contains("permanently delete your account"))
                #expect(
                    !text.contains("newer version is ready"),
                    "The nudge is still on screen under the deletion request: \(text)"
                )
            }
        }
    }

    // MARK: - Support

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

    /// Sheets present and dismiss without animating, so a poll above measures the outcome
    /// rather than the transition's timing on a busy host.
    private func withAnimationsDisabled(_ body: () async throws -> Void) async throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        try await body()
    }
}

/// The gate as `RootView` mounts it, with the hosted paywall standing in for Superwall's window.
///
/// Everything the tap reaches is production: the real presenter, the real monetization manager, the
/// real gate view and its coordinator, and the real deletion dialog. The stand-in only does what
/// the dashboard control does - fire the custom action, chain nothing - and only appears when the
/// app registers the placement and disappears when the app dismisses it, which is the arrangement
/// under test.
@MainActor
private final class GateHarness {
    let gateState: AppVersionGateState
    private let registry = SuperwallPresentationAttemptRegistry()
    private let sink = InMemoryTelemetrySink(destination: .analytics)
    private let presenter: SuperwallPaywallPresenter
    private let manager: MonetizationManager
    private let state = HostedPaywallStandInState()

    private(set) var registrationCount = 0
    private(set) var dismissalCount = 0
    private(set) var hostedPresentationSources: [String] = []

    var isHostedPaywallPresented: Bool { state.isPresented }
    var isDeletionDialogPresented: Bool { state.isDeletionDialogPresented }

    init(updatePresentation: AppUpdatePresentation? = nil) {
        gateState = AppVersionGateState(presentation: updatePresentation)
        let telemetry = makeTestTelemetry(sink: sink)
        // `EntitlementServiceStub` mints this identity, and a gate terminal is only
        // tracked while the telemetry identity matches the presentation's.
        telemetry.setUserId("test-user")
        let state = state
        let box = Box()
        presenter = SuperwallPaywallPresenter(
            telemetry: telemetry,
            attemptRegistry: registry,
            startsConfigured: true,
            registerPlacement: { _, params, _ in
                box.harness?.didRegisterPlacement(source: params?["source"] as? String)
            },
            dismissPresentation: {
                box.harness?.didDismissPresentation()
                state.isPresented = false
            }
        )
        manager = MonetizationManager(
            configuration: MonetizationConfiguration(infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test",
                MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
            ]),
            entitlementService: EntitlementServiceStub(entitlementState: .inactive),
            paywallPresenter: presenter,
            telemetry: telemetry,
            userDefaults: UserDefaults(
                suiteName: "PaywallDeleteAccountEvidence.\(UUID().uuidString)"
            )!
        )
        box.harness = self
    }

    var view: some View {
        GateEvidenceHarnessView(
            gateState: gateState,
            monetizationManager: manager,
            state: state,
            onHostedDeleteAccount: { [weak self] in
                // Exactly what the dashboard control fires, and nothing after it.
                self?.presenter.handleCustomPaywallAction(withName: "delete_account")
            }
        )
    }

    /// Superwall reporting the paywall on screen, which is what banks the token the custom action
    /// is answered against.
    func markHostedPaywallShown() {
        presenter.handlePresentationBegan(
            revision: registry.currentRevision,
            presentationID: "presentation-\(registry.currentRevision)"
        )
    }

    private func didRegisterPlacement(source: String?) {
        registrationCount += 1
        if let source { hostedPresentationSources.append(source) }
        state.isPresented = true
    }

    private func didDismissPresentation() {
        dismissalCount += 1
    }

    /// Breaks the init-time cycle between the presenter's closures and the harness that owns it.
    private final class Box {
        weak var harness: GateHarness?
    }
}

@MainActor
@Observable
private final class HostedPaywallStandInState {
    var isPresented = false
    var isDeletionDialogPresented = false
}

/// `RootView`'s gate route and its two sheets, at the same modifier level `RootView` puts them at.
/// The source of `RootView` is pinned against this arrangement by
/// `LockedOutSubscriberRecoveryContractTests`.
private struct GateEvidenceHarnessView: View {
    let gateState: AppVersionGateState
    let monetizationManager: MonetizationManager
    let state: HostedPaywallStandInState
    let onHostedDeleteAccount: () -> Void

    @State private var isShowingGateAccountDeletion = false
    @State private var isGateAccountDeletionWaitingOnNudge = false
    @State private var isNudgeSheetPresented = false
    @State private var gateAccountDeletionDismissalRevision: UInt = 0

    var body: some View {
        ZStack {
            AppAccessPaywallPlaceholderView(
                accountDeletionDismissalRevision: gateAccountDeletionDismissalRevision,
                onDeleteAccount: { presentGateAccountDeletion() },
                onSignOut: {}
            )

            if state.isPresented {
                HostedPaywallStandIn(onDeleteAccount: onHostedDeleteAccount)
            }
        }
        .environment(monetizationManager)
        .sheet(
            item: Bindable(gateState).nudgePresentation,
            onDismiss: presentGateAccountDeletionWaitingOnNudge
        ) { presentation in
            AppUpdateSheet(
                presentation: presentation,
                onOpenAppStore: {},
                onLater: gateState.dismissRecommended
            )
            .onAppear { isNudgeSheetPresented = true }
        }
        .sheet(isPresented: $isShowingGateAccountDeletion, onDismiss: {
            state.isDeletionDialogPresented = false
            gateAccountDeletionDismissalRevision &+= 1
        }) {
            DeleteAccountConfirmationView(onAccountDeleted: {})
                .onAppear { state.isDeletionDialogPresented = true }
        }
        .onChange(of: gateState.nudgePresentation) { _, presentation in
            guard presentation == nil, !isNudgeSheetPresented else { return }
            presentGateAccountDeletionWaitingOnNudge()
        }
    }

    private func presentGateAccountDeletion() {
        guard isNudgeSheetPresented else {
            gateState.dismissRecommended()
            isShowingGateAccountDeletion = true
            return
        }

        isGateAccountDeletionWaitingOnNudge = true
        gateState.dismissRecommended()
    }

    private func presentGateAccountDeletionWaitingOnNudge() {
        isNudgeSheetPresented = false
        guard isGateAccountDeletionWaitingOnNudge else { return }

        isGateAccountDeletionWaitingOnNudge = false
        isShowingGateAccountDeletion = true
    }
}

/// The Superwall-hosted paywall, drawn locally because it is remote content this branch does not
/// change. Its control fires the custom action and chains nothing, which is the whole defect.
private struct HostedPaywallStandIn: View {
    let onDeleteAccount: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("SUPERWALL-HOSTED PAYWALL")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)
            Text("test stand-in for the remote paywall")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Text("Choose your Ascend plan")
                .font(.montserratSemiBold(size: 17))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button(action: onDeleteAccount) {
                Text("DELETE ACCOUNT")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.red.opacity(0.6), lineWidth: 1)
                    )
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.07, blue: 0.05))
        .ignoresSafeArea()
    }
}
