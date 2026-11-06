import Foundation
import Observation
import SuperwallKit

/// The state behind the paywall (14) and the welcome gift (15): the plans, the purchase, restore.
///
/// One instance serves both screens, because the gift is the paywall's own yearly plan at another
/// price and the two share one purchase in flight. It never imports SwiftUI; the screens render it.
///
/// The climber is signed in by the time these screens show, so every purchase and restore is made
/// by an account. Nothing here is written to Firestore.
@MainActor
@Observable
final class OnboardingPaywallModel {
    static let live = OnboardingPaywallModel()

    enum LoadState: Equatable, Sendable {
        case loading
        case ready
        /// No yearly plan came back: offline, or the store has not published it.
        case unavailable
    }

    enum Activity: Equatable, Sendable {
        case idle
        case purchasing
        case restoring
        case checkingAccess
    }

    /// What the climber is told after something did not finish. Each is one sentence on screen.
    enum Notice: Equatable, Sendable {
        case plansUnavailable
        case checkoutFailed
        case pendingApproval
        case verificationUnavailable
        case nothingToRestore
        case restoreFailed
        case accountUnavailable
    }

    enum PurchaseOutcome: Equatable, Sendable {
        case purchased
        case cancelled
        case notCompleted
    }

    enum RestoreOutcome: Equatable, Sendable {
        case restored
        case notCompleted
    }

    private(set) var loadState: LoadState = .loading
    private(set) var activity: Activity = .idle
    private(set) var notice: Notice?
    private(set) var yearly: NativePaywallPlan?
    private(set) var lifetime: NativePaywallPlan?
    private(set) var welcome: NativePaywallPlan?
    /// A purchase or restore this model completed. The entitlement itself is read live, so a grant
    /// that arrives later - an Ask to Buy approval, a purchase still confirming - is seen too.
    private(set) var completedPurchase = false
    var selectedPlanID: String?

    @ObservationIgnored private let provider: any OnboardingPaywallPlanProviding
    @ObservationIgnored private let monetization: MonetizationManager
    @ObservationIgnored private let restoreService: AppAccessRestoreService
    @ObservationIgnored private let holdStore: PendingPurchaseHoldStore
    @ObservationIgnored private let configuration: MonetizationConfiguration
    /// What Apple is still deciding on: Ask to Buy, or a charge RevenueCat has not confirmed. Nothing
    /// else can be bought meanwhile, because another product would be a second real charge.
    private var unconfirmedPurchase: PendingPurchaseHold?

    init(
        provider: (any OnboardingPaywallPlanProviding)? = nil,
        monetization: MonetizationManager = .shared,
        restoreService: AppAccessRestoreService = .shared,
        holdStore: PendingPurchaseHoldStore = PendingPurchaseHoldStore()
    ) {
        self.monetization = monetization
        self.restoreService = restoreService
        self.holdStore = holdStore
        configuration = monetization.configuration
        unconfirmedPurchase = holdStore.hold()
        self.provider = provider ?? RevenueCatNativePaywallPlanProvider(
            configuration: monetization.configuration,
            coordinator: { monetization }
        )
    }

    // MARK: - Derived

    var selectedPlan: NativePaywallPlan? {
        [yearly, lifetime].compactMap { $0 }.first { $0.id == selectedPlanID } ?? yearly
    }

    var isBusy: Bool { activity != .idle }

    var isAwaitingConfirmation: Bool { unconfirmedPurchase != nil }

    var locksPurchase: Bool { isBusy || isAwaitingConfirmation || holdsAccess }

    /// Whether the account already holds the entitlement: a purchase just made, one confirmed late,
    /// or one restored. Reads RevenueCat's state each time, so the screens can react to it arriving
    /// while they are up. The root routes to the app on the same fact.
    var holdsAccess: Bool {
        completedPurchase || monetization.entitlementState.hasActiveEntitlement(
            configuration.revenueCatEntitlementID
        )
    }

    /// The gift, when the store has published its product. Without it there is nothing behind the
    /// paywall's close button, so the button is not drawn.
    var giftOffer: WelcomeGiftOffer? {
        guard let welcome, let yearly else { return nil }
        return WelcomeGiftOffer(welcome: welcome, regular: yearly)
    }

    // MARK: - Loading

    func load() async {
        completedPurchase = false
        loadState = .loading
        resetNotice()

        do {
            let plans = try await provider.loadOnboardingPlans()
            yearly = plans.first { $0.id == configuration.revenueCatYearlyProductID }
            lifetime = plans.first { $0.id == configuration.revenueCatLifetimeProductID }
            welcome = plans.first { $0.id == configuration.revenueCatWelcomeProductID }
        } catch {
            yearly = nil
            lifetime = nil
            welcome = nil
        }

        if yearly == nil {
            loadState = .unavailable
            notice = .plansUnavailable
        } else {
            loadState = .ready
            if selectedPlan == nil || selectedPlanID == nil { selectedPlanID = yearly?.id }
        }
    }

    // MARK: - Purchase

    func purchaseSelectedPlan() async -> PurchaseOutcome {
        guard let plan = selectedPlan else { return .notCompleted }
        return await purchase(plan)
    }

    /// Claims the gift: the same entitlement at the welcome price.
    func claimGift() async -> PurchaseOutcome {
        guard let welcome else { return .notCompleted }
        return await purchase(welcome)
    }

    private func purchase(_ plan: NativePaywallPlan) async -> PurchaseOutcome {
        guard !locksPurchase else { return .notCompleted }
        guard let identity = monetization.identityGeneration else {
            notice = .accountUnavailable
            return .notCompleted
        }

        activity = .purchasing
        notice = nil
        PaywallTransactionContextStore.shared.record(
            placement: SuperwallPlacement.onboardingPaywall.rawValue,
            presentationID: nil,
            recoveryPath: .native,
            identity: identity,
            productID: plan.id
        )

        let result = await provider.purchase(planID: plan.id)
        activity = .idle

        // The identity can move on while Apple's sheet is up; an answer for another identity says
        // nothing about this climber.
        guard monetization.identityGeneration == identity else {
            notice = .accountUnavailable
            return .notCompleted
        }

        switch result {
        case .purchased:
            completedPurchase = true
            return .purchased
        case .cancelled:
            return .cancelled
        case .pending:
            holdUnconfirmed(.askToBuy)
            return .notCompleted
        case .failed(let error):
            if let controllerError = error as? RevenueCatPurchaseControllerError,
               case .entitlementUnconfirmed = controllerError {
                holdUnconfirmed(.unconfirmedCharge)
            } else {
                notice = .checkoutFailed
            }
            return .notCompleted
        @unknown default:
            notice = .checkoutFailed
            return .notCompleted
        }
    }

    // MARK: - Restore

    func restore() async -> RestoreOutcome {
        guard activity == .idle else { return .notCompleted }

        activity = .restoring
        notice = nil
        let outcome = await restoreService.restore(
            context: .onboardingPaywall(identity: monetization.identityGeneration)
        )
        activity = .idle

        switch outcome {
        case .restored:
            completedPurchase = true
            releaseUnconfirmedPurchase()
            return .restored
        case .notFound:
            // RevenueCat found no access, which a charge it has not attached looks like too, so that
            // lock stays. Ask to Buy is released, undecided or declined: the two read the same, and
            // a declined one must not stay locked.
            if unconfirmedPurchase == .unconfirmedCharge {
                resetNotice()
            } else {
                releaseUnconfirmedPurchase()
                notice = .nothingToRestore
            }
        case .failed:
            notice = .restoreFailed
        }

        return .notCompleted
    }

    // MARK: - Checking

    /// Asks again whether the unconfirmed purchase has landed. Access arriving takes the climber into
    /// the app, because the root routes on the entitlement; anything else leaves the lock and its
    /// warning in place.
    func checkAccess() async {
        guard activity == .idle, isAwaitingConfirmation else { return }

        activity = .checkingAccess
        notice = nil
        await monetization.refreshEntitlements(force: true, waitsForPendingIdentity: true)
        activity = .idle

        if !holdsAccess { resetNotice() }
    }

    // MARK: - Progress

    /// Drops whatever the last screen was told, keeping only the warning not to purchase again.
    func resetNotice() {
        notice = unconfirmedPurchase?.notice
    }

    private func holdUnconfirmed(_ hold: PendingPurchaseHold) {
        holdStore.mark(hold)
        unconfirmedPurchase = hold
        resetNotice()
    }

    /// Ends the hold, on disk and here. The root calls it when access arrives and when the climber
    /// signs out, so a marker cannot lock the paywall once there is nothing left to wait for.
    func releaseUnconfirmedPurchase() {
        holdStore.clear()
        unconfirmedPurchase = nil
    }
}

private extension PendingPurchaseHold {
    var notice: OnboardingPaywallModel.Notice {
        switch self {
        case .askToBuy: .pendingApproval
        case .unconfirmedCharge: .verificationUnavailable
        }
    }
}

extension OnboardingPaywallModel.Notice {
    var message: String {
        switch self {
        case .plansUnavailable:
            "Plans are unavailable right now. Check your connection and try again."
        case .checkoutFailed:
            "Checkout could not finish. Check your connection and try again."
        case .pendingApproval:
            "Apple is still confirming your purchase: Ask to Buy is waiting for approval. Do not purchase again."
        case .verificationUnavailable:
            "Apple is still confirming your purchase: the charge is not confirmed yet. Do not purchase again."
        case .nothingToRestore:
            "No active Ascend purchase was found for this Apple ID."
        case .restoreFailed:
            "Apple could not finish the restore. Try again."
        case .accountUnavailable:
            "Ascend is still getting ready. Try again in a moment."
        }
    }
}
