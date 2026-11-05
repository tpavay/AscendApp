import Foundation
import RevenueCat
import SuperwallKit

enum RevenueCatNativePaywallPlanProviderError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        "Plans are unavailable right now. Try again in a moment."
    }
}

@MainActor
final class RevenueCatNativePaywallPlanProvider: NativePaywallPlanProviding {
    private let configuration: MonetizationConfiguration
    private let coordinator: @MainActor () -> any PaywallPurchaseCoordinating
    private let executor: RevenueCatPurchaseExecutor
    private let isPurchasesConfigured: @MainActor () -> Bool
    private var purchaseTargetsByProductID: [String: PurchaseTarget] = [:]

    /// - Parameter allowsAnonymousPurchase: Whether a purchase may complete for the anonymous
    ///   customer a signed-out install starts as. Only the pre-sign-in paywall passes it; the
    ///   signed-in gate keeps refusing a purchase that has no uid to attribute it to.
    init(
        configuration: MonetizationConfiguration = .live,
        allowsAnonymousPurchase: Bool = false,
        coordinator: @escaping @MainActor () -> any PaywallPurchaseCoordinating = {
            MonetizationManager.shared
        },
        isPurchasesConfigured: @escaping @MainActor () -> Bool = { Purchases.isConfigured }
    ) {
        self.configuration = configuration
        self.coordinator = coordinator
        self.isPurchasesConfigured = isPurchasesConfigured
        executor = RevenueCatPurchaseExecutor(
            entitlementID: configuration.revenueCatEntitlementID,
            allowsAnonymousPurchase: allowsAnonymousPurchase,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: {
                await coordinator().refreshEntitlements(
                    force: true,
                    waitsForPendingIdentity: true
                )
            },
            currentIdentityGeneration: {
                coordinator().identityGeneration
            },
            adoptEntitlementState: { state, identity in
                coordinator().adoptPurchaseEntitlementState(state, for: identity)
            }
        )
    }

    func loadPlans() async throws -> [NativePaywallPlan] {
        try await loadPlans(
            productIDs: configuration.launchProductIDs,
            welcomeProductID: nil
        )
    }

    /// The yearly plan, Lifetime and the welcome gift's yearly plan, for the pre-sign-in paywall.
    func loadPreAuthPlans() async throws -> [NativePaywallPlan] {
        try await loadPlans(
            productIDs: configuration.preAuthProductIDs,
            welcomeProductID: configuration.revenueCatWelcomeProductID
        )
    }

    private func loadPlans(
        productIDs: [String],
        welcomeProductID: String?
    ) async throws -> [NativePaywallPlan] {
        guard isPurchasesConfigured() else {
            throw RevenueCatNativePaywallPlanProviderError.notConfigured
        }
        let expectedProductIDs = Set(productIDs)
        let offerings = try? await Purchases.shared.offerings()
        let offering = offerings?.all[configuration.revenueCatOfferingID]
            ?? offerings?.current
        let packages = (offering?.availablePackages ?? []).filter {
            expectedProductIDs.contains($0.storeProduct.productIdentifier)
        }
        var targets = Dictionary(
            uniqueKeysWithValues: packages.map {
                ($0.storeProduct.productIdentifier, PurchaseTarget.package($0))
            }
        )
        let missingProductIDs = productIDs.filter { targets[$0] == nil }
        let directProducts = await Purchases.shared.products(missingProductIDs)
        for product in directProducts where expectedProductIDs.contains(product.productIdentifier) {
            targets[product.productIdentifier] = .product(product)
        }
        purchaseTargetsByProductID = targets

        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: Array(targets.keys)
        )

        let productTerms = targets.values.map {
            Self.productTerms(from: $0.storeProduct)
        }
        let eligibilityByProductID = Dictionary(
            uniqueKeysWithValues: targets.keys.map { productID in
                let trialEligibility: NativeTrialEligibility
                if let providerEligibility = eligibility[productID] {
                    trialEligibility = providerEligibility.status.isEligible
                        ? .eligible
                        : .ineligible
                } else {
                    trialEligibility = .unknown
                }
                return (productID, trialEligibility)
            }
        )

        return NativePaywallPlanMapper.plans(
            from: productTerms,
            eligibilityByProductID: eligibilityByProductID,
            yearlyProductID: configuration.revenueCatYearlyProductID,
            lifetimeProductID: configuration.revenueCatLifetimeProductID,
            welcomeProductID: welcomeProductID
        )
    }

    func purchase(planID: String) async -> PurchaseResult {
        guard isPurchasesConfigured() else {
            return executor.failPurchaseBeforeRevenueCatCall(
                productID: planID,
                error: RevenueCatNativePaywallPlanProviderError.notConfigured,
                errorType: .configuration
            )
        }
        guard let purchaseTarget = purchaseTargetsByProductID[planID] else {
            return executor.failPurchaseBeforeRevenueCatCall(
                productID: planID,
                error: RevenueCatPurchaseControllerError.missingStoreKitProduct,
                errorType: .missingStoreProduct
            )
        }

        return await executor.executePurchase(productID: planID) {
            let result: PurchaseResultData
            switch purchaseTarget {
            case .package(let package):
                result = try await Purchases.shared.purchase(package: package)
            case .product(let product):
                result = try await Purchases.shared.purchase(product: product)
            }
            return RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: result.userCancelled,
                entitlementState: RevenueCatPurchasesProvider.entitlementState(
                    from: result.customerInfo
                )
            )
        }
    }

    static func productTerms(
        from product: RevenueCat.StoreProduct
    ) -> NativePaywallProductTerms {
        let freeTrialPeriod = product.introductoryDiscount.flatMap { discount in
            discount.paymentMode == .freeTrial
                ? nativePeriod(from: discount.subscriptionPeriod)
                : nil
        }

        return NativePaywallProductTerms(
            productID: product.productIdentifier,
            localizedPrice: product.localizedPriceString,
            billing: product.productCategory == .subscription ? .subscription : .oneTime,
            renewalPeriod: product.subscriptionPeriod.map(nativePeriod(from:)),
            freeTrialPeriod: freeTrialPeriod,
            price: product.price,
            localizedPricePerMonth: product.subscriptionPeriod == nil
                ? nil
                : product.localizedPricePerMonth
        )
    }

    private static func nativePeriod(
        from period: RevenueCat.SubscriptionPeriod
    ) -> NativeSubscriptionPeriod {
        let unit: NativeSubscriptionPeriod.Unit = switch period.unit {
        case .day:
            .day
        case .week:
            .week
        case .month:
            .month
        case .year:
            .year
        @unknown default:
            .unknown
        }
        return NativeSubscriptionPeriod(value: period.value, unit: unit)
    }

    private enum PurchaseTarget {
        case package(Package)
        case product(RevenueCat.StoreProduct)

        var storeProduct: RevenueCat.StoreProduct {
            switch self {
            case .package(let package):
                package.storeProduct
            case .product(let product):
                product
            }
        }
    }
}
