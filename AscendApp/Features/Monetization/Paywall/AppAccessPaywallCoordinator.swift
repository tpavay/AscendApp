import Foundation

/// Drives the app-access gate.
///
/// The gate has no screen of its own: everything a climber reads or taps there is a hosted
/// Superwall screen, and the only thing Ascend draws behind and between them is
/// ``AppAccessSpinnerView``. So no outcome may end somewhere that needs words or a control. Every
/// path through this type ends in one of three places - the app, a hosted screen, or the spinner
/// while the gate tries again on a clock (``AppAccessGateRetryPolicy``).
@MainActor
final class AppAccessPaywallCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private(set) var phase: AppAccessGatePhase = .openingHosted

    private let monetizationManager: MonetizationManager
    /// Returns whether the onboarding step behind the paywall actually reopened, so the gate
    /// never leaves a climber on a hosted paywall that is already gone.
    private let onRequestOnboardingBack: (@MainActor () -> Bool)?
    /// Opens the account-deletion dialog for the hosted paywall's `DELETE ACCOUNT` control.
    ///
    /// Ascend has already dismissed the hosted paywall by the time this is asked, so the dialog has
    /// to open. `RootView` guarantees that by making the only sheet that could defer it - the soft
    /// update nudge - yield first, rather than reporting a refusal this gate would have nowhere to
    /// render.
    private let onRequestAccountDeletion: (@MainActor () -> Void)?
    /// Signs the climber out for the hosted paywall's `Sign out` control. Ascend has already
    /// dismissed the hosted paywall by the time this is asked.
    private let onRequestSignOut: (@MainActor () -> Void)?
    private let telemetry: TelemetryManager
    private let hostedOpeningDeadline: Duration
    private let retryPolicy: AppAccessGateRetryPolicy
    private let sleep: Sleep
    private var presentationRevision: UInt = 0
    private var presentationIdentity: MonetizationIdentityTransition?
    private var presentationAttemptID: String?
    private var lastTerminalPresentationRevision: UInt?
    private var watchdogTask: Task<Void, Never>?
    private var hostedRetryTask: Task<Void, Never>?
    private var accessCheckTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var letterWatchdogTask: Task<Void, Never>?
    private var freeWeekTask: Task<Void, Never>?
    private var freeWeekRevision: UInt = 0
    private var accessCheckRevision: UInt = 0
    /// Attempts to open the access paywall that have failed in a row, which is what the wait
    /// before the next one grows with.
    private var failedHostedPresentations = 0
    /// Whether the hosted paywall of the current attempt actually reached the screen. A decline
    /// from one that never did is not a climber saying no.
    private var didPresentHosted = false
    private var didShowLetter = false

    init(
        monetizationManager: MonetizationManager,
        telemetry: TelemetryManager = .shared,
        onRequestOnboardingBack: (@MainActor () -> Bool)? = nil,
        onRequestAccountDeletion: (@MainActor () -> Void)? = nil,
        onRequestSignOut: (@MainActor () -> Void)? = nil,
        hostedOpeningDeadline: Duration = .seconds(8),
        retryPolicy: AppAccessGateRetryPolicy = AppAccessGateRetryPolicy(),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.monetizationManager = monetizationManager
        self.onRequestOnboardingBack = onRequestOnboardingBack
        self.onRequestAccountDeletion = onRequestAccountDeletion
        self.onRequestSignOut = onRequestSignOut
        self.telemetry = telemetry
        self.hostedOpeningDeadline = hostedOpeningDeadline
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func start() {
        guard phase == .openingHosted, presentationIdentity == nil else { return }
        recordFreeWeekExpiredGateIfNeeded()
        presentHosted(source: "app_access_gate")
    }

    /// The app came back to the foreground.
    ///
    /// The gate has no control to tap, so leaving and coming back is the one thing a climber can
    /// do to a spinner. A paywall the gate is waiting to ask for again is asked for now, from the
    /// start of the schedule, instead of after whatever is left of the wait.
    func appWillEnterForeground() {
        guard phase == .awaitingHostedRetry else { return }
        failedHostedPresentations = 0
        presentHosted(source: "foreground_retry")
    }

    /// The account-deletion dialog closed and this gate is still on screen, so the deletion did not
    /// happen - a completed one ends the session and routes away from here entirely.
    ///
    /// Ascend dismissed the hosted paywall itself to raise that dialog, so backing out of it would
    /// otherwise leave the spinner with nothing behind it: no plans, no restore, and not even the
    /// account-deletion route Guideline 5.1.1(v) requires. Cancelling a deletion means nothing
    /// happened, so the paywall the climber was reading comes back.
    func accountDeletionDialogDismissed() {
        guard phase == .hostedPresented || phase == .openingHosted else { return }
        presentHosted(source: "account_deletion_dismissed")
    }

    func identityDidChange() {
        cancelOwnedWork(
            providerOutcome: .staleIdentity,
            entitlementActive: entitlementPresence
        )
        failedHostedPresentations = 0
        phase = .openingHosted
        start()
    }

    /// The gate left the screen. Everything it owned is stopped, and it is left where `start()`
    /// begins, so a gate shown again asks for the paywall again instead of sitting on a spinner
    /// that nothing is driving.
    func cancelOwnedWork() {
        cancelOwnedWork(
            providerOutcome: .cancelled,
            entitlementActive: entitlementPresence
        )
        failedHostedPresentations = 0
        phase = .openingHosted
    }

    private func cancelOwnedWork(
        providerOutcome: AppAccessGateProviderOutcome,
        entitlementActive: Bool?
    ) {
        recordCurrentGateTerminal(
            providerOutcome: providerOutcome,
            recoveryPath: currentRecoveryPath,
            entitlementActive: entitlementActive
        )
        presentationRevision &+= 1
        presentationIdentity = nil
        presentationAttemptID = nil
        accessCheckRevision &+= 1
        freeWeekRevision &+= 1
        letterWatchdogTask?.cancel()
        freeWeekTask?.cancel()
        watchdogTask?.cancel()
        hostedRetryTask?.cancel()
        accessCheckTask?.cancel()
        routeTask?.cancel()
        letterWatchdogTask = nil
        freeWeekTask = nil
        watchdogTask = nil
        hostedRetryTask = nil
        accessCheckTask = nil
        routeTask = nil
        monetizationManager.cancelPaywallPresentation()
    }

    func entitlementDidChange(_ state: MonetizationEntitlementState) {
        guard state.hasActiveEntitlement(
            monetizationManager.configuration.revenueCatEntitlementID
        ) else { return }
        // Active entitlement truth wins every presentation state. Retire all callback authority
        // before publishing confirmation so a late hosted terminal or retry cannot reopen a
        // paywall over a climber who already has access.
        cancelOwnedWork(
            providerOutcome: .entitlementActive,
            entitlementActive: true
        )
        awaitRoute()
    }

    /// Access is confirmed, and routing is about to take the climber into the app.
    ///
    /// Routing reads the same entitlement and free week this gate just heard about, so it leaves
    /// in the same turn and this wait is never seen. It is here because the gate cannot be where
    /// anything ends: if routing does not agree, the paywall reopens rather than leaving a spinner
    /// with nothing behind it.
    private func awaitRoute() {
        phase = .accessConfirmed
        routeTask?.cancel()
        routeTask = Task { @MainActor [weak self, sleep, deadline = retryPolicy.routeResolutionDeadline] in
            do {
                try await sleep(deadline)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.phase == .accessConfirmed else { return }
            self.routeTask = nil
            self.presentHosted(source: "access_route_unresolved")
        }
    }

    // MARK: - Access paywall

    private func presentHosted(source: String) {
        hostedRetryTask?.cancel()
        hostedRetryTask = nil
        routeTask?.cancel()
        routeTask = nil
        if let hold = monetizationManager.pendingPurchaseHold {
            confirmAccess(holding: hold)
            return
        }
        guard let identity = monetizationManager.identityGeneration else {
            // The account check has not finished. `identityDidChange()` restarts the gate when it
            // does; the retry covers an answer that lands without that change.
            scheduleHostedRetry()
            return
        }
        recordCurrentGateTerminal(
            providerOutcome: .cancelled,
            recoveryPath: currentRecoveryPath,
            entitlementActive: entitlementPresence
        )
        if presentationIdentity != nil {
            monetizationManager.cancelPaywallPresentation()
        }
        presentationRevision &+= 1
        let revision = presentationRevision
        presentationIdentity = identity
        presentationAttemptID = UUID().uuidString.lowercased()
        didPresentHosted = false
        armOpeningWatchdog(presentationRevision: revision, presentationIdentity: identity)

        monetizationManager.presentPaywall(
            .appAccessGate,
            params: [
                "source": source,
                "gate_attempt_id": presentationAttemptID as Any
            ]
        ) { [weak self] outcome in
            guard let self, self.presentationRevision == revision,
                  self.lastTerminalPresentationRevision != revision,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.handleHostedOutcome(
                outcome,
                presentationRevision: revision,
                presentationIdentity: identity
            )
        }
    }

    /// A paywall that never opens is asked for again rather than waited on forever.
    private func armOpeningWatchdog(
        presentationRevision revision: UInt,
        presentationIdentity identity: MonetizationIdentityTransition
    ) {
        phase = .openingHosted
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self, sleep, hostedOpeningDeadline] in
            do {
                try await sleep(hostedOpeningDeadline)
            } catch {
                return
            }
            guard let self, !Task.isCancelled,
                  self.presentationRevision == revision,
                  self.phase == .openingHosted,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.monetizationManager.cancelPaywallPresentation()
            self.retryHostedAfterBackoff(
                presentationRevision: revision,
                presentationIdentity: identity,
                reason: .watchdogTimeout
            )
        }
    }

    /// The access paywall did not reach the screen. The spinner stays, and the gate asks again.
    private func retryHostedAfterBackoff(
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition,
        reason: AppAccessGateRecoveryReason
    ) {
        recordGateTerminal(
            presentationRevision: presentationRevision,
            presentationIdentity: presentationIdentity,
            providerOutcome: .hostedUnavailable,
            recoveryPath: .hosted,
            recoveryReason: reason,
            entitlementActive: entitlementPresence
        )
        // Retires the attempt, so a callback it still has in flight cannot land on the next one.
        self.presentationRevision &+= 1
        self.presentationIdentity = nil
        scheduleHostedRetry()
    }

    private func scheduleHostedRetry() {
        let delay = retryPolicy.hostedPresentationDelay(afterFailures: failedHostedPresentations)
        failedHostedPresentations += 1
        watchdogTask?.cancel()
        hostedRetryTask?.cancel()
        phase = .awaitingHostedRetry
        hostedRetryTask = Task { @MainActor [weak self, sleep] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.phase == .awaitingHostedRetry else { return }
            self.hostedRetryTask = nil
            self.presentHosted(source: "presentation_retry")
        }
    }

    /// Reopens the access paywall for a climber who has nowhere else to go.
    ///
    /// The paywall is the floor: it carries its own restore, delete-account and sign-out controls.
    /// One that reached the screen reopens at once, because the climber closed it themselves. One
    /// that never did would reopen in a loop nobody is tapping through, so it waits out the
    /// backoff like any other paywall that could not open.
    private func returnToHosted(
        source: String,
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition,
        reason: AppAccessGateRecoveryReason
    ) {
        guard didPresentHosted else {
            retryHostedAfterBackoff(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: reason
            )
            return
        }
        recordGateTerminal(
            presentationRevision: presentationRevision,
            presentationIdentity: presentationIdentity,
            providerOutcome: .paywallFloor,
            recoveryPath: .hosted,
            recoveryReason: reason,
            entitlementActive: entitlementPresence
        )
        presentHosted(source: source)
    }

    private func handleHostedOutcome(
        _ outcome: PaywallPresentationOutcome,
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition
    ) {
        switch outcome {
        case .presented:
            watchdogTask?.cancel()
            didPresentHosted = true
            failedHostedPresentations = 0
            phase = .hostedPresented
        case .followOnPaywallOpening:
            armOpeningWatchdog(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity
            )
        case .purchased, .restored:
            watchdogTask?.cancel()
            recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: outcome == .purchased ? .purchased : .restored,
                recoveryPath: .hosted,
                entitlementActive: true
            )
            awaitRoute()
        case .pendingApproval, .verificationUnavailable:
            watchdogTask?.cancel()
            let providerOutcome: AppAccessGateProviderOutcome = outcome == .pendingApproval
                ? .pendingApproval
                : .verificationUnavailable
            recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: providerOutcome,
                recoveryPath: .hosted,
                entitlementActive: entitlementPresence
            )
            self.presentationRevision &+= 1
            self.presentationIdentity = nil
            confirmAccess(holding: outcome == .pendingApproval ? .askToBuy : .unconfirmedCharge)
        case .backRequested:
            watchdogTask?.cancel()
            // A flow that ends at sign-in has no stage behind the gate, and the v1 stages are ones
            // this climber never walked, so back is a plain close.
            if monetizationManager.onboardingFlowVersion == OnboardingAnalyticsContext.currentFlowVersion {
                recordOnboardingBackTapped(presentationIdentity: presentationIdentity)
                handlePaidOffersDeclined(
                    presentationRevision: presentationRevision,
                    presentationIdentity: presentationIdentity,
                    reason: .hostedBackRequested
                )
                return
            }
            // The climber asked for the onboarding step behind the paywall, not for a second one.
            recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: .backRequested,
                recoveryPath: .hosted,
                recoveryReason: .hostedBackRequested,
                entitlementActive: entitlementPresence
            )
            self.presentationRevision &+= 1
            self.presentationIdentity = nil
            guard onRequestOnboardingBack?() == true else {
                // The hosted paywall is already dismissed, so a back that could not land would
                // leave the spinner with nothing behind it. The paywall the climber left comes
                // back instead.
                presentHosted(source: "onboarding_back_unavailable")
                return
            }
            recordOnboardingBackTapped(presentationIdentity: presentationIdentity)
        case .deleteAccountRequested:
            // The climber asked to delete their account, not to shop. Deliberately does not move
            // the phase: the deletion dialog covers the gate, and
            // `accountDeletionDialogDismissed()` answers what happens if they back out.
            watchdogTask?.cancel()
            recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: .deleteAccountRequested,
                recoveryPath: .account,
                recoveryReason: .hostedDeleteAccountRequested,
                entitlementActive: entitlementPresence
            )
            onRequestAccountDeletion?()
        case .signOutRequested:
            // Signing out routes away from the gate entirely, so like a deletion request this does
            // not move the phase.
            watchdogTask?.cancel()
            recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: .signOutRequested,
                recoveryPath: .account,
                recoveryReason: .hostedSignOutRequested,
                entitlementActive: entitlementPresence
            )
            onRequestSignOut?()
        case .dismissedWithoutPurchase:
            watchdogTask?.cancel()
            handlePaidOffersDeclined(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: .hostedDismissed
            )
        case .skipped:
            watchdogTask?.cancel()
            retryHostedAfterBackoff(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: .hostedSkipped
            )
        case .failed:
            watchdogTask?.cancel()
            retryHostedAfterBackoff(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: .hostedError
            )
        }
    }

    /// Internal integration seam for crossing the production presenter/controller boundary in
    /// deterministic tests without instantiating Superwall's private web view controller.
    func handleHostedOutcomeForTesting(_ outcome: PaywallPresentationOutcome) {
        guard let presentationIdentity else { return }
        handleHostedOutcome(
            outcome,
            presentationRevision: presentationRevision,
            presentationIdentity: presentationIdentity
        )
    }

    // MARK: - Unconfirmed purchases

    /// Apple, or the server, says this account may already have paid and the device has not heard.
    ///
    /// The gate re-reads access behind the spinner rather than offering anything to buy. A charge
    /// RevenueCat has not confirmed usually lands within seconds, so it is asked about on the
    /// schedule. An Ask to Buy waits on a person, who may take days or say no, so it is asked about
    /// once.
    ///
    /// Either way the wait is bounded, and it ends on the access paywall: that is the only place
    /// restore, sign out and account deletion live, so a climber held behind the spinner any
    /// longer would have no way to do any of them. The hold is released on the way, or the paywall
    /// could never reopen. Access that lands later still opens the app, through
    /// `entitlementDidChange(_:)`.
    private func confirmAccess(holding hold: PendingPurchaseHold?) {
        guard let identity = monetizationManager.identityGeneration else {
            scheduleHostedRetry()
            return
        }
        accessCheckRevision &+= 1
        let revision = accessCheckRevision
        accessCheckTask?.cancel()
        watchdogTask?.cancel()
        phase = .confirmingAccess
        let waits: [Duration?] = hold == .askToBuy
            ? [nil]
            : [nil] + retryPolicy.accessCheckDelays.map(Optional.some)

        accessCheckTask = Task { @MainActor [weak self, monetizationManager, sleep] in
            let entitlementID = monetizationManager.configuration.revenueCatEntitlementID
            for wait in waits {
                if let wait {
                    do {
                        try await sleep(wait)
                    } catch {
                        return
                    }
                }
                let refresh = await monetizationManager.refreshEntitlements(
                    force: true,
                    waitsForPendingIdentity: true
                )
                guard let self, !Task.isCancelled,
                      self.accessCheckRevision == revision,
                      monetizationManager.identityGeneration == identity else { return }
                if case .refreshed(let state) = refresh,
                   state.hasActiveEntitlement(entitlementID) {
                    self.accessCheckTask = nil
                    self.awaitRoute()
                    return
                }
            }
            guard let self, !Task.isCancelled,
                  self.accessCheckRevision == revision,
                  monetizationManager.identityGeneration == identity else { return }
            self.accessCheckTask = nil
            // Ask to Buy gets one refresh, a charge an immediate read then 2/4/8/16 s: StoreKit guards the double charge, and an indefinite hold behind a wordless spinner would trap the climber.
            monetizationManager.releasePendingPurchaseHold()
            self.presentHosted(
                source: hold == .askToBuy ? "ask_to_buy_pending" : "access_unconfirmed"
            )
        }
    }

    // MARK: - Free week after decline

    /// The climber closed the last paid offer without buying.
    ///
    /// With `free_week_after_decline_enabled` off the paywall reopens: it is a hard paywall, and
    /// the hosted screen is the only one there is. On (`docs/free-week-after-decline.md`):
    ///
    /// - An account that has never had its week is shown the founder letter and let in.
    /// - An account whose week is over gets the hosted paywall again. That paywall is the floor:
    ///   it carries its own restore, delete-account and sign-out controls, and declining it only
    ///   reopens it.
    /// - An account the server could not be asked about is asked about again on a bounded
    ///   schedule, then gets the hosted paywall again, because showing the letter to a climber who
    ///   already spent their week would promise a second one.
    ///
    /// A pending purchase still wins over all of it: a climber Apple may already have charged is
    /// checked for access, never offered a free week on top.
    private func handlePaidOffersDeclined(
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition,
        reason: AppAccessGateRecoveryReason,
        mayReadRecord: Bool = true
    ) {
        if let hold = monetizationManager.pendingPurchaseHold {
            // A paywall whose recovery could not reach this gate still lands here when it closes.
            recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: hold == .askToBuy ? .pendingApproval : .verificationUnavailable,
                recoveryPath: .hosted,
                recoveryReason: reason,
                entitlementActive: entitlementPresence
            )
            confirmAccess(holding: hold)
            return
        }

        let freeWeek = monetizationManager.freeWeek
        guard freeWeek.isEnabled else {
            returnToHosted(
                source: "paid_offers_declined",
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: reason
            )
            return
        }

        switch freeWeek.record {
        case .absent:
            presentFounderLetter(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: reason
            )
        case .granted where freeWeek.liveGrant != nil:
            // The week is already running; routing is about to say so.
            awaitRoute()
        case .granted:
            returnToHosted(
                source: "free_week_ended",
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: reason
            )
        case .unknown, .unavailable:
            guard mayReadRecord else {
                returnToHosted(
                    source: "free_week_unavailable",
                    presentationRevision: presentationRevision,
                    presentationIdentity: presentationIdentity,
                    reason: .freeWeekUnavailable
                )
                return
            }
            readFreeWeekRecord(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: reason
            )
        }
    }

    /// Asks the server whether this account has had its week, again on the schedule until it
    /// answers or the schedule runs out.
    private func readFreeWeekRecord(
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition,
        reason: AppAccessGateRecoveryReason
    ) {
        freeWeekRevision &+= 1
        let revision = freeWeekRevision
        freeWeekTask?.cancel()
        phase = .startingFreeWeek
        let waits: [Duration?] = [nil] + retryPolicy.freeWeekDelays.map(Optional.some)

        freeWeekTask = Task { @MainActor [weak self, monetizationManager, sleep] in
            let freeWeek = monetizationManager.freeWeek
            for wait in waits {
                if let wait {
                    do {
                        try await sleep(wait)
                    } catch {
                        return
                    }
                }
                await freeWeek.refresh()
                guard let self, !Task.isCancelled,
                      self.freeWeekRevision == revision,
                      monetizationManager.identityGeneration == presentationIdentity else { return }
                if freeWeek.record != .unknown, freeWeek.record != .unavailable { break }
            }
            guard let self, !Task.isCancelled,
                  self.freeWeekRevision == revision,
                  monetizationManager.identityGeneration == presentationIdentity else { return }
            self.freeWeekTask = nil
            self.handlePaidOffersDeclined(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: reason,
                mayReadRecord: false
            )
        }
    }

    /// Asks Superwall for the founder letter, and starts the week whatever comes back.
    ///
    /// The letter is a hosted screen with no products, and both of its controls are plain closes,
    /// so there is no choice to read out of how it ended. If it cannot open at all the week starts
    /// anyway: the letter is a courtesy, the access is the promise.
    private func presentFounderLetter(
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition,
        reason: AppAccessGateRecoveryReason
    ) {
        recordGateTerminal(
            presentationRevision: presentationRevision,
            presentationIdentity: presentationIdentity,
            providerOutcome: .freeWeekOffered,
            recoveryPath: .freeWeek,
            recoveryReason: reason,
            entitlementActive: entitlementPresence
        )
        // The paid offers are finished with. Retiring their revision drops any callback still in
        // flight, and the gate attempt has already reported its one terminal.
        self.presentationRevision &+= 1
        lastTerminalPresentationRevision = self.presentationRevision
        freeWeekRevision &+= 1
        let revision = freeWeekRevision
        didShowLetter = false
        armLetterWatchdog(revision: revision, identity: presentationIdentity)

        monetizationManager.presentPaywall(
            .founderLetter,
            params: [
                "source": "paid_offers_declined",
                "gate_attempt_id": presentationAttemptID as Any
            ]
        ) { [weak self] outcome in
            guard let self, self.freeWeekRevision == revision,
                  self.monetizationManager.identityGeneration == presentationIdentity else { return }
            self.handleLetterOutcome(outcome, revision: revision, identity: presentationIdentity)
        }
    }

    /// A letter that never opens must not stand between the climber and the week.
    private func armLetterWatchdog(
        revision: UInt,
        identity: MonetizationIdentityTransition
    ) {
        phase = .openingLetter
        letterWatchdogTask?.cancel()
        letterWatchdogTask = Task { @MainActor [weak self, sleep, hostedOpeningDeadline] in
            do {
                try await sleep(hostedOpeningDeadline)
            } catch {
                return
            }
            guard let self, !Task.isCancelled,
                  self.freeWeekRevision == revision,
                  self.phase == .openingLetter,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.monetizationManager.cancelPaywallPresentation()
            self.startFreeWeek(identity: identity)
        }
    }

    private func handleLetterOutcome(
        _ outcome: PaywallPresentationOutcome,
        revision: UInt,
        identity: MonetizationIdentityTransition
    ) {
        switch outcome {
        case .presented:
            letterWatchdogTask?.cancel()
            phase = .letterPresented
            guard !didShowLetter else { return }
            didShowLetter = true
            if let userID = identity.userID {
                telemetry.track(
                    FreeWeekAnalyticsEvent.letterShown(
                        flowVersion: monetizationManager.onboardingFlowVersion
                    ),
                    ifIdentifiedAs: userID
                )
            }
        case .followOnPaywallOpening:
            // The dashboard chained another screen onto the letter. It reports through this same
            // registration, so the week waits for that one to close.
            armLetterWatchdog(revision: revision, identity: identity)
        case .purchased, .restored:
            letterWatchdogTask?.cancel()
            awaitRoute()
        case .pendingApproval, .verificationUnavailable:
            letterWatchdogTask?.cancel()
            confirmAccess(holding: outcome == .pendingApproval ? .askToBuy : .unconfirmedCharge)
        case .signOutRequested:
            // A climber leaving the account is not accepting a week on it.
            letterWatchdogTask?.cancel()
            onRequestSignOut?()
        case .dismissedWithoutPurchase, .backRequested, .deleteAccountRequested, .skipped, .failed:
            letterWatchdogTask?.cancel()
            startFreeWeek(identity: identity)
        }
    }

    /// Starts the week, again on the schedule while the call fails outright.
    ///
    /// A week that still cannot be started ends on the access paywall, never on a screen of the
    /// gate's own: the climber can decline it again, which asks for the week again.
    private func startFreeWeek(identity: MonetizationIdentityTransition) {
        freeWeekRevision &+= 1
        let revision = freeWeekRevision
        letterWatchdogTask?.cancel()
        letterWatchdogTask = nil
        freeWeekTask?.cancel()
        phase = .startingFreeWeek
        let letterShown = didShowLetter
        let waits: [Duration?] = [nil] + retryPolicy.freeWeekDelays.map(Optional.some)

        freeWeekTask = Task { @MainActor [weak self, monetizationManager, sleep] in
            var outcome = FreeWeekStartOutcome.failed
            for wait in waits {
                if let wait {
                    do {
                        try await sleep(wait)
                    } catch {
                        return
                    }
                }
                outcome = await monetizationManager.startFreeWeek(
                    letterShown: letterShown,
                    identity: identity
                )
                guard let self, !Task.isCancelled,
                      self.freeWeekRevision == revision,
                      monetizationManager.identityGeneration == identity else { return }
                // A switch turned off mid-wait is an answer, not a failure worth asking about again.
                if outcome != .failed || !monetizationManager.freeWeek.isEnabled { break }
            }
            guard let self, !Task.isCancelled,
                  self.freeWeekRevision == revision,
                  monetizationManager.identityGeneration == identity else { return }
            self.freeWeekTask = nil

            switch outcome {
            case .started:
                self.awaitRoute()
            case .alreadyUsed:
                // The server says this account's week is spent, so the paywall is the floor.
                self.presentHosted(source: "free_week_ended")
            case .paidActive:
                // The server already holds paid access for this account; the device has not heard.
                self.confirmAccess(holding: nil)
            case .failed:
                self.presentHosted(source: "free_week_unavailable")
            }
        }
    }

    /// A climber whose week is over is meeting the paywall. Counted once per account, not once per
    /// launch.
    private func recordFreeWeekExpiredGateIfNeeded() {
        guard let userID = monetizationManager.identityGeneration?.userID,
              monetizationManager.freeWeek.claimExpiredGateReport() else { return }

        telemetry.track(
            FreeWeekAnalyticsEvent.expiredGated(
                flowVersion: monetizationManager.freeWeekFlowVersion
            ),
            ifIdentifiedAs: userID
        )
    }

    // MARK: - Analytics

    private var entitlementPresence: Bool? {
        switch monetizationManager.entitlementStateForRouting {
        case .active:
            true
        case .inactive:
            false
        case .unknown:
            nil
        }
    }

    private var currentRecoveryPath: AppAccessGateRecoveryPath {
        switch phase {
        case .openingHosted, .hostedPresented, .awaitingHostedRetry, .confirmingAccess:
            .hosted
        case .openingLetter, .letterPresented, .startingFreeWeek:
            .freeWeek
        case .accessConfirmed:
            .entitlementStream
        }
    }

    private func recordCurrentGateTerminal(
        providerOutcome: AppAccessGateProviderOutcome,
        recoveryPath: AppAccessGateRecoveryPath,
        entitlementActive: Bool?
    ) {
        guard let presentationIdentity else { return }
        recordGateTerminal(
            presentationRevision: presentationRevision,
            presentationIdentity: presentationIdentity,
            providerOutcome: providerOutcome,
            recoveryPath: recoveryPath,
            entitlementActive: entitlementActive
        )
    }

    private func recordOnboardingBackTapped(presentationIdentity: MonetizationIdentityTransition) {
        guard let userID = presentationIdentity.userID else { return }
        telemetry.track(
            OnboardingAnalyticsEvent.backTapped(
                context: OnboardingAnalyticsContext.paywallHandOff(
                    flowVersion: monetizationManager.onboardingFlowVersion
                ),
                inputType: "button"
            ),
            ifIdentifiedAs: userID
        )
    }

    private func recordGateTerminal(
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition,
        providerOutcome: AppAccessGateProviderOutcome,
        recoveryPath: AppAccessGateRecoveryPath,
        recoveryReason: AppAccessGateRecoveryReason? = nil,
        entitlementActive: Bool?
    ) {
        guard lastTerminalPresentationRevision != presentationRevision else { return }
        guard let presentationAttemptID else { return }
        lastTerminalPresentationRevision = presentationRevision
        guard let userID = presentationIdentity.userID else { return }
        telemetry.track(
            PaywallAnalyticsEvent.appAccessGateAttemptTerminal(
                context: AppAccessGateAnalyticsContext(
                    attemptCorrelationID: presentationAttemptID,
                    placement: SuperwallPlacement.appAccessGate.rawValue,
                    recoveryPath: recoveryPath,
                    providerOutcome: providerOutcome,
                    recoveryReason: recoveryReason,
                    identityMatches: monetizationManager.identityGeneration
                        == presentationIdentity,
                    entitlementActive: entitlementActive
                )
            ),
            ifIdentifiedAs: userID
        )
    }
}
