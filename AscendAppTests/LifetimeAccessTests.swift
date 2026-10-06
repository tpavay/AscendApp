import Foundation
import RevenueCat
import SuperwallKit
import Testing
@testable import AscendApp

/// Lifetime is Ascend's first purchase that is not a subscription: a non-consumable RevenueCat
/// reports as an active entitlement with no expiry, no renewal and no trial. Every access path was
/// written while only subscriptions existed, so each one is held here against exactly that shape -
/// the entitlement read, the root route, both purchase verdicts, and both restore surfaces.
@MainActor
struct LifetimeAccessTests {
    private static let entitlementID = "app_access"
    private static let productID = "ascend_lifetime"

    @Test(arguments: [true, false])
    func aLifetimeEntitlementWithNoExpiryIsFullAppAccess(isSandbox: Bool) {
        let entitlement = Self.lifetimeEntitlement(isSandbox: isSandbox)
        let customerInfo = Self.customerInfo(holding: entitlement)

        #expect(entitlement.expirationDate == nil)
        #expect(entitlement.willRenew == false)
        #expect(customerInfo.entitlements.appAccessEntitlementIDs == [Self.entitlementID])
        #expect(
            RevenueCatPurchasesProvider.entitlementState(from: customerInfo)
                == .active([Self.entitlementID])
        )
    }

    @Test
    func aLifetimeOwnerRoutesStraightToTheApp() {
        let state = Self.customerInfo(holding: Self.lifetimeEntitlement(isSandbox: false))
            .entitlements.appAccessEntitlementState

        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "lifetime-climber",
            postAuthOnboardingPhase: .complete,
            entitlementState: state,
            requiredEntitlementID: Self.entitlementID
        )

        #expect(route == .mainApp)
    }

    /// The verdict both paywalls share: the hosted Superwall paywall and the native fallback each
    /// hand their purchase to this executor, so one Lifetime purchase proves both.
    @Test(arguments: [true, false])
    func buyingLifetimeIsVerifiedAndPublishedLikeAnyOtherPurchase(isSandbox: Bool) async {
        let state = Self.customerInfo(holding: Self.lifetimeEntitlement(isSandbox: isSandbox))
            .entitlements.appAccessEntitlementState
        let harness = LifetimePurchaseHarness(
            entitlementID: Self.entitlementID,
            refresh: .refreshed(state)
        )

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: false,
                entitlementState: state
            )
        }

        guard case .purchased = result else {
            Issue.record("A Lifetime purchase holding app_access must report purchased: \(result)")
            return
        }
        #expect(harness.published == [[Self.entitlementID]])
        #expect(
            RevenueCatPurchaseController.subscriptionStatus(for: [Self.entitlementID])
                == .active([SuperwallKit.Entitlement(id: Self.entitlementID)])
        )

        let names = harness.sink.records.map(\.name)
        let completed = harness.sink.records.filter { $0.name == "revenuecat_purchase_completed" }
        #expect(completed.count == 1)
        #expect(completed.first?.parameters["product_id"] == TelemetryValue.string(Self.productID))
        #expect(!names.contains("revenuecat_purchase_failed"))
    }

    /// What happens if `ascend_lifetime` is sold before RevenueCat attaches it to `app_access`:
    /// Apple takes the money and no entitlement arrives. Ascend must not call that a purchase, and
    /// must not unlock the app on the charge alone - the server grant would refuse every screen.
    @Test
    func aLifetimeChargeThatGrantsNoEntitlementIsNeverReportedAsPurchased() async {
        let harness = LifetimePurchaseHarness(
            entitlementID: Self.entitlementID,
            refresh: .refreshed(.inactive)
        )

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: false,
                entitlementState: .inactive
            )
        }

        guard case .failed(let error) = result,
              case .entitlementUnconfirmed = error as? RevenueCatPurchaseControllerError else {
            Issue.record("An unentitled Lifetime charge must fail as unconfirmed: \(result)")
            return
        }
        #expect(
            error.localizedDescription
                == "Ascend couldn't confirm your purchase. Check your connection and try again."
        )
        #expect(!harness.sink.records.map(\.name).contains("revenuecat_purchase_completed"))
    }

    @Test(arguments: [true, false])
    func restoreBringsALifetimePurchaseBackOnEverySurface(isSandbox: Bool) async {
        let state = Self.customerInfo(holding: Self.lifetimeEntitlement(isSandbox: isSandbox))
            .entitlements.appAccessEntitlementState
        let service = Self.restoreService(restoring: state)

        let outcome = await service.restore()
        guard case .restored(let entitlementIDs) = outcome else {
            Issue.record("A Lifetime purchase must restore: \(outcome)")
            return
        }
        #expect(entitlementIDs == [Self.entitlementID])
        // The app-access gate and the hosted paywall's Restore both read this outcome.
        #expect(AppAccessRestoreState(outcome: outcome) == .restored)

        // Settings -> Restore Purchases.
        let settings = RestorePurchasesViewModel(restoreService: Self.restoreService(restoring: state))
        await settings.restorePurchases()
        #expect(settings.result == .restored)
    }

    /// The found-nothing sentence is read by a climber who may own Lifetime on another Apple ID,
    /// so it names both things Ascend sells rather than only a subscription.
    @Test
    func restoreFindingNothingNamesBothWaysOfOwningAscend() async {
        let expected = "No active Ascend subscription or Lifetime purchase was found for this Apple ID."
        let settings = RestorePurchasesViewModel(
            restoreService: Self.restoreService(restoring: .inactive)
        )
        await settings.restorePurchases()

        #expect(settings.result?.title == expected)
        #expect(AppAccessRestoreState.noPurchasesFound.statusMessage == expected)
        #expect(RevenueCatPurchaseControllerError.noPurchasesFound.errorDescription == expected)
    }

    /// The hosted paywall's own restore alert is Superwall's, shown for every failed restore with
    /// the error discarded. Its default reads "No Subscription Found", so Ascend supplies copy that
    /// is true for a Lifetime owner and for a restore that never reached the store.
    @Test
    func theHostedPaywallsRestoreAlertDoesNotAssumeASubscription() {
        let options = SuperwallPaywallPresenter.makeOptions(
            configuration: MonetizationConfiguration(infoDictionary: [:])
        )
        let alert = options.paywalls.restoreFailed

        #expect(alert.title == "Nothing Restored")
        #expect(
            alert.message
                == "Ascend found no active subscription or Lifetime purchase to restore for this "
                + "Apple ID. Check your connection and try again."
        )
        #expect(alert.closeButtonTitle == "OK")
        #expect(options.paywalls.shouldShowPurchaseFailureAlert == false)
    }

    /// Both builds sell Lifetime from the fallback paywall and audit it in the offering, and neither
    /// names Monthly: Monthly is still on sale in App Store Connect, so demanding it of the
    /// offering would report a mismatch the day it is taken out.
    @Test(arguments: [
        ["ascend_staging_yearly", "ascend_staging_lifetime", "ascend_staging_monthly"],
        ["ascend_yearly", "ascend_lifetime", "ascend_monthly"]
    ])
    func theLaunchCatalogIsAnnualAndLifetimeAndTheAuditAgrees(productIDs: [String]) {
        let (yearly, lifetime, monthly) = (productIDs[0], productIDs[1], productIDs[2])
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_key",
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: yearly,
                MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: lifetime
            ]
        )

        #expect(configuration.launchProductIDs == [yearly, lifetime])

        let withoutMonthly = configuration.auditOffering(
            expectedOfferingProductIDs: [yearly, lifetime],
            currentOfferingID: "default"
        )
        #expect(withoutMonthly.isLaunchCatalogComplete)

        let stillCarryingMonthly = configuration.auditOffering(
            expectedOfferingProductIDs: [yearly, lifetime, monthly],
            currentOfferingID: "default"
        )
        #expect(stillCarryingMonthly.isLaunchCatalogComplete)

        let lifetimeNotAttached = configuration.auditOffering(
            expectedOfferingProductIDs: [yearly, monthly],
            currentOfferingID: "default"
        )
        #expect(lifetimeNotAttached.isLaunchCatalogComplete == false)
        #expect(lifetimeNotAttached.missingProductIDs == [lifetime])
    }
}

private extension LifetimeAccessTests {
    /// The entitlement RevenueCat publishes for a non-consumable attached to `app_access`.
    static func lifetimeEntitlement(isSandbox: Bool) -> RevenueCat.EntitlementInfo {
        let purchaseDate = Date(timeIntervalSince1970: 1_800_000_000)

        return EntitlementInfo(
            identifier: entitlementID,
            isActive: true,
            willRenew: false,
            periodType: .normal,
            latestPurchaseDate: purchaseDate,
            originalPurchaseDate: purchaseDate,
            expirationDate: nil,
            store: .appStore,
            productIdentifier: productID,
            isSandbox: isSandbox,
            ownershipType: .purchased
        )
    }

    static func customerInfo(
        holding entitlement: RevenueCat.EntitlementInfo
    ) -> RevenueCat.CustomerInfo {
        let requestDate = Date(timeIntervalSince1970: 1_800_000_600)

        return RevenueCat.CustomerInfo(
            entitlements: EntitlementInfos(entitlements: [entitlementID: entitlement]),
            requestDate: requestDate,
            firstSeen: requestDate.addingTimeInterval(-86_400),
            originalAppUserId: "lifetime-climber"
        )
    }

    static func restoreService(
        restoring state: MonetizationEntitlementState
    ) -> AppAccessRestoreService {
        let telemetry = makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        telemetry.setUserId("lifetime-climber")

        return AppAccessRestoreService(
            telemetry: telemetry,
            entitlementID: entitlementID,
            restorer: { LifetimeRestorer(state: state) }
        )
    }
}

@MainActor
private final class LifetimePurchaseHarness {
    let sink = InMemoryTelemetrySink(destination: .analytics)
    private(set) var published: [Set<String>] = []
    private(set) var executor: RevenueCatPurchaseExecutor!

    init(entitlementID: String, refresh: MonetizationEntitlementRefresh) {
        let identity = MonetizationIdentityTransition(revision: 1, userID: "lifetime-climber")
        let telemetry = makeTestTelemetry(sink: sink)
        telemetry.setUserId("lifetime-climber")
        executor = RevenueCatPurchaseExecutor(
            telemetry: telemetry,
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: entitlementID,
            applySubscriptionStatus: { [weak self] entitlementIDs in
                self?.published.append(entitlementIDs)
            },
            refreshEntitlementState: { refresh },
            currentIdentityGeneration: { identity },
            adoptEntitlementState: { _, candidate in candidate == identity }
        )
    }
}

@MainActor
private final class LifetimeRestorer: PurchaseRestoring {
    let isRevenueCatConfigured = true
    let identityGeneration: MonetizationIdentityTransition? = MonetizationIdentityTransition(
        revision: 1,
        userID: "lifetime-climber"
    )
    private let state: MonetizationEntitlementState

    init(state: MonetizationEntitlementState) {
        self.state = state
    }

    func restorePurchases() async throws -> MonetizationEntitlementState {
        state
    }
}
