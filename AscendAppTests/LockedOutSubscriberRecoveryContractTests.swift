import Foundation
import Testing
@testable import AscendApp

/// The three surfaces a subscriber whose card was declined has to pass through.
///
/// Apple's billing grace period is off for this app, so a routine decline drops an authenticated,
/// onboarded climber onto the app-access gate for as long as Apple keeps retrying. Everything that
/// climber is entitled to do from there - delete the account, learn that Apple keeps billing, reach
/// Apple's own subscription management - is asserted here, because each one is a written App Store
/// requirement rather than a preference that may be traded away in a later redesign.
struct LockedOutSubscriberRecoveryContractTests {
    /// Guideline 5.1.1(v) admits no paid-status exception: the gate is the only screen this climber
    /// can reach, so account deletion has to leave from it.
    @Test
    func theAppAccessGateRoutesToAccountDeletion() throws {
        let gate = try source(
            at: "AscendApp/Features/Monetization/Paywall/AppAccessPaywallPlaceholderView.swift"
        )

        #expect(gate.contains("onDeleteAccount: @escaping @MainActor () -> Void"))
        #expect(gate.contains("Button(action: onDeleteAccount)"))
        #expect(gate.contains("Text(\"Delete account\")"))
        #expect(gate.contains(".accessibilityIdentifier(\"appAccessDeleteAccount\")"))
        // The hosted Superwall paywall covers this screen for most of a locked-out climber's
        // session, and its own DELETE ACCOUNT control has to reach the same dialog. One closure
        // serves both, so the two routes cannot drift to different destinations.
        #expect(gate.contains("onRequestAccountDeletion: onDeleteAccount"))
    }

    /// A wrong-account subscriber must be able to leave the gate and authenticate as the Apple ID
    /// that owns the subscription.
    @Test
    func theAppAccessGateOffersSignOutForWrongAccountRecovery() throws {
        let gate = try source(
            at: "AscendApp/Features/Monetization/Paywall/AppAccessPaywallPlaceholderView.swift"
        )

        #expect(gate.contains("onSignOut: @escaping () -> Void"))
        #expect(gate.contains("Button(action: onSignOut)"))
        #expect(gate.contains("Text(\"Sign Out\")"))
        #expect(gate.contains(".accessibilityIdentifier(\"appAccessSignOut\")"))
    }

    /// The deletion link stays subordinate to subscribe and restore: it is the way out, not the
    /// offer. A promoted button here would read as the gate's recommended action.
    @Test
    func theDeletionLinkStaysQuieterThanSubscribeAndRestore() throws {
        let gate = try source(
            at: "AscendApp/Features/Monetization/Paywall/AppAccessPaywallPlaceholderView.swift"
        )

        let restoreIndex = try #require(gate.range(of: "coordinator.restore()")).lowerBound
        let deleteIndex = try #require(gate.range(of: "Button(action: onDeleteAccount)")).lowerBound
        #expect(restoreIndex < deleteIndex, "Deletion must sit beneath Restore Purchases")

        let link = try #require(gate.range(of: "Button(action: onDeleteAccount)"))
        let linkBlock = String(gate[link.lowerBound...].prefix(400))
        #expect(linkBlock.contains("montserratMedium(size: 13)"))
        #expect(!linkBlock.contains("Color.ascendAccent"))
        // A 44pt row keeps the quiet type from shrinking the tap target below the HIG minimum.
        #expect(linkBlock.contains("minHeight: 44"))
    }

    /// The lockout resolves above the entitlement gate and absorbs the whole app, so the same
    /// guideline reaches it. It shares the gate's one deletion sheet rather than growing a second
    /// presentation path, and offers the link only where there is an account to delete - above
    /// authentication the route is reachable with no session at all.
    @Test(.bug(id: 429))
    func theUpdateLockoutRoutesToAccountDeletionOnlyWhenAuthenticated() throws {
        let lockout = try source(at: "AscendApp/Shared/Views/AppUpdateRequiredView.swift")

        #expect(lockout.contains("var onDeleteAccount: (() -> Void)?"))
        #expect(lockout.contains("Text(\"Delete account\")"))
        #expect(lockout.contains(".accessibilityIdentifier(\"appUpdateRequiredDeleteAccount\")"))
        #expect(!lockout.localizedCaseInsensitiveContains("sign out"))
        #expect(!lockout.localizedCaseInsensitiveContains("manage subscription"))

        let link = try #require(lockout.range(of: "private func deleteAccountLink("))
        let linkBlock = String(lockout[link.lowerBound...].prefix(500))
        #expect(linkBlock.contains("montserratMedium(size: 13)"))
        #expect(!linkBlock.contains("Color.ascendAccent"))
        // At least the HIG minimum, and free to grow so AXXXL never clips the link.
        #expect(linkBlock.contains(".frame(minHeight: 44)"))

        let root = try source(at: "AscendApp/App/RootView.swift")
        #expect(root.contains("onDeleteAccount: gateAccountDeletionAction"))
        let action = try #require(
            root
                .range(of: "private var gateAccountDeletionAction: (() -> Void)?")
                .map { String(root[$0.lowerBound...].prefix(200)) }
        )
        #expect(action.contains("guard authVM.user != nil else { return nil }"))
        #expect(action.contains("presentGateAccountDeletion()"))
    }

    @Test
    func theRootRouteWiresTheGateToTheRealDeletionSheet() throws {
        let root = try source(at: "AscendApp/App/RootView.swift")

        #expect(root.contains("onDeleteAccount: { presentGateAccountDeletion() }"))
        // One presenter for both routes, and the deletion sheet has to actually open: the gate has
        // already dismissed its hosted paywall by the time it asks. The soft update nudge is the
        // only other sheet at this modifier level, so it yields rather than deferring the request
        // (#429), and the handoff runs from its own `onDismiss` so the nudge is provably gone
        // before the deletion sheet is raised.
        let presenter = try #require(
            root
                .range(of: "private func presentGateAccountDeletion() {")
                .map { String(root[$0.lowerBound...].prefix(320)) }
        )
        #expect(presenter.contains("appVersionGateState.dismissRecommended()"))
        #expect(presenter.contains("isGateAccountDeletionWaitingOnNudge = true"))
        #expect(presenter.contains("isShowingGateAccountDeletion = true"))
        #expect(
            root.contains("onDismiss: presentGateAccountDeletionWaitingOnNudge"),
            "the nudge must hand the deletion request on once it is actually gone"
        )
        // Nothing may report a refusal the gate would have nowhere to render.
        #expect(!root.contains("presentGateAccountDeletion() -> Bool"))
        #expect(root.contains(".sheet(isPresented: $isShowingGateAccountDeletion"))
        #expect(root.contains("DeleteAccountConfirmationView("))
        #expect(root.contains("onAccountDeleted: {}"))
    }

    /// The sheet outlives the route that opened it. A locked-out subscriber's entitlement can
    /// resolve mid-deletion - reauth foregrounds the app, which refreshes entitlements - and an
    /// unmount there runs `onDisappear`, cancelling the deletion with the cloud sweep half done and
    /// the failure alert on a view nobody can see.
    @Test
    func theDeletionSheetOutlivesTheEntitlementDrivenRoute() throws {
        let root = try source(at: "AscendApp/App/RootView.swift")

        let sheetIndex = try #require(
            root.range(of: ".sheet(isPresented: $isShowingGateAccountDeletion")
        ).lowerBound
        let switchIndex = try #require(
            root.range(of: "private func authenticatedContent(for route: AppRootRoute)")
        ).lowerBound
        #expect(
            sheetIndex < switchIndex,
            "The deletion sheet must hang off the root body, not the .paywall switch case"
        )

        // Deletion ends the session at the auth step, while the local sweep still has to commit,
        // clear UserDefaults, the image cache and the pending uploads. Clearing the flag on the
        // session change tore the dialog down inside that window, so a failing sweep raised its
        // alert on a sheet nobody could see - a silent leftover in an irreversible flow.
        let sessionChange = try #require(
            root
                .range(of: ".onChange(of: authVM.user?.uid)")
                .map { String(root[$0.lowerBound...].prefix(600)) }
        )
        #expect(!sessionChange.contains("isShowingGateAccountDeletion = false"))
        #expect(sessionChange.contains("dismissGateAccountDeletionWhenResolved()"))

        let deferral = try #require(
            root
                .range(of: "private func dismissGateAccountDeletionWhenResolved()")
                .map { String(root[$0.lowerBound...].prefix(300)) }
        )
        #expect(deferral.contains("guard isGateDeletionUnresolved"))
        #expect(deferral.contains("isGateDeletionDismissPending = true"))

        // The deferred clear is released by the dialog's own terminal report, never by a timer or
        // another proxy for "deletion is probably done by now".
        #expect(root.contains("onDeletionUnresolvedChange: gateAccountDeletionDidChangeResolution"))
        let release = try #require(
            root
                .range(of: "private func gateAccountDeletionDidChangeResolution(")
                .map { String(root[$0.lowerBound...].prefix(400)) }
        )
        #expect(release.contains("guard !isUnresolved, isGateDeletionDismissPending"))
        #expect(release.contains("isShowingGateAccountDeletion = false"))
    }

    /// The dialog is the only thing that knows whether the sweep is still running or is holding an
    /// unacknowledged failure, so it is the only thing allowed to say when a presenter may dismiss.
    @Test
    func theDeletionDialogReportsWhenItIsSafeToDismiss() throws {
        let confirmation = try source(
            at: "AscendApp/Features/Account/Views/DeleteAccountConfirmationView.swift"
        )

        #expect(confirmation.contains("var onDeletionUnresolvedChange: (Bool) -> Void"))
        #expect(confirmation.contains("isDeleting || showError"))
        #expect(confirmation.contains(".onChange(of: isDeletionUnresolved)"))
    }

    /// Apple's "Offering account deletion in your app" asks by name that a subscriber be told
    /// billing continues through Apple and be asked to cancel first.
    @Test
    func deletionCopySaysTheAppStoreSubscriptionKeepsBilling() throws {
        let confirmation = try source(
            at: "AscendApp/Features/Account/Views/DeleteAccountConfirmationView.swift"
        )
        let copy = try #require(
            confirmation
                .range(of: "This will permanently delete your account")
                .map { String(confirmation[$0.lowerBound...].prefix(500)) }
        )

        #expect(copy.localizedCaseInsensitiveContains("billed by Apple"))
        #expect(copy.localizedCaseInsensitiveContains("keeps renewing"))
        #expect(copy.localizedCaseInsensitiveContains("cancel it"))
        // Conditional, not entitlement-gated: a decline reads as unentitled for up to 60 days while
        // Apple is still charging, so the warning has to reach that climber - and stay true for the
        // climber who simply never subscribed.
        #expect(copy.contains("If you have an Ascend subscription"))
        #expect(!copy.contains("Your subscription is billed by Apple"))
        // The existing promises stay: deletion is permanent and reauth may be asked for.
        #expect(copy.contains("This action cannot be undone."))
        #expect(copy.localizedCaseInsensitiveContains("sign in again"))
    }

    /// A hand-tuned detent over copy that scales with Dynamic Type clips the title off the top and
    /// Cancel off the bottom at once, because the dialog centres its stack and never scrolls.
    @Test
    func theDeletionDialogSizesItselfFromItsContent() throws {
        let confirmation = try source(
            at: "AscendApp/Features/Account/Views/DeleteAccountConfirmationView.swift"
        )

        #expect(confirmation.contains(".appSheetStyle(.fittedScrolling()"))
        #expect(confirmation.contains("isInteractiveDismissDisabled: isDeleting"))
        #expect(!confirmation.contains(".dialog(height:"))
    }

    /// The actual fix for an ordinary lapse: the one place the climber's problem is solvable has to
    /// be reachable from inside Ascend, through Apple's own sheet rather than a guessed URL.
    @Test
    func settingsReachesAppleSubscriptionManagementThroughTheFirstPartySheet() throws {
        let account = try source(at: "AscendApp/Features/Account/Views/AccountView.swift")

        #expect(account.contains("import StoreKit"))
        #expect(account.contains("title: \"Manage Subscription\""))
        #expect(
            account.contains(".manageSubscriptionsSheet(isPresented: $isShowingManageSubscriptions)")
        )
        #expect(!account.contains("account/subscriptions"))

        let section = try #require(account.range(of: "private var subscriptionOptions"))
        let body = String(account[section.lowerBound...].prefix(700))
        let manageIndex = try #require(body.range(of: "Manage Subscription")).lowerBound
        let restoreIndex = try #require(body.range(of: "Restore Purchases")).lowerBound
        #expect(manageIndex < restoreIndex, "Managing the plan leads the Subscription section")
    }

    private var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
