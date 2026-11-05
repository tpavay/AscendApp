import Foundation
import Observation
import SuperwallKit

/// The state behind the paywall (13) and the welcome gift (14): the plans, the purchase, restore.
///
/// One instance serves both screens, because the gift is the paywall's own yearly plan at another
/// price and the two share one purchase in flight. It never imports SwiftUI; the screens render it.
///
/// The purchase is made as the anonymous RevenueCat customer a signed-out install starts as.
/// Signing in moves it onto the account (``PreAuthPurchaseTransfer``), so nothing here is written to
/// Firestore and nothing needs a uid.
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
        case purchased(startedTrial: Bool)
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
    private(set) var holdsAccess = false
    var selectedPlanID: String?

    @ObservationIgnored private let provider: any PreAuthPaywallPlanProviding
    @ObservationIgnored private let monetization: MonetizationManager
    @ObservationIgnored private let restoreService: AppAccessRestoreService
    @ObservationIgnored private let ledger: PreAuthPurchaseLedger
    @ObservationIgnored private let configuration: MonetizationConfiguration
    @ObservationIgnored private let now: () -> Date

    init(
        provider: (any PreAuthPaywallPlanProviding)? = nil,
        monetization: MonetizationManager = .shared,
        restoreService: AppAccessRestoreService = .shared,
        ledger: PreAuthPurchaseLedger = PreAuthPurchaseLedger(),
        now: @escaping () -> Date = Date.init
    ) {
        self.monetization = monetization
        self.restoreService = restoreService
        self.ledger = ledger
        self.now = now
        configuration = monetization.configuration
        self.provider = provider ?? RevenueCatNativePaywallPlanProvider(
            configuration: monetization.configuration,
            allowsAnonymousPurchase: true,
            coordinator: { monetization }
        )
    }

    // MARK: - Derived

    var selectedPlan: NativePaywallPlan? {
        [yearly, lifetime].compactMap { $0 }.first { $0.id == selectedPlanID } ?? yearly
    }

    var isBusy: Bool { activity != .idle }

    /// The gift, when the store has published its product. Without it there is nothing behind the
    /// paywall's close button, so the button is not drawn.
    var giftOffer: WelcomeGiftOffer? {
        guard let welcome, let yearly else { return nil }
        return WelcomeGiftOffer(welcome: welcome, regular: yearly)
    }

    // MARK: - Loading

    func load() async {
        refreshAccess()
        loadState = .loading
        notice = nil

        do {
            let plans = try await provider.loadPreAuthPlans()
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

    /// Reads whether this install already holds the entitlement - a purchase made before a
    /// relaunch, or one restored - so the paywall steps aside instead of selling twice.
    func refreshAccess() {
        holdsAccess = monetization.entitlementState.hasActiveEntitlement(
            configuration.revenueCatEntitlementID
        )
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
        guard activity == .idle else { return .notCompleted }
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
            let startedTrial = plan.freeTrialPeriod != nil
            ledger.recordPurchase(
                PreAuthPurchase(
                    productID: plan.id,
                    purchasedAt: now(),
                    startedTrial: startedTrial
                )
            )
            holdsAccess = true
            return .purchased(startedTrial: startedTrial)
        case .cancelled:
            return .cancelled
        case .pending:
            notice = .pendingApproval
            return .notCompleted
        case .failed(let error):
            if let controllerError = error as? RevenueCatPurchaseControllerError,
               case .entitlementUnconfirmed = controllerError {
                notice = .verificationUnavailable
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
            ledger.recordPurchase(
                PreAuthPurchase(
                    source: .restore,
                    productID: "restored",
                    purchasedAt: now(),
                    startedTrial: false
                )
            )
            holdsAccess = true
            return .restored
        case .notFound:
            notice = .nothingToRestore
        case .failed:
            notice = .restoreFailed
        }

        return .notCompleted
    }

    // MARK: - Progress

    func markPaywallReached() {
        ledger.markPaywallReached(at: now())
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
            "Apple is waiting for approval. Do not purchase again."
        case .verificationUnavailable:
            "Payment may still be processing. Do not purchase again."
        case .nothingToRestore:
            "No active Ascend purchase was found for this Apple ID."
        case .restoreFailed:
            "Apple could not finish the restore. Try again."
        case .accountUnavailable:
            "Ascend is still getting ready. Try again in a moment."
        }
    }
}
