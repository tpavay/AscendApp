import Foundation
import Observation
import SuperwallKit

enum AppAccessGatePhase: CaseIterable, Equatable, Sendable {
    case openingHosted
    case hostedPresented
    case loadingNative
    case nativeReady
    case purchasing
    case verifying
    case verificationUnavailable
    case pendingApproval
    case accessConfirmed
    case failed
    /// The climber asked for the onboarding step behind the paywall and it could not be reopened.
    case backUnavailable
}

@MainActor
@Observable
final class AppAccessPaywallCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private(set) var phase: AppAccessGatePhase
    private(set) var plans: [NativeSubscriptionPlan] = []
    private(set) var selectedPlanID: String?
    private(set) var statusMessage: String?
    private(set) var restoreState: AppAccessRestoreState = .idle

    private let monetizationManager: MonetizationManager
    private let nativeProvider: any NativeSubscriptionProviding
    private let restoreService: AppAccessRestoreService
    /// Returns whether the onboarding step behind the paywall actually reopened, so the gate
    /// never leaves a climber on a hosted paywall that is already gone.
    private let onRequestOnboardingBack: (@MainActor () -> Bool)?
    /// Opens the same account-deletion dialog the gate's own `Delete account` control opens, so the
    /// hosted and native routes can never reach two different destinations.
    ///
    /// Ascend has already dismissed the hosted paywall by the time this is asked, so the dialog has
    /// to open. `RootView` guarantees that by making the only sheet that could defer it - the soft
    /// update nudge - yield first, rather than reporting a refusal this gate would have nowhere to
    /// render.
    private let onRequestAccountDeletion: (@MainActor () -> Void)?
    private let telemetry: TelemetryManager
    private let hostedOpeningDeadline: Duration
    private let nativeLoadingDeadline: Duration
    private let sleep: Sleep
    private let nativeLoadSleep: Sleep
    private var presentationRevision: UInt = 0
    private var presentationIdentity: MonetizationIdentityTransition?
    private var presentationAttemptID: String?
    private var lastTerminalPresentationRevision: UInt?
    private var nativeLoadRevision: UInt = 0
    private var watchdogTask: Task<Void, Never>?
    private var nativeLoadTask: Task<Void, Never>?
    private var nativeLoadDeadlineTask: Task<Void, Never>?
    private var purchaseTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var accessCheckTask: Task<Void, Never>?
    private var purchaseRevision: UInt = 0
    private var restoreRevision: UInt = 0
    private var accessCheckRevision: UInt = 0

    init(
        monetizationManager: MonetizationManager,
        nativeProvider: (any NativeSubscriptionProviding)? = nil,
        restoreService: AppAccessRestoreService? = nil,
        telemetry: TelemetryManager = .shared,
        initialPhase: AppAccessGatePhase = .openingHosted,
        initialRestoreState: AppAccessRestoreState = .idle,
        initialPlans: [NativeSubscriptionPlan] = [],
        initialStatusMessage: String? = nil,
        onRequestOnboardingBack: (@MainActor () -> Bool)? = nil,
        onRequestAccountDeletion: (@MainActor () -> Void)? = nil,
        hostedOpeningDeadline: Duration = .seconds(8),
        nativeLoadingDeadline: Duration = .seconds(12),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        nativeLoadSleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.monetizationManager = monetizationManager
        self.nativeProvider = nativeProvider ?? RevenueCatNativeSubscriptionProvider(
            configuration: monetizationManager.configuration,
            coordinator: { monetizationManager }
        )
        self.restoreService = restoreService ?? .shared
        self.onRequestOnboardingBack = onRequestOnboardingBack
        self.onRequestAccountDeletion = onRequestAccountDeletion
        self.telemetry = telemetry
        self.phase = initialPhase
        restoreState = initialRestoreState
        plans = initialPlans
        selectedPlanID = initialPlans.first?.id
        statusMessage = initialStatusMessage
        self.hostedOpeningDeadline = hostedOpeningDeadline
        self.nativeLoadingDeadline = nativeLoadingDeadline
        self.sleep = sleep
        self.nativeLoadSleep = nativeLoadSleep
    }

    var showsProgress: Bool {
        switch phase {
        case .openingHosted, .hostedPresented, .loadingNative, .purchasing, .verifying:
            return true
        case .nativeReady, .verificationUnavailable, .pendingApproval, .accessConfirmed, .failed,
             .backUnavailable:
            return false
        }
    }

    var disablesPurchase: Bool {
        if restoreState == .restoring { return true }
        switch phase {
        case .openingHosted, .hostedPresented, .loadingNative, .purchasing, .verifying,
             .verificationUnavailable, .pendingApproval, .accessConfirmed, .backUnavailable:
            return true
        case .nativeReady, .failed:
            return false
        }
    }

    var disablesRestore: Bool {
        restoreState == .restoring || phase == .purchasing || phase == .accessConfirmed
    }

    var showsPurchaseControls: Bool {
        phase == .nativeReady
    }

    var selectedPlan: NativeSubscriptionPlan? {
        guard let selectedPlanID else { return nil }
        return plans.first { $0.id == selectedPlanID }
    }

    func start() {
        guard phase == .openingHosted else { return }
        presentHosted(source: "app_access_gate")
    }

    func retryHosted() {
        presentHosted(source: "paywall_placeholder_retry")
    }

    /// The account-deletion dialog closed and this gate is still on screen, so the deletion did not
    /// happen - a completed one ends the session and routes away from here entirely.
    ///
    /// Ascend dismissed the hosted paywall itself to raise that dialog, so backing out of it would
    /// otherwise leave the opening spinner with no controls at all: no plans, no restore, no
    /// support links, and not even the account-deletion route Guideline 5.1.1(v) requires. Cancelling
    /// a deletion means nothing happened, so the paywall the climber was reading comes back.
    ///
    /// Only from a hosted phase. A deletion raised from the gate's own control leaves the native
    /// recovery surface exactly where it was.
    ///
    /// Returns whether the hosted paywall is coming back, because the control the climber was
    /// focused on is about to stop being rendered when it is.
    @discardableResult
    func accountDeletionDialogDismissed() -> Bool {
        guard phase == .hostedPresented || phase == .openingHosted else { return false }
        presentHosted(source: "account_deletion_dismissed")
        return phase == .openingHosted
    }

    func selectPlan(_ planID: String) {
        guard restoreState != .restoring,
              !disablesPurchase,
              plans.contains(where: { $0.id == planID }) else { return }
        selectedPlanID = planID
    }

    func purchaseSelectedPlan() {
        guard phase == .nativeReady,
              restoreState != .restoring,
              let selectedPlanID,
              let identity = monetizationManager.identityGeneration else { return }
        purchaseRevision &+= 1
        let revision = purchaseRevision
        purchaseTask?.cancel()
        phase = .purchasing
        statusMessage = "Apple is opening checkout."

        purchaseTask = Task { @MainActor [weak self, nativeProvider] in
            guard let self else { return }
            PaywallTransactionContextStore.shared.record(
                placement: SuperwallPlacement.appAccessGate.rawValue,
                presentationID: nil,
                gateAttemptID: self.presentationAttemptID,
                recoveryPath: .native,
                identity: identity,
                productID: selectedPlanID
            )
            let result = await nativeProvider.purchase(planID: selectedPlanID)
            guard !Task.isCancelled,
                  self.purchaseRevision == revision,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.purchaseTask = nil

            self.handlePurchaseResult(result)
        }
    }

    func restore() {
        guard !disablesRestore,
              let identity = monetizationManager.identityGeneration else { return }
        restoreRevision &+= 1
        let revision = restoreRevision
        restoreTask?.cancel()
        restoreState = .restoring
        restoreTask = Task { @MainActor [weak self, restoreService] in
            let outcome = await restoreService.restore(
                context: .appAccessGate(
                    gateAttemptID: self?.presentationAttemptID,
                    identity: identity
                )
            )
            guard let self, !Task.isCancelled,
                  self.restoreRevision == revision,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.restoreTask = nil
            self.restoreState = AppAccessRestoreState(outcome: outcome)
            if case .restored = outcome {
                self.phase = .accessConfirmed
                self.statusMessage = "Access restored. Opening Ascend."
            }
        }
    }

    func checkAccess() {
        guard phase == .verificationUnavailable || phase == .pendingApproval,
              let identity = monetizationManager.identityGeneration else { return }
        accessCheckRevision &+= 1
        let revision = accessCheckRevision
        accessCheckTask?.cancel()
        phase = .verifying
        statusMessage = "Checking your subscription access."
        accessCheckTask = Task { @MainActor [weak self, monetizationManager] in
            let refresh = await monetizationManager.refreshEntitlements(
                force: true,
                waitsForPendingIdentity: true
            )
            guard let self, !Task.isCancelled,
                  self.accessCheckRevision == revision,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.accessCheckTask = nil
            switch refresh {
            case .refreshed(let state) where state.hasActiveEntitlement(
                self.monetizationManager.configuration.revenueCatEntitlementID
            ):
                self.phase = .accessConfirmed
                self.statusMessage = "Access confirmed. Opening Ascend."
            case .refreshed, .unavailable:
                self.phase = .verificationUnavailable
                self.statusMessage = "Payment may still be processing. Do not purchase again. Check access again, restore, manage your subscription, or contact support."
            }
        }
    }

    func identityDidChange() {
        cancelOwnedWork(
            providerOutcome: .staleIdentity,
            entitlementActive: entitlementPresence
        )
        plans = []
        selectedPlanID = nil
        restoreState = .idle
        phase = .openingHosted
        statusMessage = "Opening subscription options."
        start()
    }

    func cancelOwnedWork() {
        cancelOwnedWork(
            providerOutcome: .cancelled,
            entitlementActive: entitlementPresence
        )
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
        nativeLoadRevision &+= 1
        purchaseRevision &+= 1
        restoreRevision &+= 1
        accessCheckRevision &+= 1
        watchdogTask?.cancel()
        nativeLoadTask?.cancel()
        nativeLoadDeadlineTask?.cancel()
        purchaseTask?.cancel()
        restoreTask?.cancel()
        accessCheckTask?.cancel()
        watchdogTask = nil
        nativeLoadTask = nil
        nativeLoadDeadlineTask = nil
        purchaseTask = nil
        restoreTask = nil
        accessCheckTask = nil
        monetizationManager.cancelPaywallPresentation()
    }

    func entitlementDidChange(_ state: MonetizationEntitlementState) {
        guard state.hasActiveEntitlement(
            monetizationManager.configuration.revenueCatEntitlementID
        ) else { return }
        // Active entitlement truth wins every presentation state. Retire all callback authority
        // before publishing confirmation so a late hosted terminal or plan load cannot re-enable
        // checkout for a climber who already has access.
        cancelOwnedWork(
            providerOutcome: .entitlementActive,
            entitlementActive: true
        )
        phase = .accessConfirmed
        statusMessage = "Access confirmed. Opening Ascend."
    }

    private func presentHosted(source: String) {
        guard let identity = monetizationManager.identityGeneration else {
            phase = .failed
            statusMessage = "Ascend is still confirming your account. Try subscription options again when the account check finishes."
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
        nativeLoadRevision &+= 1
        nativeLoadTask?.cancel()
        nativeLoadTask = nil
        phase = .openingHosted
        statusMessage = "Opening subscription options."
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self, sleep, hostedOpeningDeadline] in
            do {
                try await sleep(hostedOpeningDeadline)
            } catch {
                return
            }
            guard let self, self.presentationRevision == revision,
                  self.phase == .openingHosted,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.monetizationManager.cancelPaywallPresentation()
            self.beginNativeFallback(
                message: "Subscription options took too long to open. Choose a plan below.",
                presentationRevision: revision,
                presentationIdentity: identity,
                reason: .watchdogTimeout
            )
        }

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

    private func handleHostedOutcome(
        _ outcome: PaywallPresentationOutcome,
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition
    ) {
        switch outcome {
        case .presented:
            watchdogTask?.cancel()
            phase = .hostedPresented
            statusMessage = nil
        case .purchased, .restored:
            watchdogTask?.cancel()
            recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: outcome == .purchased ? .purchased : .restored,
                recoveryPath: .hosted,
                entitlementActive: true
            )
            phase = .accessConfirmed
            statusMessage = "Access confirmed. Opening Ascend."
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
            phase = outcome == .pendingApproval ? .pendingApproval : .verificationUnavailable
            statusMessage = outcome == .pendingApproval
                ? "Apple is still waiting for approval or confirmation. Do not purchase again."
                : "Payment may still be processing. Do not purchase again while Ascend confirms access."
        case .backRequested:
            // The climber asked for the onboarding step behind the paywall, not for a second one.
            // Deliberately never falls through to the native plan list.
            watchdogTask?.cancel()
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
                // leave the gate with no controls at all - not even the account-deletion route
                // Guideline 5.1.1(v) requires. Recovery, never the native plan list.
                phase = .backUnavailable
                statusMessage = "Ascend couldn't reopen the previous step. Try subscription options again, restore, manage your subscription, or contact support."
                return
            }
            recordOnboardingBackTapped(presentationIdentity: presentationIdentity)
        case .deleteAccountRequested:
            // The climber asked to delete their account, not to shop. Deliberately never falls
            // through to the native plan list, and deliberately does not move the phase: the
            // deletion dialog covers the gate, and a phase change here would announce
            // "Loading subscription options." over that dialog to a VoiceOver climber.
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
        case .dismissedWithoutPurchase:
            watchdogTask?.cancel()
            beginNativeFallback(
                message: "No purchase was made. Choose a plan below.",
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: .hostedDismissed
            )
        case .skipped:
            watchdogTask?.cancel()
            beginNativeFallback(
                message: "Subscription options could not open. Choose a plan below.",
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                reason: .hostedSkipped
            )
        case .failed:
            watchdogTask?.cancel()
            beginNativeFallback(
                message: "Subscription options could not open. Choose a plan below.",
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

    private func beginNativeFallback(
        message: String,
        presentationRevision: UInt,
        presentationIdentity: MonetizationIdentityTransition,
        reason: AppAccessGateRecoveryReason
    ) {
        guard let identity = monetizationManager.identityGeneration else {
            phase = .failed
            statusMessage = "Ascend is still confirming your account. Try again when the account check finishes."
            return
        }
        nativeLoadRevision &+= 1
        let revision = nativeLoadRevision
        nativeLoadTask?.cancel()
        nativeLoadDeadlineTask?.cancel()
        phase = .loadingNative
        statusMessage = message
        nativeLoadDeadlineTask = Task {
            @MainActor [weak self, nativeLoadSleep, nativeLoadingDeadline] in
            do {
                try await nativeLoadSleep(nativeLoadingDeadline)
            } catch {
                return
            }
            guard let self,
                  self.nativeLoadRevision == revision,
                  self.phase == .loadingNative,
                  self.monetizationManager.identityGeneration == identity else { return }
            self.nativeLoadRevision &+= 1
            self.nativeLoadTask?.cancel()
            self.nativeLoadTask = nil
            self.nativeLoadDeadlineTask = nil
            self.recordGateTerminal(
                presentationRevision: presentationRevision,
                presentationIdentity: presentationIdentity,
                providerOutcome: .nativeUnavailable,
                recoveryPath: .native,
                recoveryReason: reason,
                entitlementActive: self.entitlementPresence
            )
            self.phase = .failed
            self.statusMessage = "Subscription options took too long to load. Try again, restore purchases, manage your subscription, or contact support."
        }
        nativeLoadTask = Task { @MainActor [weak self, nativeProvider] in
            do {
                let loadedPlans = try await nativeProvider.loadPlans()
                guard let self, !Task.isCancelled,
                      self.nativeLoadRevision == revision,
                      self.monetizationManager.identityGeneration == identity else { return }
                self.nativeLoadDeadlineTask?.cancel()
                self.nativeLoadDeadlineTask = nil
                guard !loadedPlans.isEmpty else {
                    self.recordGateTerminal(
                        presentationRevision: presentationRevision,
                        presentationIdentity: presentationIdentity,
                        providerOutcome: .nativeUnavailable,
                        recoveryPath: .native,
                        recoveryReason: reason,
                        entitlementActive: self.entitlementPresence
                    )
                    self.phase = .failed
                    self.statusMessage = "Plans are unavailable right now. Restore, manage your subscription, or contact support."
                    return
                }
                self.plans = loadedPlans
                self.selectedPlanID = loadedPlans.first?.id
                self.recordGateTerminal(
                    presentationRevision: presentationRevision,
                    presentationIdentity: presentationIdentity,
                    providerOutcome: .nativeReady,
                    recoveryPath: .native,
                    recoveryReason: reason,
                    entitlementActive: self.entitlementPresence
                )
                self.phase = .nativeReady
                if loadedPlans.count == 1, let title = loadedPlans.first?.title {
                    self.statusMessage = "\(title) is available. Cancel anytime in Apple subscriptions."
                } else {
                    let choices = loadedPlans.map(\.title).formatted(.list(type: .and))
                    self.statusMessage = "Choose from \(choices). Cancel anytime in Apple subscriptions."
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled,
                      self.nativeLoadRevision == revision,
                      self.monetizationManager.identityGeneration == identity else { return }
                self.nativeLoadDeadlineTask?.cancel()
                self.nativeLoadDeadlineTask = nil
                self.recordGateTerminal(
                    presentationRevision: presentationRevision,
                    presentationIdentity: presentationIdentity,
                    providerOutcome: .nativeUnavailable,
                    recoveryPath: .native,
                    recoveryReason: reason,
                    entitlementActive: self.entitlementPresence
                )
                self.phase = .failed
                self.statusMessage = "Plans are unavailable right now. Check your connection, restore, or contact support."
            }
        }
    }

    private func handlePurchaseResult(_ result: PurchaseResult) {
        switch result {
        case .purchased:
            phase = .accessConfirmed
            statusMessage = "Access confirmed. Opening Ascend."
        case .cancelled:
            phase = .nativeReady
            statusMessage = "No purchase was made. Choose a plan when you are ready."
        case .pending:
            phase = .pendingApproval
            statusMessage = "Apple is still waiting for approval or confirmation. Do not purchase again."
        case .failed(let error):
            if let controllerError = error as? RevenueCatPurchaseControllerError,
               case .entitlementUnconfirmed = controllerError {
                phase = .verificationUnavailable
                statusMessage = "Payment may still be processing. Do not purchase again while Ascend confirms access."
            } else {
                phase = .nativeReady
                statusMessage = "Checkout could not finish. Check your connection and try again."
            }
        @unknown default:
            phase = .nativeReady
            statusMessage = "Checkout could not finish. Check your connection and try again."
        }
    }


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
        case .openingHosted, .hostedPresented:
            .hosted
        case .loadingNative, .nativeReady, .purchasing, .verifying,
             .verificationUnavailable, .pendingApproval, .failed:
            .native
        case .backUnavailable:
            .hosted
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
                context: OnboardingAnalyticsEvent.paywallContext,
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
